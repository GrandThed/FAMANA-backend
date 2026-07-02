-- MMO backend schema. Idempotent: safe to run repeatedly.

CREATE TABLE IF NOT EXISTS players (
    id           BIGINT PRIMARY KEY,          -- Roblox UserId
    username     TEXT        NOT NULL,
    health       INT         NOT NULL DEFAULT 100,
    max_health   INT         NOT NULL DEFAULT 100,
    cell         TEXT        NOT NULL DEFAULT 'A',
    pos_x        REAL        NOT NULL DEFAULT 0,
    pos_y        REAL        NOT NULL DEFAULT 0,
    pos_z        REAL        NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_items (
    id           BIGSERIAL PRIMARY KEY,
    player_id    BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    slot_index   INT    NOT NULL,
    item_id      TEXT   NOT NULL,
    quantity     INT    NOT NULL CHECK (quantity > 0),
    UNIQUE (player_id, slot_index)
);

CREATE INDEX IF NOT EXISTS idx_inventory_player ON inventory_items (player_id);

-- Speeds up the admin dashboard's "recently active" aggregates.
CREATE INDEX IF NOT EXISTS idx_players_updated_at ON players (updated_at);

-- Append-only audit log for every admin-panel mutation. `actor` is the admin's
-- request IP (single shared password for the MVP); `detail` holds the request
-- payload / before-after context as JSON.
CREATE TABLE IF NOT EXISTS admin_audit (
    id             BIGSERIAL PRIMARY KEY,
    actor          TEXT        NOT NULL,
    action         TEXT        NOT NULL,
    target_player  BIGINT,
    detail         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_created_at ON admin_audit (created_at DESC);

-- Per-player event queue. Admin mutations enqueue rows; the game's poll loop
-- drains them (DELETE ... RETURNING) to push live updates to online players.
CREATE TABLE IF NOT EXISTS player_events (
    id           BIGSERIAL PRIMARY KEY,
    player_id    BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    kind         TEXT   NOT NULL,
    message      TEXT,
    payload      JSONB  NOT NULL DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_player_events_player ON player_events (player_id);
