-- Shared, non-secret constants. Visible to client and server.
-- (The API key is NOT here — it lives server-only in Secret.lua.)

return {
	-- Which grid cell this Place represents. Cell B's Place will set this to "B".
	cell = "A",

	inventoryCapacity = 20,

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
