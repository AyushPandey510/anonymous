use crate::{
    app::AppState,
    error::{ApiError, ApiResult},
};
use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
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
use validator::Validate;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,
    pub exp: usize,
}

#[derive(Debug, Deserialize, ToSchema, Validate)]
pub struct LoginRequest {
    #[validate(length(min = 7, max = 20))]
    pub phone_number: String,
    #[validate(length(min = 16, max = 256))]
    pub device_key: String,
}

#[derive(Debug, Serialize)]
pub struct LoginResponse {
    pub challenge_id: Uuid,
    pub expires_at: DateTime<Utc>,
    pub dev_otp: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct VerifyRequest {
    pub challenge_id: Uuid,
    pub phone_number: String,
    pub device_key: String,
    pub otp: String,
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
}

#[derive(Clone, Copy)]
pub struct AuthUser {
    pub id: Uuid,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/auth/login", post(login))
        .route("/auth/verify", post(verify))
        .route("/auth/refresh", post(refresh))
}

#[utoipa::path(post, path = "/auth/login", request_body = LoginRequest)]
pub async fn login(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginRequest>,
) -> ApiResult<Json<LoginResponse>> {
    payload
        .validate()
        .map_err(|error| ApiError::Validation(error.to_string()))?;
    let code = format!("{:06}", rand::thread_rng().gen_range(0..1_000_000));
    let code_hash = hash_secret(&code)?;
    let phone_lookup_hash = phone_lookup_hash(&payload.phone_number, &state.config.phone_pepper)?;
    let expires_at = Utc::now() + Duration::minutes(5);

    let challenge_id = sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO identity.otp_challenges (phone_lookup_hash, code_hash, expires_at) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(phone_lookup_hash)
    .bind(code_hash)
    .bind(expires_at)
    .fetch_one(&state.pool)
    .await?;

    Ok(Json(LoginResponse {
        challenge_id,
        expires_at,
        dev_otp: code,
    }))
}

#[utoipa::path(post, path = "/auth/verify", request_body = VerifyRequest, responses((status = 200, body = TokenResponse)))]
pub async fn verify(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<VerifyRequest>,
) -> ApiResult<Json<TokenResponse>> {
    let challenge = sqlx::query_as::<_, (String, DateTime<Utc>, Option<DateTime<Utc>>)>(
        "SELECT code_hash, expires_at, consumed_at FROM identity.otp_challenges WHERE id = $1",
    )
    .bind(payload.challenge_id)
    .fetch_optional(&state.pool)
    .await?
    .ok_or(ApiError::Unauthorized)?;

    if challenge.1 < Utc::now()
        || challenge.2.is_some()
        || !verify_secret(&payload.otp, &challenge.0)?
    {
        return Err(ApiError::Unauthorized);
    }

    sqlx::query("UPDATE identity.otp_challenges SET consumed_at = now() WHERE id = $1")
        .bind(payload.challenge_id)
        .execute(&state.pool)
        .await?;

    let phone_lookup = phone_lookup_hash(&payload.phone_number, &state.config.phone_pepper)?;
    let phone_hash = hash_secret(&payload.phone_number)?;
    let user_id = sqlx::query_scalar::<_, Uuid>(
        r#"
        INSERT INTO identity.users (phone_lookup_hash, phone_hash, device_key)
        VALUES ($1, $2, $3)
        ON CONFLICT (phone_lookup_hash) DO UPDATE SET device_key = EXCLUDED.device_key
        RETURNING id
        "#,
    )
    .bind(phone_lookup)
    .bind(phone_hash)
    .bind(payload.device_key)
    .fetch_one(&state.pool)
    .await?;

    issue_tokens(
        &state.pool,
        &state.config.jwt_secret,
        user_id,
        state.config.access_token_ttl,
        state.config.refresh_token_ttl,
    )
    .await
    .map(Json)
}

#[utoipa::path(post, path = "/auth/refresh", request_body = RefreshRequest, responses((status = 200, body = TokenResponse)))]
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

fn phone_lookup_hash(phone_number: &str, pepper: &str) -> ApiResult<String> {
    hash_lookup(&normalize_phone(phone_number), pepper)
}

fn normalize_phone(phone_number: &str) -> String {
    phone_number
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == '+')
        .collect()
}

fn hash_lookup(value: &str, secret: &str) -> ApiResult<String> {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(anyhow::Error::from)?;
    mac.update(value.as_bytes());
    Ok(hex::encode(mac.finalize().into_bytes()))
}

fn hash_secret(value: &str) -> ApiResult<String> {
    let salt = SaltString::generate(&mut rand::thread_rng());
    Argon2::default()
        .hash_password(value.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|error| ApiError::Internal(anyhow::anyhow!(error)))
}

fn verify_secret(value: &str, hash: &str) -> ApiResult<bool> {
    let parsed =
        PasswordHash::new(hash).map_err(|error| ApiError::Internal(anyhow::anyhow!(error)))?;
    Ok(Argon2::default()
        .verify_password(value.as_bytes(), &parsed)
        .is_ok())
}
