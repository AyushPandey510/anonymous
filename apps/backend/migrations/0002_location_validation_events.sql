ALTER TABLE activity.spaces
ADD COLUMN IF NOT EXISTS geofence_type TEXT NOT NULL DEFAULT 'circle',
ADD COLUMN IF NOT EXISTS geofence_version INTEGER NOT NULL DEFAULT 1,
ADD COLUMN IF NOT EXISTS location_label TEXT,
ADD COLUMN IF NOT EXISTS geofence_config JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS activity.location_validation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    space_id UUID NOT NULL REFERENCES activity.spaces(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters DOUBLE PRECISION,
    distance_meters DOUBLE PRECISION NOT NULL,
    speed_meters_per_second DOUBLE PRECISION,
    decision TEXT NOT NULL,
    lifecycle_state TEXT NOT NULL DEFAULT 'joining',
    reason TEXT,
    mock_location BOOLEAN NOT NULL DEFAULT false,
    spoofing_score INTEGER NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS location_validation_events_space_created_idx
ON activity.location_validation_events (space_id, created_at DESC);

CREATE INDEX IF NOT EXISTS location_validation_events_user_space_created_idx
ON activity.location_validation_events (user_id, space_id, created_at DESC);

CREATE INDEX IF NOT EXISTS location_validation_events_created_idx
ON activity.location_validation_events (created_at DESC);
