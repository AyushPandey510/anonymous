CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
    CREATE TYPE space_visibility AS ENUM ('public', 'private');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE session_status AS ENUM ('active', 'grace', 'expired');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE moderation_status AS ENUM ('clean', 'flagged', 'hidden');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE report_status AS ENUM ('pending', 'reviewed', 'actioned', 'dismissed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS activity;

CREATE TABLE IF NOT EXISTS identity.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_lookup_hash TEXT NOT NULL UNIQUE,
    phone_hash TEXT NOT NULL,
    device_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS identity.otp_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_lookup_hash TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS identity.refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS activity.spaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    visibility space_visibility NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters INTEGER NOT NULL CHECK (radius_meters > 0 AND radius_meters <= 300),
    created_by UUID NOT NULL,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS spaces_location_idx ON activity.spaces (latitude, longitude);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_space_per_creator_idx ON activity.spaces (created_by) WHERE archived_at IS NULL;

CREATE TABLE IF NOT EXISTS activity.space_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id UUID NOT NULL REFERENCES activity.spaces(id) ON DELETE CASCADE,
    invite_code TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    max_uses INTEGER,
    uses INTEGER NOT NULL DEFAULT 0,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS activity.sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    space_id UUID NOT NULL REFERENCES activity.spaces(id) ON DELETE CASCADE,
    anonymous_id TEXT NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    status session_status NOT NULL DEFAULT 'active'
);

CREATE INDEX IF NOT EXISTS sessions_user_space_idx ON activity.sessions (user_id, space_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS sessions_anonymous_space_idx ON activity.sessions (space_id, anonymous_id) WHERE status <> 'expired';

CREATE TABLE IF NOT EXISTS activity.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id UUID NOT NULL REFERENCES activity.spaces(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES activity.sessions(id) ON DELETE CASCADE,
    anonymous_id TEXT NOT NULL,
    content TEXT NOT NULL,
    reply_to UUID REFERENCES activity.messages(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    moderation_status moderation_status NOT NULL DEFAULT 'clean'
);

CREATE INDEX IF NOT EXISTS messages_space_created_idx ON activity.messages (space_id, created_at DESC);

CREATE TABLE IF NOT EXISTS activity.reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES activity.messages(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES activity.sessions(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (message_id, session_id, emoji)
);

CREATE TABLE IF NOT EXISTS activity.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL,
    message_id UUID NOT NULL REFERENCES activity.messages(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status report_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS activity.moderation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES activity.messages(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    severity TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
