-- Shared, non-secret constants. Visible to client and server.
-- (The API key is NOT here — it lives server-only in Secret.lua.)

-- Note: which grid cell a Place represents now lives in GridConfig (derived
-- from PlaceId), not here.

return {
	inventoryCapacity = 20,

	-- Effective reach (studs) of tools/weapons. Used by the server to validate
	-- combat/gather and by the client to decide what can be focused.
	reach = {
		weapon = 9, -- sword melee
		axe = 12, -- tree gather
		pickaxe = 12, -- rock gather
	},

	HP = {
		max = 100,
		regenAmount = 1, -- HP restored per tick
		regenInterval = 2, -- seconds between regen ticks
		regenDelay = 5, -- seconds out of combat before regen starts
		respawnDelay = 5, -- seconds after death before respawning
	},

	-- How often the server persists HP/position to the backend.
	autosaveInterval = 60,
}
