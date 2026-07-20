use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

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
    pub id: Uuid,
    pub space_id: Uuid,
    pub anonymous_id: String,
    pub content: String,
    pub reply_to: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub moderation_status: String,
}
