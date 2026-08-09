use super::models::{Geofence, GeofenceDecision};

pub const EXIT_BUFFER_METERS: f64 = 20.0;
pub const REQUIRED_OUTSIDE_READINGS: usize = 3;

pub fn classify_distance(
    geofence: Geofence,
    distance_meters: f64,
    effective_radius_meters: f64,
) -> GeofenceDecision {
    let enter_threshold = geofence.radius_meters as f64;
    let exit_threshold = geofence.radius_meters as f64 + EXIT_BUFFER_METERS;

    if distance_meters <= enter_threshold {
        GeofenceDecision::Inside
    } else if distance_meters <= effective_radius_meters.max(exit_threshold) {
        GeofenceDecision::NearBoundary
    } else {
        GeofenceDecision::Outside
    }
}

pub fn buffered_outside_decision(
    raw_decision: GeofenceDecision,
    consecutive_outside: usize,
) -> (GeofenceDecision, usize) {
    match raw_decision {
        GeofenceDecision::Outside => {
            let next_count = consecutive_outside + 1;
            if next_count >= REQUIRED_OUTSIDE_READINGS {
                (GeofenceDecision::Outside, next_count)
            } else {
                (GeofenceDecision::NearBoundary, next_count)
            }
        }
        GeofenceDecision::Inside | GeofenceDecision::NearBoundary => (raw_decision, 0),
        GeofenceDecision::LowAccuracy | GeofenceDecision::Rejected => {
            (raw_decision, consecutive_outside)
        }
    }
}
