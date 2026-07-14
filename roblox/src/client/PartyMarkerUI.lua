-- remarcador de party wachin: un Highlight por miembro de la party que SOLO
-- se ve cuando está tapado por una pared (ver checkLineOfSight). El nombre y
-- la distancia del compañero ya los muestra PlayerNameplateUI (mismo
-- nameplate que usa el resto de los jugadores, sin límite de distancia
-- cuando sos party con esa persona) — antes este módulo también creaba un
-- segundo BillboardGui con nombre + distancia, y quedaban dos nombres
-- pisándose arriba de la cabeza; ahora eso vive en un solo lugar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local PartyMarkerUI = {}

local MARKER_COLOR = Color3.fromRGB(255, 221, 51) -- fallback si el attribute todavía no replicó

-- Cada miembro tiene su propio Color3 asignado por PartyService (attribute
-- "PartyColor", mismo que usa MarkerUI para los pings) — así se distinguen
-- de un vistazo en vez de que todos compartan el mismo amarillo.
local function colorFor(memberPlayer)
	return memberPlayer:GetAttribute("PartyColor") or MARKER_COLOR
end

local LOS_REFRESH = 0.15 -- segundos entre chequeos de línea de visión

function PartyMarkerUI.start()
	local rows = {} -- [userId] = { highlight, characterConn }

	local function destroyRow(userId)
		local row = rows[userId]
		if not row then
			return
		end
		if row.characterConn then
			row.characterConn:Disconnect()
		end
		if row.highlight then
			row.highlight:Destroy()
		end
		rows[userId] = nil
	end

	local function attachTo(row, character)
		row.highlight.Adornee = character
		row.highlight.Parent = character
	end

	local function buildRow(memberPlayer)
		local color = colorFor(memberPlayer)

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.85
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.OutlineTransparency = 0.1
		-- AlwaysOnTop = se dibuja atravesando paredes. Lo dejamos apagado por
		-- default: solo lo prendemos (ver checkLineOfSight) cuando el
		-- raycast detecta que el compañero está tapado por geometría, así
		-- no genera ruido visual alrededor del player model cuando ya lo
		-- estás viendo directamente.
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Enabled = false

		local row = { highlight = highlight }

		if memberPlayer.Character then
			attachTo(row, memberPlayer.Character)
		end
		row.characterConn = memberPlayer.CharacterAdded:Connect(function(character)
			attachTo(row, character)
		end)

		rows[memberPlayer.UserId] = row
	end

	-- Tira un rayo desde mi HumanoidRootPart hasta el del compañero,
	-- ignorando ambos characters. Si el rayo pega contra algo en el medio
	-- (una pared, el terreno, etc.) quiere decir que está tapado -> ahí sí
	-- prendemos el highlight (que atraviesa paredes por el DepthMode). Si
	-- el rayo llega limpio, ya lo estás viendo directamente y apagamos el
	-- highlight para no ensuciar la vista.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local function checkLineOfSight(myRoot, theirRoot, myCharacter, theirCharacter)
		raycastParams.FilterDescendantsInstances = { myCharacter, theirCharacter }
		local direction = theirRoot.Position - myRoot.Position
		local result = Workspace:Raycast(myRoot.Position, direction, raycastParams)
		return result ~= nil -- true = hay algo en el medio -> está tapado
	end

	-- actualiza la lista de miembros de la party, agregando o eliminando los que entran o salen
	local function refresh()
		local myPartyId = player:GetAttribute("PartyId")

		if not myPartyId then
			for userId in pairs(rows) do
				destroyRow(userId)
			end
			return
		end

		local seen = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other:GetAttribute("PartyId") == myPartyId then
				seen[other.UserId] = true
				if not rows[other.UserId] then
					buildRow(other)
				end
			end
		end
		for userId in pairs(rows) do
			if not seen[userId] then
				destroyRow(userId)
			end
		end
	end

	local function watchPlayer(p)
		p:GetAttributeChangedSignal("PartyId"):Connect(refresh)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watchPlayer(p)
		refresh()
	end)
	Players.PlayerRemoving:Connect(function(p)
		destroyRow(p.UserId)
		refresh()
	end)

	refresh()

	local losAccumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		losAccumulator += dt
		if losAccumulator < LOS_REFRESH then
			return
		end
		losAccumulator = 0

		local myCharacter = player.Character
		local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
		if not myRoot then
			return
		end

		for userId, row in pairs(rows) do
			local memberPlayer = Players:GetPlayerByUserId(userId)
			local character = memberPlayer and memberPlayer.Character
			local theirRoot = character and character:FindFirstChild("HumanoidRootPart")

			if theirRoot then
				row.highlight.Enabled = checkLineOfSight(myRoot, theirRoot, myCharacter, character)
			else
				row.highlight.Enabled = false
			end
		end
	end)
end

return PartyMarkerUI