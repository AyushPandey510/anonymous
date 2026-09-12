ALTER TABLE activity.messages ADD COLUMN poll_options JSONB;

CREATE TABLE activity.poll_votes (
    message_id UUID NOT NULL REFERENCES activity.messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    option_index INTEGER NOT NULL CHECK (option_index BETWEEN 0 AND 5),
    PRIMARY KEY (message_id, user_id)
);
