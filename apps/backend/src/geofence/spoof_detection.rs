use super::{geometry::distance_meters, models::LocationFix};

pub const JUMP_THRESHOLD_M: f64 = 500.0;
pub const JUMP_WINDOW_SECONDS: i64 = 5;
pub const WALKING_SPEED_REJECT_MPS: f64 = 55.56; // 200 km/h
pub const HARD_SPEED_REJECT_MPS: f64 = 138.89; // 500 km/h

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SpoofSignal {
    None,
    MockLocation,
    ImpossibleJump,
    ExcessiveSpeed,
}

pub fn speed_meters_per_second(previous: LocationFix, current: LocationFix) -> Option<f64> {
    let elapsed = (current.captured_at - previous.captured_at)
        .num_milliseconds()
        .abs() as f64
        / 1000.0;
    if elapsed <= 0.0 {
        return None;
    }
    Some(distance_meters(previous.point, current.point) / elapsed)
}

pub fn detect_spoofing(
    previous: Option<LocationFix>,
    current: LocationFix,
    mock_location: bool,
) -> (SpoofSignal, Option<f64>) {
    if mock_location {
        return (SpoofSignal::MockLocation, None);
    }

    let Some(previous) = previous else {
        return (SpoofSignal::None, None);
    };

    let Some(speed) = speed_meters_per_second(previous, current) else {
        return (SpoofSignal::None, None);
    };

    let elapsed_seconds = (current.captured_at - previous.captured_at)
        .num_seconds()
        .abs();
    let distance = distance_meters(previous.point, current.point);
    if elapsed_seconds <= JUMP_WINDOW_SECONDS && distance > JUMP_THRESHOLD_M {
        return (SpoofSignal::ImpossibleJump, Some(speed));
    }
    if speed > HARD_SPEED_REJECT_MPS || speed > WALKING_SPEED_REJECT_MPS {
        return (SpoofSignal::ExcessiveSpeed, Some(speed));
    }

    (SpoofSignal::None, Some(speed))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geofence::models::Point;
    use chrono::{Duration, Utc};

    #[test]
    fn computes_speed_and_rejects_fast_jump() {
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
                latitude: 13.1,
                longitude: 77.5946,
            },
            accuracy_meters: Some(12.0),
            captured_at: now + Duration::seconds(3),
        };

        let (signal, speed) = detect_spoofing(Some(previous), current, false);

        assert_eq!(signal, SpoofSignal::ImpossibleJump);
        assert!(speed.unwrap() > HARD_SPEED_REJECT_MPS);
    }
}
