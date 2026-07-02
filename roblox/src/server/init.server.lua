-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GridConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GridConfig"))

local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ToolService = require(script:WaitForChild("ToolService"))
local GatheringService = require(script:WaitForChild("GatheringService"))
local EnemyService = require(script:WaitForChild("EnemyService"))
local DropService = require(script:WaitForChild("DropService"))
local BorderService = require(script:WaitForChild("BorderService"))
local WorldService = require(script:WaitForChild("WorldService"))
local AdminSyncService = require(script:WaitForChild("AdminSyncService"))

WorldService.start()
PlayerService.start()
HealthService.start()
ToolService.start()
GatheringService.start()
EnemyService.start()
DropService.start()
BorderService.start()
AdminSyncService.start()

print("[FAMANA] Server systems started (cell " .. GridConfig.currentCell() .. ").")
