-- Loads the uploaded Style-A mesh models (shared/MeshAssets) at boot:
--   * item models  -> ReplicatedStorage.Assets[<itemId>], the custom-model
--     override folder ToolService/ItemModels already check first
--   * world models -> ReplicatedStorage.MeshModels[<key>], cloned via
--     get/place/weldVisual by the enemy/gathering/crafting services
-- Every load is a pcall: when an asset can't load (Studio without asset
-- access, moderation, offline) the game keeps its ArtKit fallback look —
-- same philosophy as ContentService's Luau mirrors.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))

local MeshAssetService = {}

local templates = {} -- [key] = Model, world models only

local LOAD_TIMEOUT = 15 -- seconds before boot proceeds with fallbacks

-- Palette keys sorted longest-first so substring matches pick the most
-- specific name (fam_wood_dark before fam_wood).
local paletteKeys = {}
for key in pairs(MeshAssets.palette) do
	table.insert(paletteKeys, key)
end
table.sort(paletteKeys, function(a, b)
	return #a > #b
end)

-- Flattens an inserted asset into one Model of anchored, non-colliding
-- SmoothPlastic parts (the art style) and sets PrimaryPart to the largest
-- part. The FBX pipeline drops material colors, so every part — exported as
-- one object per Blender material and named after it — is recolored by name
-- from MeshAssets.palette; *_emit parts glow.
local function normalize(container, name)
	local model = Instance.new("Model")
	model.Name = name

	local parts = {}
	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	local biggest, biggestVolume
	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.SmoothPlastic
		local lower = part.Name:lower()
		for _, key in ipairs(paletteKeys) do
			if string.find(lower, key, 1, true) then
				part.Color = MeshAssets.palette[key]
				break
			end
		end
		if string.find(lower, "_emit", 1, true) then
			part.Material = Enum.Material.Neon
			if string.find(lower, "orb", 1, true) then
				part.Name = "Orb" -- held Orb parts get ToolService's PointLight
			end
		end
		part.Parent = model
		local size = part.Size
		local volume = size.X * size.Y * size.Z
		if not biggest or volume > biggestVolume then
			biggest, biggestVolume = part, volume
		end
	end

	model.PrimaryPart = biggest
	return model
end

function MeshAssetService.get(key)
	return templates[key]
end

-- The mesh pipeline lands our baked -Z fronts on +Z, so both placement
-- helpers spin the visual 180° — game-side, a mesh model's front is -Z of
-- the origin/part it's placed on, same as the enemy convention.
local FRONT_FLIP = CFrame.Angles(0, math.pi, 0)

-- Clones a world template bottom-centered onto `origin` (a ground-level
-- CFrame; its rotation carries into the model, front lands on its -Z).
-- Returns nil when the template didn't load.
function MeshAssetService.place(key, origin, scale)
	local template = templates[key]
	if not template then
		return nil
	end
	local clone = template:Clone()
	if scale and scale ~= 1 then
		clone:ScaleTo(scale)
	end
	local bounds, size = clone:GetBoundingBox()
	clone:PivotTo(origin * FRONT_FLIP * CFrame.new(0, size.Y / 2, 0) * (bounds:Inverse() * clone:GetPivot()))
	return clone
end

-- Clones `key`'s template scaled to `targetHeight` studs, bottom-aligns it
-- to `part`'s footprint and welds it on (ArtKit.weld conventions: massless,
-- non-colliding, no raycast hits). Returns the visual Model, or nil.
function MeshAssetService.weldVisual(part, key, targetHeight)
	local template = templates[key]
	if not template then
		return nil
	end
	local visual = template:Clone()
	local _, size = visual:GetBoundingBox()
	if targetHeight and size.Y > 0 then
		visual:ScaleTo(targetHeight / size.Y)
	end
	local bounds, scaledSize = visual:GetBoundingBox()
	local target = part.CFrame * FRONT_FLIP * CFrame.new(0, -part.Size.Y / 2 + scaledSize.Y / 2, 0)
	visual:PivotTo(target * (bounds:Inverse() * visual:GetPivot()))
	for _, p in ipairs(visual:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = p
			weld.Parent = p
		end
	end
	visual.Name = "Visual"
	visual.Parent = part
	return visual
end

function MeshAssetService.start()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		assetsFolder = Instance.new("Folder")
		assetsFolder.Name = "Assets"
		assetsFolder.Parent = ReplicatedStorage
	end
	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "MeshModels"
	worldFolder.Parent = ReplicatedStorage

	local pending = 0
	local function load(key, def, finish)
		pending += 1
		task.spawn(function()
			local ok, err = pcall(function()
				local container = InsertService:LoadAsset(def.assetId)
				local model = normalize(container, key)
				container:Destroy()
				finish(model)
			end)
			if not ok then
				warn(("[MeshAssetService] %s (%d) failed to load: %s"):format(key, def.assetId, tostring(err)))
			end
			pending -= 1
		end)
	end

	for itemId, def in pairs(MeshAssets.items) do
		load(itemId, def, function(model)
			-- Invisible Handle at the grip height: ToolService welds the mesh
			-- parts to it and the hand holds its center; ItemModels pivots
			-- display clones on it too.
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(0.4, 0.4, 0.4)
			handle.Transparency = 1
			handle.CanCollide = false
			handle.Anchored = true
			handle.CFrame = CFrame.new(0, def.grip or 1, 0)
			handle.Parent = model
			model.PrimaryPart = handle
			model.Parent = assetsFolder
		end)
	end
	for key, def in pairs(MeshAssets.world) do
		load(key, def, function(model)
			templates[key] = model
			model.Parent = worldFolder
		end)
	end

	-- Boot blocks here: the world builders (nodes, enemies, workbenches) read
	-- their templates synchronously in their own start() right after this.
	local deadline = os.clock() + LOAD_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	if pending > 0 then
		warn("[MeshAssetService] timed out waiting for mesh assets; ArtKit fallbacks stay in effect")
	end
end

return MeshAssetService
