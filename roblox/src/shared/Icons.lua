-- UI icon asset registry (assets/icons_png — the design-system glyphs from
-- docs/UI.md §7: white-on-transparent 256px PNGs, tinted at runtime via
-- ImageColor3, previewed in assets/icons_png/contact-sheet.html).
--
-- To activate: upload the PNGs (Studio → View → Asset Manager → Bulk Import,
-- or create.roblox.com → Development Items → Images) and paste each asset id
-- into `ids` below. Every consumer falls back to the old emoji/text look
-- while an id is still 0, so the set can be filled in incrementally.

local Icons = {}

-- [file name in assets/icons_png] = rbxassetid number (0 = not uploaded yet)
Icons.ids = {
	-- trait / school glyphs
	Bastion = 125875089644187,
	Warden = 102241184690962,
	Brawler = 99075254279279,
	Berserker = 80745821021675,
	Blademaster = 135653541230944,
	Scout = 131123954844186,
	Ranger = 109091191980897,
	Sniper = 133789431809732,
	Lynx = 129162835561328,
	Pyromancer = 99557677233633,
	Mystic = 121135477483712,
	Trapper = 102329358004091,
	-- item glyphs
	Chest = 75574766693073,
	Sword = 70551384772884,
	Shield = 96526506293941,
	Boots = 91908404055483,
	Helm = 74009425908336,
	Potion = 128085265071136,
	Ring = 101001290942817,
	Gem = 96413547798576,
	Scroll = 130542583621138,
	Staff = 113000318775739,
	Ration = 123015992725896,
	Coin = 126066670953988,
	-- shape & effect helpers
	Hexagon = 138537098088899, -- flat-top hex badge (256x282, the §6.3 signature element)
	RadialGlow = 106577338725614,
	Shadow9Slice = 117191511679292,
}

-- Game trait/school ids → glyph name. The set was drawn for the mock's
-- placeholder trait list, so name-matches are exact and the rest are the
-- closest semantic fits — provisional picks (perseverance/invoker/justicar
-- especially), swap freely once bespoke glyphs are exported.
Icons.glyphFor = {
	-- stat traits (shared/Traits.lua)
	lynx_eye = "Lynx", -- the eye glyph
	agile_hands = "Blademaster", -- swift blades ≈ attack speed
	perseverance = "Scroll", -- lasting enchantments ≈ buff duration
	brawler = "Brawler", -- the fist
	bastion = "Bastion", -- the barred shield
	evasion = "Scout", -- the feather (light on your feet; scout reuses it)
	-- schools (shared/Spells.lua)
	pyromancer = "Pyromancer",
	arcanist = "Mystic", -- the arcane star
	invoker = "Gem", -- summoning crystal
	berserker = "Berserker",
	sentinel = "Warden", -- the guardian's shield
	justicar = "Sword", -- the blade of judgment
	sniper = "Sniper",
	trapper = "Trapper",
	scout = "Scout",
	-- class passives (shared/ClassPassives.lua) — reuse the closest existing
	-- glyph rather than commissioning dedicated art (Bastion/Lynx/Scroll/etc.
	-- are already used by unrelated equipment traits, so these pick the next
	-- best semantic fit instead of colliding with them).
	oakskin = "Shield", -- Knight: plain shield, distinct from Bastion (armor trait)
	hawk_eye = "Ranger", -- Archer: the ranger glyph (Lynx is taken by Lynx Eye)
	arcane_mastery = "Mystic", -- Mage: the arcane star
	vital_aura = "Potion", -- Cleric: the healing potion
}

-- "rbxassetid://N" for an uploaded asset name, or nil while it's still 0.
function Icons.image(name)
	local id = Icons.ids[name]
	if typeof(id) == "number" and id > 0 then
		return "rbxassetid://" .. id
	end
	return nil
end

-- The tintable glyph image for a trait/school id, or nil (callers fall back
-- to the def's emoji icon).
function Icons.forTrait(traitOrSchoolId)
	local name = Icons.glyphFor[traitOrSchoolId]
	if name then
		return Icons.image(name)
	end
	return nil
end

return Icons
