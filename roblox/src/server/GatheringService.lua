-- Resource nodes. Swinging the matching tool near a node harvests its resource
-- into the player's inventory (persisted via the backend). Nodes deplete and
-- regrow. In-memory per server (per the MVP spec). Node types are data-driven,
-- so adding a resource is just a new entry in NODE_DEFS + its builder.
-- Placement: authored maps use Node_<key> markers (see shared/MapMarkers);
-- the defs' `spots` lists are the fallback for places without a map.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerService = require(script.Parent.PlayerService)
local ToolService = require(script.Parent.ToolService)
local TargetService = require(script.Parent.TargetService)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArtKit"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local MapMarkers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapMarkers"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local GatheringService = {}

local GATHER_COOLDOWN = 1 -- global per-player gather cooldown (any node)
local PARTICLE_BURST = 0.2 -- seconds the node's emitter stays on per harvest

local nodes = {} -- { def, amount, anchor (Part), deplete(), restore(), emitter? }
local lastGather = {} -- [userId] = os.clock()
local resourceFolder

-- [n] = function(player, itemId, amount, position)  fired after a successful
-- harvest (the drop system hooks in to fly the resource to the player).
GatheringService.gatheredHandlers = {}
function GatheringService.onGathered(fn)
	table.insert(GatheringService.gatheredHandlers, fn)
end

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
	local origin = CFrame.new(spot.X, y, spot.Z)

	-- Low-poly: square trunk + three stacked, offset-rotated canopy slabs.
	local model = ArtKit.build("Tree", origin, {
		{ name = "Trunk", size = Vector3.new(1.8, 8, 1.8), offset = Vector3.new(0, 4, 0), rot = Vector3.new(0, 15, 0), color = "trunk", primary = true },
		{ name = "Canopy1", size = Vector3.new(9, 3.2, 9), offset = Vector3.new(0, 8.6, 0), rot = Vector3.new(0, 10, 0), color = "leafDark", canCollide = false },
		{ name = "Canopy2", size = Vector3.new(6.8, 2.8, 6.8), offset = Vector3.new(0, 11.2, 0), rot = Vector3.new(0, 40, 0), color = "leaf", canCollide = false },
		{ name = "Canopy3", size = Vector3.new(4.2, 2.4, 4.2), offset = Vector3.new(0, 13.4, 0), rot = Vector3.new(0, 70, 0), color = "leafLight", canCollide = false },
	})

	local trunk = model.PrimaryPart
	local canopy = { model.Canopy1, model.Canopy2, model.Canopy3 }
	local trunkCFrame, trunkSize = trunk.CFrame, trunk.Size

	trunk:SetAttribute("Depleted", false)
	model.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = trunk,
		deplete = function()
			for _, slab in ipairs(canopy) do
				slab.Transparency = 1
			end
			trunk.Size = Vector3.new(1.8, 1.6, 1.8)
			trunk.CFrame = origin * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(15), 0)
			trunk.Color = ArtKit.Palette.trunkDark
			trunk:SetAttribute("Depleted", true)
		end,
		restore = function()
			for _, slab in ipairs(canopy) do
				slab.Transparency = 0
			end
			trunk.Size = trunkSize
			trunk.CFrame = trunkCFrame
			trunk.Color = ArtKit.Palette.trunk
			trunk:SetAttribute("Depleted", false)
		end,
	}
end

-- Old-growth tree: thicker, darker trunk and a denser, darker canopy than
-- the regular Tree, so it visually reads as "needs a better axe" up front —
-- same idea as IronRock vs. Rock.
local function buildHardwoodTree(spot, def)
	local y = groundY(spot.X, spot.Z)
	local origin = CFrame.new(spot.X, y, spot.Z)

	local model = ArtKit.build("HardwoodTree", origin, {
		{ name = "Trunk", size = Vector3.new(2.6, 9, 2.6), offset = Vector3.new(0, 4.5, 0), rot = Vector3.new(0, 15, 0), color = "trunkDark", primary = true },
		{ name = "Canopy1", size = Vector3.new(9.6, 3.4, 9.6), offset = Vector3.new(0, 9.6, 0), rot = Vector3.new(0, 10, 0), color = "leafDark", canCollide = false },
		{ name = "Canopy2", size = Vector3.new(7.4, 3, 7.4), offset = Vector3.new(0, 12.4, 0), rot = Vector3.new(0, 40, 0), color = "leafDark", canCollide = false },
		{ name = "Canopy3", size = Vector3.new(4.6, 2.6, 4.6), offset = Vector3.new(0, 14.8, 0), rot = Vector3.new(0, 70, 0), color = "leaf", canCollide = false },
	})

	local trunk = model.PrimaryPart
	local canopy = { model.Canopy1, model.Canopy2, model.Canopy3 }
	local trunkCFrame, trunkSize = trunk.CFrame, trunk.Size

	trunk:SetAttribute("Depleted", false)
	model.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = trunk,
		deplete = function()
			for _, slab in ipairs(canopy) do
				slab.Transparency = 1
			end
			trunk.Size = Vector3.new(2.6, 1.8, 2.6)
			trunk.CFrame = origin * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, math.rad(15), 0)
			trunk.Color = ArtKit.Palette.stoneDark
			trunk:SetAttribute("Depleted", true)
		end,
		restore = function()
			for _, slab in ipairs(canopy) do
				slab.Transparency = 0
			end
			trunk.Size = trunkSize
			trunk.CFrame = trunkCFrame
			trunk.Color = ArtKit.Palette.trunkDark
			trunk:SetAttribute("Depleted", false)
		end,
	}
end

local function buildRock(spot, def)
	local y = groundY(spot.X, spot.Z)
	local origin = CFrame.new(spot.X, y, spot.Z)

	-- Low-poly: a main boulder with two smaller chunks jutting out at angles.
	local model = ArtKit.build("Rock", origin, {
		{ name = "Boulder", size = Vector3.new(4.2, 2.8, 3.6), offset = Vector3.new(0, 1.3, 0), rot = Vector3.new(6, 25, -4), color = "stone", primary = true },
		{ name = "Chunk1", size = Vector3.new(2.6, 2, 2.4), offset = Vector3.new(1.7, 0.9, -1), rot = Vector3.new(-10, -35, 8), color = "stoneDark" },
		{ name = "Chunk2", size = Vector3.new(1.7, 1.3, 1.7), offset = Vector3.new(-1.8, 0.6, 1.2), rot = Vector3.new(0, 50, 12), color = "stoneLight" },
	})

	local boulder = model.PrimaryPart
	local chunks = { model.Chunk1, model.Chunk2 }
	local boulderCFrame, boulderSize = boulder.CFrame, boulder.Size

	boulder:SetAttribute("Depleted", false)
	model.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = boulder,
		deplete = function()
			for _, chunk in ipairs(chunks) do
				chunk.Transparency = 1
				chunk.CanCollide = false
			end
			boulder.Size = Vector3.new(2.2, 1, 2)
			boulder.CFrame = origin * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(25), 0)
			boulder.Color = ArtKit.Palette.stoneDark
			boulder:SetAttribute("Depleted", true)
		end,
		restore = function()
			for _, chunk in ipairs(chunks) do
				chunk.Transparency = 0
				chunk.CanCollide = true
			end
			boulder.Size = boulderSize
			boulder.CFrame = boulderCFrame
			boulder.Color = ArtKit.Palette.stone
			boulder:SetAttribute("Depleted", false)
		end,
	}
end

-- Iron vein: same silhouette as the regular rock, but darker with rust-red
-- streaks (ArtKit.Palette.rust) so it visually reads as "needs a better
-- pick" at a glance, before the player even swings at it.
local function buildIronRock(spot, def)
	local y = groundY(spot.X, spot.Z)
	local origin = CFrame.new(spot.X, y, spot.Z)

	local model = ArtKit.build("IronRock", origin, {
		{ name = "Boulder", size = Vector3.new(4.2, 2.8, 3.6), offset = Vector3.new(0, 1.3, 0), rot = Vector3.new(6, 25, -4), color = "stoneDark", primary = true },
		{ name = "Chunk1", size = Vector3.new(2.6, 2, 2.4), offset = Vector3.new(1.7, 0.9, -1), rot = Vector3.new(-10, -35, 8), color = "rust" },
		{ name = "Chunk2", size = Vector3.new(1.7, 1.3, 1.7), offset = Vector3.new(-1.8, 0.6, 1.2), rot = Vector3.new(0, 50, 12), color = "rust" },
	})

	local boulder = model.PrimaryPart
	local chunks = { model.Chunk1, model.Chunk2 }
	local boulderCFrame, boulderSize = boulder.CFrame, boulder.Size

	boulder:SetAttribute("Depleted", false)
	model.Parent = resourceFolder

	return {
		def = def,
		amount = def.capacity,
		anchor = boulder,
		deplete = function()
			for _, chunk in ipairs(chunks) do
				chunk.Transparency = 1
				chunk.CanCollide = false
			end
			boulder.Size = Vector3.new(2.2, 1, 2)
			boulder.CFrame = origin * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(25), 0)
			boulder.Color = ArtKit.Palette.stoneDark
			boulder:SetAttribute("Depleted", true)
		end,
		restore = function()
			for _, chunk in ipairs(chunks) do
				chunk.Transparency = 0
				chunk.CanCollide = true
			end
			boulder.Size = boulderSize
			boulder.CFrame = boulderCFrame
			boulder.Color = ArtKit.Palette.stoneDark
			boulder:SetAttribute("Depleted", false)
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
		build = buildTree,
		particleColors = { "leafLight", "trunk" }, -- leaves + wood chips
		spots = {
			Vector3.new(20, 0, 12),
			Vector3.new(28, 0, 18),
			Vector3.new(16, 0, 24),
			Vector3.new(34, 0, 8),
			Vector3.new(24, 0, 30),
		},
	},
	hardwood_tree = {
		toolType = "axe",
		-- Sólo un hacha con toolTier >= 2 puede talar esto (ver toolMatches).
		-- axe_basic es tier 1; axe_copper (crafteada en la mesa con lingotes
		-- de cobre) es la primera en tier 2.
		minToolTier = 2,
		yield = "hardwood",
		capacity = 5,
		respawn = 90,
		build = buildHardwoodTree,
		particleColors = { "trunkDark", "leafDark" },
		spots = {
			Vector3.new(6, 0, 22),
			Vector3.new(10, 0, 34),
			Vector3.new(2, 0, 40),
		},
	},
	rock = {
		toolType = "pickaxe",
		yield = "stone",
		capacity = 5,
		respawn = 60,
		build = buildRock,
		particleColors = { "stoneLight", "stoneDark" }, -- rock shards
		-- Drop extra, chance-based (no consume node capacity, no cuenta
		-- para el depleted/respawn — es puro bonus arriba del yield fijo).
		-- Genérico a propósito: cualquier node type puede sumar el suyo
		-- (ej: un árbol con semillas raras) con solo esta misma tabla.
		bonusYield = { itemId = "copper_ore", chance = 0.12 },
		spots = {
			Vector3.new(22, 0, -12),
			Vector3.new(30, 0, -18),
			Vector3.new(18, 0, -26),
			Vector3.new(36, 0, -14),
		},
	},
	iron_rock = {
		toolType = "pickaxe",
		-- Sólo un pico con toolTier >= 2 puede minar esto (ver toolMatches).
		-- pickaxe_basic es tier 1; pickaxe_copper (crafteado en la mesa con
		-- lingotes de cobre) es el primero en tier 2.
		minToolTier = 2,
		yield = "iron_ore",
		capacity = 4,
		respawn = 90,
		build = buildIronRock,
		particleColors = { "rust", "stoneDark" },
		spots = {
			Vector3.new(44, 0, -8),
			Vector3.new(50, 0, -18),
			Vector3.new(46, 0, -30),
		},
	},
}

-- ---- Gathering -----------------------------------------------------------

-- Node-themed particle burst each time the node yields. Toggled via Enabled
-- (a property, so it replicates) rather than Emit() (a method call, which
-- wouldn't reach clients from the server). The emitter is built lazily and
-- lives on the node's anchor across deplete/restore.
local function burstParticles(node)
	local emitter = node.emitter
	if not emitter then
		local colors = node.def.particleColors or { "stone", "stoneDark" }
		emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Rate = 60
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(6, 11)
		emitter.SpreadAngle = Vector2.new(55, 55)
		emitter.Acceleration = Vector3.new(0, -30, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.LightEmission = 0.1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Color = ColorSequence.new(
			ArtKit.Palette[colors[1]] or ArtKit.Palette.stone,
			ArtKit.Palette[colors[2] or colors[1]] or ArtKit.Palette.stone
		)
		emitter.Parent = node.anchor
		node.emitter = emitter
	end
	emitter.Enabled = true
	task.delay(PARTICLE_BURST, function()
		emitter.Enabled = false
	end)
end

-- Whether a tool (its Items.lua def) is strong enough to work a node: same
-- toolType, and the tool's toolTier (nil = 1, i.e. a basic tool) must meet
-- the node's minToolTier (nil = 1, i.e. any tool of that type works).
local function toolMatches(nodeDef, toolDef)
	return nodeDef.toolType == toolDef.toolType and (toolDef.toolTier or 1) >= (nodeDef.minToolTier or 1)
end

local function findNearbyNode(character, toolDef, reach)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local closest, closestDist
	for _, node in ipairs(nodes) do
		if toolMatches(node.def, toolDef) and node.amount > 0 then
			local dist = (node.anchor.Position - root.Position).Magnitude
			if dist <= reach and (not closestDist or dist < closestDist) then
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

	-- Reach is the tool's own stat (shared with combat/focus).
	local reach = def.reach or Config.defaultReach

	-- Prefer the player's focused node if it's valid, in range, and matches the
	-- tool; otherwise fall back to the nearest matching node.
	local node
	local focusPart = TargetService.get(player)
	if focusPart then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		for _, n in ipairs(nodes) do
			if n.anchor == focusPart then
				if
					root
					and toolMatches(n.def, def)
					and n.amount > 0
					and (n.anchor.Position - root.Position).Magnitude <= reach
				then
					node = n
				end
				break
			end
		end
	end
	if not node then
		node = findNearbyNode(player.Character, def, reach)
	end
	if not node then
		-- No node this tool can harvest is in range — but if there's one in
		-- range that just needs a stronger tool of the same type, let the
		-- player know instead of the swing silently doing nothing.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			for _, n in ipairs(nodes) do
				if
					n.def.toolType == def.toolType
					and n.amount > 0
					and (n.def.minToolTier or 1) > (def.toolTier or 1)
					and (n.anchor.Position - root.Position).Magnitude <= reach
				then
					Remotes.get("Notify"):FireClient(player, "Necesitás una herramienta mejor para esto")
					return
				end
			end
		end
	end
	if not node then
		return
	end
	lastGather[player.UserId] = now

	local amount = math.min(def.gatherPower or 1, node.amount)

	-- eto hace que suene cuando le pegas a la piedra o al rbol
	Remotes.get("GatherFeedback"):FireClient(player, node.def.yield, amount, node.anchor.Position)
	burstParticles(node)

	local ok = PlayerService.addItem(player, node.def.yield, amount)
	if not ok then
		return -- inventory full or backend error; leave the node alone
	end

	-- The item landed in the backend; the loot toast needs the real running
	-- total, so it's fine for this one to lag a beat behind the swing.
	do
		local itemDef = Items.get(node.def.yield)
		local total = PlayerService.getItemCount(player, node.def.yield)
		Remotes.get("Notify"):FireClient(
			player,
			string.format("+%d %s (%d)", amount, itemDef and itemDef.name or node.def.yield, total)
		)
	end
	for _, fn in ipairs(GatheringService.gatheredHandlers) do
		task.spawn(fn, player, node.def.yield, amount, node.anchor.Position)
	end

	-- Bonus chance-based, aparte del yield fijo de arriba: no consume
	-- capacidad del nodo (no cuenta para el deplete/respawn), y si el
	-- inventario está lleno simplemente no cae (no vale la pena bloquear
	-- el yield principal, que ya se acreditó, por esto).
	local bonus = node.def.bonusYield
	if bonus and math.random() < bonus.chance then
		if PlayerService.addItem(player, bonus.itemId, 1) then
			local bonusDef = Items.get(bonus.itemId)
			local bonusTotal = PlayerService.getItemCount(player, bonus.itemId)
			Remotes.get("GatherFeedback"):FireClient(player, bonus.itemId, 1, node.anchor.Position)
			Remotes.get("Notify"):FireClient(
				player,
				string.format("+%d %s (%d)", 1, bonusDef and bonusDef.name or bonus.itemId, bonusTotal)
			)
			for _, fn in ipairs(GatheringService.gatheredHandlers) do
				task.spawn(fn, player, bonus.itemId, 1, node.anchor.Position)
			end
		end
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
	-- Pre-create remote so client doesn't warn/yield infinitely at startup
	Remotes.get("GatherFeedback")

	resourceFolder = Instance.new("Folder")
	resourceFolder.Name = "Resources"
	resourceFolder.Parent = Workspace

	if MapMarkers.mapPresent() then
		local markers = MapMarkers.takeFor("Node_", NODE_DEFS)
		for key, def in pairs(NODE_DEFS) do
			for _, marker in ipairs(markers[key] or {}) do
				table.insert(nodes, def.build(marker.cframe.Position, def))
			end
		end
	else
		for _, def in pairs(NODE_DEFS) do
			for _, spot in ipairs(def.spots) do
				table.insert(nodes, def.build(spot, def))
			end
		end
	end

	ToolService.registerActivated("tool", onToolSwing)

	Players.PlayerRemoving:Connect(function(player)
		lastGather[player.UserId] = nil
	end)
end

return GatheringService

