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
