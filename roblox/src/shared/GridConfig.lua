-- Grid layout for the server-grid MMO. Both cells run the SAME code; each
-- running Place figures out which cell it is from its PlaceId. To add cells,
-- publish a Place, then add its placeId + neighbors here.

local GridConfig = {}

-- ==========================================================================
-- FILL THESE IN after publishing each Place (see roblox/README.md, step 7).
-- Find a Place's id in the Creator Dashboard, or in Studio via game.PlaceId.
-- ==========================================================================
GridConfig.cells = {
	A = {
		placeId = 130890869057243, -- Cell A (start place)
		neighbors = { south = "B" }, -- per the world map: B lies across the strait
		theme = {
			name = "CELL A",
			ground = Color3.fromRGB(86, 140, 78), -- grassy green
			signColor = Color3.fromRGB(120, 220, 120),
		},
	},
	B = {
		placeId = 96623482055191, -- Cell B
		neighbors = { north = "A" },
		theme = {
			name = "CELL B",
			ground = Color3.fromRGB(168, 130, 92), -- sandy brown
			signColor = Color3.fromRGB(240, 200, 120),
		},
	},
}

-- Used when the running PlaceId matches no configured cell (e.g. Studio before
-- you've filled in the ids). Lets you keep testing Cell A locally.
GridConfig.defaultCell = "A"

-- Non-cell places (instances: dungeons, housing, ...) register here by
-- placeId; anything else — the grid cells and the Studio fallback — is role
-- "cell". init.server.lua uses the role to skip cell-only services
-- (borders, cell theming) in instance places.
GridConfig.places = {
	-- [123456789] = { role = "dungeon" },
}

function GridConfig.currentRole()
	local entry = GridConfig.places[game.PlaceId]
	return entry and entry.role or "cell"
end

-- Geometry (studs). Border walls sit at +/- HALF on the crossing axis; you
-- arrive INSET studs inside the opposite border.
GridConfig.HALF = 40
GridConfig.ENTRY_INSET = 6
GridConfig.ENTRY_Y = 5

local OPPOSITE = { east = "west", west = "east", north = "south", south = "north" }

function GridConfig.oppositeEdge(edge)
	return OPPOSITE[edge]
end

function GridConfig.currentCell()
	local placeId = game.PlaceId
	if placeId ~= 0 then
		for cellId, cell in pairs(GridConfig.cells) do
			if cell.placeId == placeId then
				return cellId
			end
		end
	end
	return GridConfig.defaultCell
end

function GridConfig.placeIdOf(cellId)
	local cell = GridConfig.cells[cellId]
	return cell and cell.placeId or 0
end

function GridConfig.neighbors(cellId)
	local cell = GridConfig.cells[cellId]
	return cell and cell.neighbors or {}
end

function GridConfig.theme(cellId)
	local cell = GridConfig.cells[cellId]
	return cell and cell.theme or { name = cellId, ground = Color3.fromRGB(120, 120, 120), signColor = Color3.new(1, 1, 1) }
end

-- X offset of a border wall for the given edge.
function GridConfig.borderX(edge)
	if edge == "east" then
		return GridConfig.HALF
	elseif edge == "west" then
		return -GridConfig.HALF
	end
	return 0
end

-- Where a player should appear when they enter a cell from `entryEdge`.
function GridConfig.entryPoint(entryEdge)
	local inset = GridConfig.HALF - GridConfig.ENTRY_INSET
	local x = 0
	if entryEdge == "west" then
		x = -inset
	elseif entryEdge == "east" then
		x = inset
	end
	return Vector3.new(x, GridConfig.ENTRY_Y, 0)
end

return GridConfig
