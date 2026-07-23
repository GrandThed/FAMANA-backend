--[[
	TerrainGen — Path A map creation: native voxel terrain generated from one
	continuous WORLD-SPACE height field, palette-tinted via SetMaterialColor.
	(See new_art_style/map/TERRAIN_STYLE.md — Path A is the decided route.)

	Each grid cell samples the same world function at its own offset (derived
	from GridConfig neighbors), so terrain SEAMS across cell borders by
	construction — math.noise is deterministic everywhere.

	Runs at SERVER BOOT (init.server.lua, cell places only): regeneration is
	deterministic, so terrain never needs to persist in the place file — it
	survives the map pull/deploy pipeline, which only keeps Workspace.Map.
	For a quick edit-time preview (Rojo connected, command bar):
	  require(game.ReplicatedStorage.Shared.TerrainGen).generateCell()
	Explicit cell / tweaks:
	  .generateCell("B", { size = 480, clear = false })

	Spawn/entry areas are flattened to walkable height so the border handoff
	(ENTRY_Y) never buries players. If you edit this module, re-require via
	:Clone() to dodge the edit-mode require cache.
]]

local GridConfig = require(script.Parent.GridConfig)
local WorldMap = require(script.Parent.WorldMap)

local TerrainGen = {}

local SEED = 7
local SCALE = 3 -- studs per recipe unit (recipe authored on a ~160-unit tile)
local VOXEL = 4
local FLAT_H = 8 -- studs — spawn-disc height, matched to the village plateau

local function fbm(x, y, scale, octaves)
	octaves = octaves or 5
	local amp, freq, sum, norm = 1, 1, 0, 0
	for i = 1, octaves do
		sum += amp * math.noise(
			x * scale * freq + 13.1,
			y * scale * freq - 7.7,
			SEED * 9.7 + i * 7.77
		)
		norm += amp
		amp *= 0.5
		freq *= 2
	end
	return sum / norm
end

local function ridged(x, y, scale, octaves)
	octaves = octaves or 5
	local amp, freq, sum, prev = 0.5, 1, 0, 1
	for i = 1, octaves do
		local n = math.noise(
			x * scale * freq + 33.3,
			y * scale * freq - 71.7,
			5.5 + i * 3.3
		)
		n = 1 - math.abs(n)
		n = n * n
		sum += n * amp * prev
		prev = n
		amp *= 0.5
		freq *= 2
	end
	return sum
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- EXPERIMENT: the rift — a jagged fracture carved into the world, dressed
-- with decor parts (pure-black Neon void floor + translucent dark layers)
-- so it reads as bottomless. World-space like every feature, so it seams
-- across cells. Runs north→south down the west side of cell A: from the
-- mountain wall, staircasing southwest past spawn toward the shore.
local RIFT = {
	points = { -- polyline, world units — the north frontier fracture: it
		-- bites into cell A's north shore and runs on into the future cell
		{ -12, -336 }, { 12, -294 }, { -9, -258 }, { 9, -222 }, { -3, -192 },
	},
	width = 8, -- half-width (units) of the open crevasse (~48-stud opening)
	band = 2.5, -- wall transition band (units) — bigger rift, still steep
	floorU = -14.5, -- carved floor in units (≈ -43.5 studs, above the voxel region floor)
}

local function riftDistance(xu, yu)
	local best = math.huge
	local pts = RIFT.points
	for i = 1, #pts - 1 do
		local ax, ay = pts[i][1], pts[i][2]
		local vx, vy = pts[i + 1][1] - ax, pts[i + 1][2] - ay
		local t = math.clamp(
			((xu - ax) * vx + (yu - ay) * vy) / (vx * vx + vy * vy), 0, 1)
		local dx, dy = xu - (ax + vx * t), yu - (ay + vy * t)
		local d2 = dx * dx + dy * dy
		if d2 < best then
			best = d2
		end
	end
	return math.sqrt(best)
end

local function riftInfluence(xu, yu)
	return smoothstep(
		(RIFT.width + RIFT.band - riftDistance(xu, yu)) / RIFT.band)
end

-- Corruption halo: darkened, dying ground bleeding outward from the
-- fracture. Reach is wobbled by low-frequency noise so the edge creeps in
-- tendrils instead of a clean band. 1 at the crevasse edge -> 0 outside.
local CORRUPTION_REACH = 8 -- units, average (~24 studs)

local function corruptionAt(xu, yu, riftDist)
	local d = (riftDist or riftDistance(xu, yu)) - (RIFT.width + RIFT.band)
	if d <= 0 then
		return 1
	end
	local reach = CORRUPTION_REACH
		* (0.7 + 0.6 * fbm(xu * 3 + 7, yu * 3 - 3, 0.08, 3))
	return math.clamp(1 - d / math.max(reach, 2), 0, 1)
end

-- World-space height in recipe units (x/y = world studs / SCALE). Water = 0.
-- Geography comes from WorldMap (the painted zone map): landmass coasts,
-- hill bands, the village plateau, fords across water frontiers. `ridged`
-- is kept for future mountain zones (cell B's east range).
local _ = ridged

local function heightU(x, y)
	local sd = WorldMap.landSDF(x, y)
	-- meadows: rolling, never flat
	local land = 4.5 * fbm(x, y, 0.03) + 1.2 * fbm(x + 100, y - 50, 0.09) + 2.6
	land += WorldMap.hillsMask(x, y) * (5 + 5 * fbm(x - 40, y + 90, 0.05))
	local ct = WorldMap.cityMask(x, y)
	if ct > 0 then
		-- village plateau: level enough to build on, still gently uneven
		land = land * (1 - ct) + (2.6 + 0.6 * fbm(x * 2, y * 2, 0.15)) * ct
	end
	local seaFloor = -3.5 + 1.2 * fbm(x + 55, y + 21, 0.05)
	local t = smoothstep((sd + 2) / 8)
	local h = seaFloor * (1 - t) + land * t
	for _, ford in ipairs(WorldMap.fords) do
		local fd = math.sqrt((x - ford.x) ^ 2 + (y - ford.y) ^ 2)
		local f = smoothstep((ford.r - fd) / 4)
		if f > 0 then
			h = h * (1 - f) + 0.7 * f -- shallow walkable crossing
		end
	end
	-- the rift only fractures LAND — over open sea (unauthored cells) it
	-- stays dormant, and grows automatically as coastlines get authored
	local rt = riftInfluence(x, y) * smoothstep((sd + 4) / 6)
	if rt > 0 then
		h = h * (1 - rt) + RIFT.floorU * rt
	end
	return h
end

-- Zone rules from TERRAIN_STYLE.md, mapped to terrain materials.
local function materialFor(xu, yu, zu, slope)
	local nBand = fbm(xu - 13, yu + 57, 0.03, 3)
	local rockLine = 13 + 4 * nBand
	local snowLine = 26 + 3 * nBand
	if zu < -1 then
		return Enum.Material.Mud
	elseif zu < 0.9 + 0.5 * nBand then
		return Enum.Material.Sand
	elseif zu > rockLine then
		if zu > snowLine and slope < 1.2 then
			return Enum.Material.Snow
		end
		return Enum.Material.Rock
	end
	if slope > 1.4 then
		return zu < 6 and Enum.Material.Ground or Enum.Material.Rock
	end
	return Enum.Material.Grass
end

local PALETTE = {
	[Enum.Material.Grass] = Color3.fromRGB(115, 178, 77),
	[Enum.Material.Ground] = Color3.fromRGB(168, 130, 87),
	[Enum.Material.Rock] = Color3.fromRGB(158, 145, 128),
	[Enum.Material.Snow] = Color3.fromRGB(245, 245, 252),
	[Enum.Material.Sand] = Color3.fromRGB(230, 204, 145),
	[Enum.Material.Mud] = Color3.fromRGB(140, 140, 97),
	[Enum.Material.Basalt] = Color3.fromRGB(13, 11, 17), -- rift walls, near-black
	[Enum.Material.Slate] = Color3.fromRGB(84, 74, 90), -- corruption: ashen mid-ring
	[Enum.Material.LeafyGrass] = Color3.fromRGB(94, 108, 62), -- corruption: dying grass fringe
}

-- World offset (studs) of a cell's window, from WorldMap. Cells are not a
-- uniform grid — each declares its own center + size.
local function cellWindow(cellId)
	local def = WorldMap.cells[cellId]
	if def then
		return def.center, def.size
	end
	warn(("TerrainGen: cell %s has no WorldMap window — using origin")
		:format(tostring(cellId)))
	return Vector2.zero, GridConfig.HALF * 2
end

-- Flatten disc around the spawn point so the SpawnLocation always sits on
-- open, level ground (fords handle the border crossings in heightU).
local function flattenDiscs(offset)
	local spawn = WorldMap.spawnStuds - offset
	return { { x = spawn.X, z = spawn.Y, r = 20 } }
end

local function applyFlatten(discs, wx, wz, hStuds)
	for _, disc in ipairs(discs) do
		local d = math.sqrt((wx - disc.x) ^ 2 + (wz - disc.z) ^ 2)
		local t = smoothstep((disc.r + 8 - d) / 8)
		if t > 0 then
			hStuds = hStuds * (1 - t) + FLAT_H * t
		end
	end
	return hStuds
end

-- The "infinitely deep" dressing, built PER SEGMENT of the fracture
-- polyline (oriented slabs — one big bbox would poke out into the lake
-- basin): a pure-black Neon slab as the void floor (black Neon renders
-- flat and unlit — Roblox's standard bottomless trick), translucent black
-- layers above it so brightness falls off with depth, a dark veil Beam
-- across the opening, rising dust, and a spaced-out low rumble. Slabs
-- overhang into solid ground; the opaque voxels hide the excess.
local function buildRiftDecor(offset, half)
	local old = workspace:FindFirstChild("TerrainRiftDecor")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "TerrainRiftDecor"
	local widthStuds = (RIFT.width + RIFT.band * 0.5) * 2 * SCALE
	local margin = widthStuds
	local pts = RIFT.points
	local built = 0
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i][1] * SCALE - offset.X, 0,
			pts[i][2] * SCALE - offset.Y)
		local b = Vector3.new(pts[i + 1][1] * SCALE - offset.X, 0,
			pts[i + 1][2] * SCALE - offset.Y)
		local aIn = math.abs(a.X) < half + margin and math.abs(a.Z) < half + margin
		local bIn = math.abs(b.X) < half + margin and math.abs(b.Z) < half + margin
		-- no dressing over open sea: the rift is dormant there (see heightU)
		local onLand = WorldMap.landSDF(pts[i][1], pts[i][2]) > -6
			or WorldMap.landSDF(pts[i + 1][1], pts[i + 1][2]) > -6
		if (aIn or bIn) and onLand then
			built += 1
			local mid = (a + b) / 2
			local len = (b - a).Magnitude + widthStuds * 0.6 -- overlap the joints
			local function slab(name, y, transparency, material)
				local part = Instance.new("Part")
				part.Name = name
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CastShadow = false
				part.Color = Color3.new(0, 0, 0)
				part.Material = material
				part.Transparency = transparency
				part.Size = Vector3.new(widthStuds, 0.5, len)
				part.CFrame = CFrame.lookAt(
					Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
				part.Parent = folder
				return part
			end
			local floor = slab("VoidFloor", -40, 0, Enum.Material.Neon)
			slab("VoidLayer1", -18, 0.25, Enum.Material.SmoothPlastic)
			slab("VoidLayer2", -6, 0.55, Enum.Material.SmoothPlastic)

			-- rising dust motes, unlit so the darkness stays dark
			local dust = Instance.new("ParticleEmitter")
			dust.Rate = math.clamp(len / 8, 4, 14)
			dust.Lifetime = NumberRange.new(6, 10)
			dust.Speed = NumberRange.new(1.5, 3)
			dust.SpreadAngle = Vector2.new(12, 12)
			dust.EmissionDirection = Enum.NormalId.Top
			dust.Color = ColorSequence.new(Color3.fromRGB(110, 95, 150))
			dust.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0.1),
			})
			dust.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			})
			dust.LightEmission = 0.25
			dust.LightInfluence = 0
			dust.Parent = floor

			-- low rumble every third segment so the whole fracture hums:
			-- the ambient wind loop pitched way down reads as a sub-rumble;
			-- swap the id for a real drone when one is picked.
			if i % 3 == 1 then
				local rumble = Instance.new("Sound")
				rumble.Name = "RiftRumble"
				rumble.SoundId = "rbxassetid://131187945"
				rumble.PlaybackSpeed = 0.35
				rumble.Volume = 0.9
				rumble.Looped = true
				rumble.RollOffMode = Enum.RollOffMode.Inverse
				rumble.RollOffMinDistance = 15
				rumble.RollOffMaxDistance = 110
				rumble.Playing = true
				rumble.Parent = floor
			end

			-- dark veil: a flat black gradient Beam across the opening just
			-- below the rim. Attachment axes are laid so the ribbon renders
			-- as a horizontal sheet, not a wall.
			local dir = (b - a).Unit
			local sideways = dir:Cross(Vector3.yAxis)
			local function veilAttachment(p)
				local attachment = Instance.new("Attachment")
				attachment.WorldCFrame = CFrame.fromMatrix(
					Vector3.new(p.X, 1, p.Z), dir, sideways)
				attachment.Parent = floor
				return attachment
			end
			local veil = Instance.new("Beam")
			veil.Attachment0 = veilAttachment(a - dir * widthStuds * 0.3)
			veil.Attachment1 = veilAttachment(b + dir * widthStuds * 0.3)
			veil.FaceCamera = false
			veil.Width0 = widthStuds
			veil.Width1 = widthStuds
			veil.Color = ColorSequence.new(Color3.new(0, 0, 0))
			veil.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.3),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			veil.LightInfluence = 0
			veil.Segments = 10
			veil.Parent = floor
		end
	end
	if built > 0 then
		folder.Parent = workspace
	else
		folder:Destroy()
	end
end

-- Tints the terrain materials to the map palette + sets the water look.
-- Safe to run on a hand-sculpted map (touches no voxels); material colors
-- save with the place. Command bar:
--   require(game.ReplicatedStorage.Shared.TerrainGen).applyPalette()
function TerrainGen.applyPalette()
	local terrain = workspace.Terrain
	for material, color in PALETTE do
		terrain:SetMaterialColor(material, color)
	end
	terrain.WaterColor = Color3.fromRGB(61, 158, 158)
	terrain.WaterTransparency = 0.2
end

function TerrainGen.generateCell(cellId, config)
	-- Workspace attributes override the defaults (handy in Studio: set
	-- TerrainCell / TerrainSize on Workspace to control what Play builds).
	cellId = cellId
		or workspace:GetAttribute("TerrainCell")
		or GridConfig.currentCell()
	config = config or {}
	local terrain = workspace.Terrain
	local offset, windowSize = cellWindow(cellId)
	local attrSize = workspace:GetAttribute("TerrainSize")
	if attrSize and attrSize ~= windowSize then
		warn(("TerrainGen: TerrainSize attribute (%d) overrides cell %s's "
			.. "WorldMap window (%d) — remove the attribute to generate "
			.. "the full map"):format(attrSize, tostring(cellId), windowSize))
	end
	local sizeStuds = config.size
		or attrSize
		or windowSize
	-- Keep size (and size/2) voxel-aligned so the slab arrays match the region.
	sizeStuds = math.max(VOXEL * 2, math.floor(sizeStuds / (VOXEL * 2) + 0.5) * VOXEL * 2)
	local half = sizeStuds / 2
	local discs = config.flatten ~= false and flattenDiscs(offset) or {}

	if config.clear ~= false then
		terrain:Clear()
	end
	TerrainGen.applyPalette()

	local yMin, yMax = -48, 144
	local n = sizeStuds / VOXEL
	local ny = (yMax - yMin) / VOXEL
	local slabW = 20

	-- Height pass: one heightU sample per column, cached — slopes come from
	-- neighboring grid samples instead of extra height calls (5x cheaper,
	-- which matters at real map sizes).
	local heights = table.create(n)
	for ix = 1, n do
		local wx = -half + (ix - 1) * VOXEL + VOXEL / 2
		local xu = (wx + offset.X) / SCALE
		local row = table.create(n)
		heights[ix] = row
		for iz = 1, n do
			local wz = -half + (iz - 1) * VOXEL + VOXEL / 2
			local yu = (wz + offset.Y) / SCALE
			row[iz] = applyFlatten(discs, wx, wz, heightU(xu, yu) * SCALE)
		end
	end

	for slabStart = 0, n - 1, slabW do
		local slabN = math.min(slabW, n - slabStart)
		local mats = table.create(slabN)
		local occs = table.create(slabN)
		for ix = 1, slabN do
			local gx = slabStart + ix
			local wx = -half + (gx - 1) * VOXEL + VOXEL / 2
			local xu = (wx + offset.X) / SCALE
			local matsX, occsX = table.create(ny), table.create(ny)
			mats[ix], occs[ix] = matsX, occsX
			for iy = 1, ny do
				matsX[iy] = table.create(n)
				occsX[iy] = table.create(n)
			end
			local rowW = heights[math.min(gx + 1, n)]
			local rowE = heights[math.max(gx - 1, 1)]
			local row = heights[gx]
			for iz = 1, n do
				local wz = -half + (iz - 1) * VOXEL + VOXEL / 2
				local yu = (wz + offset.Y) / SCALE
				local hStuds = row[iz]
				local slope = math.sqrt(
					(rowW[iz] - rowE[iz]) ^ 2
						+ (row[math.min(iz + 1, n)] - row[math.max(iz - 1, 1)]) ^ 2
				) / (2 * VOXEL)
				local material = materialFor(xu, yu, hStuds / SCALE, slope)
				local riftDist = riftDistance(xu, yu)
				local landGate = smoothstep(
					(WorldMap.landSDF(xu, yu) + 4) / 6)
				local rift = landGate * smoothstep(
					(RIFT.width + RIFT.band - riftDist) / RIFT.band)
				if rift > 0.2 then
					material = Enum.Material.Basalt
				else
					-- corruption halo: basalt -> ash -> dying grass, with a
					-- high-frequency speckle so the rings blend organically
					local corr = landGate * corruptionAt(xu, yu, riftDist)
					if corr > 0 then
						local speckle = corr
							+ 0.18 * fbm(xu * 5 - 31, yu * 5 + 17, 0.3, 2)
						if speckle > 0.85 then
							material = Enum.Material.Basalt
						elseif speckle > 0.55 then
							material = Enum.Material.Slate
						elseif speckle > 0.25 then
							material = Enum.Material.LeafyGrass
						end
					end
				end
				for iy = 1, ny do
					local voxBottom = yMin + (iy - 1) * VOXEL
					local fill = math.clamp((hStuds - voxBottom) / VOXEL, 0, 1)
					if fill > 0 then
						matsX[iy][iz] = material
						occsX[iy][iz] = fill
					elseif voxBottom < 0 and rift <= 0.2 then
						matsX[iy][iz] = Enum.Material.Water
						occsX[iy][iz] = 1
					else
						matsX[iy][iz] = Enum.Material.Air
						occsX[iy][iz] = 0
					end
				end
			end
		end
		local region = Region3.new(
			Vector3.new(-half + slabStart * VOXEL, yMin, -half),
			Vector3.new(-half + (slabStart + slabN) * VOXEL, yMax, half)
		):ExpandToGrid(VOXEL)
		terrain:WriteVoxels(region, VOXEL, mats, occs)
	end
	buildRiftDecor(offset, half)
	print(("TerrainGen: cell %s done (%d studs, offset %d,%d)")
		:format(cellId, sizeStuds, offset.X, offset.Y))
end

return TerrainGen
