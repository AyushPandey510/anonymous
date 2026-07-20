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
use chrono::Utc;
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

    Ok(Json(ValidateLocationResponse {
        decision: decision.to_string(),
        lifecycle_state: lifecycle_state.to_string(),
        distance_meters: round_one(validation.distance_meters),
        effective_radius_meters: round_one(validation.effective_radius_meters),
        speed_meters_per_second: validation.speed_meters_per_second.map(round_one),
        confidence: validation.confidence.to_string(),
        reason: validation.reason.map(str::to_string),
        consecutive_outside: validation.consecutive_outside,
        can_participate: validation.can_participate(),
    }))
}

fn round_one(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}
