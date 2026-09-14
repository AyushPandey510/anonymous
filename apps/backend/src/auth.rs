use crate::{
    app::AppState,
    error::{ApiError, ApiResult},
};
use async_trait::async_trait;
use axum::{
    extract::{FromRequestParts, State},
    http::request::Parts,
    routing::post,
    Json, Router,
};
use chrono::{DateTime, Duration, Utc};
use hmac::{Hmac, Mac};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use rand::{distributions::Alphanumeric, Rng};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use sqlx::PgPool;
use std::sync::Arc;
use utoipa::ToSchema;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    pub exp: usize,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RegisterRequest {
    pub device_id: String,
    pub device_name: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub user_id: Uuid,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RegisterResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub user_id: Uuid,
    pub is_new: bool,
}

#[derive(Clone, Copy)]
pub struct AuthUser {
    pub id: Uuid,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/refresh", post(refresh))
}

pub async fn migrate_plaintext_device_ids(pool: &PgPool, secret: &str) -> ApiResult<u64> {
    let rows = sqlx::query_as::<_, (Uuid, String)>(
        r#"
        SELECT id, device_id
        FROM identity.users
        WHERE device_id IS NOT NULL
        "#,
    )
    .fetch_all(pool)
    .await?;

    let mut migrated = 0;
    for (id, device_id) in rows {
        let device_id_hash = hash_lookup(&device_id, secret)?;
        let result = sqlx::query(
            r#"
            UPDATE identity.users
            SET device_id_hash = CASE
                    WHEN device_id_hash IS NOT NULL THEN device_id_hash
                    WHEN EXISTS (
                        SELECT 1
                        FROM identity.users other
                        WHERE other.device_id_hash = $2
                          AND other.id <> $1
                    ) THEN device_id_hash
                    ELSE $2
                END,
                device_name = CASE
                    WHEN device_name LIKE 'Space-%' THEN NULL
                    ELSE device_name
                END,
                device_id = NULL
            WHERE id = $1
              AND device_id IS NOT NULL
            "#,
        )
        .bind(id)
        .bind(device_id_hash)
        .execute(pool)
        .await?;
        migrated += result.rows_affected();
    }

    Ok(migrated)
}

#[utoipa::path(post, path = "/auth/register", request_body = RegisterRequest)]
pub async fn register(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterRequest>,
) -> ApiResult<Json<RegisterResponse>> {
    if payload.device_id.trim().is_empty() {
        return Err(ApiError::Validation("device_id is required".to_string()));
    }
    // Keep the request shape stable, but do not store device names as identifiers.
    let _device_name = &payload.device_name;

    let device_id_hash = hash_lookup(&payload.device_id, &state.config.jwt_secret)?;
    let existing = sqlx::query_as::<_, (Uuid,)>(
        r#"
        SELECT id
        FROM identity.users
        WHERE device_id_hash = $1 OR device_id = $2
        ORDER BY CASE WHEN device_id_hash = $1 THEN 0 ELSE 1 END
        LIMIT 1
        "#,
    )
    .bind(&device_id_hash)
    .bind(&payload.device_id)
    .fetch_optional(&state.pool)
    .await?;

    let (user_id, is_new) = if let Some((id,)) = existing {
        sqlx::query(
            r#"
            UPDATE identity.users
            SET last_seen_at = now(),
                device_name = CASE
                    WHEN device_name LIKE 'Space-%' THEN NULL
                    ELSE device_name
                END,
                device_id_hash = $2,
                device_id = NULL
            WHERE id = $1
            "#,
        )
        .bind(id)
        .bind(&device_id_hash)
        .execute(&state.pool)
        .await?;
        (id, false)
    } else {
        let id = sqlx::query_scalar::<_, Uuid>(
            r#"
            INSERT INTO identity.users (device_id_hash)
            VALUES ($1)
            RETURNING id
            "#,
        )
        .bind(&device_id_hash)
        .fetch_one(&state.pool)
        .await?;
        (id, true)
    };

    let tokens = issue_tokens(
        &state.pool,
        &state.config.jwt_secret,
        user_id,
        state.config.access_token_ttl,
        state.config.refresh_token_ttl,
    )
    .await?;

    Ok(Json(RegisterResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type,
        user_id,
        is_new,
    }))
}

#[utoipa::path(post, path = "/auth/refresh", request_body = RefreshRequest)]
pub async fn refresh(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RefreshRequest>,
) -> ApiResult<Json<TokenResponse>> {
    let token_hash = hash_lookup(&payload.refresh_token, &state.config.jwt_secret)?;
    let row = sqlx::query_as::<_, (Uuid, DateTime<Utc>, Option<DateTime<Utc>>)>(
        "SELECT user_id, expires_at, revoked_at FROM identity.refresh_tokens WHERE token_hash = $1",
    )
    .bind(token_hash)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::Unauthorized)?;

    if row.1 < Utc::now() || row.2.is_some() {
        return Err(ApiError::Unauthorized);
    }
    issue_tokens(
        &state.pool,
        &state.config.jwt_secret,
        row.0,
        state.config.access_token_ttl,
        state.config.refresh_token_ttl,
    )
    .await
    .map(Json)
}

async fn issue_tokens(
    pool: &PgPool,
    jwt_secret: &str,
    user_id: Uuid,
    access_ttl: std::time::Duration,
    refresh_ttl: std::time::Duration,
) -> ApiResult<TokenResponse> {
    let exp = (Utc::now() + Duration::from_std(access_ttl).map_err(anyhow::Error::from)?)
        .timestamp() as usize;
    let access_token = encode(
        &Header::default(),
        &Claims { sub: user_id, exp },
        &EncodingKey::from_secret(jwt_secret.as_bytes()),
    )
    .map_err(anyhow::Error::from)?;
    let refresh_token: String = rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(64)
        .map(char::from)
        .collect();
    let refresh_hash = hash_lookup(&refresh_token, jwt_secret)?;
    let refresh_exp = Utc::now() + Duration::from_std(refresh_ttl).map_err(anyhow::Error::from)?;

    sqlx::query(
        "INSERT INTO identity.refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)",
    )
    .bind(user_id)
    .bind(refresh_hash)
    .bind(refresh_exp)
    .execute(pool)
    .await?;

    Ok(TokenResponse {
        access_token,
        refresh_token,
        token_type: "Bearer".to_string(),
        user_id,
    })
}

#[async_trait]
impl FromRequestParts<Arc<AppState>> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &Arc<AppState>,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .ok_or(ApiError::Unauthorized)?;
        let token = header
            .strip_prefix("Bearer ")
            .ok_or(ApiError::Unauthorized)?;
        let claims = decode::<Claims>(
            token,
            &DecodingKey::from_secret(state.config.jwt_secret.as_bytes()),
            &Validation::default(),
        )
        .map_err(|_| ApiError::Unauthorized)?
        .claims;
        Ok(AuthUser { id: claims.sub })
    }
}

fn hash_lookup(value: &str, secret: &str) -> ApiResult<String> {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(anyhow::Error::from)?;
    mac.update(value.as_bytes());
    Ok(hex::encode(mac.finalize().into_bytes()))
}
