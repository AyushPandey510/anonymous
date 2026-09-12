use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Serialize, Deserialize, ToSchema)]
pub struct ReactionSummary {
    pub emoji: String,
    pub count: i64,
}

#[derive(Serialize, sqlx::FromRow, ToSchema)]
pub struct Space {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub visibility: String,
    pub latitude: f64,
    pub longitude: f64,
    pub radius_meters: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, sqlx::FromRow, ToSchema)]
pub struct Session {
    pub id: Uuid,
    pub space_id: Uuid,
    pub anonymous_id: String,
    pub expires_at: DateTime<Utc>,
    pub status: String,
}

#[derive(Serialize, sqlx::FromRow, ToSchema)]
pub struct Message {
    #[sqlx(default)]
    pub poll: Option<serde_json::Value>,
    pub id: Uuid,
    pub space_id: Uuid,
    pub anonymous_id: String,
    pub content: String,
    pub reply_to: Option<Uuid>,
    #[sqlx(default)]
    #[serde(default)]
    pub reply_content: Option<String>,
    pub created_at: DateTime<Utc>,
    pub moderation_status: String,
    #[sqlx(default)]
    #[serde(default)]
    pub reactions: Json<Vec<ReactionSummary>>,
}
