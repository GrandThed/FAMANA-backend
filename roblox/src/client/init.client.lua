-- Client entry point. Rojo turns this folder into a LocalScript named "Client";
-- the UI modules are its children.

local ContentSync = require(script:WaitForChild("ContentSync"))
local HudUI = require(script:WaitForChild("HudUI"))
local InventoryUI = require(script:WaitForChild("InventoryUI"))
local BorderFadeUI = require(script:WaitForChild("BorderFadeUI"))
local NotificationUI = require(script:WaitForChild("NotificationUI"))
local StoreUI = require(script:WaitForChild("StoreUI"))
local ShiftLockController = require(script:WaitForChild("ShiftLockController"))
local TargetingController = require(script:WaitForChild("TargetingController"))
local ChatConfig = require(script:WaitForChild("ChatConfig"))

ContentSync.start() -- first: overlays backend item defs onto the mirror
HudUI.start()
InventoryUI.start()
BorderFadeUI.start()
NotificationUI.start()
StoreUI.start()
ShiftLockController.start()
TargetingController.start()
ChatConfig.start()
