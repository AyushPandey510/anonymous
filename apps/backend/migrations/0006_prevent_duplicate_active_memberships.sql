WITH duplicate_memberships AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, space_id
      ORDER BY joined_at DESC, id DESC
    ) AS membership_rank
  FROM activity.sessions
  WHERE status IN ('active', 'grace')
)
UPDATE activity.sessions
SET status = 'expired', expires_at = now()
WHERE id IN (
  SELECT id
  FROM duplicate_memberships
  WHERE membership_rank > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS sessions_one_current_user_space_idx
ON activity.sessions (user_id, space_id)
WHERE status IN ('active', 'grace');
