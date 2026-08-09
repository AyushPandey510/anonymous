use super::{
    geometry::{distance_meters, valid_lat_lon},
    hysteresis::{buffered_outside_decision, classify_distance},
    models::{
        Geofence, GeofenceDecision, GeofenceValidation, LocationFix, PreviousLocationFix,
        SessionLifecycleState, ValidationHistory,
    },
    smoothing::median_smoothed_fix,
    spoof_detection::{detect_spoofing, SpoofSignal},
    tracking::lifecycle_for_decision,
};

const MAX_ACCURACY_TOLERANCE_M: f64 = 35.0;
const MAX_ACCEPTABLE_JOIN_ACCURACY_M: f64 = 75.0;

pub fn validate(
    geofence: Geofence,
    fix: LocationFix,
    previous: Option<PreviousLocationFix>,
) -> GeofenceValidation {
    let history = ValidationHistory {
        latest_fix: previous.map(|previous| previous.fix),
        recent_fixes: [previous.map(|previous| previous.fix), None, None],
        consecutive_outside: 0,
        previous_lifecycle: SessionLifecycleState::Joining,
    };
    validate_with_history(geofence, fix, history, false)
}

pub fn validate_with_history(
    geofence: Geofence,
    fix: LocationFix,
    history: ValidationHistory,
    mock_location: bool,
) -> GeofenceValidation {
    if !valid_lat_lon(fix.point.latitude, fix.point.longitude) || geofence.radius_meters <= 0 {
        return rejected("invalid_coordinate");
    }

    if let Some(accuracy) = fix.accuracy_meters {
        if !accuracy.is_finite() || accuracy < 0.0 {
            return rejected("invalid_accuracy");
        }
    }

    let (spoof_signal, speed) = detect_spoofing(history.latest_fix, fix, mock_location);
    match spoof_signal {
        SpoofSignal::MockLocation => {
            return rejected_with_distance(geofence, fix, speed, "mock_location_detected");
        }
        SpoofSignal::ImpossibleJump => {
            return rejected_with_distance(geofence, fix, speed, "impossible_location_jump");
        }
        SpoofSignal::ExcessiveSpeed => {
            return rejected_with_distance(geofence, fix, speed, "excessive_speed");
        }
        SpoofSignal::None => {}
    }

    let accuracy = fix
        .accuracy_meters
        .unwrap_or(MAX_ACCEPTABLE_JOIN_ACCURACY_M + 1.0);
    let smoothed_fix = median_smoothed_fix(fix, &history.recent_fixes);
    let distance = distance_meters(geofence.center, smoothed_fix.point);
    let effective_radius = geofence.radius_meters as f64 + accuracy.min(MAX_ACCURACY_TOLERANCE_M);

    if accuracy > MAX_ACCEPTABLE_JOIN_ACCURACY_M {
        return GeofenceValidation {
            decision: GeofenceDecision::LowAccuracy,
            lifecycle_state: history.previous_lifecycle,
            distance_meters: distance,
            effective_radius_meters: effective_radius,
            speed_meters_per_second: speed,
            confidence: "low",
            reason: Some("accuracy_too_low"),
            consecutive_outside: history.consecutive_outside,
        };
    }

    let raw_decision = classify_distance(geofence, distance, effective_radius);
    let (decision, consecutive_outside) =
        buffered_outside_decision(raw_decision, history.consecutive_outside);
    let lifecycle_state = lifecycle_for_decision(decision, history.previous_lifecycle);

    GeofenceValidation {
        decision,
        lifecycle_state,
        distance_meters: distance,
        effective_radius_meters: effective_radius,
        speed_meters_per_second: speed,
        confidence: confidence_for_accuracy(accuracy),
        reason: reason_for_decision(raw_decision, decision),
        consecutive_outside,
    }
}

fn reason_for_decision(raw: GeofenceDecision, buffered: GeofenceDecision) -> Option<&'static str> {
    if raw == GeofenceDecision::Outside && buffered == GeofenceDecision::NearBoundary {
        Some("outside_buffer_pending")
    } else if buffered == GeofenceDecision::NearBoundary {
        Some("within_hysteresis_or_accuracy_tolerance")
    } else {
        None
    }
}

fn confidence_for_accuracy(accuracy: f64) -> &'static str {
    if accuracy <= 25.0 {
        "high"
    } else if accuracy <= MAX_ACCEPTABLE_JOIN_ACCURACY_M {
        "medium"
    } else {
        "low"
    }
}

fn rejected(reason: &'static str) -> GeofenceValidation {
    GeofenceValidation {
        decision: GeofenceDecision::Rejected,
        lifecycle_state: SessionLifecycleState::Outside,
        distance_meters: 0.0,
        effective_radius_meters: 0.0,
        speed_meters_per_second: None,
        confidence: "low",
        reason: Some(reason),
        consecutive_outside: 0,
    }
}

fn rejected_with_distance(
    geofence: Geofence,
    fix: LocationFix,
    speed: Option<f64>,
    reason: &'static str,
) -> GeofenceValidation {
    GeofenceValidation {
        decision: GeofenceDecision::Rejected,
        lifecycle_state: SessionLifecycleState::Outside,
        distance_meters: distance_meters(geofence.center, fix.point),
        effective_radius_meters: geofence.radius_meters as f64,
        speed_meters_per_second: speed,
        confidence: "low",
        reason: Some(reason),
        consecutive_outside: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geofence::models::Point;
    use chrono::{Duration, Utc};

    #[test]
    fn validates_inside_with_high_confidence() {
        let result = validate(test_geofence(), test_fix(12.97161, 77.59461, 12.0), None);

        assert_eq!(result.decision, GeofenceDecision::Inside);
        assert_eq!(result.lifecycle_state, SessionLifecycleState::Inside);
        assert_eq!(result.confidence, "high");
    }

    #[test]
    fn marks_boundary_with_hysteresis_tolerance() {
        let result = validate(test_geofence(), test_fix(12.97279, 77.5946, 35.0), None);

        assert_eq!(result.decision, GeofenceDecision::NearBoundary);
    }

    #[test]
    fn rejects_low_accuracy_join() {
        let result = validate(test_geofence(), test_fix(12.97161, 77.59461, 120.0), None);

        assert_eq!(result.decision, GeofenceDecision::LowAccuracy);
        assert_eq!(result.reason, Some("accuracy_too_low"));
    }

    #[test]
    fn buffers_first_outside_readings() {
        let result = validate_with_history(
            test_geofence(),
            test_fix(12.9740, 77.5946, 12.0),
            ValidationHistory {
                latest_fix: None,
                recent_fixes: [None, None, None],
                consecutive_outside: 1,
                previous_lifecycle: SessionLifecycleState::Inside,
            },
            false,
        );

        assert_eq!(result.decision, GeofenceDecision::NearBoundary);
        assert_eq!(result.lifecycle_state, SessionLifecycleState::NearBoundary);
        assert_eq!(result.consecutive_outside, 2);
    }

    #[test]
    fn exits_after_consecutive_outside_readings() {
        let result = validate_with_history(
            test_geofence(),
            test_fix(12.9740, 77.5946, 12.0),
            ValidationHistory {
                latest_fix: None,
                recent_fixes: [None, None, None],
                consecutive_outside: 2,
                previous_lifecycle: SessionLifecycleState::Inside,
            },
            false,
        );

        assert_eq!(result.decision, GeofenceDecision::Outside);
        assert_eq!(result.lifecycle_state, SessionLifecycleState::GracePeriod);
        assert_eq!(result.consecutive_outside, 3);
    }

    #[test]
    fn rejects_impossible_jump() {
        let now = Utc::now();
        let previous = LocationFix {
            point: Point {
                latitude: 12.9716,
                longitude: 77.5946,
            },
            accuracy_meters: Some(12.0),
            captured_at: now,
        };
        let current = LocationFix {
            point: Point {
                latitude: 13.1000,
                longitude: 77.5946,
            },
            accuracy_meters: Some(12.0),
            captured_at: now + Duration::seconds(3),
        };

        let result = validate_with_history(
            test_geofence(),
            current,
            ValidationHistory {
                latest_fix: Some(previous),
                recent_fixes: [Some(previous), None, None],
                consecutive_outside: 0,
                previous_lifecycle: SessionLifecycleState::Inside,
            },
            false,
        );

        assert_eq!(result.decision, GeofenceDecision::Rejected);
        assert_eq!(result.reason, Some("impossible_location_jump"));
    }

    #[test]
    fn rejects_mock_location_signal() {
        let result = validate_with_history(
            test_geofence(),
            test_fix(12.97161, 77.59461, 12.0),
            ValidationHistory {
                latest_fix: None,
                recent_fixes: [None, None, None],
                consecutive_outside: 0,
                previous_lifecycle: SessionLifecycleState::Joining,
            },
            true,
        );

        assert_eq!(result.decision, GeofenceDecision::Rejected);
        assert_eq!(result.reason, Some("mock_location_detected"));
    }

    fn test_geofence() -> Geofence {
        Geofence {
            center: Point {
                latitude: 12.9716,
                longitude: 77.5946,
            },
            radius_meters: 100,
        }
    }

    fn test_fix(latitude: f64, longitude: f64, accuracy_meters: f64) -> LocationFix {
        LocationFix {
            point: Point {
                latitude,
                longitude,
            },
            accuracy_meters: Some(accuracy_meters),
            captured_at: Utc::now(),
        }
    }
}
