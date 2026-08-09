ALTER TABLE activity.location_validation_events
ADD COLUMN IF NOT EXISTS speed_meters_per_second DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS lifecycle_state TEXT NOT NULL DEFAULT 'joining',
ADD COLUMN IF NOT EXISTS mock_location BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS spoofing_score INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS location_validation_events_created_idx
ON activity.location_validation_events (created_at DESC);
