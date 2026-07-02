-- Client entry point. Rojo turns this folder into a LocalScript named "Client";
-- the UI modules are its children.

local HealthUI = require(script:WaitForChild("HealthUI"))
local InventoryUI = require(script:WaitForChild("InventoryUI"))

HealthUI.start()
InventoryUI.start()
