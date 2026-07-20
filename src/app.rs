use crate::{auth, chat, config::Config, geofence, models, moderation, spaces};
use axum::{routing::get, Json, Router};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
    pub moderation_tx: tokio::sync::mpsc::Sender<moderation::ModerationJob>,
}

pub fn build_router(pool: PgPool, config: Config) -> Router {
    let (moderation_tx, moderation_rx) = tokio::sync::mpsc::channel(256);
    tokio::spawn(moderation::worker(pool.clone(), moderation_rx));
    let state = Arc::new(AppState {
        pool,
        config,
        moderation_tx,
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

#[derive(OpenApi)]
#[openapi(
    paths(
        auth::login,
        auth::verify,
        auth::refresh,
        spaces::create_space,
        spaces::discover_spaces,
        spaces::join_space,
        spaces::leave_space,
        geofence::api::validate_location,
        chat::list_messages,
        chat::send_message,
        chat::report_message
    ),
    components(schemas(
        auth::LoginRequest,
        auth::VerifyRequest,
        auth::TokenResponse,
        spaces::CreateSpaceRequest,
        spaces::DiscoverQuery,
        spaces::JoinSpaceRequest,
        geofence::ValidateLocationRequest,
        geofence::ValidateLocationResponse,
        chat::SendMessageRequest,
        chat::ReportMessageRequest,
        models::Space,
        models::Session,
        models::Message
    ))
)]
struct ApiDoc;
