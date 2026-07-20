# Space Backend

Rust/Axum MVP backend for the Space SRS v1.1.

## Run

```bash
cp .env.example .env
docker compose up -d
sqlx migrate run
cargo run
```

OpenAPI docs are served at `http://localhost:8080/docs`. The Compose Postgres instance is published on host port `55432` to avoid colliding with any local Postgres.

## Implemented MVP Surface

- Phone OTP auth scaffold with separated identity storage.
- JWT access and refresh tokens.
- Create/discover/join/leave spaces with geofence validation.
- Dedicated `POST /geofence/validate` endpoint with accuracy tolerance, near-boundary decisions, low-accuracy handling, and impossible-jump rejection.
- One active space per creator and ten nearby active spaces per location.
- Messages, replies, own recent deletion, and reporting.
- Asynchronous moderation worker hook with severe auto-hide behavior.
