-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local ContentService = require(script:WaitForChild("ContentService"))
local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ManaService = require(script:WaitForChild("ManaService"))
local ToolService = require(script:WaitForChild("ToolService"))
local TargetService = require(script:WaitForChild("TargetService"))
local GatheringService = require(script:WaitForChild("GatheringService"))
local EnemyService = require(script:WaitForChild("EnemyService"))
local EffectService = require(script:WaitForChild("EffectService"))
local DropService = require(script:WaitForChild("DropService"))
local ItemStandService = require(script:WaitForChild("ItemStandService"))
local BorderService = require(script:WaitForChild("BorderService"))
local WorldService = require(script:WaitForChild("WorldService"))
local AdminSyncService = require(script:WaitForChild("AdminSyncService"))

ContentService.start() -- first: overlays backend item defs onto the mirror
WorldService.start()
PlayerService.start()
HealthService.start()
ManaService.start()
ToolService.start()
TargetService.start()
GatheringService.start()
EnemyService.start()
EffectService.start() -- after EnemyService: hooks onPlayerHit
DropService.start()
ItemStandService.start() -- after DropService: stands spawn drops
BorderService.start()
AdminSyncService.start()

print("[FAMANA] Server systems started (cell " .. GridConfig.currentCell() .. ").")
