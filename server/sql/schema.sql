CREATE DOMAIN email_type AS TEXT
    CHECK (VALUE ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$');

CREATE TABLE IF NOT EXISTS user (
    id SERIAL PRIMARY KEY,
    username VARCHAR(20) UNIQUE NOT NULL,
    email email_type UNIQUE NOT NULL,
    password_hashed TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

----------------------CHARACTER: one per user-----------------------
CREATE TABLE IF NOT EXISTS character (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    skin SMALLINT NOT NULL DEFAULT 0,
    hair SMALLINT NOT NULL DEFAULT 0,
    eyes SMALLINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-------------------FRIENDSHIP: self join on user-----------------------
CREATE TABLE IF NOT EXISTS friendship (
    id SERIAL PRIMARY KEY,
    requester_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    addressee_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (requester_id, addressee_id),
    CHECK (requester_id <> addressee_id)
);

-------------------SESSION: many per user-----------------------
CREATE TABLE IF NOT EXISTS session (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

    CREATE INDEX idx_sessions_user_id    ON sessions (user_id);
    CREATE INDEX idx_sessions_expires_at ON sessions (expires_at);

-----------------------DORM: one per user-----------------------
CREATE TABLE IF NOT EXISTS dorm (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES user(id) ON DELETE CASCADE,
    updated_at TIMESTAMPZ NOT NULL DEFAULT now()
)

                    --DORM_ITEMS: placement--
CREATE TABLE dorm_items (
    id SERIAL PRIMARY KEY,
    dorm_id INTEGER NOT NULL REFERENCES dorm(id) ON DELETE CASCADE,
    item_id INTEGER NOT NULL REFERENCES item_catalog(id),
    x REAL NOT NULL,
    y REAL NOT NULL,
    scale REAL NOT NULL DEFAULT 1,
    z SMALLINT NOT NULL DEFAULT 0
);
    CREATE INDEX idx_dorm_items_dorm_id ON dorm_items (dorm_id);
