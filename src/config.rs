use std::{env, time::Duration};

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub bind_addr: String,
    pub access_token_ttl: Duration,
    pub refresh_token_ttl: Duration,
    pub session_ttl: Duration,
    pub session_grace: Duration,
    pub geofence_check_interval: Duration,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            database_url: env::var("DATABASE_URL")?,
            jwt_secret: env::var("JWT_SECRET")?,
            bind_addr: env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".to_string()),
            access_token_ttl: Duration::from_secs(env_u64("ACCESS_TOKEN_MINUTES", 60) * 60),
            refresh_token_ttl: Duration::from_secs(
                env_u64("REFRESH_TOKEN_DAYS", 30) * 24 * 60 * 60,
            ),
            session_ttl: Duration::from_secs(env_u64("SESSION_TTL_HOURS", 2) * 3600),
            session_grace: Duration::from_secs(env_u64("SESSION_GRACE_SECONDS", 120)),
            geofence_check_interval: Duration::from_secs(env_u64("GEOFENCE_CHECK_INTERVAL_SECONDS", 30)),
        })
    }
}

fn env_u64(name: &str, fallback: u64) -> u64 {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(fallback)
}
