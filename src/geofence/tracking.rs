use super::models::{GeofenceDecision, SessionLifecycleState};

pub fn lifecycle_for_decision(
    decision: GeofenceDecision,
    previous: SessionLifecycleState,
) -> SessionLifecycleState {
    match decision {
        GeofenceDecision::Inside => SessionLifecycleState::Inside,
        GeofenceDecision::NearBoundary => SessionLifecycleState::NearBoundary,
        GeofenceDecision::Outside => match previous {
            SessionLifecycleState::Inside | SessionLifecycleState::NearBoundary => {
                SessionLifecycleState::GracePeriod
            }
            SessionLifecycleState::GracePeriod => SessionLifecycleState::GracePeriod,
            _ => SessionLifecycleState::Outside,
        },
        GeofenceDecision::LowAccuracy => previous,
        GeofenceDecision::Rejected => SessionLifecycleState::Outside,
    }
}
