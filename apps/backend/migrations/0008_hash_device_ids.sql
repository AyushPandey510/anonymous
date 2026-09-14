ALTER TABLE identity.users
  ADD COLUMN IF NOT EXISTS device_id_hash TEXT,
  ALTER COLUMN device_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_device_id_hash_idx
ON identity.users (device_id_hash)
WHERE device_id_hash IS NOT NULL;
