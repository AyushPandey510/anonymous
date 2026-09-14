ALTER TABLE activity.location_validation_events
  ALTER COLUMN latitude DROP NOT NULL,
  ALTER COLUMN longitude DROP NOT NULL,
  ALTER COLUMN distance_meters DROP NOT NULL,
  ALTER COLUMN accuracy_meters DROP NOT NULL,
  ALTER COLUMN speed_meters_per_second DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS distance_bucket TEXT,
  ADD COLUMN IF NOT EXISTS accuracy_bucket TEXT,
  ADD COLUMN IF NOT EXISTS speed_bucket TEXT,
  ADD COLUMN IF NOT EXISTS precise_location_expires_at TIMESTAMPTZ;

UPDATE activity.location_validation_events
SET distance_bucket = CASE
      WHEN distance_meters < 25 THEN '0-25m'
      WHEN distance_meters < 50 THEN '25-50m'
      WHEN distance_meters < 100 THEN '50-100m'
      WHEN distance_meters < 300 THEN '100-300m'
      ELSE '300m+'
    END,
    accuracy_bucket = CASE
      WHEN accuracy_meters IS NULL THEN 'unknown'
      WHEN accuracy_meters <= 25 THEN 'high'
      WHEN accuracy_meters <= 75 THEN 'medium'
      ELSE 'low'
    END,
    speed_bucket = CASE
      WHEN speed_meters_per_second IS NULL THEN 'unknown'
      WHEN speed_meters_per_second < 1 THEN 'stationary'
      WHEN speed_meters_per_second < 3 THEN 'walking'
      WHEN speed_meters_per_second < 30 THEN 'vehicle'
      ELSE 'fast_vehicle'
    END,
    precise_location_expires_at = COALESCE(
      precise_location_expires_at,
      created_at + interval '10 minutes'
    );

UPDATE activity.location_validation_events
SET latitude = NULL,
    longitude = NULL,
    distance_meters = NULL,
    accuracy_meters = NULL,
    speed_meters_per_second = NULL
WHERE precise_location_expires_at < now();

CREATE INDEX IF NOT EXISTS location_validation_events_precise_expiry_idx
ON activity.location_validation_events (precise_location_expires_at)
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
