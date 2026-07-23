-- Client-side rim effect for the terrain rift (see shared/TerrainGen):
-- as the player approaches the opening, the world darkens and desaturates
-- through a DEDICATED ColorCorrectionEffect — post effects stack, so this
-- never fights DayNightService's Lighting ownership. Horizontal distance
-- only: standing at the rim (or inside the rift) counts as close even
-- though the void floor is ~45 studs down.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local RiftEffects = {}

local FAR = 55 -- studs (XZ) where the effect starts
local NEAR = 8 -- studs (XZ) where it peaks
local MAX_DARKEN = -0.2
local MAX_DESATURATE = -0.6
local TINT_NEAR = Color3.fromRGB(205, 196, 230) -- cold violet cast at the rim
local CHECK_INTERVAL = 0.15

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Horizontal distance from `position` to a (possibly rotated) floor
-- segment's footprint, in the part's local space (0 when over the opening).
local function distanceXZ(position, floor)
	local localPos = floor.CFrame:PointToObjectSpace(position)
	local dx = math.max(math.abs(localPos.X) - floor.Size.X / 2, 0)
	local dz = math.max(math.abs(localPos.Z) - floor.Size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Nearest fracture segment (the decor folder holds one VoidFloor per
-- polyline segment).
local function nearestFloorDistance(position)
	local decor = workspace:FindFirstChild("TerrainRiftDecor")
	if not decor then
		return nil
	end
	local best
	for _, child in ipairs(decor:GetChildren()) do
		if child.Name == "VoidFloor" then
			local d = distanceXZ(position, child)
			if not best or d < best then
				best = d
			end
		end
	end
	return best
end

function RiftEffects.start()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "RiftColorCorrection"
	cc.Parent = Lighting

	local sinceCheck = 0
	local intensity = 0
	local target = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= CHECK_INTERVAL then
			sinceCheck = 0
			target = 0
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local d = nearestFloorDistance(root.Position)
				if d then
					target = smoothstep((FAR - d) / (FAR - NEAR))
				end
			end
		end
		-- ease toward the target so entering/leaving the radius feels soft
		intensity += (target - intensity) * math.min(dt * 4, 1)
		cc.Brightness = MAX_DARKEN * intensity
		cc.Saturation = MAX_DESATURATE * intensity
		cc.TintColor = Color3.new(1, 1, 1):Lerp(TINT_NEAR, intensity)
	end)
end

return RiftEffects
