-- Resource nodes. Swinging the matching tool near a node harvests its resource
-- into the player's inventory (persisted via the backend). Nodes deplete and
-- regrow. In-memory per server (per the MVP spec). Node types are data-driven,
-- so adding a resource is just a new entry in NODE_DEFS + its builder.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GatheringService = {}

local GATHER_COOLDOWN = 1 -- global per-player gather cooldown (any node)

local nodes = {} -- { def, amount, anchor (Part), deplete(), restore() }
local lastGather = {} -- [userId] = os.clock()
local resourceFolder

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { resourceFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

-- ---- Node builders -------------------------------------------------------

local function buildTree(spot, def)
	local y = groundY(spot.X, spot.Z)
	local base = Vector3.new(spot.X, y, spot.Z)

	local model = Instance.new("Model")
	model.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(2, 8, 2)
	trunk.Position = base + Vector3.new(0, 4, 0)
	trunk.Color = Color3.fromRGB(105, 70, 40)
	trunk.Material = Enum.Material.Wood
	trunk.Parent = model

	local leaves = Instance.new("Part")
	leaves.Name = "Leaves"
	leaves.Shape = Enum.PartType.Ball
	leaves.Anchored = true
	leaves.CanCollide = false
	leaves.Size = Vector3.new(8, 8, 8)
	leaves.Position = base + Vector3.new(0, 10, 0)
	leaves.Color = Color3.fromRGB(60, 140, 60)
	leaves.Material = Enum.Material.Grass
	leaves.Parent = model

	model.PrimaryPart = trunk
	model.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = trunk,
		deplete = function()
			leaves.Transparency = 1
			trunk.Size = Vector3.new(2, 2, 2)
			trunk.Position = base + Vector3.new(0, 1, 0)
			trunk.Color = Color3.fromRGB(80, 55, 32)
		end,
		restore = function()
			leaves.Transparency = 0
			trunk.Size = Vector3.new(2, 8, 2)
			trunk.Position = base + Vector3.new(0, 4, 0)
			trunk.Color = Color3.fromRGB(105, 70, 40)
		end,
	}
end

local function buildRock(spot, def)
	local y = groundY(spot.X, spot.Z)
	local base = Vector3.new(spot.X, y, spot.Z)

	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Anchored = true
	rock.Size = Vector3.new(4, 3, 4)
	rock.Position = base + Vector3.new(0, 1.5, 0)
	rock.Color = Color3.fromRGB(120, 120, 125)
	rock.Material = Enum.Material.Slate
	rock.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = rock,
		deplete = function()
			rock.Size = Vector3.new(2, 1, 2)
			rock.Position = base + Vector3.new(0, 0.5, 0)
			rock.Color = Color3.fromRGB(90, 90, 95)
		end,
		restore = function()
			rock.Size = Vector3.new(4, 3, 4)
			rock.Position = base + Vector3.new(0, 1.5, 0)
			rock.Color = Color3.fromRGB(120, 120, 125)
		end,
	}
end

-- ---- Node type definitions ----------------------------------------------

local NODE_DEFS = {
	tree = {
		toolType = "axe",
		yield = "wood",
		capacity = 5,
		respawn = 60,
		range = Config.reach.axe,
		build = buildTree,
		spots = {
			Vector3.new(20, 0, 12),
			Vector3.new(28, 0, 18),
			Vector3.new(16, 0, 24),
			Vector3.new(34, 0, 8),
			Vector3.new(24, 0, 30),
		},
	},
	rock = {
		toolType = "pickaxe",
		yield = "stone",
		capacity = 5,
		respawn = 60,
		range = Config.reach.pickaxe,
		build = buildRock,
		spots = {
			Vector3.new(22, 0, -12),
			Vector3.new(30, 0, -18),
			Vector3.new(18, 0, -26),
			Vector3.new(36, 0, -14),
		},
	},
}

-- ---- Gathering -----------------------------------------------------------

local function findNearbyNode(character, toolType)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local closest, closestDist
	for _, node in ipairs(nodes) do
		if node.def.toolType == toolType and node.amount > 0 then
			local dist = (node.anchor.Position - root.Position).Magnitude
			if dist <= node.def.range and (not closestDist or dist < closestDist) then
				closest, closestDist = node, dist
			end
		end
	end
	return closest
end

-- Called by ToolService when a "tool" item is activated. The tool's toolType
-- selects which node type it can harvest (axe->tree, pickaxe->rock).
local function onToolSwing(player, tool, def)
	if not def.toolType then
		return
	end

	local now = os.clock()
	if now - (lastGather[player.UserId] or 0) < GATHER_COOLDOWN then
		return
	end

	local node = findNearbyNode(player.Character, def.toolType)
	if not node then
		return
	end
	lastGather[player.UserId] = now

	local amount = math.min(def.gatherPower or 1, node.amount)
	local ok = PlayerService.addItem(player, node.def.yield, amount)
	if not ok then
		return -- inventory full or backend error; leave the node alone
	end

	node.amount -= amount
	if node.amount <= 0 then
		node.deplete()
		task.delay(node.def.respawn, function()
			node.amount = node.def.capacity
			node.restore()
		end)
	end
end

function GatheringService.start()
	resourceFolder = Instance.new("Folder")
	resourceFolder.Name = "Resources"
	resourceFolder.Parent = Workspace

	for _, def in pairs(NODE_DEFS) do
		for _, spot in ipairs(def.spots) do
			table.insert(nodes, def.build(spot, def))
		end
	end

	ToolService.registerActivated("tool", onToolSwing)

	Players.PlayerRemoving:Connect(function(player)
		lastGather[player.UserId] = nil
	end)
end

return GatheringService
