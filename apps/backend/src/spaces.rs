use crate::{
    app::AppState,
    auth::AuthUser,
    error::{ApiError, ApiResult},
    geofence::{self, Geofence, GeofenceDecision, LocationFix, Point},
    models::{Session, Space},
};
use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{Duration, Utc};
use rand::{distributions::Alphanumeric, seq::SliceRandom, Rng};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;
use validator::Validate;

const MIN_RADIUS_METERS: i32 = 30;
const MAX_RADIUS_METERS: i32 = 300;
const MAX_ACTIVE_SPACES_PER_LOCATION: usize = 10;

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct CreateSpaceRequest {
    #[validate(length(min = 2, max = 80))]
    pub name: String,
    #[validate(length(min = 4, max = 280))]
    pub description: String,
    pub visibility: String,
    pub latitude: f64,
    pub longitude: f64,
    #[validate(range(min = 30, max = 300))]
    pub radius_meters: i32,
}

#[derive(Debug, Deserialize, IntoParams, ToSchema)]
pub struct DiscoverQuery {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct JoinSpaceRequest {
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: Option<f64>,
    pub invite_code: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct JoinByInviteRequest {
    pub invite_code: String,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: Option<f64>,
}

#[derive(Serialize, ToSchema)]
pub struct CreateSpaceResponse {
    #[serde(flatten)]
    pub space: Space,
    pub invite_code: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct InviteCodeResponse {
    pub invite_code: String,
    pub expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Serialize, ToSchema)]
pub struct JoinByInviteResponse {
    pub space: SpaceWithDistance,
    pub session: Session,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SpaceWithDistance {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub visibility: String,
    pub latitude: f64,
    pub longitude: f64,
    pub radius_meters: i32,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub distance_meters: f64,
    pub member_count: i32,
    pub joined: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LeaveResponse {
    pub status: String,
    pub message: String,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/spaces", post(create_space))
        .route("/spaces/join-by-code", post(join_space_by_invite))
        .route("/spaces/discover", get(discover_spaces))
        .route("/spaces/:space_id/invitations", post(create_invitation))
        .route("/spaces/:space_id/join", post(join_space))
        .route("/spaces/:space_id/leave", post(leave_space))
        .route("/me/spaces", get(list_my_spaces))
        .route("/me/joined-spaces", get(list_joined_spaces))
}

#[utoipa::path(post, path = "/spaces", request_body = CreateSpaceRequest, responses((status = 200, body = CreateSpaceResponse)))]
pub async fn create_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateSpaceRequest>,
) -> ApiResult<Json<CreateSpaceResponse>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    validate_space_payload(&payload)?;

    let nearby = sqlx::query_as::<_, (f64, f64, i32)>(
        "SELECT latitude, longitude, radius_meters FROM activity.spaces WHERE archived_at IS NULL",
    )
    .fetch_all(&state.pool)
    .await?;
    let candidate = Point {
        latitude: payload.latitude,
        longitude: payload.longitude,
    };
    let overlapping_count = nearby
        .iter()
        .filter(|(lat, lon, radius)| {
            geofence::distance_meters(
                candidate,
                Point {
                    latitude: *lat,
                    longitude: *lon,
                },
            ) <= (payload.radius_meters + *radius) as f64
        })
        .count();
    if overlapping_count >= MAX_ACTIVE_SPACES_PER_LOCATION {
        return Err(ApiError::Conflict(
            "this location already has the maximum active spaces (10)".to_string(),
        ));
    }

    let space = sqlx::query_as::<_, Space>(
        r#"
        INSERT INTO activity.spaces (name, description, visibility, latitude, longitude, radius_meters, created_by)
        VALUES ($1, $2, $3::space_visibility, $4, $5, $6, $7)
        RETURNING id, name, description, visibility::text, latitude, longitude, radius_meters, created_at
        "#,
    )
    .bind(&payload.name)
    .bind(payload.description.trim())
    .bind(&payload.visibility)
    .bind(payload.latitude)
    .bind(payload.longitude)
    .bind(payload.radius_meters)
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;

    let invite_code = if space.visibility == "private" {
        Some(
            create_invite_code(&state.pool, space.id, user_id)
                .await?
                .invite_code,
        )
    } else {
        None
    };

    Ok(Json(CreateSpaceResponse { space, invite_code }))
}

#[utoipa::path(get, path = "/spaces/discover", params(DiscoverQuery))]
pub async fn discover_spaces(
    user: AuthUser,
    State(state): State<Arc<AppState>>,
    Query(query): Query<DiscoverQuery>,
) -> ApiResult<Json<Vec<SpaceWithDistance>>> {
    if !geofence::valid_lat_lon(query.latitude, query.longitude) {
        return Err(ApiError::Validation(
            "invalid latitude or longitude".to_string(),
        ));
    }

    let joined_ids: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT space_id FROM activity.sessions WHERE user_id = $1 AND status IN ('active', 'grace') AND expires_at > now()",
    )
    .bind(user.id)
    .fetch_all(&state.pool)
    .await?;
    let joined_set: std::collections::HashSet<Uuid> = joined_ids.into_iter().map(|r| r.0).collect();

    let spaces = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            Option<String>,
            String,
            f64,
            f64,
            i32,
            chrono::DateTime<chrono::Utc>,
            i64,
        ),
    >(
        r#"
        SELECT
            s.id, s.name, s.description, s.visibility::text, s.latitude, s.longitude,
            s.radius_meters, s.created_at,
            COUNT(DISTINCT sess.id) FILTER (
                WHERE sess.status IN ('active', 'grace') AND sess.expires_at > now()
            ) AS active_member_count
        FROM activity.spaces s
        LEFT JOIN activity.sessions sess ON sess.space_id = s.id
        WHERE s.archived_at IS NULL AND s.visibility = 'public'
        GROUP BY s.id
        ORDER BY s.created_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    let here = Point {
        latitude: query.latitude,
        longitude: query.longitude,
    };

    let mut result: Vec<SpaceWithDistance> = spaces
        .into_iter()
        .filter(|space| {
            geofence::contains(
                Point {
                    latitude: space.4,
                    longitude: space.5,
                },
                space.6,
                here,
            )
        })
        .map(|space| {
            let dist = geofence::distance_meters(
                Point {
                    latitude: space.4,
                    longitude: space.5,
                },
                here,
            );
            let joined = joined_set.contains(&space.0);
            SpaceWithDistance {
                id: space.0,
                name: space.1,
                description: space.2,
                visibility: space.3,
                latitude: space.4,
                longitude: space.5,
                radius_meters: space.6,
                created_at: space.7,
                distance_meters: (dist * 10.0).round() / 10.0,
                member_count: space.8 as i32,
                joined,
            }
        })
        .collect();

    result.sort_by(|a, b| {
        a.distance_meters
            .partial_cmp(&b.distance_meters)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    Ok(Json(result))
}

#[utoipa::path(post, path = "/spaces/{space_id}/join")]
pub async fn join_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
    Json(payload): Json<JoinSpaceRequest>,
) -> ApiResult<Json<Session>> {
    let session_ttl =
        Duration::from_std(state.config.session_ttl).unwrap_or_else(|_| Duration::hours(2));
    if !geofence::valid_lat_lon(payload.latitude, payload.longitude) {
        return Err(ApiError::Validation(
            "invalid latitude or longitude".to_string(),
        ));
    }

    let space = sqlx::query_as::<_, (f64, f64, i32, String, Uuid)>(
        "SELECT latitude, longitude, radius_meters, visibility::text, created_by FROM activity.spaces WHERE id = $1 AND archived_at IS NULL",
    )
    .bind(space_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)?;

    let should_count_invite_use = if space.3 == "private" && space.4 != user_id {
        let invite_code = payload.invite_code.as_deref().ok_or(ApiError::Forbidden)?;
        ensure_invite_is_usable(&state.pool, space_id, &invite_code).await?;
        true
    } else {
        false
    };

    let existing = sqlx::query_as::<_, (Uuid, String, chrono::DateTime<chrono::Utc>)>(
        "SELECT id, anonymous_id, expires_at FROM activity.sessions WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace') AND expires_at > now()",
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_optional(&state.pool)
    .await?;

    if let Some((session_id, _, _)) = existing {
        let session = sqlx::query_as::<_, Session>(
            "UPDATE activity.sessions SET status = 'active', lifecycle_state = 'inside', consecutive_outside = 0, last_validated_at = now(), expires_at = $2 WHERE id = $1 RETURNING id, space_id, anonymous_id, expires_at, status::text",
        )
        .bind(session_id)
        .bind(Utc::now() + session_ttl)
        .fetch_one(&state.pool)
        .await?;
        return Ok(Json(session));
    }

    let validation = geofence::validate(
        Geofence {
            center: Point {
                latitude: space.0,
                longitude: space.1,
            },
            radius_meters: space.2,
        },
        LocationFix {
            point: Point {
                latitude: payload.latitude,
                longitude: payload.longitude,
            },
            accuracy_meters: payload.accuracy_meters,
            captured_at: Utc::now(),
        },
        None,
    );
    if !matches!(
        validation.decision,
        GeofenceDecision::Inside | GeofenceDecision::NearBoundary
    ) {
        return Err(ApiError::Forbidden);
    }

    let anonymous_id = random_anonymous_name();
    let expires_at = Utc::now() + session_ttl;
    let session = sqlx::query_as::<_, Session>(
        r#"
        INSERT INTO activity.sessions (user_id, space_id, anonymous_id, expires_at, status, lifecycle_state)
        VALUES ($1, $2, $3, $4, 'active', 'inside')
        RETURNING id, space_id, anonymous_id, expires_at, status::text
        "#,
    )
    .bind(user_id)
    .bind(space_id)
    .bind(&anonymous_id)
    .bind(expires_at)
    .fetch_one(&state.pool)
    .await?;

    sqlx::query("UPDATE activity.spaces SET member_count = member_count + 1 WHERE id = $1")
        .bind(space_id)
        .execute(&state.pool)
        .await?;

    if should_count_invite_use {
        let invite_code = payload.invite_code.as_deref().ok_or(ApiError::Forbidden)?;
        increment_invite_uses(&state.pool, space_id, invite_code).await?;
    }

    Ok(Json(session))
}

#[utoipa::path(post, path = "/spaces/{space_id}/invitations", responses((status = 200, body = InviteCodeResponse)))]
pub async fn create_invitation(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<InviteCodeResponse>> {
    let can_invite = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.spaces s WHERE s.id = $1 AND s.visibility = 'private' AND s.archived_at IS NULL AND (s.created_by = $2 OR EXISTS(SELECT 1 FROM activity.sessions sess WHERE sess.space_id = s.id AND sess.user_id = $2 AND sess.status IN ('active', 'grace') AND sess.expires_at > now())))",
    )
    .bind(space_id)
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;
    if !can_invite {
        return Err(ApiError::Forbidden);
    }

    Ok(Json(
        create_invite_code(&state.pool, space_id, user_id).await?,
    ))
}

#[utoipa::path(post, path = "/spaces/join-by-code", request_body = JoinByInviteRequest, responses((status = 200, body = JoinByInviteResponse)))]
pub async fn join_space_by_invite(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<JoinByInviteRequest>,
) -> ApiResult<Json<JoinByInviteResponse>> {
    let invite_code = normalize_invite_code(&payload.invite_code);
    if invite_code.is_empty() {
        return Err(ApiError::Validation("invite code is required".to_string()));
    }

    let space_id = sqlx::query_scalar::<_, Uuid>(
        r#"
        SELECT i.space_id
        FROM activity.space_invitations i
        JOIN activity.spaces s ON s.id = i.space_id
        WHERE i.invite_code = $1
          AND i.expires_at > now()
          AND (i.max_uses IS NULL OR i.uses < i.max_uses)
          AND s.archived_at IS NULL
          AND s.visibility = 'private'
        "#,
    )
    .bind(&invite_code)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::Forbidden)?;

    let session = join_space(
        AuthUser { id: user_id },
        State(state.clone()),
        Path(space_id),
        Json(JoinSpaceRequest {
            latitude: payload.latitude,
            longitude: payload.longitude,
            accuracy_meters: payload.accuracy_meters,
            invite_code: Some(invite_code),
        }),
    )
    .await?
    .0;

    let space = space_summary(
        &state.pool,
        space_id,
        user_id,
        payload.latitude,
        payload.longitude,
    )
    .await?
    .ok_or(ApiError::NotFound)?;

    Ok(Json(JoinByInviteResponse { space, session }))
}

#[utoipa::path(post, path = "/spaces/{space_id}/leave")]
pub async fn leave_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<LeaveResponse>> {
    let result = sqlx::query(
        "UPDATE activity.sessions SET status = 'expired', expires_at = now() WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace')",
    )
    .bind(user_id)
    .bind(space_id)
    .execute(&state.pool)
    .await?;

    if result.rows_affected() > 0 {
        sqlx::query("UPDATE activity.spaces SET member_count = GREATEST(member_count - $2::integer, 0) WHERE id = $1")
            .bind(space_id)
            .bind(result.rows_affected() as i32)
            .execute(&state.pool)
            .await?;
    }

    Ok(Json(LeaveResponse {
        status: "left".to_string(),
        message: "You have left the space".to_string(),
    }))
}

pub async fn list_my_spaces(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
) -> ApiResult<Json<Vec<SpaceWithDistance>>> {
    let spaces = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            Option<String>,
            String,
            f64,
            f64,
            i32,
            chrono::DateTime<chrono::Utc>,
            i64,
        ),
    >(
        r#"
        SELECT
            s.id, s.name, s.description, s.visibility::text, s.latitude, s.longitude,
            s.radius_meters, s.created_at,
            COUNT(DISTINCT sess.id) FILTER (
                WHERE sess.status IN ('active', 'grace') AND sess.expires_at > now()
            ) AS active_member_count
        FROM activity.spaces s
        LEFT JOIN activity.sessions sess ON sess.space_id = s.id
        WHERE s.created_by = $1 AND s.archived_at IS NULL
        GROUP BY s.id
        ORDER BY s.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(
        spaces.into_iter().map(space_with_zero_distance).collect(),
    ))
}

pub async fn list_joined_spaces(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
) -> ApiResult<Json<Vec<SpaceWithDistance>>> {
    let spaces = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            Option<String>,
            String,
            f64,
            f64,
            i32,
            chrono::DateTime<chrono::Utc>,
            i64,
        ),
    >(
        r#"
        SELECT
            s.id, s.name, s.description, s.visibility::text, s.latitude, s.longitude,
            s.radius_meters, s.created_at,
            COUNT(DISTINCT active_sess.id) FILTER (
                WHERE active_sess.status IN ('active', 'grace') AND active_sess.expires_at > now()
            ) AS active_member_count
        FROM activity.spaces s
        JOIN activity.sessions sess ON sess.space_id = s.id
        LEFT JOIN activity.sessions active_sess ON active_sess.space_id = s.id
        WHERE sess.user_id = $1
          AND sess.status IN ('active', 'grace')
          AND sess.expires_at > now()
          AND s.archived_at IS NULL
        GROUP BY s.id, sess.joined_at
        ORDER BY sess.joined_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(
        spaces.into_iter().map(space_with_zero_distance).collect(),
    ))
}

fn space_with_zero_distance(
    space: (
        Uuid,
        String,
        Option<String>,
        String,
        f64,
        f64,
        i32,
        chrono::DateTime<chrono::Utc>,
        i64,
    ),
) -> SpaceWithDistance {
    SpaceWithDistance {
        id: space.0,
        name: space.1,
        description: space.2,
        visibility: space.3,
        latitude: space.4,
        longitude: space.5,
        radius_meters: space.6,
        created_at: space.7,
        distance_meters: 0.0,
        member_count: space.8 as i32,
        joined: true,
    }
}

async fn space_summary(
    pool: &sqlx::PgPool,
    space_id: Uuid,
    user_id: Uuid,
    latitude: f64,
    longitude: f64,
) -> ApiResult<Option<SpaceWithDistance>> {
    let space = sqlx::query_as::<
        _,
        (
            Uuid,
            String,
            Option<String>,
            String,
            f64,
            f64,
            i32,
            chrono::DateTime<chrono::Utc>,
            i64,
        ),
    >(
        r#"
        SELECT
            s.id, s.name, s.description, s.visibility::text, s.latitude, s.longitude,
            s.radius_meters, s.created_at,
            COUNT(DISTINCT sess.id) FILTER (
                WHERE sess.status IN ('active', 'grace') AND sess.expires_at > now()
            ) AS active_member_count
        FROM activity.spaces s
        LEFT JOIN activity.sessions sess ON sess.space_id = s.id
        WHERE s.id = $1 AND s.archived_at IS NULL
        GROUP BY s.id
        "#,
    )
    .bind(space_id)
    .fetch_optional(pool)
    .await?;

    let joined = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.sessions WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace') AND expires_at > now())",
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_one(pool)
    .await?;

    let here = Point {
        latitude,
        longitude,
    };

    Ok(space.map(|space| {
        let distance = geofence::distance_meters(
            Point {
                latitude: space.4,
                longitude: space.5,
            },
            here,
        );
        SpaceWithDistance {
            id: space.0,
            name: space.1,
            description: space.2,
            visibility: space.3,
            latitude: space.4,
            longitude: space.5,
            radius_meters: space.6,
            created_at: space.7,
            distance_meters: (distance * 10.0).round() / 10.0,
            member_count: space.8 as i32,
            joined,
        }
    }))
}

async fn create_invite_code(
    pool: &sqlx::PgPool,
    space_id: Uuid,
    created_by: Uuid,
) -> ApiResult<InviteCodeResponse> {
    let expires_at = Utc::now() + Duration::days(7);
    for _ in 0..5 {
        let invite_code = random_invite_code();
        let inserted = sqlx::query_as::<_, (String, chrono::DateTime<chrono::Utc>)>(
            r#"
            INSERT INTO activity.space_invitations (space_id, invite_code, expires_at, created_by)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (invite_code) DO NOTHING
            RETURNING invite_code, expires_at
            "#,
        )
        .bind(space_id)
        .bind(&invite_code)
        .bind(expires_at)
        .bind(created_by)
        .fetch_optional(pool)
        .await?;

        if let Some((invite_code, expires_at)) = inserted {
            return Ok(InviteCodeResponse {
                invite_code,
                expires_at,
            });
        }
    }

    Err(ApiError::Conflict(
        "could not create a unique invite code".to_string(),
    ))
}

async fn ensure_invite_is_usable(
    pool: &sqlx::PgPool,
    space_id: Uuid,
    invite_code: &str,
) -> ApiResult<()> {
    let usable = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM activity.space_invitations WHERE space_id = $1 AND invite_code = $2 AND expires_at > now() AND (max_uses IS NULL OR uses < max_uses))",
    )
    .bind(space_id)
    .bind(normalize_invite_code(invite_code))
    .fetch_one(pool)
    .await?;

    if usable {
        Ok(())
    } else {
        Err(ApiError::Forbidden)
    }
}

async fn increment_invite_uses(
    pool: &sqlx::PgPool,
    space_id: Uuid,
    invite_code: &str,
) -> ApiResult<()> {
    sqlx::query(
        "UPDATE activity.space_invitations SET uses = uses + 1 WHERE space_id = $1 AND invite_code = $2",
    )
    .bind(space_id)
    .bind(normalize_invite_code(invite_code))
    .execute(pool)
    .await?;
    Ok(())
}

fn validate_space_payload(payload: &CreateSpaceRequest) -> ApiResult<()> {
    if payload.description.trim().is_empty() {
        return Err(ApiError::Validation("description is required".to_string()));
    }
    if !matches!(payload.visibility.as_str(), "public" | "private") {
        return Err(ApiError::Validation(
            "visibility must be public or private".to_string(),
        ));
    }
    if !(MIN_RADIUS_METERS..=MAX_RADIUS_METERS).contains(&payload.radius_meters)
        || !geofence::valid_lat_lon(payload.latitude, payload.longitude)
    {
        return Err(ApiError::Validation("invalid geofence".to_string()));
    }
    Ok(())
}

fn random_anonymous_name() -> String {
    let adjectives = [
        "Silent", "Hidden", "Blue", "Bright", "Calm", "Neon", "Quiet", "Swift",
    ];
    let nouns = [
        "Fox", "Wolf", "Panda", "Comet", "Signal", "Orbit", "Nova", "Echo",
    ];
    let mut rng = rand::thread_rng();
    let suffix: String = (&mut rng)
        .sample_iter(&Alphanumeric)
        .take(4)
        .map(char::from)
        .collect();
    format!(
        "{}{}{}",
        adjectives.choose(&mut rng).unwrap(),
        nouns.choose(&mut rng).unwrap(),
        suffix
    )
}

fn random_invite_code() -> String {
    let mut rng = rand::thread_rng();
    let raw: String = (&mut rng)
        .sample_iter(&Alphanumeric)
        .take(8)
        .map(char::from)
        .collect();
    normalize_invite_code(&raw)
}

fn normalize_invite_code(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_radius_cap() {
        let mut payload = CreateSpaceRequest {
            name: "Cafe".to_string(),
            description: "A quiet place nearby".to_string(),
            visibility: "public".to_string(),
            latitude: 1.0,
            longitude: 1.0,
            radius_meters: 301,
        };
        assert!(validate_space_payload(&payload).is_err());
        payload.radius_meters = 29;
        assert!(validate_space_payload(&payload).is_err());
        payload.radius_meters = 30;
        assert!(validate_space_payload(&payload).is_ok());
    }

    #[test]
    fn requires_description() {
        let payload = CreateSpaceRequest {
            name: "Cafe".to_string(),
            description: "   ".to_string(),
            visibility: "public".to_string(),
            latitude: 1.0,
            longitude: 1.0,
            radius_meters: 120,
        };
        assert!(validate_space_payload(&payload).is_err());
    }
}
