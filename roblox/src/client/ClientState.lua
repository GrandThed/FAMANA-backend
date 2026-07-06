-- Shared client-side control/UI state. A plain mutable table read by the client
-- controllers so they can coordinate without requiring each other directly.

return {
	aiming = false, -- right mouse button held → enemy targeting is active
	inventoryOpen = false, -- inventory panel visible → free the cursor for clicks
	spellHover = false, -- hovering a spell row in the tracker → number keys bind, not cast
}
