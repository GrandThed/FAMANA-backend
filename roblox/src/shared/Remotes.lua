-- Remote factory usable from both sides:
--   server: creates the instance if missing (under ReplicatedStorage/Remotes)
--   client: waits for it to replicate
-- Keeps client and server referring to the same objects by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

return Remotes
