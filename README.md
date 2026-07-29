# Space

Anonymous location-aware communication app.

- **Backend**: Rust/Axum with PostgreSQL (SQLx)
- **Frontend**: Flutter mobile app (Android/iOS)
- **Infrastructure**: Docker Compose (Postgres + Redis + backend)

---

## Backend

### Tech Stack

| Component | Technology |
|---|---|
| Web framework | Axum (with WebSocket support) |
| Database | PostgreSQL via SQLx |
| Auth | Argon2, JWT (HS256), refresh token rotation |
| Geofence | Haversine distance, median smoothing, hysteresis buffering |
| Moderation | Keyword-based async worker |
| API docs | Utoipa + Swagger UI |

### Configuration

All via environment variables (see `.env.example`):

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string |
| `JWT_SECRET` | — | HMAC/JWT signing secret |
| `BIND_ADDR` | `0.0.0.0:8080` | HTTP listen address |
| `ACCESS_TOKEN_MINUTES` | `60` | JWT access token TTL |
| `REFRESH_TOKEN_DAYS` | `30` | Refresh token TTL |
| `SESSION_GRACE_SECONDS` | `120` | Grace period before session expiry |
| `GEOFENCE_CHECK_INTERVAL_SECONDS` | `30` | Background geofence sweep interval |

### Run

```bash
cp .env.example .env
docker compose up -d
sqlx migrate run
cargo run
```

OpenAPI docs at `http://localhost:8080/docs`. Postgres published on host port `55432`.

### Database Schema

Two schemas:

- **`identity`** — users, refresh tokens, OTP challenges
- **`activity`** — spaces, sessions, messages, reactions, reports, moderation events, location validation events

**Tables:**

| Table | Schema | Purpose |
|---|---|---|
| `users` | identity | Device-registered users (device_id, display_name) |
| `otp_challenges` | identity | Phone OTP challenges (legacy) |
| `refresh_tokens` | identity | JWT refresh token storage (hashed) |
| `spaces` | activity | Geofenced spaces (name, location, radius, visibility) |
| `space_invitations` | activity | Private space invite codes |
| `sessions` | activity | User sessions in spaces (anonymous_id, lifecycle_state) |
| `messages` | activity | Chat messages with reply_to and moderation_status |
| `reactions` | activity | Emoji reactions on messages |
| `reports` | activity | Message reports |
| `moderation_events` | activity | Auto-moderation action log |
| `location_validation_events` | activity | Geofence check audit log |

**ENUM types:** `space_visibility` (public, private), `session_status` (active, grace, expired), `moderation_status` (clean, flagged, hidden), `report_status` (pending, reviewed, actioned, dismissed)

### API Endpoints (17 routes)

#### Auth

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | No | Register/login via device_id, returns JWT + refresh token |
| `POST` | `/auth/refresh` | No | Exchange refresh token for new token pair |

#### Spaces

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/spaces` | Yes | Create a geofenced space (name, visibility, location, radius) |
| `GET` | `/spaces/discover` | Yes | Discover nearby public spaces within geofences |
| `POST` | `/spaces/{id}/join` | Yes | Join a space (geofence check, invite_code for private) |
| `POST` | `/spaces/{id}/leave` | Yes | Leave a space |
| `GET` | `/me/spaces` | Yes | List spaces I created |
| `GET` | `/me/joined-spaces` | Yes | List spaces I've joined |

#### Chat

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/spaces/{id}/messages` | Yes | List messages (max 100, excludes hidden/deleted) |
| `POST` | `/spaces/{id}/messages` | Yes | Send message (content 1-2000 chars, optional reply_to) |
| `POST` | `/messages/{id}/report` | Yes | Report a message |
| `POST` | `/messages/{id}/delete` | Yes | Soft-delete own message (within 15 min) |
| `POST` | `/messages/{id}/react` | Yes | React with emoji |
| `GET` | `/ws/spaces/{id}` | Yes | WebSocket (placeholder) |

#### Geofence

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/geofence/validate` | Yes | Full location validation with spoof detection, smoothing, hysteresis |

#### System

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/health` | No | Health check |
| `GET` | `/docs` | No | Swagger UI |
| `GET` | `/api-docs/openapi.json` | No | OpenAPI spec |

### Geofence Engine

Sophisticated location validation pipeline:

1. **Coordinate validation** — lat/lon bounds check
2. **Spoof detection** — mock location flag, impossible jump (>500m in <5s), excessive speed (>200 km/h walking reject, >500 km/h hard reject)
3. **Accuracy check** — max 75m for joining, max 35m tolerance
4. **Haversine distance** — calculates distance from geofence center
5. **Median smoothing** — filters GPS jitter across current + up to 3 recent fixes
6. **Distance classification** — inside, near-boundary, outside
7. **Hysteresis buffering** — 20m exit buffer, requires 3 consecutive outside readings
8. **Lifecycle state machine** — Joining → Inside → NearBoundary → GracePeriod → Outside → Expired

**Decision values:** `inside`, `near_boundary`, `outside`, `low_accuracy`, `rejected`

### Moderation System

- Async worker via `tokio::sync::mpsc` channel (256 buffer)
- Keyword-based classification:
  - **Hard block** (severe_safety): "kill myself", "self harm", "bomb threat", "shoot up" → hidden
  - **Soft flag** (toxicity): "idiot", "stupid", "harass" → flagged
  - Clean — no action
- Events logged to `moderation_events` table with category and severity

### Background Worker

- Session expiry sweeper runs every `GEOFENCE_CHECK_INTERVAL_SECONDS` (default 30s)
- Expires sessions past `expires_at`

### Error Handling

| Error | HTTP | Description |
|---|---|---|
| `Unauthorized` | 401 | Missing/invalid auth token |
| `Forbidden` | 403 | Not allowed (geofence rejected, not in space) |
| `NotFound` | 404 | Space/message not found |
| `Validation` | 400 | Payload validation failed |
| `Conflict` | 409 | Max spaces reached |
| `Db` / `Internal` | 500 | Server errors |

### Tests

- Space validation (radius cap)
- Geofence engine (inside, boundary, low accuracy, outside buffering, impossible jump, mock location, speed check)
- Moderation classification (hard block, soft flag)
- Smoothing (median spike rejection)
- Spoof detection (speed computation)

---

## Frontend

### Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter with Material 3 |
| Maps | flutter_map + OpenStreetMap tiles |
| Location | geolocator (GPS) |
| HTTP | http package with JWT auto-refresh |
| Persistence | SharedPreferences |
| Geofence | Client-side validation engine matching backend logic |

### Screens & Flows

#### 1. AppLoader (Splash)

- Initializes API client, auth service
- Registers device on first launch (UUID v4)
- Restores persisted tokens on subsequent launches
- Shows loading/error states

#### 2. LocationSelectionScreen

- Requests location permission
- Interactive OpenStreetMap with:
  - Dark-themed tile rendering
  - Search bar with Nominatim geocoding (debounced)
  - GPS "My Location" button
  - Zoom in/out controls
  - Long-press or drag to place pin
  - Geofence radius circle overlay
  - Status bar (coordinates, validation)
- "Use this location" button
- Saves location to SharedPreferences

#### 3. SpaceDiscoveryScreen

- Discovers nearby public spaces via API
- States: loading, error (with retry), empty (with "Create a Space"), populated
- Space cards: name, distance, member count, joined badge
- Tap joined space to enter chat
- "Create a Space" button
- Change location / logout in header

#### 4. CreateSpaceScreen

- Step 1 — Name (defaults to "Untitled Space")
- Step 2 — Visibility toggle (Public / Private)
- Step 3 — Geofence radius slider (30m–300m) with real-time validation status
- "Create Space" button with loading state
- Auto-joins the creator after creation

#### 5. ChatScreen

- Header: space name, anonymous name, leave button
- Message history with loading/empty states
- Message cards: colored dot, anonymous name, text
- Chat composer: text input + send button (submit-on-enter)
- Optimistic UI for sent messages
- 30-second geofence exit polling
- Alert dialog on geofence exit → auto-leave space

### API Integration

| Method | Endpoint | Usage |
|---|---|---|
| `POST` | `/auth/register` | Device registration on first launch |
| `POST` | `/auth/refresh` | Token refresh on 401 |
| `GET` | `/spaces/discover` | Discover nearby spaces |
| `POST` | `/spaces` | Create a space |
| `POST` | `/spaces/{id}/join` | Join a space |
| `POST` | `/spaces/{id}/leave` | Leave a space |
| `GET` | `/spaces/{id}/messages` | Get chat messages |
| `POST` | `/spaces/{id}/messages` | Send a message |
| `POST` | `/geofence/validate` | Geofence exit monitoring |

### Geofence Validation Engine

Client-side implementation matching the backend's algorithm:

- Haversine distance
- Median-smoothed location fixes
- Accuracy-adjusted effective radius
- 5 decisions: inside, nearBoundary, outside, lowAccuracy, rejected
- 6 lifecycle states: joining, inside, nearBoundary, gracePeriod, outside, expired
- Consecutive outside buffering (3 required), grace period
- Impossible jump detection, excessive speed, mock location checks

### Design System

Dark theme with custom color palette:

| Token | Hex | Usage |
|---|---|---|
| `black` | `#0B0B0C` | Background |
| `surface` | `#151518` | Surfaces |
| `card` | `#1C1C20` | Cards |
| `white` | `#FFFFFF` | Primary text |
| `secondary` | `#B4B4BC` | Secondary text |
| `disabled` | `#6E6E78` | Disabled elements |
| `accent` | `#37D399` | Primary accent (green-teal) |

Radial gradient background (`#13211F` → `#0B0B0C`) on all screens. Inter font family. Material 3. Consistent 19px / 22px border radius.

### Authentication Flow

1. First launch: generate UUID v4 device ID → `POST /auth/register` → store JWT tokens
2. Subsequent launches: load from SharedPreferences → verify connectivity
3. On 401: auto-refresh via `/auth/refresh` → retry original request
4. Logout: clear persisted tokens

### Persistence (SharedPreferences)

- `device_id` — stable device identity
- `access_token`, `refresh_token`, `user_id` — JWT auth
- `selected_latitude`, `selected_longitude` — chosen location

### Tests

- Widget smoke test (SpaceApp renders)
- Geofence validator (8 tests): inside, boundary, low accuracy, impossible jump, outside buffering (3 consecutive), grace period, mock location, excessive speed

### Not Yet Wired Up

- WebSocket real-time chat (dependency exists, WS URL builder exists, but not consumed)
- `mySpaces()` and `joinedSpaces()` API methods (not called from UI)
- Message reply UI (`replyTo` in model and API, no UI)
- Message reactions (field exists, always 0)

---

## Infrastructure

### Docker Compose

```yaml
services:
  postgres: 16-alpine (port 55432)
  redis: 7-alpine
  backend: multi-stage Rust build
```

### Dockerfile

Multi-stage: `rust:1.89-slim-bookworm` → `debian:bookworm-slim`, produces `space-backend` binary.
