-- FAMANA map bootstrap (Studio Command Bar script) — run ONCE per place.
--
-- Builds Workspace.Map with a marker for EVERY world object the code
-- currently spawns from hardcoded positions (trees, rocks, enemies, vendor,
-- quest giver, camp architect, workbenches, item stands) — each one placed
-- exactly where it stands in the live game today. After running it, the
-- world is yours to edit visually: drag markers around, Ctrl+D to add more,
-- delete what you don't want, then File → Publish to Roblox.
--
-- Playtest (F5) previews the result: the moment Workspace.Map exists, the
-- services build the real objects from these markers instead of their code
-- position lists.
--
-- Positions mirror the service defs as of 2026-07-14 (EnemyService,
-- GatheringService, VendorService, CraftingService, QuestService,
-- CampArchitectService, ItemStandService). If you already RAN this and
-- edited the map, don't run it again — it refuses while Workspace.Map
-- exists, so it can't wipe your work.
--
-- Build everything INSIDE the Map folder — anything loose in Workspace
-- outside it isn't part of the map and won't survive a deploy.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

if Workspace:FindFirstChild("Map") then
	error("Workspace.Map already exists — delete it first if you really want to re-bootstrap from the code positions.")
end

-- { tag, x, z, facing (degrees yaw, only for things with a front), color }
local COLORS = {
	Node = Color3.fromRGB(76, 156, 68),
	Enemy = Color3.fromRGB(200, 80, 70),
	Vendor = Color3.fromRGB(209, 153, 56),
	Workbench = Color3.fromRGB(97, 64, 36),
	QuestGiver = Color3.fromRGB(150, 90, 200),
	CampArchitect = Color3.fromRGB(80, 120, 220),
	ItemStand = Color3.fromRGB(184, 191, 204),
}

local MARKERS = {
	-- gathering nodes (GatheringService NODE_DEFS)
	{ "Node_tree", 20, 12 },
	{ "Node_tree", 28, 18 },
	{ "Node_tree", 16, 24 },
	{ "Node_tree", 34, 8 },
	{ "Node_tree", 24, 30 },
	{ "Node_hardwood_tree", 6, 22 },
	{ "Node_hardwood_tree", 10, 34 },
	{ "Node_hardwood_tree", 2, 40 },
	{ "Node_conifer_tree", 42, 18 },
	{ "Node_conifer_tree", 48, 26 },
	{ "Node_conifer_tree", 40, 32 },
	{ "Node_dead_tree", 40, -52 },
	{ "Node_dead_tree", 48, -58 },
	{ "Node_dead_tree", 34, -62 },
	{ "Node_stone_rock", 10, -14 },
	{ "Node_stone_rock", 16, -22 },
	{ "Node_stone_rock", 8, -28 },
	{ "Node_stone_rock", 4, -20 },
	{ "Node_copper_rock", 22, -12 },
	{ "Node_copper_rock", 30, -18 },
	{ "Node_copper_rock", 18, -26 },
	{ "Node_copper_rock", 36, -14 },
	{ "Node_iron_rock", 44, -8 },
	{ "Node_iron_rock", 50, -18 },
	{ "Node_iron_rock", 46, -30 },
	-- enemies (EnemyService ENEMY_DEFS)
	{ "Enemy_slime", -20, 12 },
	{ "Enemy_slime", -28, 20 },
	{ "Enemy_slime", -15, 26 },
	{ "Enemy_goblin", -34, -8 },
	{ "Enemy_goblin", -40, -18 },
	{ "Enemy_golem", -62, -34 },
	{ "Enemy_golem", -72, -16 },
	{ "Enemy_spider", 55, -65 },
	{ "Enemy_spider", 48, -72 },
	-- NPCs + stations (facing = the way they look, marker front is -Z)
	{ "Vendor_general_goods", -16, -34, 205 },
	{ "QuestGiver_quest_giver_village", -8, -34, 160 },
	{ "CampArchitect_npc", -6, -40, 205 },
	{ "Workbench_crafting_table", 22, -28, 200 },
	{ "Workbench_simple_forge", 28, -34, 160 },
	-- item stands (ItemStandService STAND_DEFS)
	{ "ItemStand_sword_basic", 2, -34 },
	{ "ItemStand_sword_iron", 7, -34 },
	{ "ItemStand_staff_basic", 12, -34 },
	{ "ItemStand_bow_basic", 17, -34 },
	{ "ItemStand_axe_basic", -3, -34 },
	{ "ItemStand_pickaxe_basic", -8, -34 },
	{ "ItemStand_ring_brawler", -8, -41 },
	{ "ItemStand_ring_lynx", -3, -41 },
	{ "ItemStand_helmet_bastion", 2, -41 },
	{ "ItemStand_sword_duelist", 7, -41 },
	{ "ItemStand_chest_colossus", 12, -41 },
	{ "ItemStand_boots_evader", 17, -41 },
	{ "ItemStand_emblem_pyromancer", 22, -41 },
	{ "ItemStand_emblem_berserker", 27, -41 },
}

local map = Instance.new("Folder")
map.Name = "Map"

local markers = Instance.new("Model")
markers.Name = "Markers"
markers.Parent = map

for _, def in ipairs(MARKERS) do
	local tag, x, z, facing = def[1], def[2], def[3], def[4]
	local kind = tag:match("^(%a+)_") or tag

	local part = Instance.new("Part")
	part.Name = tag
	part.Size = Vector3.new(2, 2, 2)
	part.Color = COLORS[kind] or Color3.fromRGB(255, 0, 255)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(x, 1, z) * CFrame.Angles(0, math.rad(facing or 0), 0)
	CollectionService:AddTag(part, tag)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 22)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = tag
	label.Parent = billboard

	if facing then
		local front = Instance.new("SurfaceGui")
		front.Face = Enum.NormalId.Front
		front.Parent = part
		local frontLabel = Instance.new("TextLabel")
		frontLabel.Size = UDim2.new(1, 0, 1, 0)
		frontLabel.BackgroundTransparency = 1
		frontLabel.Font = Enum.Font.GothamBlack
		frontLabel.TextScaled = true
		frontLabel.TextColor3 = Color3.new(1, 1, 1)
		frontLabel.TextTransparency = 0.3
		frontLabel.Text = "FRONT"
		frontLabel.Parent = front
	end

	part.Parent = markers
end

-- Border crossings to neighboring cells are markers too: Border_<edge>. THE
-- MARKER'S SIZE IS THE TRIGGER WALL — stretch/move/rotate it to fit your map.
-- Deleting it disconnects that neighbor (the boot output warns about it).
local borders = 0
local okGrid, GridConfig = pcall(function()
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared", 5):WaitForChild("GridConfig", 5))
end)
if okGrid and GridConfig then
	for edge, destCell in pairs(GridConfig.neighbors(GridConfig.currentCell())) do
		local tag = "Border_" .. edge
		local wall = Instance.new("Part")
		wall.Name = tag
		wall.Size = Vector3.new(2, 30, 90)
		wall.CFrame = CFrame.new(GridConfig.borderX(edge), 15, 0)
		wall.Color = Color3.fromRGB(80, 140, 255)
		wall.Transparency = 0.6
		wall.Material = Enum.Material.ForceField
		wall.Anchored = true
		wall.CanCollide = false
		CollectionService:AddTag(wall, tag)

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 240, 0, 22)
		billboard.StudsOffset = Vector3.new(0, 17, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 200
		billboard.Parent = wall
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Text = tag .. " (crossing to cell " .. destCell .. ")"
		label.Parent = billboard

		wall.Parent = markers
		borders += 1
	end
else
	warn("[MapBootstrap] couldn't require GridConfig — place Border_<edge> markers by hand (docs/MAP_AUTHORING.md).")
end

map.Parent = Workspace
print(("[MapBootstrap] built %d markers (+%d border crossings) in Workspace.Map.Markers — press Play to preview (world should look exactly like before), edit freely, then File → Publish to Roblox."):format(#MARKERS, borders))
print("[MapBootstrap] build all scenery INSIDE the Map folder; tools/marker_kit.lua gives you templates for placing NEW marker types later.")
