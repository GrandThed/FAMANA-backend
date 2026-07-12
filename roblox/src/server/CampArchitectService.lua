-- Camp Architect NPC: sells camp tier upgrades (docs/CAMP_TIERS.md §5) — a
-- ONE-TIME, PERMANENT, per-player stat purchase (PlayerService.setCampTier),
-- deliberately separate from CraftingService/VendorService's item-trading
-- machinery: an upgrade doesn't produce an inventory item, it mutates a
-- player stat directly, so it doesn't belong in either "craft an item" or
-- "buy/sell an item" — it's its own small transaction, sized to match.
--
-- No confirm-panel UI yet: the ProximityPrompt directly attempts to upgrade
-- to CURRENT TIER + 1 (tiers are strictly sequential, no picking-and-
-- choosing) and reports the result via Notify. A nicer "here's what tier N
-- costs and unlocks, confirm?" panel is future polish — same
-- ships-functional-but-not-fully-populated posture as the cauldron/
-- cosmetics in the steps before this one.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerService = require(script.Parent.PlayerService)

local CampArchitectService = {}

local CAMP = Config.Camp
local MAX_TRADE_DISTANCE = 16 -- same as VendorService.MAX_TRADE_DISTANCE

-- Placeholder position, same convention as VendorService.VENDOR_DEFS — a
-- map with a "CampArchitect_" marker overrides this (see start() below).
local NPC_DEF = { name = "The Camp Architect", position = Vector3.new(-6, 0, -40), facing = 205 }

local npcFolder
local npcPositions = {} -- Vector3, for the distance check (usually just one)
local notifyRemote

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npcFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

-- Same body plan as VendorService.buildVendor, dressed differently (stone/
-- steel instead of leather) so the two NPC "professions" read apart at a
-- glance without needing a whole second rig.
local function buildNpc(def)
	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z) * CFrame.Angles(0, math.rad(def.facing or 0), 0)

	local model = ArtKit.build("CampArchitect", origin, {
		{ name = "Tunic", size = Vector3.new(1.8, 1.8, 1.0), offset = Vector3.new(0, 2.3, 0), color = "stoneDark", primary = true },
		{ name = "Belt", size = Vector3.new(1.9, 0.3, 1.1), offset = Vector3.new(0, 1.7, 0), color = "steelDark" },
		{ name = "LegL", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(-0.4, 0.7, 0), color = "stone" },
		{ name = "LegR", size = Vector3.new(0.6, 1.4, 0.6), offset = Vector3.new(0.4, 0.7, 0), color = "stone" },
		{ name = "ArmL", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(-1.2, 2.4, 0), rot = Vector3.new(0, 0, 8), color = "stoneDark" },
		{ name = "ArmR", size = Vector3.new(0.5, 1.5, 0.5), offset = Vector3.new(1.2, 2.4, 0), rot = Vector3.new(0, 0, -8), color = "stoneDark" },
		{ name = "Head", size = Vector3.new(1.1, 1.1, 1.1), offset = Vector3.new(0, 3.85, 0), color = "skin" },
		{ name = "EyeL", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(-0.24, 3.95, -0.56), color = "ink" },
		{ name = "EyeR", size = Vector3.new(0.14, 0.22, 0.06), offset = Vector3.new(0.24, 3.95, -0.56), color = "ink" },
		-- A little builder's square instead of the vendor's hat, so the
		-- silhouette reads differently even from far away.
		{ name = "SquareA", size = Vector3.new(0.9, 0.15, 0.15), offset = Vector3.new(0.35, 4.3, -0.5), rot = Vector3.new(0, 0, 45), color = "gold" },
		{ name = "SquareB", size = Vector3.new(0.9, 0.15, 0.15), offset = Vector3.new(0.35, 4.3, -0.5), rot = Vector3.new(0, 0, -45), color = "gold" },
	})
	model.Parent = npcFolder

	table.insert(npcPositions, model.PrimaryPart.Position)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Upgrade Camp"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.4 -- a bit longer than the vendor's: this is a one-way, permanent spend
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(player)
		local ok, message = CampArchitectService.tryUpgrade(player)
		notify(player, message)
	end)
end

local function nearNpc(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, position in ipairs(npcPositions) do
		if (root.Position - position).Magnitude <= MAX_TRADE_DISTANCE then
			return true
		end
	end
	return false
end

-- Shared by the ProximityPrompt and the UpgradeCampTier RemoteFunction (kept
-- as two entry points into the same logic rather than duplicating it) — the
-- server always derives the CURRENT tier itself, never trusts a tier number
-- from the client.
function CampArchitectService.tryUpgrade(player)
	if not nearNpc(player) then
		return false, "You need to be near the Camp Architect."
	end

	local currentTier = PlayerService.getCampTier(player)
	local nextTier = currentTier + 1
	if nextTier > CAMP.maxTier then
		return false, "Your camp is already at the highest tier."
	end

	local tierData = CAMP.tiers[nextTier]
	if not tierData or not tierData.cost then
		-- tier 3's cost is nil until a tier-3 material exists
		-- (docs/CAMP_TIERS.md §8) — this is the honest, current answer, not
		-- a bug to paper over with a fake price.
		return false, "That tier isn't available to purchase yet."
	end

	for itemId, quantity in pairs(tierData.cost) do
		if PlayerService.getItemCount(player, itemId) < quantity then
			return false, "You don't have the materials for this upgrade yet."
		end
	end

	-- Remove first, same posture as CraftingService.handleCraft: counts were
	-- just verified above, so a failure here only comes from a genuine race
	-- (rare enough not to need a full atomic transaction) — refund and bail.
	local removed = {}
	for itemId, quantity in pairs(tierData.cost) do
		if not PlayerService.removeItem(player, itemId, quantity) then
			for _, back in ipairs(removed) do
				PlayerService.addItem(player, back.itemId, back.quantity)
			end
			return false, "You don't have the materials for this upgrade yet."
		end
		table.insert(removed, { itemId = itemId, quantity = quantity })
	end

	if not PlayerService.setCampTier(player, nextTier) then
		for _, back in ipairs(removed) do
			PlayerService.addItem(player, back.itemId, back.quantity)
		end
		return false, "Something went wrong — try again."
	end

	return true, ("Camp upgraded to tier %d! Replant your Acampada to see it."):format(nextTier)
end

local function handleUpgradeRemote(player)
	local ok, message = CampArchitectService.tryUpgrade(player)
	return { ok = ok, message = message }
end

function CampArchitectService.start()
	notifyRemote = Remotes.get("Notify")

	npcFolder = Instance.new("Folder")
	npcFolder.Name = "CampArchitect"
	npcFolder.Parent = Workspace

	if MapMarkers.mapPresent() then
		-- MapMarkers.take requires a non-empty suffix after the prefix (see
		-- shared/MapMarkers.lua), so the authored map tag is "CampArchitect_npc"
		-- (not a bare "CampArchitect_") — "npc" is just a fixed key, there's
		-- only ever one of these.
		local markers = MapMarkers.takeFor("CampArchitect_", { npc = NPC_DEF })
		for _, marker in ipairs(markers.npc or {}) do
			buildNpc({
				name = NPC_DEF.name,
				position = marker.cframe.Position,
				facing = MapMarkers.facing(marker),
			})
		end
	else
		buildNpc(NPC_DEF)
	end

	local upgradeCampTier = Remotes.getFunction("UpgradeCampTier")
	upgradeCampTier.OnServerInvoke = handleUpgradeRemote
end

return CampArchitectService
