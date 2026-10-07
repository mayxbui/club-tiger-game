DO $$ BEGIN
    CREATE DOMAIN email_type AS TEXT
        CHECK (VALUE ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(20) UNIQUE NOT NULL,
    email email_type UNIQUE NOT NULL,
    password_hashed TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Usernames are unique ignoring capitals
CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key ON users (lower(username));

----------------------CHARACTER: one per users-----------------------
CREATE TABLE IF NOT EXISTS characters (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    skin SMALLINT NOT NULL DEFAULT 0,
    hair SMALLINT NOT NULL DEFAULT 0,
    eyes SMALLINT NOT NULL DEFAULT 0,
    top SMALLINT NOT NULL DEFAULT 0,
    bottom SMALLINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-------------------FRIENDSHIP: self join on users-----------------------
CREATE TABLE IF NOT EXISTS friendships (
    id SERIAL PRIMARY KEY,
    requester_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted','declined')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (requester_id, addressee_id),
    CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair
    ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

-------------------BLOCKS: self join on users-----------------------
CREATE TABLE IF NOT EXISTS blocks (
    id SERIAL PRIMARY KEY,
    blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

-------------------SESSION: many per users-----------------------
CREATE TABLE IF NOT EXISTS sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hashed TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

    CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions (user_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);

-------------------PASSWORD_RESETS: at most one active code per user-----------------------
CREATE TABLE IF NOT EXISTS password_resets(
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hashed TEXT NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    reset_token_hashed TEXT UNIQUE,
    token_expires_at TIMESTAMPTZ
);

    CREATE INDEX IF NOT EXISTS idx_password_resets_expires_at ON password_resets(expires_at);

-- For databases where password_resets was created before the token columns existed (CREATE TABLE IF NOT EXISTS
-- doesn't add new columns to an existing table). Does nothing if the columns are already there.
ALTER TABLE password_resets ADD COLUMN IF NOT EXISTS reset_token_hashed TEXT UNIQUE;
ALTER TABLE password_resets ADD COLUMN IF NOT EXISTS token_expires_at TIMESTAMPTZ;

-----------------------dorms: one per users-----------------------
CREATE TABLE IF NOT EXISTS dorms (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

            --ITEM CATALOG & DORM_ITEMS: multiple per user--
                    
CREATE TABLE IF NOT EXISTS item_catalog (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    description TEXT,
    -- price INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(64) NOT NULL,
    -- created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sprite_key VARCHAR(64) NOT NULL,
    min_scale REAL NOT NULL DEFAULT 0.1,
    max_scale REAL NOT NULL DEFAULT 10.0
);

CREATE TABLE IF NOT EXISTS dorm_items (
    id SERIAL PRIMARY KEY,
    dorm_id INTEGER NOT NULL REFERENCES dorms(id) ON DELETE CASCADE,
    item_id INTEGER NOT NULL REFERENCES item_catalog(id),
    x REAL NOT NULL,
    y REAL NOT NULL,
    z SMALLINT NOT NULL DEFAULT 0,
    scale REAL NOT NULL DEFAULT 1

);
    CREATE INDEX IF NOT EXISTS idx_dorm_items_dorm_id ON dorm_items (dorm_id);
