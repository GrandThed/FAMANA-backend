-- Territory: fixed points of interest, each guarded by a tough enemy.
-- Killing the guardian claims the settlement for the killer's guild (the
-- backend is the source of truth — backend/src/settlements.js); a
-- "challenger" respawns later so ownership can change hands. Buffs only
-- apply to guild members standing inside `radius` (SettlementService checks
-- this every time it's asked, not by tracking who's "inside" over time).
--
-- `guardian` reuses the exact same shape as EnemyService's ENEMY_DEFS, minus
-- `spots`/`respawn` — a settlement's position comes from `position` below
-- and its respawn timing is settlement-driven (grace + challengerRespawn),
-- not the ordinary per-mob respawn timer. EnemyService.start() merges these
-- into its own spawn table alongside the regular mob defs, tagging each
-- entry with `settlementId` so killEnemy can special-case it (see there).
--
-- `cell`: which grid cell (see shared/GridConfig) this settlement is in.
-- Only that cell's running server spawns/tracks it.

local Settlements = {}

Settlements.defs = {
	ruins_north = {
		name = "Bosque del Norte",
		cell = "A",
		position = Vector3.new(20, 0, 40),
		radius = 22, -- studs; buff applies to guild members standing inside this
		challengerRespawn = 7200, -- 2h after a capture before a challenger appears to contest it
		graceSeconds = 600, -- 10 min a fresh capture is safe from being flipped back
		buff = {
			resourceMult = 0.25, -- +25% gathering yield inside the radius, owner's guild only
		},
		guardian = {
			name = "Protector del Bosque",
			hp = 420,
			ad = 22,
			ap = 0,
			damageKind = "physical",
			armor = 30,
			magicResist = 20,
			minLevel = 9,
			maxLevel = 12, -- fixed level: a boss doesn't need the day/night roll range
			xpReward = 220,
			attackCooldown = 1.8,
			walkSpeed = 10,
			aggroRange = 40,
			attackRange = 7,
			lootSource = "ruins_guardian",
			size = Vector3.new(6, 8, 6),
			color = Color3.fromRGB(120, 40, 40),
			material = Enum.Material.SmoothPlastic,
		},
	},
}

return Settlements
