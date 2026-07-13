-- Remote factory usable from both sides:
--   server: creates the instance if missing (under ReplicatedStorage/Remotes)
--   client: waits for it to replicate
-- Keeps client and server referring to the same objects by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function getInstance(name, className)
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	else
		return folder:WaitForChild(name)
	end
end

function Remotes.get(name)
	return getInstance(name, "RemoteEvent")
end

function Remotes.getFunction(name)
	return getInstance(name, "RemoteFunction")
end

-- Server-only: fires `name` to every player whose character is within
-- `radius` studs of `position`, instead of a single player. Used for "world"
-- SFX (weapon swings, hits, enemy deaths) so everyone standing nearby hears
-- them too, not just whoever caused it — see Config.CombatSfxHearRadius.
function Remotes.fireNearby(name, position, radius, ...)
	assert(RunService:IsServer(), "Remotes.fireNearby is server-only")
	local remote = Remotes.get(name)
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			remote:FireClient(plr, ...)
		end
	end
end

return Remotes
