-- Achievement catalog + pure progress math, shared by AchievementsService
-- (server, decides unlocks + grants rewards) and AchievementsUI (client,
-- renders progress bars) — see docs/ACHIEVEMENTS.md.
--
-- `Achievements.progress(metric, target, stats)` is the single source of
-- truth for "how far along is this achievement", called on both sides
-- against a `stats` table shaped the same way whether it's the server's
-- live profile or the client's replicated mirror:
--   stats.bestiaryKills      = { [lootSource] = count }      (shared/Bestiary.lua)
--   stats.gathered           = { [itemId] = count }
--   stats.crafted            = count
--   stats.maxClassLevel      = highest level reached by any class
--   stats.questsCompleted    = count
local Achievements = {}

-- id, name, description, metric, target (optional, metric-specific),
-- amount (progress needed), reward (gold only for now).
Achievements.LIST = {
	{
		id = "first_blood",
		name = "First Blood",
		description = "Kill your first enemy.",
		metric = "kills_total",
		amount = 1,
		reward = { gold = 25 },
	},
	{
		id = "slime_slayer",
		name = "Slime Slayer",
		description = "Kill 50 slimes.",
		metric = "kills",
		target = "slime",
		amount = 50,
		reward = { gold = 50 },
	},
	{
		id = "goblin_bane",
		name = "Goblin Bane",
		description = "Kill 50 goblins.",
		metric = "kills",
		target = "goblin",
		amount = 50,
		reward = { gold = 50 },
	},
	{
		id = "woodcutter",
		name = "Woodcutter",
		description = "Gather 100 wood.",
		metric = "gathered",
		target = "wood",
		amount = 100,
		reward = { gold = 40 },
	},
	{
		id = "artisan",
		name = "Artisan",
		description = "Craft 25 items.",
		metric = "crafted",
		amount = 25,
		reward = { gold = 60 },
	},
	{
		id = "adventurer",
		name = "Adventurer",
		description = "Reach level 10 with any class.",
		metric = "level",
		amount = 10,
		reward = { gold = 100 },
	},
	{
		id = "quest_regular",
		name = "Quest Regular",
		description = "Complete 5 quests.",
		metric = "questsCompleted",
		amount = 5,
		reward = { gold = 75 },
	},
}

-- Current progress toward `metric`/`target` given a `stats` table (see
-- header comment for its shape). Unknown metrics return 0 rather than
-- erroring — a stats table missing a field just reads as "no progress yet".
function Achievements.progress(metric, target, stats)
	stats = stats or {}
	if metric == "kills_total" then
		local total = 0
		for _, count in pairs(stats.bestiaryKills or {}) do
			total += count
		end
		return total
	elseif metric == "kills" then
		return (stats.bestiaryKills or {})[target] or 0
	elseif metric == "gathered" then
		return (stats.gathered or {})[target] or 0
	elseif metric == "crafted" then
		return stats.crafted or 0
	elseif metric == "level" then
		return stats.maxClassLevel or 0
	elseif metric == "questsCompleted" then
		return stats.questsCompleted or 0
	end
	return 0
end

-- true once `def`'s progress has reached its target.
function Achievements.isComplete(def, stats)
	return Achievements.progress(def.metric, def.target, stats) >= def.amount
end

return Achievements
