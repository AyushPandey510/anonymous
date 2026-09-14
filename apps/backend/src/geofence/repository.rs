use super::models::{LocationFix, Point, SessionLifecycleState, ValidationHistory};
use crate::error::ApiResult;
use chrono::{DateTime, Duration, Utc};
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
          -- Only recent exact points can be used for smoothing and speed checks.
          AND latitude IS NOT NULL
          AND longitude IS NOT NULL
          AND precise_location_expires_at > now()
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
    pub precise_location_retention: Duration,
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
    let precise_location_expires_at = Utc::now() + event.precise_location_retention;

    sqlx::query(
        r#"
        INSERT INTO activity.location_validation_events
            (user_id, space_id, latitude, longitude, accuracy_meters, distance_meters,
             speed_meters_per_second, decision, lifecycle_state, reason, mock_location,
             spoofing_score, metadata, distance_bucket, accuracy_bucket, speed_bucket,
             precise_location_expires_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
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
    .bind(distance_bucket(event.distance_meters))
    .bind(accuracy_bucket(event.accuracy_meters))
    .bind(speed_bucket(event.speed_meters_per_second))
    .bind(precise_location_expires_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn anonymize_expired_precise_locations(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let result = sqlx::query(
        r#"
        UPDATE activity.location_validation_events
        SET latitude = NULL,
            longitude = NULL,
            distance_meters = NULL,
            accuracy_meters = NULL,
            speed_meters_per_second = NULL
        WHERE precise_location_expires_at < now()
          -- Keep the audit row, but remove the exact location trail.
          AND (latitude IS NOT NULL
               OR longitude IS NOT NULL
               OR distance_meters IS NOT NULL
               OR accuracy_meters IS NOT NULL
               OR speed_meters_per_second IS NOT NULL)
        "#,
    )
    .execute(pool)
    .await?;
    Ok(result.rows_affected())
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

fn distance_bucket(distance_meters: f64) -> &'static str {
    if distance_meters < 25.0 {
        "0-25m"
    } else if distance_meters < 50.0 {
        "25-50m"
    } else if distance_meters < 100.0 {
        "50-100m"
    } else if distance_meters < 300.0 {
        "100-300m"
    } else {
        "300m+"
    }
}

fn accuracy_bucket(accuracy_meters: Option<f64>) -> &'static str {
    match accuracy_meters {
        Some(value) if value <= 25.0 => "high",
        Some(value) if value <= 75.0 => "medium",
        Some(_) => "low",
        None => "unknown",
    }
}

fn speed_bucket(speed_meters_per_second: Option<f64>) -> &'static str {
    match speed_meters_per_second {
        Some(value) if value < 1.0 => "stationary",
        Some(value) if value < 3.0 => "walking",
        Some(value) if value < 30.0 => "vehicle",
        Some(_) => "fast_vehicle",
        None => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buckets_distance_for_long_term_audit() {
        assert_eq!(distance_bucket(12.0), "0-25m");
        assert_eq!(distance_bucket(43.0), "25-50m");
        assert_eq!(distance_bucket(90.0), "50-100m");
        assert_eq!(distance_bucket(240.0), "100-300m");
        assert_eq!(distance_bucket(301.0), "300m+");
    }

    #[test]
    fn buckets_accuracy_for_long_term_audit() {
        assert_eq!(accuracy_bucket(Some(12.0)), "high");
        assert_eq!(accuracy_bucket(Some(60.0)), "medium");
        assert_eq!(accuracy_bucket(Some(120.0)), "low");
        assert_eq!(accuracy_bucket(None), "unknown");
    }

    #[test]
    fn buckets_speed_for_long_term_audit() {
        assert_eq!(speed_bucket(Some(0.2)), "stationary");
        assert_eq!(speed_bucket(Some(1.5)), "walking");
        assert_eq!(speed_bucket(Some(12.0)), "vehicle");
        assert_eq!(speed_bucket(Some(35.0)), "fast_vehicle");
        assert_eq!(speed_bucket(None), "unknown");
    }
}
