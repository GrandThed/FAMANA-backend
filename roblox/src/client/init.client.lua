-- Client entry point. Rojo turns this folder into a LocalScript named "Client";
-- the UI modules are its children.

local HudUI = require(script:WaitForChild("HudUI"))
local InventoryUI = require(script:WaitForChild("InventoryUI"))
local BorderFadeUI = require(script:WaitForChild("BorderFadeUI"))
local NotificationUI = require(script:WaitForChild("NotificationUI"))
local ShiftLockController = require(script:WaitForChild("ShiftLockController"))
local TargetingController = require(script:WaitForChild("TargetingController"))
local ChatConfig = require(script:WaitForChild("ChatConfig"))

HudUI.start()
InventoryUI.start()
BorderFadeUI.start()
NotificationUI.start()
ShiftLockController.start()
TargetingController.start()
ChatConfig.start()
