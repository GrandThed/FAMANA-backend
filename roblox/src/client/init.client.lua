-- Client entry point. Rojo turns this folder into a LocalScript named "Client";
-- the UI modules are its children.

local HealthUI = require(script:WaitForChild("HealthUI"))
local InventoryUI = require(script:WaitForChild("InventoryUI"))
local BorderFadeUI = require(script:WaitForChild("BorderFadeUI"))
local NotificationUI = require(script:WaitForChild("NotificationUI"))
local CameraFaceController = require(script:WaitForChild("CameraFaceController"))
local TargetingController = require(script:WaitForChild("TargetingController"))

HealthUI.start()
InventoryUI.start()
BorderFadeUI.start()
NotificationUI.start()
CameraFaceController.start()
TargetingController.start()
