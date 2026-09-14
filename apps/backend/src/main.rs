mod app;
mod auth;
mod chat;
mod config;
mod error;
mod geofence;
mod models;
mod moderation;
mod spaces;

use crate::{app::build_router, config::Config};
use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "space_backend=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = Config::from_env()?;
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await
        .context("connect to postgres")?;
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .context("run migrations")?;
    let migrated_devices = auth::migrate_plaintext_device_ids(&pool, &config.jwt_secret).await?;
    if migrated_devices > 0 {
        tracing::info!(%migrated_devices, "hashed legacy device ids");
    }

    let app = build_router(pool, config.clone()).layer(TraceLayer::new_for_http());
    let listener = TcpListener::bind(&config.bind_addr).await?;
    tracing::info!("listening on {}", config.bind_addr);
    axum::serve(listener, app).await?;
    Ok(())
}
