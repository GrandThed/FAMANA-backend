-- FAMANA map-marker kit (Studio Command Bar script).
--
-- Paste this whole file into Studio's Command Bar (View → Command Bar) and
-- press Enter. It builds ReplicatedStorage.MapMarkerKit: one pre-tagged,
-- color-coded, labeled template part per marker type.
--
-- To place markers: copy a template (Ctrl+C in the Explorer), paste it into
-- your Workspace.Map folder (Ctrl+V) and move it where the object should
-- stand — then Ctrl+D duplicates it in place (duplicates KEEP the tag).
-- Rotate a marker to aim things that face somewhere (vendors, workbenches,
-- quest givers): the front is the surface labeled FRONT (-Z).
--
-- The kit lives in ReplicatedStorage ON PURPOSE: markers only count while
-- under Workspace, so the templates themselves never spawn anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MARKERS = {
	-- { tag, color, note }
	{ "Node_tree", Color3.fromRGB(76, 156, 68), "harvestable green oak (random variant)" },
	{ "Node_hardwood_tree", Color3.fromRGB(196, 112, 48), "autumn oak, needs tier-2 axe" },
	{ "Node_conifer_tree", Color3.fromRGB(62, 110, 88), "winter conifer, drops plain wood" },
	{ "Node_dead_tree", Color3.fromRGB(94, 96, 102), "gnarled dead tree, drops plain wood" },
	{ "Node_stone_rock", Color3.fromRGB(130, 132, 140), "plain rock — stone only (was Node_rock)" },
	{ "Node_copper_rock", Color3.fromRGB(204, 107, 46), "copper vein — yields copper_ore, tier-1 pick" },
	{ "Node_iron_rock", Color3.fromRGB(80, 82, 92), "iron vein, needs tier-2 pick" },
	{ "Enemy_slime", Color3.fromRGB(120, 200, 100), "slime spawn point" },
	{ "Enemy_goblin", Color3.fromRGB(115, 181, 74), "goblin spawn point" },
	{ "Enemy_golem", Color3.fromRGB(140, 142, 150), "rock golem spawn point (Lv4-7 tank — keep away from goblin camps, aggro chains)" },
	{ "Enemy_spider", Color3.fromRGB(70, 55, 40), "cave spider spawn point (fast, 32-stud aggro — keep 35+ studs from NPCs)" },
	{ "Vendor_general_goods", Color3.fromRGB(209, 153, 56), "Marla the Trader" },
	{ "Workbench_crafting_table", Color3.fromRGB(97, 64, 36), "town crafting table" },
	{ "Workbench_simple_forge", Color3.fromRGB(160, 60, 40), "town forge" },
	{ "QuestGiver_quest_giver_village", Color3.fromRGB(150, 90, 200), "Elena la Anciana" },
	{ "CampArchitect_npc", Color3.fromRGB(80, 120, 220), "camp architect NPC" },
	{ "ItemStand_sword_basic", Color3.fromRGB(184, 191, 204), "item stand — retag for other items" },
	{ "Border_east", Color3.fromRGB(80, 140, 255), "cell crossing — THE MARKER'S SIZE IS THE TRIGGER WALL (stretch it!); retag Border_west/north/south for other edges" },
}

local old = ReplicatedStorage:FindFirstChild("MapMarkerKit")
if old then
	old:Destroy()
end
local kit = Instance.new("Folder")
kit.Name = "MapMarkerKit"

for i, def in ipairs(MARKERS) do
	local tag, color, note = def[1], def[2], def[3]
	local part = Instance.new("Part")
	part.Name = tag
	part.Size = Vector3.new(2, 2, 2)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.Position = Vector3.new((i - 1) * 3, 2, 0)
	CollectionService:AddTag(part, tag)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 220, 0, 24)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = tag
	label.Parent = billboard

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

	part:SetAttribute("note", note)
	part.Parent = kit
end

kit.Parent = ReplicatedStorage
print(("[MarkerKit] built %d templates in ReplicatedStorage.MapMarkerKit — copy into Workspace.Map, Ctrl+D to duplicate"):format(#MARKERS))
