-- Bestiary: turns a player's lifetime kill count against a `lootSource`
-- (EnemyService.ENEMY_DEFS[...].lootSource, same key Loot.TABLE/Loot.GEAR
-- are indexed by) into a reveal TIER — how much of that enemy's drop table
-- the client is allowed to show. See docs/BESTIARY.md.
--
-- Tier 0: never killed — nothing revealed (EnemyInspectUI/BestiaryUI show
--         it as an unknown entry, no stats/drops).
-- Tier 1 (1 kill):  confirms the entry exists — reveals the "always/common"
--         drops (Loot entries tagged tier = 1).
-- Tier 2 (10 kills): reveals uncommon drops (tier = 2).
-- Tier 3 (30 kills): reveals rare drops and the Loot.GEAR pool (tier = 3).
--
-- Numbers are a starting point for playtesting (docs/BESTIARY.md), not
-- final — tune TIER_THRESHOLDS, not the call sites.
local Bestiary = {}

Bestiary.TIER_THRESHOLDS = { 1, 10, 30 }

-- Display name per lootSource, for the full bestiary panel (BestiaryUI) —
-- EnemyService.ENEMY_DEFS (the source of truth for the `name` field) is a
-- server-only module, so this small mirror is what the client can require.
-- Keep in sync by hand when ENEMY_DEFS gains a new `lootSource`; an entry
-- missing here just falls back to the raw id (see BestiaryUI.displayName).
Bestiary.NAMES = {
	slime = "Slime",
	goblin = "Goblin",
}

-- Every lootSource with a known drop table (Loot.TABLE or Loot.GEAR),
-- sorted for stable display order. Enemies without loot data yet (e.g. an
-- ENEMY_DEFS entry added before its Loot.TABLE row) simply don't appear —
-- there'd be nothing to reveal.
function Bestiary.knownSources(Loot)
	local seen = {}
	local sources = {}
	for source in pairs(Loot.TABLE) do
		if not seen[source] then
			seen[source] = true
			table.insert(sources, source)
		end
	end
	for source in pairs(Loot.GEAR) do
		if not seen[source] then
			seen[source] = true
			table.insert(sources, source)
		end
	end
	table.sort(sources)
	return sources
end

-- Highest tier unlocked by `kills` (0 if the enemy has never been killed).
function Bestiary.tierForKills(kills)
	kills = tonumber(kills) or 0
	local tier = 0
	for i, threshold in ipairs(Bestiary.TIER_THRESHOLDS) do
		if kills >= threshold then
			tier = i
		end
	end
	return tier
end

-- Kills still needed to reach the next tier, or nil if already maxed.
function Bestiary.killsToNextTier(kills)
	kills = tonumber(kills) or 0
	local tier = Bestiary.tierForKills(kills)
	if tier >= #Bestiary.TIER_THRESHOLDS then
		return nil
	end
	local nextThreshold = Bestiary.TIER_THRESHOLDS[tier + 1]
	return nextThreshold - kills
end

-- Whether a Loot entry/pool tagged with `entryTier` (1/2/3) is revealed yet
-- given `kills` against that lootSource. Entries with no tier default to 1
-- (always revealed on first kill) so existing Loot data without a `tier`
-- field doesn't silently disappear.
function Bestiary.isRevealed(entryTier, kills)
	return Bestiary.tierForKills(kills) >= (entryTier or 1)
end

return Bestiary
