-- Aethelgard design tokens (docs/UI.md §2, converted 1:1 to Color3/Font).
-- Every client UI reads colors/fonts/sizes from here — no inline RGB in the
-- UI modules. Global rules (§0): sharp corners everywhere except orbs and
-- small chips; one ember accent; two serif families, no sans; no UICorner
-- on panels; borders are UIStrokes, gradients are UIGradients.
--
-- RARITY colors are NOT here — they live in shared/Rarity.lua (the server
-- needs them for drop labels); this module is client-only chrome.

local Theme = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- ---- colors -----------------------------------------------------------------
Theme.Color = {
	-- Ink (backgrounds & panels)
	Ink900 = rgb(8, 5, 5),
	Ink850 = rgb(11, 7, 7),
	Ink800 = rgb(12, 8, 8),
	Ink750 = rgb(19, 12, 12),
	Ink700 = rgb(23, 15, 15),
	Ink650 = rgb(26, 18, 16),
	Ink600 = rgb(30, 20, 20),
	-- Stone (structure)
	Stone800 = rgb(46, 30, 26),
	Stone700 = rgb(58, 38, 32),
	Stone600 = rgb(61, 42, 34),
	Stone500 = rgb(74, 50, 38),
	StoneLine = rgb(42, 26, 22),
	-- Ember (the one accent)
	Ember600 = rgb(90, 32, 16),
	Ember500 = rgb(138, 58, 30),
	Ember400 = rgb(200, 106, 58),
	Ember300 = rgb(214, 100, 42), -- primary accent
	Ember200 = rgb(232, 132, 58),
	-- Blood (danger)
	Blood600 = rgb(58, 28, 20),
	Blood500 = rgb(107, 50, 38),
	Blood400 = rgb(214, 122, 90),
	-- Gold / bone
	Gold400 = rgb(232, 184, 79),
	Gold300 = rgb(232, 206, 172),
	NameGold = rgb(224, 168, 106),
	-- Parchment text ramp
	Parch100 = rgb(240, 228, 208),
	Parch200 = rgb(216, 200, 184),
	Parch300 = rgb(184, 152, 120),
	Parch400 = rgb(138, 106, 84),
	Parch500 = rgb(122, 80, 64),
	Parch600 = rgb(106, 74, 58),
	BrownLabel = rgb(138, 90, 68),
	-- Cool metals / mana
	Steel400 = rgb(205, 214, 222),
	Steel600 = rgb(90, 99, 108),
	Mana400 = rgb(58, 122, 198),
	Mana600 = rgb(20, 48, 106),
}

-- Semantic aliases — UI code references these, not raw ramp names.
local C = Theme.Color
Theme.Semantic = {
	PanelTop = C.Ink700,
	PanelBot = C.Ink800,
	SurfaceWell = C.Ink850,
	BorderPanel = C.Stone600,
	BorderSlot = C.Stone600,
	BorderMuted = C.Stone700,
	BorderDivider = C.Stone500,
	BorderHair = C.StoneLine,
	TextTitle = C.Gold300,
	TextHero = C.NameGold,
	TextBody = C.Parch200,
	TextStrong = C.Parch100,
	TextSecondary = C.Parch300,
	TextMuted = C.Parch400,
	TextDim = C.Parch500,
	TextFaint = C.Parch600,
	TextLabel = C.BrownLabel,
	Accent = C.Ember300,
	AccentHi = C.Ember200,
	AccentShadow = C.Ember600,
	Currency = C.Gold400,
	Danger = C.Blood400,
	Good = rgb(127, 176, 85), -- fits/valid (uncommon green family)
	Bad = C.Blood400,
}

-- Status orbs (§6.7): top→bottom fill ramp + ring color.
Theme.Orb = {
	HpTop = rgb(214, 74, 58),
	HpBottom = rgb(122, 24, 16),
	HpRing = rgb(46, 18, 12),
	ManaTop = rgb(58, 122, 198),
	ManaBottom = rgb(20, 48, 106),
	ManaRing = rgb(14, 30, 52),
}

-- ---- trait tiers (hex badge metals, §6.3) --------------------------------------
Theme.Tier = {
	Inactive = { border = C.Stone700, fill = C.Ink650, icon = C.Parch600 },
	Bronze = { border = rgb(192, 132, 74), fill = rgb(62, 38, 18), icon = rgb(244, 216, 184) },
	Silver = { border = rgb(205, 214, 222), fill = rgb(46, 52, 58), icon = rgb(255, 255, 255) },
	Gold = { border = rgb(240, 196, 76), fill = rgb(78, 58, 14), icon = rgb(255, 244, 208) },
	Prismatic = { border = rgb(255, 255, 255), fill = rgb(20, 16, 25), icon = rgb(255, 255, 255) },
}
Theme.PrismaticSequence = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, rgb(224, 118, 58)),
	ColorSequenceKeypoint.new(0.20, rgb(240, 196, 76)),
	ColorSequenceKeypoint.new(0.40, rgb(143, 176, 90)),
	ColorSequenceKeypoint.new(0.60, rgb(106, 164, 224)),
	ColorSequenceKeypoint.new(0.80, rgb(167, 106, 214)),
	ColorSequenceKeypoint.new(1.00, rgb(224, 118, 58)),
})

-- The metal tier for `reached` of `total` thresholds: Inactive below the
-- first, Prismatic at the cap, else Bronze/Silver/Gold by progress.
function Theme.tierFor(reached, total)
	if reached <= 0 then
		return Theme.Tier.Inactive
	end
	if reached >= total then
		return Theme.Tier.Prismatic
	end
	local fraction = reached / total
	if fraction <= 1 / 3 then
		return Theme.Tier.Bronze
	elseif fraction <= 2 / 3 then
		return Theme.Tier.Silver
	end
	return Theme.Tier.Gold
end

-- ---- type ---------------------------------------------------------------------
-- Two Roblox-native serifs (§3). Guarded lookup: if a Studio build lacks the
-- family, everything falls back to Gotham instead of erroring the UI away.
local function fontFromEnum(name, weight, style)
	local ok, font = pcall(function()
		local family = Font.fromEnum(Enum.Font[name])
		if weight or style then
			return Font.new(family.Family, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal)
		end
		return family
	end)
	if ok then
		return font
	end
	return Font.fromEnum(weight and Enum.Font.GothamBold or Enum.Font.Gotham)
end

Theme.Font = {
	Display = fontFromEnum("GrenzeGotisch"),
	DisplayBold = fontFromEnum("GrenzeGotisch", Enum.FontWeight.SemiBold),
	Body = fontFromEnum("Merriweather"),
	BodyBold = fontFromEnum("Merriweather", Enum.FontWeight.Bold),
	BodyItalic = fontFromEnum("Merriweather", nil, Enum.FontStyle.Italic), -- flavor text
}

-- Text sizes (px at the 1280×720 design resolution).
Theme.Text = {
	Title = 23,
	Hero = 19,
	Item = 18,
	Lg = 15,
	Body = 13,
	Sm = 12,
	Xs = 11,
	Label = 10,
	Micro = 8,
}

-- ---- spacing & geometry ---------------------------------------------------------
Theme.Space = { s1 = 3, s2 = 5, s3 = 8, s4 = 12, s5 = 16, s6 = 24, s7 = 40 }
Theme.Size = {
	Cell = 42, -- inventory grid module (the spine)
	Slot = 46, -- equipment slot
	Chip = 30,
	BorderW = 1,
	BorderW2 = 2,
}

-- ---- motion (§11) ---------------------------------------------------------------
Theme.Tween = {
	UI = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
}

return Theme
