# Space Map & Geofencing System

Production-ready blueprint for the first stable location feature.

## 1. Product Goal

The map system must answer three questions with high confidence:

- Where is the user now?
- Which location did the user intentionally select?
- Is the user currently allowed inside a Space geofence?

The client improves experience and responsiveness. The backend remains the authority for creation and access validation.

## 2. UX Flow

### Permission Onboarding

Screen states:

- `intro`: Explain why Space needs location: presence-based access, no GPS history.
- `services_disabled`: Location services are off. CTA opens system location settings.
- `permission_prompt`: Request foreground permission.
- `denied`: Explain limited mode. CTA retries permission request.
- `denied_permanently`: CTA opens app settings.
- `restricted`: Explain OS/account policy restriction.
- `granted`: Continue to map.

UX copy should be brief and calm. Avoid fear-based permission language.

### Current Location

States:

- `locating`: Skeleton map + animated status pill.
- `located`: Map centers on current fix.
- `low_accuracy`: Show accuracy meter and continue with caution.
- `timeout`: Retry button and manual search.
- `offline`: Cached map/search unavailable notice.
- `error`: Human-readable error with retry.

Display:

- Accuracy radius in meters.
- Last updated time.
- Source confidence: high, medium, low.

### Interactive Map

Controls:

- Fixed center pin for selection.
- Re-center button.
- Compass when rotated.
- Radius circle overlay.
- Bottom selection sheet with address, coordinates, accuracy, and radius.

Interaction model:

- Dragging the map moves the location under a fixed center pin.
- Long press can snap the selected point.
- Search result animates camera to the selected location.
- Radius changes update the circle immediately.

### Location Search

Search accepts:

- Address
- Landmark
- Business/place
- Latitude/longitude pair

States:

- `idle`
- `typing`
- `suggestions`
- `no_results`
- `ambiguous`
- `network_error`
- `selected`

Selection behavior:

- Place result moves camera to coordinate.
- Reverse geocode selected coordinate.
- If search confidence is low, show a warning before creation.

### Geofence Creation

Inputs:

- Center latitude
- Center longitude
- Radius meters
- Optional address label
- Source: `current_location`, `search`, `pin_drag`, `long_press`

Rules:

- Minimum radius: configurable, default `30m`.
- Maximum radius: backend-enforced, MVP `300m`.
- Radius slider: continuous UI, rounded to nearest meter.
- Numeric field: clamped server-side and client-side.
- Creation disabled when coordinate is invalid or accuracy is unacceptable.

## 3. Flutter Architecture

Suggested feature layout:

```text
lib/features/location/
├── domain/
│   ├── geo_point.dart
│   ├── geofence.dart
│   ├── location_fix.dart
│   ├── location_permission_state.dart
│   └── geofence_validator.dart
├── data/
│   ├── location_service.dart
│   ├── geocoding_repository.dart
│   ├── places_repository.dart
│   └── space_location_api.dart
├── presentation/
│   ├── location_permission_screen.dart
│   ├── space_map_screen.dart
│   ├── location_search_sheet.dart
│   ├── selected_location_sheet.dart
│   ├── geofence_radius_control.dart
│   └── geofence_status_pill.dart
└── state/
    ├── map_controller.dart
    ├── location_tracker.dart
    └── geofence_creation_controller.dart
```

Recommended abstractions:

- `LocationService`: permissions, services status, foreground stream, settings redirects.
- `MapAdapter`: hides Google Maps/Mapbox choice from app logic.
- `PlacesRepository`: autocomplete and place details.
- `GeocodingRepository`: reverse geocode selected pin.
- `GeofenceValidator`: deterministic pure Dart validation, unit tested.
- `SpaceLocationApi`: sends create/join/validate requests to backend.

State management:

- MVP can use `ChangeNotifier`/`ValueNotifier`.
- Move to Riverpod or Bloc once async flows grow.
- Keep geofence math pure and independent from UI.

## 4. Backend Architecture

Backend remains authoritative.

Modules:

```text
src/geofence/
├── validation.rs
├── accuracy.rs
├── anti_spoofing.rs
└── dto.rs

src/spaces/
├── create.rs
├── discovery.rs
├── join.rs
└── location_validation.rs
```

Responsibilities:

- Validate coordinate ranges.
- Enforce min/max radius.
- Enforce active-space limits.
- Validate user location against geofence with tolerance.
- Store only required geofence center/radius, not GPS history.
- Record coarse validation events for debugging without storing continuous tracks.

## 5. Database Schema

Current circular geofence fields remain:

```sql
latitude DOUBLE PRECISION NOT NULL,
longitude DOUBLE PRECISION NOT NULL,
radius_meters INTEGER NOT NULL CHECK (radius_meters > 0 AND radius_meters <= 300)
```

Recommended production additions:

```sql
ALTER TABLE activity.spaces
ADD COLUMN geofence_type TEXT NOT NULL DEFAULT 'circle',
ADD COLUMN geofence_version INTEGER NOT NULL DEFAULT 1,
ADD COLUMN location_label TEXT,
ADD COLUMN geofence_config JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE activity.location_validation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    space_id UUID NOT NULL REFERENCES activity.spaces(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters DOUBLE PRECISION,
    distance_meters DOUBLE PRECISION NOT NULL,
    decision TEXT NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX location_validation_events_space_created_idx
ON activity.location_validation_events (space_id, created_at DESC);
```

Retention:

- Keep validation events short-lived, for example 7 to 14 days.
- Do not use this as user location history.

## 6. API Contracts

### Create Space

`POST /spaces`

```json
{
  "name": "Startup Engineering",
  "description": "Deploys and incidents",
  "visibility": "public",
  "latitude": 12.9716,
  "longitude": 77.5946,
  "radius_meters": 120,
  "location_label": "Church Street, Bengaluru",
  "selection_source": "pin_drag"
}
```

Server validates:

- Authenticated user.
- Coordinate ranges.
- Radius min/max.
- One active Space per user.
- Ten active overlapping spaces near location.

### Validate Location

`POST /geofence/validate`

```json
{
  "space_id": "uuid",
  "latitude": 12.97162,
  "longitude": 77.59458,
  "accuracy_meters": 18.5,
  "client_timestamp": "2026-07-20T16:10:00Z"
}
```

Response:

```json
{
  "decision": "inside",
  "distance_meters": 12.4,
  "effective_radius_meters": 138.5,
  "confidence": "high",
  "grace_expires_at": null
}
```

Decisions:

- `inside`
- `near_boundary`
- `outside`
- `low_accuracy`
- `rejected`

### Join Space

`POST /spaces/{space_id}/join`

Use the same location payload as validation. Join succeeds only if server decision is `inside` or acceptable `near_boundary`.

## 7. Geofence Validation Algorithm

Inputs:

- Space center
- Space radius
- User latitude/longitude
- GPS accuracy meters
- Previous validation state
- Grace period

Core distance:

- Use Haversine for circle validation.
- For high precision under 300m, Haversine is sufficient and stable.

Tolerance:

```text
effective_radius = configured_radius + min(accuracy_meters, max_accuracy_tolerance)
near_boundary_band = max(10m, accuracy_meters * 0.5)
```

Default config:

- `max_accuracy_tolerance`: `35m`
- `max_acceptable_accuracy_for_join`: `75m`
- `near_boundary_band`: `10m minimum`
- `exit_grace_period`: `120s`
- `jump_threshold`: `500m in under 5s`

Decision logic:

```text
if coordinate invalid:
  rejected

if accuracy missing or accuracy > max_acceptable_accuracy_for_join:
  low_accuracy

if sudden impossible jump:
  rejected or require fresh fix

distance = haversine(user, center)
effective_radius = radius + min(accuracy, max_accuracy_tolerance)

if distance <= radius:
  inside
else if distance <= effective_radius:
  near_boundary
else:
  outside
```

State transition rules:

- Enter only after one high-confidence inside reading.
- Exit only after repeated outside readings or grace timeout.
- Near-boundary keeps session active but starts softer monitoring.
- Low-accuracy does not immediately eject an active user.

## 8. GPS Accuracy Strategy

Foreground:

- Use high accuracy during create/join.
- After joining, reduce polling frequency unless near boundary.

Suggested polling:

- Inside and far from boundary: every `30-60s`.
- Near boundary: every `5-10s`.
- Outside reading: verify again within `5s`.
- Low accuracy: request fresh fix, avoid immediate ejection.

Accuracy tiers:

- High: `<= 25m`
- Medium: `26-75m`
- Low: `> 75m`

Client display:

- High: normal state.
- Medium: “Accuracy 42m”.
- Low: “Weak location signal”.

## 9. Background Tracking Strategy

MVP recommendation:

- Foreground-only continuous tracking.
- Background grace support through OS geofencing APIs where available.
- Avoid aggressive background GPS until user trust and battery behavior are validated.

Production path:

- Android: foreground service only while actively inside a Space.
- iOS: significant location changes + region monitoring.
- Store minimal session state locally.
- On app reopen, immediately revalidate before enabling chat.

Battery rules:

- Never poll high accuracy continuously when far inside boundary.
- Increase accuracy only during join, create, and boundary transitions.
- Stop tracking after session expiry.

## 10. Edge Case Handling

- Weak GPS: show low accuracy and retry fresh fix.
- Indoor: allow larger creator radius but cap at 300m.
- Airplane mode: allow map cache, block server validation.
- No internet: allow pin selection, queue no create/join.
- Spoofing: detect impossible jumps, emulator/mock-location where OS exposes it.
- Sudden GPS jump: require another fix before changing state.
- App killed: on reopen validate before chat.
- Device reboot: session must revalidate.
- Network loss during verification: keep UI pending, do not grant access.
- Search unavailable: manual pin selection still works.

## 11. Security Considerations

- Server validates all geofence decisions.
- Client location is untrusted input.
- Clamp radius server-side.
- Do not store GPS trails.
- Rate-limit location validation and join attempts.
- Log validation decisions without exposing phone identity.
- Use HTTPS/WSS only.
- Treat mock-location detection as a signal, not absolute proof.
- Future: device integrity APIs such as Play Integrity / App Attest.

## 12. Testing Strategy

Unit tests:

- Haversine distance.
- Radius clamp.
- Inside/outside/near-boundary decisions.
- Low accuracy behavior.
- Impossible jump detection.
- Grace-period transitions.

Flutter widget tests:

- Permission states.
- Loading/error/retry states.
- Radius slider and numeric input sync.
- Search result selection.
- Selected address display.

Integration tests:

- Create space with valid geofence.
- Reject invalid coordinates.
- Reject radius above 300m.
- Join inside.
- Reject outside.
- Preserve session during near-boundary jitter.

Field tests:

- Outdoor high GPS accuracy.
- Indoor office.
- Elevator/stairwell.
- Multi-floor building.
- Network drop mid-session.
- App background/reopen.
- Walking across boundary.

## 13. Future Roadmap

### Polygon Geofences

Add:

```json
{
  "geofence_type": "polygon",
  "geofence_config": {
    "points": [
      {"latitude": 12.9716, "longitude": 77.5946}
    ]
  }
}
```

Keep API versioned so `circle` and `polygon` can coexist.

### Multi-Zone Spaces

Support several allowed zones for one Space:

- Office lobby
- Cafeteria
- Conference room

### Indoor Positioning

Possible options:

- BLE beacons
- Wi-Fi RTT where supported
- QR-based room verification
- Office network verification

### Anti-Spoofing Hardening

- OS mock-location checks.
- Device integrity attestation.
- Velocity anomaly detection.
- IP/location mismatch signals.
- Repeated validation scoring.

## 14. Implementation Order

1. Add pure geofence validator in Flutter and Rust.
2. Add backend `/geofence/validate`.
3. Add production migration fields.
4. Build Flutter permission and current-location controller.
5. Build map screen with fixed center pin and radius overlay.
6. Add search abstraction and provider implementation.
7. Connect create/join flows to backend.
8. Add tests for validation and edge cases.
9. Field-test in the pilot location.
