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

local templates = {} -- [key] = { Model, ... } — world variant pools; most
-- keys hold one model, gathering trees hold several (same species, small
-- differences) and every placement draws a random one
local worldScale = {} -- [key] = default placement scale (MeshAssets def.scale)
local animatedTemplates = {} -- [key] = rig Model (skinned MeshPart + Bones +
-- AnimationController), kept UN-flattened — normalize() would strip the rig

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
			if string.find(lower, "ember", 1, true) then
				part.Name = "Ember" -- campfire/lantern code hangs PointLights on this name
			elseif string.find(lower, "orb", 1, true) or string.find(lower, "flame", 1, true) then
				part.Name = "Orb" -- held Orb parts (staff, torch) get ToolService's PointLight
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

-- Rebases every part so the model's content sits upright, bottom-centered
-- at the LOCAL origin (+ an optional yaw, degrees). The import pipeline
-- leaves arbitrary orientations in the raw part CFrames — the world path's
-- bounding-box placement corrects that implicitly, but items are pivoted on
-- their Handle and welded raw into Tools, so the template itself must be
-- canonical: thumbnails, held tools and grip heights all rely on it.
local function canonicalize(model, yawDeg)
	local bounds, size = model:GetBoundingBox()
	local rebase = CFrame.Angles(0, math.rad(yawDeg or 0), 0)
		* CFrame.new(0, size.Y / 2, 0)
		* bounds:Inverse()
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CFrame = rebase * p.CFrame
		end
	end
end

function MeshAssetService.get(key)
	local pool = templates[key]
	return pool and pool[1]
end

-- The mesh pipeline lands our baked -Z fronts on +Z, so both placement
-- helpers spin the visual 180° — game-side, a mesh model's front is -Z of
-- the origin/part it's placed on, same as the enemy convention.
local FRONT_FLIP = CFrame.Angles(0, math.pi, 0)

-- Clones a world template bottom-centered onto `origin` (a ground-level
-- CFrame; its rotation carries into the model, front lands on its -Z).
-- Returns nil when the template didn't load.
function MeshAssetService.place(key, origin, scale)
	local pool = templates[key]
	if not pool or #pool == 0 then
		return nil
	end
	local clone = pool[math.random(#pool)]:Clone()
	scale = scale or worldScale[key] or 1
	if scale ~= 1 then
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
	local pool = templates[key]
	if not pool or #pool == 0 then
		return nil
	end
	local visual = pool[math.random(#pool)]:Clone()
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

-- Clones an animated rig template scaled to `targetHeight`, bottom-aligns it
-- to `part`'s footprint and welds the skinned MeshPart on (massless, no
-- collide/query — same ride-along contract as weldVisual). The animated
-- exports already face -Z (the enemy convention), so no FRONT_FLIP here.
-- Loads the def's animation clips through the rig's AnimationController and
-- returns { model, tracks = { idle?, walk?, attack? } }, or nil when the
-- template didn't load (callers fall back to weldVisual/ArtKit looks).
function MeshAssetService.attachAnimatedVisual(part, key, targetHeight)
	local template = animatedTemplates[key]
	local def = MeshAssets.animated and MeshAssets.animated[key]
	if not template or not def then
		return nil
	end
	local visual = template:Clone()
	local _, size = visual:GetBoundingBox()
	if targetHeight and size.Y > 0 and math.abs(size.Y - targetHeight) > 0.01 then
		visual:ScaleTo(targetHeight / size.Y)
	end
	local bounds, scaledSize = visual:GetBoundingBox()
	local target = part.CFrame * CFrame.new(0, -part.Size.Y / 2 + scaledSize.Y / 2, 0)
	visual:PivotTo(target * (bounds:Inverse() * visual:GetPivot()))

	local mesh = visual:FindFirstChildWhichIsA("MeshPart", true)
	if not mesh then
		visual:Destroy()
		return nil
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = mesh
	weld.Parent = mesh
	visual.Name = "Visual"
	visual.Parent = part

	-- The upload pipeline ships an AnimationController inside the model;
	-- reuse it (a second controller on the same rig silently animates nothing).
	local controller = visual:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = visual
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local tracks = {}
	for name, id in pairs(def.animations or {}) do
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track.Looped = name ~= "attack"
			track.Priority = name == "attack" and Enum.AnimationPriority.Action
				or name == "walk" and Enum.AnimationPriority.Movement
				or Enum.AnimationPriority.Idle
			tracks[name] = track
		else
			warn(("[MeshAssetService] %s animation %s (%d) failed to load: %s"):format(key, name, id, tostring(track)))
		end
	end
	return { model = visual, tracks = tracks }
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
			canonicalize(model, def.yaw)
			-- Held items get an invisible Handle at the grip height: ToolService
			-- welds the mesh parts to it and the hand holds its center. Gear that
			-- is never held (armor, rings) skips it — normalize's biggest-part
			-- PrimaryPart is fine for thumbnails and drops.
			if def.grip then
				local handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Size = Vector3.new(0.4, 0.4, 0.4)
				handle.Transparency = 1
				handle.CanCollide = false
				handle.Anchored = true
				handle.CFrame = CFrame.new(0, def.grip, 0)
				handle.Parent = model
				model.PrimaryPart = handle
			end
			model.Parent = assetsFolder
		end)
	end
	for key, def in pairs(MeshAssets.world) do
		worldScale[key] = def.scale
		local ids = def.assetIds or { def.assetId }
		for index, assetId in ipairs(ids) do
			load(("%s#%d"):format(key, index), { assetId = assetId }, function(model)
				canonicalize(model, 0)
				templates[key] = templates[key] or {}
				table.insert(templates[key], model)
				model.Parent = worldFolder
			end)
		end
	end
	-- Animated rigs skip normalize/canonicalize entirely: flattening would
	-- strip the Bones and AnimationController, and recoloring is pointless —
	-- their look comes from the palette texture baked into the MeshPart.
	for key, def in pairs(MeshAssets.animated or {}) do
		pending += 1
		task.spawn(function()
			local ok, err = pcall(function()
				local container = InsertService:LoadAsset(def.assetId)
				local mesh = container:FindFirstChildWhichIsA("MeshPart", true)
				assert(mesh, "no MeshPart in asset")
				local model = mesh:FindFirstAncestorOfClass("Model") or container
				model.Name = "Anim_" .. key
				mesh.Anchored = false
				mesh.CanCollide = false
				mesh.CanQuery = false
				mesh.Massless = true
				-- Import bookkeeping the game never reads; drop it so enemy
				-- clones don't replicate a folder of dead CFrameValues each.
				local initialPoses = model:FindFirstChild("InitialPoses")
				if initialPoses then
					initialPoses:Destroy()
				end
				model.Parent = worldFolder
				animatedTemplates[key] = model
				if model ~= container then
					container:Destroy()
				end
			end)
			if not ok then
				warn(("[MeshAssetService] animated %s (%d) failed to load: %s"):format(key, def.assetId, tostring(err)))
			end
			pending -= 1
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
