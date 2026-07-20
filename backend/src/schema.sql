-- MMO backend schema. Idempotent: safe to run repeatedly.

CREATE TABLE IF NOT EXISTS players (
    id           BIGINT PRIMARY KEY,          -- Roblox UserId
    username     TEXT        NOT NULL,
    health       INT         NOT NULL DEFAULT 100,
    max_health   INT         NOT NULL DEFAULT 100,
    gold         BIGINT      NOT NULL DEFAULT 0,
    level        INT         NOT NULL DEFAULT 1,
    xp           BIGINT      NOT NULL DEFAULT 0,
    hotbar_binds JSONB       NOT NULL DEFAULT '{}'::jsonb, -- ["3".."0" key slot] = itemId
    settings     JSONB       NOT NULL DEFAULT '{}'::jsonb, -- client prefs (trait tracker mode, ...)
     granted_starter_items JSONB NOT NULL DEFAULT '[]'::jsonb, -- itemIds ever granted as starter kit
    current_class TEXT       NOT NULL DEFAULT 'knight',    -- knight|archer|mage|
    class_levels JSONB       NOT NULL DEFAULT '{}'::jsonb, -- { [classId]: { level, xp } }
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
ALTER TABLE players ADD COLUMN IF NOT EXISTS level INT NOT NULL DEFAULT 1;
ALTER TABLE players ADD COLUMN IF NOT EXISTS xp BIGINT NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS hotbar_binds JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE players ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE players ADD COLUMN IF NOT EXISTS current_class TEXT NOT NULL DEFAULT 'knight';
ALTER TABLE players ADD COLUMN IF NOT EXISTS class_levels JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE players ADD COLUMN IF NOT EXISTS granted_starter_items JSONB NOT NULL DEFAULT '[]'::jsonb;
-- Quest progress: { [questId]: { status: "active"|"completed", objectives: { [objectiveId]: count } } }.
-- Same shape as the old in-memory QuestService.progress table.
ALTER TABLE players ADD COLUMN IF NOT EXISTS quest_progress JSONB NOT NULL DEFAULT '{}'::jsonb;
-- Which quest the quest log panel has marked as "tracked" (drives the HUD
-- tracker). '' = none — TEXT with an empty-string default, not nullable, so
-- we never have to distinguish JSON null from "field omitted" over the wire
-- (see savePlayer's `!== undefined` convention in playerService.js).
ALTER TABLE players ADD COLUMN IF NOT EXISTS tracked_quest_id TEXT NOT NULL DEFAULT '';
-- Saved camp furniture layout, keyed to the owner (not the live camp
-- instance, which is in-memory/session-only — see CampService.lua). Rebuilt
-- exactly when the owner plants a new Acampada; written whenever their camp
-- is torn down (expired or otherwise) so nothing is lost between camps.
-- Shape: { pieces: [ { itemId, dx, dz, chestItems? } ] } — dx/dz are offsets
-- from the camp center so they replay correctly at a new location.
ALTER TABLE players ADD COLUMN IF NOT EXISTS camp_layout JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Camp tier (0-3): a persistent, one-time-purchased upgrade to the owner's
-- Acampada — bigger zone, more furniture slots, a more elaborate campfire
-- model. Unlike camp_layout (the live furniture arrangement), this is a
-- flat player stat, same shape as gold/level — see docs/CAMP_TIERS.md.
-- Applied the next time the owner (re)plants a camp, not retroactively to
-- an already-standing one.
ALTER TABLE players ADD COLUMN IF NOT EXISTS camp_tier INT NOT NULL DEFAULT 0;

-- Bestiary: lifetime kill counts per enemy lootSource, e.g. { slime: 12,
-- goblin: 3 }. Flat persistent stat, same shape/lifecycle as quest_progress
-- (bumped on every EnemyService.onKilled, travels with the profile, never
-- reset) — see docs/BESTIARY.md. Gates how much of that enemy's Loot.TABLE/
-- Loot.GEAR the client is shown (EnemyInspectUI, BestiaryUI): shared/
-- Bestiary.lua turns a count into a tier, and each loot entry's own `tier`
-- field says which tier reveals it.
ALTER TABLE players ADD COLUMN IF NOT EXISTS bestiary_kills JSONB NOT NULL DEFAULT '{}'::jsonb;

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

-- Per-instance item data (rolled trait items): { itemLevel, traits: {id: pts} }.
-- NULL = a plain item. Rows with meta never stack/merge and survive sorting
-- as their own stacks — see inventory.js.
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS meta JSONB;

CREATE INDEX IF NOT EXISTS idx_inventory_player ON inventory_items (player_id);

-- Speeds up the admin dashboard's "recently active" aggregates.
CREATE INDEX IF NOT EXISTS idx_players_updated_at ON players (updated_at);

-- Guilds: name/tag unique, one guild per player enforced by guild_members'
-- PRIMARY KEY on player_id (a row per member, one row max since it's also
-- the PK — see below). leader_id is a plain FK, not a role column on
-- guild_members: MVP has exactly two roles (leader/member), and
-- "who's leader" only ever needs a single answer, not a per-row flag.
-- Leadership transfers (leader leaves, members remain) UPDATE this column;
-- it never needs its own migration path if officers get added later
-- (that would be an ADD COLUMN on guild_members, additive).
CREATE TABLE IF NOT EXISTS guilds (
    id           BIGSERIAL PRIMARY KEY,
    name         TEXT        NOT NULL UNIQUE,
    tag          TEXT        NOT NULL,
    leader_id    BIGINT      NOT NULL REFERENCES players(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per member; player_id itself is the PRIMARY KEY (not
-- (guild_id, player_id)) specifically so a player can never end up in two
-- guilds at once — a second INSERT for the same player_id fails outright,
-- no separate uniqueness check needed beyond the FK/PK.
CREATE TABLE IF NOT EXISTS guild_members (
    guild_id     BIGINT      NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
    player_id    BIGINT      PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    joined_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_guild_members_guild ON guild_members (guild_id);

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

-- Place registry + deploy ledger (docs/DEPLOYMENT.md). `places` is upserted
-- from roblox/places.json by scripts/deploy-places.mjs on every deploy, so
-- every place the pipeline knows about appears here automatically. `deploys`
-- is the append-only history behind the drift check (a version bump the
-- ledger didn't record = someone published outside the pipeline) and the
-- future dashboard Places screen.
CREATE TABLE IF NOT EXISTS places (
    place_id     BIGINT PRIMARY KEY,          -- Roblox PlaceId
    universe_id  BIGINT NOT NULL,
    name         TEXT   NOT NULL,             -- manifest key, e.g. 'cellA'
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deploys (
    id             BIGSERIAL PRIMARY KEY,
    place_id       BIGINT NOT NULL REFERENCES places(place_id),
    version_number INT    NOT NULL,           -- Roblox place version
    version_type   TEXT   NOT NULL,           -- Published | Saved
    git_commit     TEXT,                      -- short hash baked into BuildInfo
    deployed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deploys_place ON deploys (place_id, id DESC);

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