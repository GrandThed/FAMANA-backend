-- Bumps a player's lifetime kill count per enemy `lootSource` on every kill,
-- so EnemyInspectUI/BestiaryUI can reveal drop info progressively (see
-- docs/BESTIARY.md, shared/Bestiary.lua). Same decoupled-hook pattern as
-- QuestService/DropService: reads EnemyService.onKilled, never touches
-- combat or drops itself.
--
-- Persistence: PlayerService.bumpBestiaryKill mutates profile.bestiaryKills
-- in the cache and republishes the BestiaryKills attribute immediately; the
-- row itself rides the normal autosave/leave save, same as quest kill
-- objectives — no immediate save needed for a single kill tick.

local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)

local BestiaryService = {}

local function onEnemyKilled(lootSource, _position, killer, _level)
	if not (killer and killer:IsA("Player")) then
		return
	end
	PlayerService.bumpBestiaryKill(killer, lootSource)
end

function BestiaryService.start()
	EnemyService.onKilled(onEnemyKilled)
end

return BestiaryService
