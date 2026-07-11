-- Low-poly art kit: the design frame for all part-built world assets.
-- The style is flat palette colors, SmoothPlastic, and a few chunky
-- rotated blocks instead of detail. Build assets declaratively with
-- ArtKit.build so everything stays on-style; new colors go in the
-- palette, not inline in builders.

local ArtKit = {}

-- Shared flat-color palette. Part specs reference colors by key so assets
-- stay consistent and retheming is a one-line change here.
ArtKit.Palette = {
	-- wood / foliage
	trunk = Color3.fromRGB(110, 76, 48),
	trunkDark = Color3.fromRGB(82, 56, 36),
	leaf = Color3.fromRGB(88, 156, 76),
	leafDark = Color3.fromRGB(62, 126, 60),
	leafLight = Color3.fromRGB(122, 180, 92),
	-- stone / earth
	stone = Color3.fromRGB(132, 134, 140),
	stoneDark = Color3.fromRGB(98, 100, 106),
	stoneLight = Color3.fromRGB(158, 160, 166),
	dirt = Color3.fromRGB(124, 92, 60),
	rust = Color3.fromRGB(150, 80, 54), -- iron ore veins
	-- metal / magic (tools, weapons)
	steel = Color3.fromRGB(188, 192, 202),
	steelDark = Color3.fromRGB(136, 140, 150),
	gold = Color3.fromRGB(206, 164, 74),
	magic = Color3.fromRGB(150, 90, 255),
	-- armor / trinkets
	leather = Color3.fromRGB(146, 96, 56),
	leatherDark = Color3.fromRGB(104, 66, 38),
	ruby = Color3.fromRGB(200, 62, 70),
	sapphire = Color3.fromRGB(64, 112, 200),
	-- people (vendor NPCs)
	skin = Color3.fromRGB(224, 178, 138),
	-- creatures (match ENEMY_DEFS so drops read as coming from their source)
	slime = Color3.fromRGB(80, 200, 120),
	goblin = Color3.fromRGB(90, 150, 70),
	goblinDark = Color3.fromRGB(64, 108, 50),
	ink = Color3.fromRGB(28, 32, 30), -- eyes, mouths, dark accents
}

-- One material everywhere is what sells the flat low-poly look.
ArtKit.Material = Enum.Material.SmoothPlastic

local function resolveColor(color)
	if typeof(color) == "Color3" then
		return color
	end
	-- Loud magenta fallback so a bad palette key is obvious in-game.
	return ArtKit.Palette[color] or Color3.fromRGB(255, 0, 255)
end

-- Creates one on-style part from a spec:
-- { name, shape = "Block"|"Ball"|"Cylinder"|"Wedge"|"CornerWedge",
--   size (Vector3), color (palette key or Color3), material?, canCollide?,
--   anchored? }
function ArtKit.part(spec)
	local shape = spec.shape or "Block"
	local part
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType[shape]
	end
	part.Name = spec.name or "Part"
	part.Size = spec.size
	part.Color = resolveColor(spec.color)
	part.Material = spec.material or ArtKit.Material
	part.Transparency = spec.transparency or 0
	part.Anchored = spec.anchored ~= false
	part.CanCollide = spec.canCollide ~= false
	return part
end

-- Builds a Model from part specs placed relative to an origin CFrame, so
-- assets can be dropped (and rotated) anywhere. Extra per-spec fields:
--   offset (Vector3, from origin) · rot (Vector3, degrees) · primary (bool)
-- PrimaryPart is the spec marked primary, else the first part.
function ArtKit.build(name, origin, specs)
	local model = Instance.new("Model")
	model.Name = name
	local primary
	for _, spec in ipairs(specs) do
		local part = ArtKit.part(spec)
		local rot = spec.rot or Vector3.zero
		part.CFrame = origin
			* CFrame.new(spec.offset or Vector3.zero)
			* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		part.Parent = model
		if spec.primary or not primary then
			primary = part
		end
	end
	model.PrimaryPart = primary
	return model
end

-- Welds detail parts onto a handle part (for held Tools and other physics
-- assemblies). Same specs as ArtKit.build with offsets relative to the
-- handle, but parts are unanchored, massless, non-colliding, and parented
-- under the handle so they follow it. `scale` (default 1) shrinks/grows the
-- whole assembly (sizes and offsets) — e.g. miniature ground drops.
function ArtKit.weld(handle, specs, scale)
	scale = scale or 1
	for _, spec in ipairs(specs) do
		local part = ArtKit.part(spec)
		part.Size = part.Size * scale
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false -- cosmetic; don't intercept raycasts (ground checks, aim)
		part.Massless = true
		local rot = spec.rot or Vector3.zero
		part.CFrame = handle.CFrame
			* CFrame.new((spec.offset or Vector3.zero) * scale)
			* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
		part.Parent = handle
	end
end

return ArtKit
