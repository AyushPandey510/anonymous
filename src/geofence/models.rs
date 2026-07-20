use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Debug, Clone, Copy)]
pub struct Point {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, Copy)]
pub struct Geofence {
    pub center: Point,
    pub radius_meters: i32,
}

#[derive(Debug, Clone, Copy)]
pub struct LocationFix {
    pub point: Point,
    pub accuracy_meters: Option<f64>,
    pub captured_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy)]
pub struct PreviousLocationFix {
    pub fix: LocationFix,
}

#[derive(Debug, Clone, Copy)]
pub struct ValidationHistory {
    pub latest_fix: Option<LocationFix>,
    pub recent_fixes: [Option<LocationFix>; 3],
    pub consecutive_outside: usize,
    pub previous_lifecycle: SessionLifecycleState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GeofenceDecision {
    Inside,
    NearBoundary,
    Outside,
    LowAccuracy,
    Rejected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionLifecycleState {
    Joining,
    Inside,
    NearBoundary,
    GracePeriod,
    Outside,
    Expired,
}

#[derive(Debug, Clone)]
pub struct GeofenceValidation {
    pub decision: GeofenceDecision,
    pub lifecycle_state: SessionLifecycleState,
    pub distance_meters: f64,
    pub effective_radius_meters: f64,
    pub speed_meters_per_second: Option<f64>,
    pub confidence: &'static str,
    pub reason: Option<&'static str>,
    pub consecutive_outside: usize,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ValidateLocationRequest {
    pub space_id: Uuid,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: Option<f64>,
    pub client_timestamp: Option<DateTime<Utc>>,
    pub mock_location: Option<bool>,
    pub device_integrity: Option<String>,
    pub platform: Option<String>,
    pub app_version: Option<String>,
    pub gps_provider: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ValidateLocationResponse {
    pub decision: String,
    pub lifecycle_state: String,
    pub distance_meters: f64,
    pub effective_radius_meters: f64,
    pub speed_meters_per_second: Option<f64>,
    pub confidence: String,
    pub reason: Option<String>,
    pub consecutive_outside: usize,
    pub can_participate: bool,
}

impl GeofenceDecision {
    pub fn as_str(&self) -> &'static str {
        match self {
            GeofenceDecision::Inside => "inside",
            GeofenceDecision::NearBoundary => "near_boundary",
            GeofenceDecision::Outside => "outside",
            GeofenceDecision::LowAccuracy => "low_accuracy",
            GeofenceDecision::Rejected => "rejected",
        }
    }
}

impl SessionLifecycleState {
    pub fn as_str(&self) -> &'static str {
        match self {
            SessionLifecycleState::Joining => "joining",
            SessionLifecycleState::Inside => "inside",
            SessionLifecycleState::NearBoundary => "near_boundary",
            SessionLifecycleState::GracePeriod => "grace_period",
            SessionLifecycleState::Outside => "outside",
            SessionLifecycleState::Expired => "expired",
        }
    }
}

impl GeofenceValidation {
    pub fn can_participate(&self) -> bool {
        matches!(
            self.decision,
            GeofenceDecision::Inside | GeofenceDecision::NearBoundary
        ) || matches!(
            self.lifecycle_state,
            SessionLifecycleState::Inside
                | SessionLifecycleState::NearBoundary
                | SessionLifecycleState::GracePeriod
        )
    }
}
