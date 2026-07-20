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
use rand::seq::SliceRandom;
use serde::Deserialize;
use std::sync::Arc;
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;
use validator::Validate;

const MAX_RADIUS_METERS: i32 = 300;
const MAX_ACTIVE_SPACES_PER_LOCATION: usize = 10;

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct CreateSpaceRequest {
    #[validate(length(min = 2, max = 80))]
    pub name: String,
    #[validate(length(max = 280))]
    pub description: Option<String>,
    pub visibility: String,
    pub latitude: f64,
    pub longitude: f64,
    #[validate(range(min = 1, max = 300))]
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

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/spaces", post(create_space))
        .route("/spaces/discover", get(discover_spaces))
        .route("/spaces/:space_id/join", post(join_space))
        .route("/spaces/:space_id/leave", post(leave_space))
        .route("/me/spaces", get(list_user_spaces))
}

#[utoipa::path(post, path = "/spaces", request_body = CreateSpaceRequest, responses((status = 200, body = Space)))]
pub async fn create_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateSpaceRequest>,
) -> ApiResult<Json<Space>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    validate_space_payload(&payload)?;

    let active_count = sqlx::query_scalar::<_, i64>(
        "SELECT count(*) FROM activity.spaces WHERE archived_at IS NULL AND created_by = $1",
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;
    if active_count > 0 {
        return Err(ApiError::Conflict(
            "users may create one active space at a time".to_string(),
        ));
    }

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
            "this location already has the maximum active spaces".to_string(),
        ));
    }

    let space = sqlx::query_as::<_, Space>(
        r#"
        INSERT INTO activity.spaces (name, description, visibility, latitude, longitude, radius_meters, created_by)
        VALUES ($1, $2, $3::space_visibility, $4, $5, $6, $7)
        RETURNING id, name, description, visibility::text, latitude, longitude, radius_meters, created_at
        "#,
    )
    .bind(payload.name)
    .bind(payload.description)
    .bind(payload.visibility)
    .bind(payload.latitude)
    .bind(payload.longitude)
    .bind(payload.radius_meters)
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(space))
}

#[utoipa::path(get, path = "/spaces/discover", params(DiscoverQuery), responses((status = 200, body = Vec<Space>)))]
pub async fn discover_spaces(
    _user: AuthUser,
    State(state): State<Arc<AppState>>,
    Query(query): Query<DiscoverQuery>,
) -> ApiResult<Json<Vec<Space>>> {
    if !geofence::valid_lat_lon(query.latitude, query.longitude) {
        return Err(ApiError::Validation(
            "invalid latitude or longitude".to_string(),
        ));
    }

    let spaces = sqlx::query_as::<_, Space>(
        r#"
        SELECT id, name, description, visibility::text, latitude, longitude, radius_meters, created_at
        FROM activity.spaces
        WHERE archived_at IS NULL AND visibility = 'public'
        ORDER BY created_at DESC
        "#,
    )
    .fetch_all(&state.pool)
    .await?;

    let here = Point {
        latitude: query.latitude,
        longitude: query.longitude,
    };
    Ok(Json(
        spaces
            .into_iter()
            .filter(|space| {
                geofence::contains(
                    Point {
                        latitude: space.latitude,
                        longitude: space.longitude,
                    },
                    space.radius_meters,
                    here,
                )
            })
            .collect(),
    ))
}

#[utoipa::path(post, path = "/spaces/{space_id}/join", request_body = JoinSpaceRequest, responses((status = 200, body = Session)))]
pub async fn join_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
    Json(payload): Json<JoinSpaceRequest>,
) -> ApiResult<Json<Session>> {
    if !geofence::valid_lat_lon(payload.latitude, payload.longitude) {
        return Err(ApiError::Validation(
            "invalid latitude or longitude".to_string(),
        ));
    }

    let space = sqlx::query_as::<_, (f64, f64, i32, String)>(
        "SELECT latitude, longitude, radius_meters, visibility::text FROM activity.spaces WHERE id = $1 AND archived_at IS NULL",
    )
    .bind(space_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)?;

    if space.3 == "private" {
        let invite_code = payload.invite_code.ok_or(ApiError::Forbidden)?;
        let usable = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM activity.space_invitations WHERE space_id = $1 AND invite_code = $2 AND expires_at > now() AND (max_uses IS NULL OR uses < max_uses))",
        )
        .bind(space_id)
        .bind(invite_code)
        .fetch_one(&state.pool)
        .await?;
        if !usable {
            return Err(ApiError::Forbidden);
        }
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
    let expires_at = Utc::now() + Duration::days(1);
    let session = sqlx::query_as::<_, Session>(
        r#"
        INSERT INTO activity.sessions (user_id, space_id, anonymous_id, expires_at, status)
        VALUES ($1, $2, $3, $4, 'active')
        RETURNING id, space_id, anonymous_id, expires_at, status::text
        "#,
    )
    .bind(user_id)
    .bind(space_id)
    .bind(anonymous_id)
    .bind(expires_at)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(session))
}

#[utoipa::path(post, path = "/spaces/{space_id}/leave")]
pub async fn leave_space(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Path(space_id): Path<Uuid>,
) -> ApiResult<Json<serde_json::Value>> {
    let grace_until =
        Utc::now() + Duration::from_std(state.config.session_grace).map_err(anyhow::Error::from)?;
    sqlx::query("UPDATE activity.sessions SET status = 'grace', expires_at = $3 WHERE user_id = $1 AND space_id = $2 AND status = 'active'")
        .bind(user_id)
        .bind(space_id)
        .bind(grace_until)
        .execute(&state.pool)
        .await?;
    Ok(Json(
        serde_json::json!({ "status": "grace", "expires_at": grace_until }),
    ))
}

pub async fn list_user_spaces(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
) -> ApiResult<Json<Vec<Space>>> {
    let spaces = sqlx::query_as::<_, Space>(
        r#"
        SELECT id, name, description, visibility::text, latitude, longitude, radius_meters, created_at
        FROM activity.spaces
        WHERE created_by = $1 AND archived_at IS NULL
        ORDER BY created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(spaces))
}

fn validate_space_payload(payload: &CreateSpaceRequest) -> ApiResult<()> {
    if !matches!(payload.visibility.as_str(), "public" | "private") {
        return Err(ApiError::Validation(
            "visibility must be public or private".to_string(),
        ));
    }
    if payload.radius_meters > MAX_RADIUS_METERS
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
    format!(
        "{}{}",
        adjectives.choose(&mut rng).unwrap(),
        nouns.choose(&mut rng).unwrap()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_radius_cap() {
        let payload = CreateSpaceRequest {
            name: "Cafe".to_string(),
            description: None,
            visibility: "public".to_string(),
            latitude: 1.0,
            longitude: 1.0,
            radius_meters: 301,
        };
        assert!(validate_space_payload(&payload).is_err());
    }
}
