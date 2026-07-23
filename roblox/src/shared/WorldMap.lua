--[[
	WorldMap — hand-authored world geography, translated from the painted
	zone map (2026-07-22): cell A = the northern island, cell B = the
	southern landmass across the strait. Frontiers are physical — sea,
	frontier rivers, the rift, and (later, cell B) the great walls.

	Coordinates are RECIPE UNITS (1 unit = TerrainGen's SCALE = 3 studs);
	+x = east, +y = south (Roblox +Z), negative y = north. Design
	shorthand: 1 stud ~= 1 m, so cell A's village zone is ~100 units
	= 300 m across.

	Cells are NOT uniform squares — each declares its own world window
	(center + size, in STUDS). TerrainGen samples the shared world through
	that window, so cells of any size still seam.
]]

local WorldMap = {}

-- Per-cell world windows (studs).
WorldMap.cells = {
	A = { center = Vector2.new(0, 0), size = 1440 },
	-- placeholder window; refine when cell B's geography is authored
	B = { center = Vector2.new(0, 1440), size = 1440 },
}

-- Spawn: the cell A city plateau (village zone center), world studs.
WorldMap.spawnStuds = Vector2.new(72, 162)

-- Cell A coastline (closed polygon, units). Water everywhere outside.
local COAST_A = {
	{ 0, -210 }, { 36, -198 }, { 60, -180 }, { 105, -186 }, { 144, -174 },
	{ 174, -150 }, { 156, -126 }, { 120, -132 }, { 102, -114 }, { 126, -90 },
	{ 114, -54 }, { 99, -18 }, { 102, 24 }, { 90, 66 }, { 96, 102 },
	{ 66, 120 }, { 24, 126 }, { -24, 132 }, { -66, 120 }, { -90, 102 },
	{ -102, 60 }, { -114, 18 }, { -102, -30 }, { -84, -72 }, { -66, -114 },
	{ -42, -150 }, { -24, -180 },
}

-- Village zone (yellow in the sketch): flattened-ish plateau, ~300 m across.
WorldMap.city = { x = 24, y = 54, r = 50 }

-- Hill band across the island's upper interior (brown in the sketch).
WorldMap.hills = {
	points = { { -48, -120 }, { 6, -138 }, { 66, -114 }, { 90, -90 } },
	halfWidth = 21,
}

-- Stepping points (cyan in the sketch): shallow fords raised to walkable
-- height where the player crosses a water frontier.
WorldMap.fords = {
	{ x = 12, y = 150, r = 15 }, -- strait crossing, cell A <-> cell B
	{ x = 6, y = -198, r = 12 }, -- north frontier crossing (future cell)
}

local function segDist2(px, py, ax, ay, bx, by)
	local vx, vy = bx - ax, by - ay
	local t = math.clamp(
		((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0, 1)
	local dx, dy = px - (ax + vx * t), py - (ay + vy * t)
	return dx * dx + dy * dy
end

-- Signed distance to the nearest coastline: positive inland, negative at sea.
function WorldMap.landSDF(x, y)
	local best = math.huge
	local inside = false
	local j = #COAST_A
	for i = 1, #COAST_A do
		local xi, yi = COAST_A[i][1], COAST_A[i][2]
		local xj, yj = COAST_A[j][1], COAST_A[j][2]
		if (yi > y) ~= (yj > y) then
			if x < (xj - xi) * (y - yi) / (yj - yi) + xi then
				inside = not inside
			end
		end
		local d2 = segDist2(x, y, xi, yi, xj, yj)
		if d2 < best then
			best = d2
		end
		j = i
	end
	best = math.sqrt(best)
	return inside and best or -best
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0..1 over the hill band, soft edges.
function WorldMap.hillsMask(x, y)
	local pts = WorldMap.hills.points
	local best = math.huge
	for i = 1, #pts - 1 do
		local d2 = segDist2(x, y,
			pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
		if d2 < best then
			best = d2
		end
	end
	return smoothstep(
		(WorldMap.hills.halfWidth - math.sqrt(best))
			/ (WorldMap.hills.halfWidth * 0.6))
end

-- 0..1 over the village plateau.
function WorldMap.cityMask(x, y)
	local d = math.sqrt((x - WorldMap.city.x) ^ 2 + (y - WorldMap.city.y) ^ 2)
	return smoothstep((WorldMap.city.r - d) / 12)
end

return WorldMap
