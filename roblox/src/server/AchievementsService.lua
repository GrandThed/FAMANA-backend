-- Checks every shared/Achievements.lua entry against the player's current
-- stats whenever something that could complete one happens, and grants the
-- gold reward the first time it does. Same decoupled-hook pattern as
-- QuestService/BestiaryService: reads other services' onX hooks, never
-- touches combat/crafting/gathering itself. See docs/ACHIEVEMENTS.md.
--
-- Stat bumping is split from the check: PlayerService.bumpGathered/
-- bumpCrafted/bumpQuestsCompleted own writing profile.stats (kills reuse
-- BestiaryService's bestiaryKills directly, no separate counter needed);
-- this module just reacts to the same events to re-run checkAll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Achievements = require(Shared:WaitForChild("Achievements"))
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local GatheringService = require(script.Parent.GatheringService)
local CraftingService = require(script.Parent.CraftingService)
local QuestService = require(script.Parent.QuestService)
local Remotes = require(Shared:WaitForChild("Remotes"))

local AchievementsService = {}

local notifyRemote

-- Re-checks every not-yet-unlocked achievement for `player` and grants any
-- that just became complete. Cheap: shared/Achievements.LIST is a short,
-- fixed catalog, and unlockAchievement is a no-op past the first time.
local function checkAll(player)
	local stats = PlayerService.getAchievementStats(player)
	if not stats then
		return
	end
	for _, def in ipairs(Achievements.LIST) do
		if Achievements.isComplete(def, stats) then
			if PlayerService.unlockAchievement(player, def.id) then
				local reward = def.reward or {}
				if reward.gold then
					PlayerService.addGold(player, reward.gold)
				end
				if notifyRemote then
					notifyRemote:FireClient(
						player,
						string.format("🏆 Achievement unlocked: %s%s", def.name, reward.gold and (" (+" .. reward.gold .. "g)") or "")
					)
				end
			end
		end
	end
end

function AchievementsService.start()
	notifyRemote = Remotes.get("Notify")

	EnemyService.onKilled(function(_lootSource, _position, killer, _level)
		if killer and killer:IsA("Player") then
			checkAll(killer)
		end
	end)

	GatheringService.onGathered(function(player, itemId, amount)
		PlayerService.bumpGathered(player, itemId, amount)
		checkAll(player)
	end)

	CraftingService.onCrafted(function(player, _recipeId, quantity)
		PlayerService.bumpCrafted(player, quantity)
		checkAll(player)
	end)

	QuestService.onCompleted(function(player, _questId)
		PlayerService.bumpQuestsCompleted(player)
		checkAll(player)
	end)

	PlayerService.registerLevelUpHandler(function(player)
		checkAll(player)
	end)
end

return AchievementsService
