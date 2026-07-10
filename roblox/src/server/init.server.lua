-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local ContentService = require(script:WaitForChild("ContentService"))
local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ManaService = require(script:WaitForChild("ManaService"))
local ClassService = require(script:WaitForChild("ClassService"))
local PartyService = require(script:WaitForChild("PartyService"))
local ToolService = require(script:WaitForChild("ToolService"))
local TargetService = require(script:WaitForChild("TargetService"))
local GatheringService = require(script:WaitForChild("GatheringService"))
local EnemyService = require(script:WaitForChild("EnemyService"))
local EffectService = require(script:WaitForChild("EffectService"))
local SpellService = require(script:WaitForChild("SpellService"))
local SynergyService = require(script:WaitForChild("SynergyService"))
local ClassPassiveService = require(script:WaitForChild("ClassPassiveService"))
local DropService = require(script:WaitForChild("DropService"))
local ItemStandService = require(script:WaitForChild("ItemStandService"))
local VendorService = require(script:WaitForChild("VendorService"))
local CraftingService = require(script:WaitForChild("CraftingService"))
local QuestService = require(script:WaitForChild("QuestService"))
local BorderService = require(script:WaitForChild("BorderService"))
local WorldService = require(script:WaitForChild("WorldService"))
local AdminSyncService = require(script:WaitForChild("AdminSyncService"))

-- Cell-only services (border teleports, cell theming) don't start in
-- instance places (dungeons, housing — see GridConfig.places).
local role = GridConfig.currentRole()

ContentService.start() -- first: overlays backend item defs onto the mirror
if role == "cell" then
	WorldService.start()
end
PlayerService.start()
HealthService.start()
ManaService.start()
ClassService.start() -- after ManaService: overrides its CharacterAdded refill with class-scaled caps
PartyService.start() -- before EnemyService: it reads party membership to share kill xp
ToolService.start()
TargetService.start()
GatheringService.start()
EnemyService.start()
EffectService.start() -- after EnemyService: hooks onPlayerHit
SpellService.start() -- after EnemyService/EffectService: registers damage hooks
SynergyService.start() -- equipment trait synergies: registers stat hooks everywhere
ClassPassiveService.start() -- per-class level passive: registers the same-style hooks, no equipment involved
DropService.start()
ItemStandService.start() -- after DropService: stands spawn drops
VendorService.start()
CraftingService.start()
QuestService.start() -- after EnemyService/GatheringService: hooks their onKilled/onGathered
if role == "cell" then
	BorderService.start()
end
AdminSyncService.start()

if role == "cell" then
	print("[FAMANA] Server systems started (cell " .. GridConfig.currentCell() .. ").")
else
	print("[FAMANA] Server systems started (role " .. role .. ").")
end
