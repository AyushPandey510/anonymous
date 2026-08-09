ALTER TABLE identity.users
  ADD COLUMN IF NOT EXISTS device_id TEXT,
  ADD COLUMN IF NOT EXISTS device_name TEXT,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS display_name TEXT;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'identity' AND table_name = 'users' AND column_name = 'device_key') THEN
        UPDATE identity.users SET device_id = device_key WHERE device_id IS NULL;
    END IF;
END $$;

ALTER TABLE identity.users
  ALTER COLUMN phone_lookup_hash DROP NOT NULL,
  ALTER COLUMN phone_hash DROP NOT NULL,
  ALTER COLUMN device_id SET NOT NULL,
  DROP COLUMN IF EXISTS device_key;

ALTER TABLE identity.users DROP CONSTRAINT IF EXISTS users_phone_lookup_hash_key;
CREATE UNIQUE INDEX IF NOT EXISTS users_device_id_idx ON identity.users (device_id);

ALTER TABLE activity.spaces
  DROP CONSTRAINT IF EXISTS spaces_created_by_fkey,
  ADD COLUMN IF NOT EXISTS member_count INTEGER NOT NULL DEFAULT 0;

DROP INDEX IF EXISTS activity.one_active_space_per_creator_idx;
CREATE INDEX IF NOT EXISTS spaces_created_by_idx ON activity.spaces (created_by);

ALTER TABLE activity.sessions
  ADD COLUMN IF NOT EXISTS device_id TEXT,
  ADD COLUMN IF NOT EXISTS last_validated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lifecycle_state TEXT NOT NULL DEFAULT 'joining',
  ADD COLUMN IF NOT EXISTS consecutive_outside INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS sessions_device_idx ON activity.sessions (device_id);
