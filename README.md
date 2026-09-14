# Space

Anonymous location-aware communication app.

- **Backend**: Rust/Axum with PostgreSQL (SQLx)
- **Frontend**: Flutter mobile app (Android/iOS/Web/desktop)
- **Infrastructure**: Docker Compose (Postgres + Redis + backend + nginx)

Users are anonymous (device-bound identities only), get access to a "Space" only when their GPS location is inside its geofence, can chat in real time, vote in polls, and react to messages — all while the backend enforces location validity.

---

## Backend

### Tech Stack

| Component | Technology |
|---|---|
| Web framework | Axum (with WebSocket support) |
| Database | PostgreSQL 16 via SQLx (async) |
| Auth | Device-id registration, JWT (HS256), hashed opaque refresh tokens |
| Geofence | Haversine distance, median smoothing, spoof detection, hysteresis buffering, lifecycle state machine |
| Moderation | Keyword-based async worker (mpsc) |
| Realtime | In-memory per-space broadcast channels (`tokio::sync::broadcast`) |
| API docs | Utoipa + Swagger UI |
| Validation | `validator` crate (request payloads) |

### Features

- **Device auth** — register/login with a `device_id`; issues a JWT access token + hashed refresh token.
- **Spaces** — create public/private geofenced spaces (name, description, location, radius), discover nearby public spaces, join/leave, invite via one-time codes.
- **Chat** — REST message history + WebSocket realtime fan-out; replies (`reply_to`), emoji reactions, polls with voting, soft-delete of own messages, message reports.
- **Geofence engine** — server-authoritative location validation pipeline (see below) with an audit log.
- **Moderation** — async keyword classifier that hides hard-blocked content and flags soft violations.
- **Background workers** — session-expiry sweeper that rotates `active` → `expired` and `grace` → `expired` sessions.

### Configuration

All via environment variables (see `apps/backend/.env.example`):

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string |
| `JWT_SECRET` | — | HMAC/JWT signing secret (also keying refresh-token hashes) |
| `BIND_ADDR` | `0.0.0.0:8080` | HTTP listen address |
| `ACCESS_TOKEN_MINUTES` | `60` | JWT access token TTL |
| `REFRESH_TOKEN_DAYS` | `30` | Refresh token TTL |
| `SESSION_TTL_HOURS` | `2` | Active session lifetime while inside a space |
| `SESSION_GRACE_SECONDS` | `120` | Grace period after leaving before session expiry |
| `GEOFENCE_CHECK_INTERVAL_SECONDS` | `30` | Background geofence/session sweep interval |

### Run

```bash
cp .env.example .env
docker compose up -d --build
```

OpenAPI docs at `http://localhost:8080/docs`. Postgres is published on host port `55432`. The Flutter app lives in `apps/frontend/`; from the repo root use the wrapper: `.\flutter-frontend.ps1 run -d chrome` (or run `flutter` directly from `apps/frontend/`).

Native run (requires a local Postgres on `localhost:55432` and `sqlx-cli`):

```bash
cd apps/backend
sqlx migrate run
cargo run
```

Migrations also run automatically at startup via `sqlx::migrate!`.

### Local + Production Gateway

Docker Compose includes an nginx reverse proxy in front of the Rust backend so local development stays convenient while production looks like a real deployment.

#### Local development

```bash
cp .env.example .env
docker compose up -d --build
```

Then use:

| URL | Purpose |
|---|---|
| `http://localhost/health` | Backend health through nginx |
| `http://localhost/docs` | Swagger UI through nginx |
| `http://localhost/api-docs/openapi.json` | OpenAPI JSON through nginx |
| `ws://localhost/ws/spaces/{id}` | Chat WebSocket through nginx |

Flutter should also use nginx locally:

```bash
cd apps/frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost
```

For Android emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2
```

For a physical phone on the same Wi-Fi:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP
```

Local Compose also publishes these direct development ports via `docker-compose.override.yml` (loaded automatically for local runs):

| URL | Purpose |
|---|---|
| `http://localhost:8080` | Direct backend access, useful while debugging |
| `localhost:55432` | Direct Postgres access from local tools |

#### Production deployment

On a server, point your domain's DNS `A` record to the server IP first, then create a production `.env`:

```bash
cp .env.production.example .env
```

Edit `.env` and set:

| Variable | Production value |
|---|---|
| `SERVER_NAME` | Your API domain, for example `api.example.com` |
| `POSTGRES_PASSWORD` | Strong database password |
| `JWT_SECRET` | Long random secret |

For the first certificate, start nginx in HTTP bootstrap mode:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.bootstrap.yml up -d --build
```

Request the Let's Encrypt certificate:

```bash
set -a
. ./.env
set +a
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile certbot run --rm certbot certonly --webroot --webroot-path /var/www/certbot --cert-name space-api -d "$SERVER_NAME" --email you@example.com --agree-tos --no-eff-email
```

Then switch to the HTTPS production config:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Production exposes only nginx on ports `80` and `443`; backend and Postgres stay inside the Docker network. The production nginx config uses the fixed certificate name `space-api`, so the same nginx file works for any domain.

Renew certificates with:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile certbot run --rm certbot renew
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec nginx nginx -s reload
```

When building the Flutter app for people to use, point it at the public API:

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.example.com
```

Ways nginx helps this project:

| Use | How it applies here |
|---|---|
| Reverse proxy | Expose one public entrypoint while routing traffic to the Axum backend container. |
| HTTPS/TLS termination | Serve `https://api.yourdomain.com` with Certbot or mounted certificates while the backend stays on internal HTTP. |
| WebSocket proxying | Preserve `/ws/spaces/{id}` upgrades for real-time chat events. |
| API gateway | Route `/auth`, `/spaces`, `/messages`, `/geofence`, `/docs`, and `/api-docs` consistently through one host. |
| Static Flutter web hosting | Serve `apps/frontend/build/web` directly from nginx if you later publish the Flutter web app. |
| Rate limiting | Add stricter limits for auth, refresh tokens, chat posting, reports, and geofence validation. |
| Request size limits | Keep message/report payloads small with `client_max_body_size`. |
| Security headers | Add browser-facing protections for docs or future web builds. |
| Caching | Cache immutable Flutter web assets, icons, manifests, and map-related static assets. |
| Compression | Enable gzip/Brotli for OpenAPI JSON and Flutter web files. |
| Blue-green deploys | Route traffic between two backend versions during releases. |
| Observability | Centralize access logs, latency, client IPs, and upstream error tracking. |

### Database Schema

Two schemas:

- **`identity`** — users, refresh tokens, OTP challenges (legacy phone auth)
- **`activity`** — spaces, sessions, messages, reactions, reports, moderation events, location validation events, poll votes

**Tables:**

| Table | Schema | Purpose |
|---|---|---|
| `users` | identity | Device-registered users (`device_id`, `device_name`, `last_seen_at`) |
| `otp_challenges` | identity | Phone OTP challenges (legacy) |
| `refresh_tokens` | identity | JWT refresh token storage (HMAC-hashed token strings) |
| `spaces` | activity | Geofenced spaces (name, description, location, radius, visibility) |
| `space_invitations` | activity | Private space invite codes (`max_uses`, `uses`) |
| `sessions` | activity | User sessions in spaces (anonymous id, lifecycle state, consecutive-outside counter) |
| `messages` | activity | Chat messages with `reply_to`, `moderation_status`, and `poll_options` |
| `reactions` | activity | Emoji reactions on messages |
| `reports` | activity | Message reports (written; moderation review pending) |
| `moderation_events` | activity | Auto-moderation action log (category + severity) |
| `location_validation_events` | activity | Geofence check audit log (JSON metadata, spoofing score) |
| `poll_votes` | activity | Poll votes per user/message (`option_index`) |

**ENUM types:** `space_visibility` (public, private), `session_status` (active, grace, expired), `moderation_status` (clean, flagged, hidden), `report_status` (pending, reviewed, actioned, dismissed)

**Migrations:** `0001_init` (base schema) → `0002` (location validation events) → `0003` (extended event columns, index) → `0004` (device auth / users migration) → `0005` (polls) → `0006` (dedupe + unique active-membership guard)

### API Endpoints (21 routes)

#### Auth

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | No | Register/login via `device_id`; returns JWT + refresh token |
| `POST` | `/auth/refresh` | No | Exchange hashed refresh token for a new token pair |

#### Spaces

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/spaces` | Yes | Create a geofenced space (name 2–80, description 4–280, radius 30–300m) |
| `GET` | `/spaces/discover` | Yes | Discover nearby public spaces within geofences |
| `POST` | `/spaces/{id}/join` | Yes | Join a space (geofence check; private spaces require an invite code) |
| `POST` | `/spaces/{id}/leave` | Yes | Leave a space |
| `POST` | `/spaces/{id}/invitations` | Yes | Create an invite code for a space you own |
| `POST` | `/spaces/join-by-code` | Yes | Join a private space by invite code |
| `GET` | `/me/spaces` | Yes | List spaces I created |
| `GET` | `/me/joined-spaces` | Yes | List spaces I've joined |

#### Chat

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/spaces/{id}/messages` | Yes | List messages (max 100, excludes hidden/deleted) |
| `POST` | `/spaces/{id}/messages` | Yes | Send message (content 1–2000 chars, optional `reply_to`, optional poll) |
| `POST` | `/messages/{id}/report` | Yes | Report a message (reason 2–120 chars) |
| `POST` | `/messages/{id}/delete` | Yes | Soft-delete own message (within 15 min) |
| `POST` | `/messages/{id}/react` | Yes | React with an emoji (1–16 chars) |
| `POST` | `/messages/{id}/vote` | Yes | Vote on a message poll |
| `GET` | `/ws/spaces/{id}` | Yes | WebSocket: real-time `message`, `reaction`, `poll_updated` events |

#### Geofence

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/geofence/validate` | Yes | Full location validation with spoof detection, smoothing, hysteresis; updates session lifecycle |

#### System

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/health` | No | Health check |
| `GET` | `/docs` | No | Swagger UI |
| `GET` | `/api-docs/openapi.json` | No | OpenAPI spec |

### Auth Flow

1. First launch: client generates a UUID v4 `device_id` → `POST /auth/register` (upserts the user by `device_id`) → returns `user_id`, JWT access token, and an opaque refresh token.
2. Access token: signed HS256 JWT (`sub` = user id, `exp`), TTL configurable (default 60 min).
3. Refresh token: 64-char random string, stored **hashed** (`HMAC-SHA256(secret, token)`) in `identity.refresh_tokens`.
4. `POST /auth/refresh` exchanges a valid, unexpired, unrevoked refresh token for a fresh pair.
5. Authenticated handlers use the `AuthUser` extractor requiring `Authorization: Bearer <jwt>`.

### Geofence Engine

Server-authoritative location validation pipeline:

1. **Coordinate validation** — lat/lon bounds check
2. **Spoof detection** — `mock_location` flag, impossible jump (>500m in <5s), excessive speed
3. **Accuracy check** — max 75m for joining; up to 35m tolerance folded into the effective radius
4. **Haversine distance** — distance from geofence center
5. **Median smoothing** — filters GPS jitter across current + up to 3 recent fixes
6. **Distance classification** — inside, near-boundary, outside
7. **Hysteresis buffering** — 20m exit buffer, requires 3 consecutive outside readings
8. **Lifecycle state machine** — Joining → Inside → NearBoundary → GracePeriod → Outside → Expired
9. **Effective state reporting** — after each validation the real session status is re-read; once grace has elapsed the API returns `expired` / `can_participate: false` so clients auto-exit
10. **Audit logging** — every event persisted to `location_validation_events` with decision, reason, spoofing score, and JSON metadata

**Decision values:** `inside`, `near_boundary`, `outside`, `low_accuracy`, `rejected`

Validation history is loaded per (user, space) from the last 3 events to feed smoothing, outside-buffering, and lifecycle transitions.

### Moderation System

- Async worker consuming a `tokio::sync::mpsc` channel (256 capacity)
- Keyword-based classification:
  - **Hard block** (severe_safety): "kill myself", "self harm", "bomb threat", "shoot up" → `hidden`
  - **Soft flag** (toxicity): "idiot", "stupid", "harass" → `flagged`
  - Clean — no action
- Events logged to `moderation_events` with category and severity

### Background Workers

- **Session expiry sweeper** (every `GEOFENCE_CHECK_INTERVAL_SECONDS`, default 30s) — expires `active` sessions past `expires_at` and `grace` sessions past their grace expiry.
- **Moderation worker** — consumes moderation jobs from the in-memory queue.

### Error Handling

| Error | HTTP | Description |
|---|---|---|
| `Unauthorized` | 401 | Missing/invalid auth token |
| `Forbidden` | 403 | Not allowed (geofence rejected, not in space) |
| `NotFound` | 404 | Space/message not found |
| `Validation` | 400 | Payload validation failed |
| `Conflict` | 409 | Max spaces reached per location |
| `Db` / `Internal` | 500 | Server errors |

### Tests

Pure-Rust unit tests (no DB required), ~20 across 8 modules:

- Moderation classification (hard block, soft flag)
- Chat poll option validation
- Space radius caps (30–300m) and payload validation
- Geofence: inside, near-boundary tolerance, low accuracy, outside buffering, impossible jump, mock location, speed check, lifecycle resolution
- Haversine contains near/far
- Median smoothing spike rejection
- Spoof detection speed computation

---

## Frontend

### Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter with Material 3 |
| Maps | flutter_map + OpenStreetMap tiles |
| Geocoding | Nominatim (debounced search, reverse geocode) |
| Location | geolocator (GPS) |
| HTTP | http package with JWT auto-refresh |
| Realtime | web_socket_channel |
| Persistence | SharedPreferences |
| Geofence | Client-side validation engine matching backend logic |

### App Loader (Splash)

`AppLoader` bootstraps the app:

- Builds the API client, auth service, and api service
- Registers the device on first launch (UUID v4) or restores persisted tokens
- Shows an animated orbit splash (minimum 2.6s) while initializing
- Full-screen error state with **Retry** on auth failure

### Location Selection

Interactive OpenStreetMap screen (dark themed tiles) with:

- Location permission request and services-detection handling
- Fixed center pin plus drag-to-move and long-press to place a point
- Search bar with Nominatim geocoding (debounced) and result selection
- GPS "My Location" button with live accuracy readout
- Zoom in/out controls
- Geofence radius circle overlay with animated transitions
- Live validation status panel (decision, distance, radius, confidence)
- "Use this location" action that persists the chosen coordinates to SharedPreferences

### Space Discovery

- Discovers nearby public spaces via `/spaces/discover`
- States: loading, error (with retry), empty (with "Create a Space"), populated
- Space cards: name, distance, member count, joined badge
- Tap to join (or re-join) and enter chat
- **Invite-code join** dialog for private spaces
- Header actions: change location, toggle light/dark theme
- Gradient FAB opens Create Space

### Create Space

Multi-step flow:

- **Step 1 — Details**: name (min 2 chars) and description (min 4 chars) with live validation
- **Step 2 — Visibility**: public / private toggle
- **Step 3 — Geofence radius**: slider from 30m–300m with real-time validation status
- **Create** with loading state; creator is auto-joined after creation
- Private spaces surface an **invite code** after creation

### My Spaces (tab)

- Bottom navigation: Discover / My Spaces
- Lists spaces you've created (`/me/spaces`) and joined (`/me/joined-spaces` — active sessions)
- Tap a space to re-join and open chat
- **Invite codes shown to owners** of private spaces
- Leave action with confirmation dialog
- States: loading, error (with retry), empty, populated

### Chat

- Header: space name, anonymous name, theme toggle, leave
- Message history (REST) with loading/empty states
- Message cards: colored dot, anonymous name, text, reply quote, reaction chips, poll UI
- **Long-press** a message → action sheet: Reply, 6 reactions (👍 ❤️ 😄 😂 🔥 🎉), Delete (own messages only), Report
- **Delete own message**: confirmation dialog, only within 15 min of sending (backend-enforced 403 otherwise)
- **Report**: reason picker (Spam, Harassment, Hate speech, Inappropriate content, Other)
- **Reply composer** with "Replying to…" banner and cancel
- **Polls**: compose 2–6 distinct options (≤100 chars each), vote, live per-option counts, changeable vote
- **Real-time** messages/reactions/poll updates via WebSocket (auto-reconnect with exponential backoff, typed events)
- Android back-button intercepted to leave the chat safely
- **Geofence exit policing**: 30-second location polling; on `can_participate: false` a non-dismissible alert explains the exit and auto-leaves the space

### API Integration

| Method | Endpoint | Usage |
|---|---|---|
| `POST` | `/auth/register` | Device registration on first launch |
| `POST` | `/auth/refresh` | Token refresh on 401 |
| `GET` | `/spaces/discover` | Discover nearby spaces |
| `POST` | `/spaces` | Create a space |
| `POST` | `/spaces/{id}/join` | Join (or re-join) a space |
| `POST` | `/spaces/{id}/leave` | Leave a space |
| `POST` | `/spaces/join-by-code` | Join private space via invite code |
| `GET` | `/me/spaces` | My Spaces tab (owned) |
| `GET` | `/me/joined-spaces` | My Spaces tab (joined) |
| `GET` | `/spaces/{id}/messages` | Get chat messages |
| `POST` | `/spaces/{id}/messages` | Send a message (optional `reply_to`, optional poll) |
| `POST` | `/messages/{id}/react` | React to a message |
| `POST` | `/messages/{id}/vote` | Vote on a poll |
| `POST` | `/messages/{id}/delete` | Soft-delete own message |
| `POST` | `/messages/{id}/report` | Report a message (reason) |
| `GET` | `/ws/spaces/{id}` | Real-time chat, reactions, polls |
| `POST` | `/geofence/validate` | Geofence exit monitoring |

### Geofence Validation Engine (Client)

Client-side implementation matching the backend's algorithm, used for instant on-screen feedback (the server remains the authority):

- Haversine distance, median-smoothed location fixes, accuracy-adjusted effective radius
- 5 decisions: inside, nearBoundary, outside, lowAccuracy, rejected
- Lifecycle state machine: joining, inside, nearBoundary, gracePeriod, outside, expired
- Consecutive-outside buffering (3 required), grace period
- Impossible-jump detection, excessive speed, mock-location checks

### Authentication & Persistence

1. First launch: generate UUID v4 device ID → `POST /auth/register` → store JWT tokens
2. Subsequent launches: load from SharedPreferences → reconnect/refresh
3. On 401 (any request): auto-refresh via `/auth/refresh` → retry the original request once
4. Chat socket reads the token fresh on every (re)connect so it uses the latest token
5. Tokens persisted: `device_id`, `access_token`, `refresh_token`, `user_id`, plus `selected_latitude` / `selected_longitude`

Base URL selection: `API_BASE_URL` via `--dart-define` wins; otherwise emulator, physical-device, or production constants in `lib/config/app_config.dart`.

### WebSocket Events

| Type | Payload | Description |
|---|---|---|
| `message` | `{ type: "message", message: { id, space_id, anonymous_id, content, reply_to, reply_content, created_at, moderation_status, reactions[], poll } }` | New chat message |
| `reaction` | `{ type: "reaction", message_id, emoji, count }` | Reaction count update |
| `poll_updated` | `{ type: "poll_updated", message_id }` | Poll changed; client re-fetches messages |

### Design System

Material 3 with a light and a dark theme (dark is default). Custom `ThemeExtension` tokens:

| Token family | Examples | Usage |
|---|---|---|
| Backgrounds | `background`, `surface`, `surface2`, `surface3`, `card`, `navBackground`, `chipBackground` | Scaffolds, surfaces, cards, navigation |
| Text | `primaryText`, `secondaryText`, `disabled` | Text hierarchy |
| Accents | `accent` (`#0xFFADC6FF` main – blue), `secondaryAccent`, `tertiary`, `onAccent` | Buttons, highlights |
| Status | `danger`, `warning`, `dangerStrong` | Errors, destructive actions |
| Lines | `outline`, `outlineSubtle` | Borders, dividers |
| Gradients | `gradientTop` → `gradientBottom` | Radial background (`#13211F` → `#0B0B0C` in dark) |

Typography declares `Montserrat` (display), `Hanken Grotesk` (body), and `JetBrains Mono` (technical) families; these are not bundled in `pubspec.yaml`, so Flutter falls back to system fonts until font assets are added. Consistent 19px / 22px border radius, pill-shaped buttons, custom dialog/bottom-sheet/snackbar theming.

### Tests

- **Widget tests** (~21): app boot/splash, discovery render + join, chat over WebSocket (message send, dedupe, reactions, replies with failure-restore, delete own message, report flow), My Spaces list/open/empty/leave, owned-spaces invite visibility, poll composer + voting
- **API client tests**: `getList` auto-refresh on 401 and retry with rotated token, 401 when refresh rejected, `createSpace` payload
- **Geofence validator tests**: inside, boundary, low accuracy, impossible jump, outside buffering (3 consecutive), grace period, mock location, excessive speed
- **Orbit animation tests**: splash renders across widths/brightnesses

---

## Infrastructure

### Docker Compose

| Service | Image | Purpose |
|---|---|---|
| `postgres` | postgres:16-alpine | Database (published on host `55432` in dev) |
| `redis` | redis:7-alpine | Cache/queue (reserved; not yet used by backend) |
| `backend` | multi-stage Rust build | Axum API server |
| `nginx` | nginx:1.27-alpine | Reverse proxy / TLS gateway |

Full Dockerfile (see `apps/backend/Dockerfile`): multi-stage — `rust:1.89-slim-bookworm` builder → `debian:bookworm-slim` runner producing the `space-backend` binary (deps cached via a dummy `main.rs` for fast rebuilds).