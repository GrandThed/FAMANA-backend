-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ToolService = require(script:WaitForChild("ToolService"))
local GatheringService = require(script:WaitForChild("GatheringService"))
local EnemyService = require(script:WaitForChild("EnemyService"))
local DropService = require(script:WaitForChild("DropService"))

PlayerService.start()
HealthService.start()
ToolService.start()
GatheringService.start()
EnemyService.start()
DropService.start()

print("[FAMANA] Server systems started (cell "
	.. require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")).cell
	.. ").")
