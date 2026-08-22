use super::{
    models::{Geofence, LocationFix, Point, ValidateLocationRequest, ValidateLocationResponse},
    repository::{insert_validation_event, validation_history, ValidationEventInsert},
    validator::validate_with_history,
};
use crate::{
    app::AppState,
    auth::AuthUser,
    error::{ApiError, ApiResult},
};
use axum::{extract::State, routing::post, Json, Router};
use chrono::{DateTime, Duration, Utc};
use std::sync::Arc;

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/geofence/validate", post(validate_location))
}

#[utoipa::path(post, path = "/geofence/validate", request_body = ValidateLocationRequest, responses((status = 200, body = ValidateLocationResponse)))]
pub async fn validate_location(
    AuthUser { id: user_id }: AuthUser,
    State(state): State<Arc<AppState>>,
    Json(payload): Json<ValidateLocationRequest>,
) -> ApiResult<Json<ValidateLocationResponse>> {
    let space = sqlx::query_as::<_, (f64, f64, i32)>(
        "SELECT latitude, longitude, radius_meters FROM activity.spaces WHERE id = $1 AND archived_at IS NULL",
    )
    .bind(payload.space_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::NotFound)?;

    let history = validation_history(&state.pool, user_id, payload.space_id).await?;
    let fix = LocationFix {
        point: Point {
            latitude: payload.latitude,
            longitude: payload.longitude,
        },
        accuracy_meters: payload.accuracy_meters,
        captured_at: payload.client_timestamp.unwrap_or_else(Utc::now),
    };
    let validation = validate_with_history(
        Geofence {
            center: Point {
                latitude: space.0,
                longitude: space.1,
            },
            radius_meters: space.2,
        },
        fix,
        history,
        payload.mock_location.unwrap_or(false),
    );

    let decision = validation.decision.as_str();
    let lifecycle_state = validation.lifecycle_state.as_str();
    insert_validation_event(
        &state.pool,
        ValidationEventInsert {
            user_id,
            space_id: payload.space_id,
            latitude: payload.latitude,
            longitude: payload.longitude,
            accuracy_meters: payload.accuracy_meters,
            distance_meters: validation.distance_meters,
            speed_meters_per_second: validation.speed_meters_per_second,
            decision,
            lifecycle_state,
            reason: validation.reason,
            mock_location: payload.mock_location.unwrap_or(false),
            device_integrity: payload.device_integrity.as_deref(),
            platform: payload.platform.as_deref(),
            app_version: payload.app_version.as_deref(),
            gps_provider: payload.gps_provider.as_deref(),
        },
    )
    .await?;

    // Update session lifecycle based on validation result
    update_session_from_validation(
        &state.pool,
        user_id,
        payload.space_id,
        decision,
        lifecycle_state,
        session_grace(&state),
        session_ttl(&state),
    )
    .await?;

    let effective_state =
        effective_lifecycle_state(&state.pool, user_id, payload.space_id, lifecycle_state).await?;

    Ok(Json(ValidateLocationResponse {
        decision: decision.to_string(),
        lifecycle_state: effective_state.to_string(),
        distance_meters: round_one(validation.distance_meters),
        effective_radius_meters: round_one(validation.effective_radius_meters),
        speed_meters_per_second: validation.speed_meters_per_second.map(round_one),
        confidence: validation.confidence.to_string(),
        reason: validation.reason.map(str::to_string),
        consecutive_outside: validation.consecutive_outside,
        can_participate: validation.can_participate() && effective_state != "expired",
    }))
}

fn session_grace(state: &AppState) -> Duration {
    Duration::from_std(state.config.session_grace).unwrap_or_else(|_| Duration::seconds(120))
}

fn session_ttl(state: &AppState) -> Duration {
    Duration::from_std(state.config.session_ttl).unwrap_or_else(|_| Duration::hours(2))
}

async fn effective_lifecycle_state<'a>(
    pool: &sqlx::PgPool,
    user_id: uuid::Uuid,
    space_id: uuid::Uuid,
    fallback: &'a str,
) -> ApiResult<&'a str> {
    let session = sqlx::query_as::<_, (String, DateTime<Utc>)>(
        "SELECT status, expires_at FROM activity.sessions WHERE user_id = $1 AND space_id = $2 ORDER BY joined_at DESC LIMIT 1",
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_optional(pool)
    .await?;
    Ok(resolve_lifecycle_state(session.as_ref(), fallback))
}

fn resolve_lifecycle_state<'a>(
    session: Option<&(String, DateTime<Utc>)>,
    fallback: &'a str,
) -> &'a str {
    match session {
        Some((status, expires))
            if status == "expired" || (status == "grace" && *expires <= Utc::now()) =>
        {
            "expired"
        }
        _ => fallback,
    }
}

async fn update_session_from_validation(
    pool: &sqlx::PgPool,
    user_id: uuid::Uuid,
    space_id: uuid::Uuid,
    decision: &str,
    lifecycle_state: &str,
    grace: Duration,
    session_ttl: Duration,
) -> Result<(), sqlx::Error> {
    match decision {
        "outside" | "rejected" => {
            let grace_until = Utc::now() + grace;
            sqlx::query(
                r#"
                UPDATE activity.sessions
                SET status = 'grace',
                    expires_at = $4,
                    lifecycle_state = $3,
                    last_validated_at = now(),
                    consecutive_outside = consecutive_outside + 1
                WHERE user_id = $1 AND space_id = $2 AND status = 'active'
                "#,
            )
            .bind(user_id)
            .bind(space_id)
            .bind(lifecycle_state)
            .bind(grace_until)
            .execute(pool)
            .await?;
        }
        "inside" | "near_boundary" => {
            sqlx::query(
                r#"
                UPDATE activity.sessions
                SET status = 'active',
                    expires_at = $4,
                    lifecycle_state = $3,
                    last_validated_at = now(),
                    consecutive_outside = 0
                WHERE user_id = $1 AND space_id = $2 AND status IN ('active', 'grace')
                "#,
            )
            .bind(user_id)
            .bind(space_id)
            .bind(lifecycle_state)
            .bind(Utc::now() + session_ttl)
            .execute(pool)
            .await?;
        }
        _ => {}
    }
    Ok(())
}

fn round_one(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session(status: &str, minutes_from_now: i64) -> (String, DateTime<Utc>) {
        (
            status.to_string(),
            Utc::now() + Duration::minutes(minutes_from_now),
        )
    }

    #[test]
    fn active_session_keeps_fallback_state() {
        assert_eq!(
            resolve_lifecycle_state(Some(&session("active", 30)), "grace_period"),
            "grace_period"
        );
        assert_eq!(
            resolve_lifecycle_state(Some(&session("active", 30)), "outside"),
            "outside"
        );
    }

    #[test]
    fn active_grace_session_keeps_fallback_state() {
        assert_eq!(
            resolve_lifecycle_state(Some(&session("grace", 1)), "grace_period"),
            "grace_period"
        );
    }

    #[test]
    fn expired_grace_session_resolves_to_expired() {
        assert_eq!(
            resolve_lifecycle_state(Some(&session("grace", -1)), "grace_period"),
            "expired"
        );
    }

    #[test]
    fn expired_session_resolves_to_expired() {
        assert_eq!(
            resolve_lifecycle_state(Some(&session("expired", 0)), "inside"),
            "expired"
        );
    }

    #[test]
    fn missing_session_keeps_fallback_state() {
        assert_eq!(
            resolve_lifecycle_state(None, "grace_period"),
            "grace_period"
        );
    }
}
