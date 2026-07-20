-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local ContentService = require(script:WaitForChild("ContentService"))
local MeshAssetService = require(script:WaitForChild("MeshAssetService"))
local DayNightService = require(script:WaitForChild("DayNightService"))
local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ManaService = require(script:WaitForChild("ManaService"))
local ClassService = require(script:WaitForChild("ClassService"))
local PartyService = require(script:WaitForChild("PartyService"))
local GuildService = require(script:WaitForChild("GuildService"))
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
local CampService = require(script:WaitForChild("CampService"))
local CampFurnitureService = require(script:WaitForChild("CampFurnitureService"))
local RestedService = require(script:WaitForChild("RestedService"))
local CampArchitectService = require(script:WaitForChild("CampArchitectService"))
local QuestService = require(script:WaitForChild("QuestService"))
local BestiaryService = require(script:WaitForChild("BestiaryService"))
local MarkerService = require(script:WaitForChild("MarkerService"))
local BorderService = require(script:WaitForChild("BorderService"))
local WorldService = require(script:WaitForChild("WorldService"))
local AdminSyncService = require(script:WaitForChild("AdminSyncService"))

-- Cell-only services (border teleports, cell theming) don't start in
-- instance places (dungeons, housing — see GridConfig.places).
local role = GridConfig.currentRole()

ContentService.start() -- first: overlays backend item defs onto the mirror
MeshAssetService.start() -- loads the Style-A mesh models before the world builds; ArtKit looks are the fallback
DayNightService.start() -- ticks Lighting.ClockTime; runs everywhere (not gated by role) so isNight() is always meaningful
if role == "cell" then
	WorldService.start()
end
PlayerService.start()
HealthService.start()
ManaService.start()
ClassService.start() -- after ManaService: overrides its CharacterAdded refill with class-scaled caps
PartyService.start() -- before EnemyService: it reads party membership to share kill xp
GuildService.start() -- persisted membership (backend-backed), independent of Party
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
CampService.start() -- después de CraftingService: consume el item "acampada" que esta produce
CampFurnitureService.start() -- después de CampService: mobiliario solo se planta dentro de una acampada activa
RestedService.start() -- banca el buff "Descansado" mientras estás en un camp seguro de noche (reemplaza el viejo bonus de regen por coziness)
CampArchitectService.start() -- independiente de los otros dos: solo lee/escribe PlayerService.campTier
QuestService.start() -- after EnemyService/GatheringService: hooks their onKilled/onGathered
BestiaryService.start() -- after EnemyService: hooks onKilled, bumps lifetime kill counts
MarkerService.start() -- after PartyService (lee membresía) y EnemyService/DropService (valida anchors)
if role == "cell" then
	BorderService.start()
end
AdminSyncService.start()

if role == "cell" then
	print("[FAMANA] Server systems started (cell " .. GridConfig.currentCell() .. ").")
else
	print("[FAMANA] Server systems started (role " .. role .. ").")
end
