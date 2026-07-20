use super::models::{LocationFix, Point, SessionLifecycleState, ValidationHistory};
use crate::error::ApiResult;
use chrono::{DateTime, Utc};
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

pub async fn validation_history(
    pool: &PgPool,
    user_id: Uuid,
    space_id: Uuid,
) -> ApiResult<ValidationHistory> {
    let rows = sqlx::query_as::<_, (f64, f64, Option<f64>, String, DateTime<Utc>)>(
        r#"
        SELECT latitude, longitude, accuracy_meters, decision, created_at
        FROM activity.location_validation_events
        WHERE user_id = $1 AND space_id = $2
        ORDER BY created_at DESC
        LIMIT 3
        "#,
    )
    .bind(user_id)
    .bind(space_id)
    .fetch_all(pool)
    .await?;

    let mut recent_fixes = [None, None, None];
    let mut consecutive_outside = 0;
    let mut previous_lifecycle = SessionLifecycleState::Joining;

    for (index, row) in rows.iter().enumerate() {
        let fix = LocationFix {
            point: Point {
                latitude: row.0,
                longitude: row.1,
            },
            accuracy_meters: row.2,
            captured_at: row.4,
        };
        recent_fixes[index] = Some(fix);
        if row.3 == "outside" {
            consecutive_outside += 1;
        } else if index == 0 {
            previous_lifecycle = lifecycle_from_decision(&row.3);
            break;
        } else {
            break;
        }
        if index == 0 {
            previous_lifecycle = lifecycle_from_decision(&row.3);
        }
    }

    Ok(ValidationHistory {
        latest_fix: recent_fixes[0],
        recent_fixes,
        consecutive_outside,
        previous_lifecycle,
    })
}

pub struct ValidationEventInsert<'a> {
    pub user_id: Uuid,
    pub space_id: Uuid,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: Option<f64>,
    pub distance_meters: f64,
    pub speed_meters_per_second: Option<f64>,
    pub decision: &'a str,
    pub lifecycle_state: &'a str,
    pub reason: Option<&'a str>,
    pub mock_location: bool,
    pub device_integrity: Option<&'a str>,
    pub platform: Option<&'a str>,
    pub app_version: Option<&'a str>,
    pub gps_provider: Option<&'a str>,
}

pub async fn insert_validation_event(
    pool: &PgPool,
    event: ValidationEventInsert<'_>,
) -> ApiResult<()> {
    let spoofing_score = if event.mock_location || event.decision == "rejected" {
        100
    } else if event.speed_meters_per_second.unwrap_or(0.0) > 30.0 {
        50
    } else {
        0
    };
    let metadata = json!({
        "platform": event.platform,
        "app_version": event.app_version,
        "gps_provider": event.gps_provider,
        "device_integrity": event.device_integrity,
    });

    sqlx::query(
        r#"
        INSERT INTO activity.location_validation_events
            (user_id, space_id, latitude, longitude, accuracy_meters, distance_meters,
             speed_meters_per_second, decision, lifecycle_state, reason, mock_location,
             spoofing_score, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        "#,
    )
    .bind(event.user_id)
    .bind(event.space_id)
    .bind(event.latitude)
    .bind(event.longitude)
    .bind(event.accuracy_meters)
    .bind(event.distance_meters)
    .bind(event.speed_meters_per_second)
    .bind(event.decision)
    .bind(event.lifecycle_state)
    .bind(event.reason)
    .bind(event.mock_location)
    .bind(spoofing_score)
    .bind(metadata)
    .execute(pool)
    .await?;
    Ok(())
}

fn lifecycle_from_decision(decision: &str) -> SessionLifecycleState {
    match decision {
        "inside" => SessionLifecycleState::Inside,
        "near_boundary" => SessionLifecycleState::NearBoundary,
        "outside" => SessionLifecycleState::GracePeriod,
        "expired" => SessionLifecycleState::Expired,
        _ => SessionLifecycleState::Joining,
    }
}
