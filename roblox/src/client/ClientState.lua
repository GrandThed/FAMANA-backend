-- Shared client-side control/UI state. A plain mutable table read by the client
-- controllers so they can coordinate without requiring each other directly.

return {
	aiming = false, -- right mouse button held → enemy targeting is active
	inventoryOpen = false, -- inventory panel visible → free the cursor for clicks
	storeOpen = false, -- vendor trade screen visible → same treatment as the inventory
	questOpen = false, -- quest giver panel visible → same treatment as the inventory
	spellHover = false, -- hovering a spell row in the tracker → number keys bind, not cast

	-- Cross-close hooks: the inventory and store screens overlap, so opening
	-- one closes the other. Each screen registers its close() here at start —
	-- a plain callback slot instead of a require cycle.
	closeInventory = nil, -- set by InventoryUI
	closeStore = nil, -- set by StoreUI
	closeQuest = nil, -- set by QuestUI
}
