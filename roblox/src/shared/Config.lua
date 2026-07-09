-- Shared, non-secret constants. Visible to client and server.
-- (The API key is NOT here — it lives server-only in Secret.lua.)

-- Note: which grid cell a Place represents now lives in GridConfig (derived
-- from PlaceId), not here.

return {
	-- The main inventory grid: fixed width, `height` rows for the basic
	-- backpack (bigger packs add rows later). MUST match backend items.js GRID.
	inventoryGrid = { width = 10, height = 30 },

	-- Reach (studs) now lives per-item as a `reach` stat on each weapon/tool def
	-- (see Items.lua). Server combat/gather and client focus all read that single
	-- value. This is the fallback for any equippable that forgot to set one.
	defaultReach = 9,

	HP = {
		max = 100,
		regenAmount = 1, -- HP restored per tick
		regenInterval = 2, -- seconds between regen ticks
		regenDelay = 5, -- seconds out of combat before regen starts
		respawnDelay = 5, -- seconds after death before respawning

		-- Downed state (a lethal hit downs instead of killing outright):
		downedBleedTime = 15, -- seconds before a downed player dies for real
		downedReviveTime = 4, -- seconds an ally must hold the revive prompt
		downedReviveHealPercent = 0.5, -- HP fraction restored on a full revive
		downedWalkSpeed = 4, -- crawl speed while downed
	},

	-- Mana: a live gameplay resource (not persisted) that powers ranged magic.
	-- Regenerates steadily; the staff spends it per cast (see Items manaCost).
	Mana = {
		max = 100,
		regenAmount = 3, -- mana restored per tick
		regenInterval = 1, -- seconds between regen ticks
	},

	-- How often the server persists HP/position to the backend.
	autosaveInterval = 60,

	-- Combat feel: chance for a weapon swing to land as a critical hit, and
	-- the damage multiplier applied when it does. Read by EnemyService.
	Combat = {
		critChance = 0.15, -- 15% of hits crit
		critMultiplier = 2, -- crits deal 2x damage

		-- Mob levels: each spawn rolls a random level in its def's
		-- [minLevel, maxLevel] range. Every level above 1 scales the mob's
		-- base hp/damage/xp reward by these fractions (linear, not compounding).
		mobLevel = {
			hpPerLevel = 0.15, -- +15% hp per level above 1
			damagePerLevel = 0.10, -- +10% damage per level above 1
			xpPerLevel = 0.20, -- +20% xp reward per level above 1
		},
	},

	-- Player leveling curve. xpToNext(level) = baseXp + (level-1)*xpPerLevel.
	-- Purely cosmetic for now (level + progress bar) — no stat bonuses yet.
	-- The class system (Archer/Berserker/Knight) will read `level` later to
	-- apply its own per-class bonuses on top of this.
	PlayerLeveling = {
		baseXp = 50, -- xp needed to go from level 1 -> 2
		xpPerLevel = 25, -- extra xp required per level after that
		maxLevel = 60, -- soft cap; xp stops accruing once reached
	},

	-- Parties: solo en la memoría del sv, no en la base de datos
	Party = {
		maxSize = 6,
		inviteTimeout = 30, -- las invitaciones sn validas por 30 segs
		xpShareRadius = 60, -- radio para compartir xp entre miembros de party
	},
}
