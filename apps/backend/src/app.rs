use crate::{auth, chat, config::Config, geofence, models, moderation, spaces};
use axum::{routing::get, Json, Router};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;
use tower_http::cors::CorsLayer;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;
use uuid::Uuid;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
    pub moderation_tx: tokio::sync::mpsc::Sender<moderation::ModerationJob>,
    pub room_broadcasts: Arc<Mutex<HashMap<Uuid, broadcast::Sender<String>>>>,
}

impl AppState {
    pub fn broadcast_sender(&self, space_id: Uuid) -> broadcast::Sender<String> {
        let mut rooms = self.room_broadcasts.lock().unwrap();
        rooms
            .entry(space_id)
            .or_insert_with(|| broadcast::channel(256).0)
            .clone()
    }
}

pub fn build_router(pool: PgPool, config: Config) -> Router {
    let (moderation_tx, moderation_rx) = tokio::sync::mpsc::channel(256);
    tokio::spawn(moderation::worker(pool.clone(), moderation_rx));

    let state = Arc::new(AppState {
        pool: pool.clone(),
        config: config.clone(),
        moderation_tx,
        room_broadcasts: Arc::new(Mutex::new(HashMap::new())),
    });

    let worker_state = state.clone();
    tokio::spawn(async move {
        geofence_session_worker(worker_state).await;
    });

    Router::new()
        .route("/health", get(health))
        .merge(auth::router())
        .merge(spaces::router())
        .merge(chat::router())
        .merge(geofence::router())
        .merge(SwaggerUi::new("/docs").url("/api-docs/openapi.json", ApiDoc::openapi()))
        .layer(CorsLayer::permissive())
        .with_state(state)
}

async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

async fn geofence_session_worker(state: Arc<AppState>) {
    let interval = state.config.geofence_check_interval;
    loop {
        tokio::time::sleep(interval).await;
        if let Err(e) = expire_stale_sessions(&state.pool).await {
            tracing::warn!(%e, "session expiry worker error");
        }
    }
}

async fn expire_stale_sessions(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE activity.sessions
        SET status = 'expired', expires_at = now()
        WHERE status = 'active'
          AND expires_at < now()
        "#,
    )
    .execute(pool)
    .await?;

    let expired = sqlx::query_scalar::<_, i64>(
        r#"
        WITH expired AS (
          UPDATE activity.sessions
          SET status = 'expired', expires_at = now()
          WHERE status = 'grace'
            AND expires_at < now()
          RETURNING space_id
        )
        SELECT COUNT(*) FROM expired
        "#,
    )
    .fetch_one(pool)
    .await?;

    if expired > 0 {
        tracing::info!(%expired, "expired grace sessions");
    }

    Ok(())
}

#[derive(OpenApi)]
#[openapi(
    paths(
        auth::register,
        auth::refresh,
        spaces::create_space,
        spaces::discover_spaces,
        spaces::create_invitation,
        spaces::join_space_by_invite,
        spaces::join_space,
        spaces::leave_space,
        geofence::api::validate_location,
        chat::list_messages,
        chat::send_message,
        chat::vote_poll,
        chat::report_message
    ),
    components(schemas(
        auth::RegisterRequest,
        auth::TokenResponse,
        auth::RegisterResponse,
        spaces::CreateSpaceRequest,
        spaces::CreateSpaceResponse,
        spaces::DiscoverQuery,
        spaces::InviteCodeResponse,
        spaces::JoinByInviteRequest,
        spaces::JoinByInviteResponse,
        spaces::JoinSpaceRequest,
        spaces::SpaceWithDistance,
        spaces::LeaveResponse,
        geofence::ValidateLocationRequest,
        geofence::ValidateLocationResponse,
        chat::SendMessageRequest,
        chat::VoteRequest,
        chat::ReportMessageRequest,
        models::Space,
        models::Session,
        models::Message
    ))
)]
struct ApiDoc;
