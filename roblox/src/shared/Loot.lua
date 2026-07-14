-- Shared loot tables — single source of truth for what each enemy type can
-- drop, so both the server (DropService, which actually rolls kills into
-- ground drops) and the client (EnemyInspectUI's "Drops" section on the
-- scout card) agree on the odds without a remote round-trip.
--
-- Loot.TABLE: [lootSource] = { { itemId, chance, min, max }, ... } — each
-- entry rolls independently on kill (DropService.rollLoot).
-- Loot.GEAR: [lootSource] = { chance, pool } — on a hit, one base item from
-- `pool` rolls with instance meta (shared/Traits); `chance` gates whether
-- anything drops at all, the pool item itself is picked uniformly.

local Loot = {}

Loot.TABLE = {
	slime = {
		{ itemId = "slime_goo", chance = 1.0, min = 1, max = 1 },
		{ itemId = "wood", chance = 0.25, min = 1, max = 1 },
	},
	goblin = {
		{ itemId = "goblin_ear", chance = 1.0, min = 1, max = 1 },
		{ itemId = "stone", chance = 0.4, min = 1, max = 2 },
		{ itemId = "sword_iron", chance = 0.05, min = 1, max = 1 }, -- rare
	},
}

Loot.GEAR = {
	slime = { chance = 0.08, pool = { "ring_vitality", "ring_focus" } },
	goblin = {
		chance = 1.0, -- goblins ALWAYS drop a rolled piece (decided 2026-07-06)
		pool = {
			"sword_basic",
			"helmet_leather",
			"chest_leather",
			"gloves_leather",
			"legs_leather",
			"boots_leather",
		},
	},
}

return Loot
