-- Marcadores de ping: click medio sobre un enemigo, un drop en el suelo, o
-- el terreno, para dejar una baliza visible. El cliente (MarkerUI) solo manda
-- INTENCIÓN — qué quiere marcar y para quién (Shift = party) — este service
-- valida y decide a quién se lo replica, mismo patrón que PartyService con
-- las invitaciones o CampPlacementUI con la colocación.
--
-- Un jugador tiene como máximo UN marcador activo a la vez: poner uno nuevo
-- reemplaza (y limpia) el anterior, tanto para vos como para quien lo veía.
-- Los marcadores sobre un enemigo/drop se auto-limpian solos cuando ese
-- anchor deja de existir (enemigo muere, drop se levanta o despawnea); los
-- de piso expiran solos después de Config.Markers.groundDuration.
--
-- Sin persistencia — mismo criterio que Party/Camp: es un concepto de sesión
-- en vivo, no data que sobreviva un restart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PartyService = require(script.Parent:WaitForChild("PartyService"))

local MAX_DISTANCE = Config.Markers.maxDistance
local GROUND_DURATION = Config.Markers.groundDuration

local MarkerService = {}

-- [ownerUserId] = { anchor (Instance?), recipients ({Player}), ancestryConn, expireToken }
local activeMarks = {}

local markerUpdatedRemote -- RemoteEvent, resolved in start()
local markerClearedRemote -- RemoteEvent, resolved in start()
local notifyRemote -- RemoteEvent, resolved in start() (reutiliza el toast genérico)

-- Avisa a todos los que lo estaban viendo (incluido el dueño) que el
-- marcador de `ownerUserId` ya no existe, y limpia el estado del server.
local function clearMark(ownerUserId)
	local mark = activeMarks[ownerUserId]
	if not mark then
		return
	end
	activeMarks[ownerUserId] = nil
	if mark.ancestryConn then
		mark.ancestryConn:Disconnect()
	end
	for _, recipient in ipairs(mark.recipients) do
		if recipient.Parent then
			markerClearedRemote:FireClient(recipient, ownerUserId)
		end
	end
end

-- scope == "party": todos los miembros online de la party de `player`
-- (incluido él). Si no está en party, cae a "solo vos" con un toast
-- explicando por qué. scope == "self" (o cualquier otra cosa): solo vos.
local function recipientsFor(player, scope)
	if scope == "party" then
		local partyId = PartyService.getPartyId(player)
		if partyId then
			local list = {}
			for _, other in ipairs(Players:GetPlayers()) do
				if PartyService.getPartyId(other) == partyId then
					table.insert(list, other)
				end
			end
			return list
		end
		notifyRemote:FireClient(player, "No estás en un grupo — el marcador solo es visible para vos.")
	end
	return { player }
end

-- Nunca confiamos en la instancia que manda el cliente a ojos cerrados:
-- tiene que ser un enemigo/drop real, vivo, en la carpeta esperada — mismo
-- chequeo que TargetingController/EnemyInspectUI hacen del lado cliente.
local function validAnchor(kind, instance)
	if typeof(instance) ~= "Instance" or not instance:IsA("BasePart") then
		return false
	end
	if kind == "enemy" then
		local folder = Workspace:FindFirstChild("Enemies")
		return folder ~= nil and instance.Parent == folder and instance:FindFirstChild("HealthBar") ~= nil
	elseif kind == "loot" then
		local folder = Workspace:FindFirstChild("Drops")
		return folder ~= nil and instance.Parent == folder and instance.Name == "Drop"
	end
	return false
end

function MarkerService.start()
	markerUpdatedRemote = Remotes.get("MarkerUpdated")
	markerClearedRemote = Remotes.get("MarkerCleared")
	notifyRemote = Remotes.get("Notify")

	Remotes.get("RequestMark").OnServerEvent:Connect(function(player, kind, instance, position, scope)
		if kind ~= "enemy" and kind ~= "loot" and kind ~= "ground" then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		local anchor, worldPosition
		if kind == "ground" then
			if typeof(position) ~= "Vector3" then
				return
			end
			worldPosition = position
		else
			if not validAnchor(kind, instance) then
				return
			end
			anchor = instance
			worldPosition = anchor.Position
		end

		if (worldPosition - root.Position).Magnitude > MAX_DISTANCE then
			return -- muy lejos para ser un click legítimo, ignorar
		end

		clearMark(player.UserId) -- solo un marcador activo por jugador a la vez

		local recipients = recipientsFor(player, scope == "party" and "party" or "self")
		local mark = { anchor = anchor, recipients = recipients }
		activeMarks[player.UserId] = mark

		local payload = {
			kind = kind,
			ownerUserId = player.UserId,
			ownerName = player.Name,
			anchor = anchor, -- nil para "ground"
			position = worldPosition,
		}
		for _, recipient in ipairs(recipients) do
			if recipient.Parent then
				markerUpdatedRemote:FireClient(recipient, payload)
			end
		end

		if anchor then
			-- AncestryChanged dispara cuando el anchor se destruye/despawnea
			-- (enemigo muere, drop se levanta o su timeout lo despawnea).
			mark.ancestryConn = anchor.AncestryChanged:Connect(function(_, parent)
				if not parent then
					clearMark(player.UserId)
				end
			end)
		else
			local token = {}
			mark.expireToken = token
			task.delay(GROUND_DURATION, function()
				local current = activeMarks[player.UserId]
				if current and current.expireToken == token then
					clearMark(player.UserId)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearMark(player.UserId)
	end)
end

return MarkerService
