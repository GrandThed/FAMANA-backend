-- Map markers: authored places carry their world layout as tagged parts in
-- the place file instead of the hardcoded `spots`/`position` lists in the
-- service defs. A marker is any BasePart in Workspace tagged
-- "<Prefix>_<key>" (Studio: select the part → Properties → Tags), e.g.
-- Node_tree, Enemy_goblin, Vendor_general_goods, Workbench_crafting_table,
-- ItemStand_sword_iron. Markers are read once at boot and destroyed; their
-- CFrame is the placement (position + facing) and their attributes ride
-- along for future per-marker overrides. Workflow in docs/MAP_AUTHORING.md.
--
-- The switch is the map itself: a place with a Workspace.Map folder (an
-- authored map) spawns ONLY from markers; without one, services fall back
-- to their hardcoded defs so a bare Studio baseplate and the pre-map cells
-- keep working.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local MapMarkers = {}

-- True when this place carries an authored map (a Workspace.Map folder).
function MapMarkers.mapPresent()
	return Workspace:FindFirstChild("Map") ~= nil
end

-- Collects and DESTROYS every marker tagged "<prefix><key>" (prefix includes
-- the trailing underscore, e.g. "Node_"). Returns
-- { [key] = { { cframe = CFrame, attributes = {} }, ... } }.
function MapMarkers.take(prefix)
	local byKey = {}
	for _, tag in ipairs(CollectionService:GetAllTags()) do
		if #tag > #prefix and tag:sub(1, #prefix) == prefix then
			local key = tag:sub(#prefix + 1)
			for _, inst in ipairs(CollectionService:GetTagged(tag)) do
				if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
					byKey[key] = byKey[key] or {}
					table.insert(byKey[key], {
						cframe = inst.CFrame,
						size = inst.Size, -- borders build a wall the marker's size
						attributes = inst:GetAttributes(),
					})
					inst:Destroy()
				end
			end
		end
	end
	return byKey
end

-- take() with validation against a def table keyed the same way: a tag whose
-- key has no def is a mapping mistake (warn); a def with no markers in an
-- authored map is legitimate but worth surfacing (print), because "why didn't
-- my trees spawn" is almost always a typo'd tag.
function MapMarkers.takeFor(prefix, defsByKey)
	local byKey = MapMarkers.take(prefix)
	for key in pairs(byKey) do
		if defsByKey[key] == nil then
			warn(("[MapMarkers] %s%s markers match no def — ignored"):format(prefix, key))
		end
	end
	for key in pairs(defsByKey) do
		if byKey[key] == nil then
			print(("[MapMarkers] map has no %s%s markers — none spawned"):format(prefix, key))
		end
	end
	return byKey
end

-- Yaw (degrees) a marker faces, for defs with a `facing` field: built models
-- look along -Z, so rotate the marker part to aim the thing it places.
function MapMarkers.facing(marker)
	local look = marker.cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

return MapMarkers
