-- MMO backend schema. Idempotent: safe to run repeatedly.

CREATE TABLE IF NOT EXISTS players (
    id           BIGINT PRIMARY KEY,          -- Roblox UserId
    username     TEXT        NOT NULL,
    health       INT         NOT NULL DEFAULT 100,
    max_health   INT         NOT NULL DEFAULT 100,
    gold         BIGINT      NOT NULL DEFAULT 0,
    hotbar_binds JSONB       NOT NULL DEFAULT '{}'::jsonb, -- ["3".."0" key slot] = itemId
    cell         TEXT        NOT NULL DEFAULT 'A',
    pos_x        REAL        NOT NULL DEFAULT 0,
    pos_y        REAL        NOT NULL DEFAULT 0,
    pos_z        REAL        NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Columns added after launch: CREATE TABLE IF NOT EXISTS won't touch an
-- existing table, so each also needs an idempotent ALTER here.
ALTER TABLE players ADD COLUMN IF NOT EXISTS gold BIGINT NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS hotbar_binds JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Grid inventory: items occupy a WxH footprint at (x, y) in a
-- container. container_id is 'main' (the 10x30 grid) or 'equipment' (paper
-- doll; x = slot index, y = 0). Legacy rows (pre-grid) have x/y NULL and are
-- repacked into grid positions on first read.
CREATE TABLE IF NOT EXISTS inventory_items (
    id           BIGSERIAL PRIMARY KEY,
    player_id    BIGINT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    slot_index   INT,                     -- legacy flat slot (pre-grid), unused
    container_id TEXT    NOT NULL DEFAULT 'main',
    x            INT,
    y            INT,
    rotated      BOOLEAN NOT NULL DEFAULT false,
    item_id      TEXT   NOT NULL,
    quantity     INT    NOT NULL CHECK (quantity > 0)
);

-- Grid-era columns / constraint relaxations for tables created pre-grid.
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS container_id TEXT NOT NULL DEFAULT 'main';
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS x INT;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS y INT;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS rotated BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE inventory_items ALTER COLUMN slot_index DROP NOT NULL;
ALTER TABLE inventory_items DROP CONSTRAINT IF EXISTS inventory_items_player_id_slot_index_key;

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
