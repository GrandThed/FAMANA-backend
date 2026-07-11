-- Trackea progreso de quests y entrega recompensas. Se engancha a los hooks
-- que YA existen (EnemyService.onKilled, GatheringService.onGathered) en vez
-- de meterse en esos sistemas — mismo patrón desacoplado que DropService/
-- EffectService.
--
-- Progreso persistido: vive en profile.questProgress (PlayerService), que
-- viaja con el resto del profile a través del backend — sobrevive
-- desconexiones Y cruces de cell (cada cell es un Place distinto). Este
-- servicio solo lee/escribe esa tabla en memoria a través del cache de
-- PlayerService; PlayerService.save() es quien la manda al backend
-- (autosave cada Config.autosaveInterval + on-leave/BindToClose, más un
-- save inmediato acá en start/complete — ver saveNow).
--
-- questProgress[questId] = {
--   status = "active" | "completed",
--   objectives = { [objectiveId] = count },
-- }

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared:WaitForChild("Quests"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))

local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local GatheringService = require(script.Parent.GatheringService)

local QuestService = {}

local notifyRemote -- RemoteEvent, resolved in start()
local questUpdatedRemote -- RemoteEvent, resolved in start() — pushes progress to the client (future quest log UI)

local function notify(player, message)
	if notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

-- eventType: "started" | "completed" | "progress" (default). Puramente
-- informativo para el cliente (QuestSfx.lua elige el sonido según esto);
-- el estado real de la quest sigue viviendo en `entry`, esto no cambia
-- nada de la lógica de servidor.
local function pushUpdate(player, questId, eventType)
	if questUpdatedRemote then
		local entry = QuestService.getProgress(player, questId)
		questUpdatedRemote:FireClient(player, questId, entry, eventType or "progress")
	end
end

-- Tabla questProgress del profile en cache de PlayerService (nil si el
-- profile todavía no cargó o es temporal — sin backend no hay donde
-- persistir, la quest simplemente no progresa esa sesión).
local function questTable(player)
	local profile = PlayerService.get(player)
	if not profile or profile._temporary then
		return nil
	end
	profile.questProgress = profile.questProgress or {}
	return profile.questProgress
end

-- Guardado inmediato para los momentos "importantes" (start/complete) en
-- vez de esperar al autosave — los bumps de kill/gather individuales NO
-- llaman esto, viajan con el próximo autosave/leave (mismo criterio que
-- gold/XP en PlayerService).
local function saveNow(player)
	PlayerService.save(player)
end

-- Espera a que el profile termine de cargar (misma espera con timeout que
-- requestInventory en PlayerService — el cliente puede pedir esto antes de
-- que el HTTP de carga del profile haya vuelto).
local function waitForProfile(player)
	local deadline = os.clock() + 10
	while not PlayerService.get(player) and os.clock() < deadline do
		task.wait(0.1)
	end
	return PlayerService.get(player)
end

-- ---- Consultas -------------------------------------------------------

-- true si el jugador puede empezar `questId`: no la tiene activa/completada
-- ya (salvo que sea repeatable), y cumple el nivel mínimo si tiene uno.
function QuestService.canStart(player, questId)
	local def = Quests.get(questId)
	if not def then
		return false, "unknown_quest"
	end

	local playerQuests = questTable(player)
	local existing = playerQuests and playerQuests[questId]
	if existing then
		if existing.status == "active" then
			return false, "already_active"
		end
		if existing.status == "completed" and not def.repeatable then
			return false, "already_completed"
		end
	end

	if def.minLevel then
		local profile = PlayerService.get(player)
		if not profile or profile.level < def.minLevel then
			return false, "level_too_low"
		end
	end

	return true
end

function QuestService.getProgress(player, questId)
	local playerQuests = questTable(player)
	return playerQuests and playerQuests[questId]
end

-- Lista de { def, entry } para las quests activas del jugador — pensado
-- para el futuro quest log UI.
function QuestService.listActive(player)
	local playerQuests = questTable(player)
	local list = {}
	if not playerQuests then
		return list
	end
	for questId, entry in pairs(playerQuests) do
		if entry.status == "active" then
			table.insert(list, { def = Quests.get(questId), entry = entry })
		end
	end
	return list
end

-- Texto + progreso actual de un objetivo, para la UI. Los "deliver" leen el
-- inventario en vivo (mismo criterio que canComplete); kill/gather leen el
-- contador guardado. Definida acá arriba (en vez de junto al NPC dador,
-- donde vivía originalmente) porque buildQuestLogPayload también la usa.
local function describeObjective(player, objective, entry)
	local current
	if objective.type == "deliver" then
		current = math.min(PlayerService.getItemCount(player, objective.target), objective.amount)
	else
		current = entry and (entry.objectives[objective.id] or 0) or 0
	end
	return {
		label = objective.label or objective.target,
		current = current,
		amount = objective.amount,
	}
end

-- ---- Quest log + tracked quest -----------------------------------------
-- "Tracked" = la única quest activa que se muestra en el HUD (QuestTrackerUI).
-- Se elige a mano desde el quest log panel (QuestLogUI, botón "Track"), pero
-- SIEMPRE hay un fallback: si la trackeada se completa/deja de ser válida y
-- el jugador tiene otra activa, se re-trackea sola en vez de dejar el HUD
-- vacío con quests pendientes. profile.trackedQuestId persiste como el resto
-- del profile (autosave/leave), "" = ninguna.

-- Payload liviano para el HUD: no necesita el def completo, solo lo que
-- muestra. nil si no hay nada trackeado.
local function buildTrackedPayload(questId, entry)
	if not questId or not entry then
		return nil
	end
	local def = Quests.get(questId)
	if not def then
		return nil
	end
	local objectives = {}
	for _, objective in ipairs(def.objectives) do
		table.insert(objectives, {
			label = objective.label or objective.target,
			current = entry.objectives[objective.id] or 0,
			amount = objective.amount,
		})
	end
	return { questId = questId, name = def.name, objectives = objectives }
end

local trackedChangedRemote -- RemoteEvent, resolved in start()

local function pushTracked(player, questId, entry)
	if trackedChangedRemote then
		trackedChangedRemote:FireClient(player, buildTrackedPayload(questId, entry))
	end
end

-- Devuelve (questId, entry) de la quest trackeada actual, resolviendo el
-- fallback si hace falta: si profile.trackedQuestId no apunta a algo activo
-- (nunca se eligió una, se completó, etc.), cae en la primera quest activa
-- del catálogo (orden de Quests.list()) — nunca deja al jugador con quests
-- activas y el tracker vacío. El fallback se persiste (rides el próximo
-- autosave, no hace falta saveNow) pero SÍ empuja el cambio al cliente ya,
-- así el HUD no queda mostrando algo viejo/completado.
function QuestService.getTrackedQuest(player)
	local profile = PlayerService.get(player)
	local playerQuests = questTable(player)
	if not profile or not playerQuests then
		return nil
	end

	local trackedId = profile.trackedQuestId
	if trackedId ~= "" then
		local entry = playerQuests[trackedId]
		if entry and entry.status == "active" then
			return trackedId, entry
		end
	end

	for _, def in ipairs(Quests.list()) do
		local entry = playerQuests[def.id]
		if entry and entry.status == "active" then
			if profile.trackedQuestId ~= def.id then
				profile.trackedQuestId = def.id
				pushTracked(player, def.id, entry)
			end
			return def.id, entry
		end
	end

	if profile.trackedQuestId ~= "" then
		profile.trackedQuestId = ""
		pushTracked(player, nil, nil)
	end
	return nil
end

-- Verbo del quest log panel: marcar `questId` como la trackeada. Solo válido
-- si el jugador la tiene activa (no completada, no inexistente).
function QuestService.setTrackedQuest(player, questId)
	local playerQuests = questTable(player)
	local profile = PlayerService.get(player)
	if not playerQuests or not profile then
		return false
	end
	local entry = playerQuests[questId]
	if not entry or entry.status ~= "active" then
		return false
	end

	profile.trackedQuestId = questId
	pushTracked(player, questId, entry)
	return true
end

-- Todas las quests que el jugador tiene (activas + completadas), en el
-- orden del catálogo, con la misma forma de objectives que buildGiverPayload
-- — pensado para el quest log panel (QuestLogUI).
local function buildQuestLogPayload(player)
	local playerQuests = questTable(player)
	local list = {}
	if not playerQuests then
		return list
	end

	local trackedId = select(1, QuestService.getTrackedQuest(player))

	for _, def in ipairs(Quests.list()) do
		local entry = playerQuests[def.id]
		if entry then
			local objectives = {}
			for _, objective in ipairs(def.objectives) do
				table.insert(objectives, describeObjective(player, objective, entry))
			end
			table.insert(list, {
				id = def.id,
				name = def.name,
				description = def.description,
				status = entry.status,
				objectives = objectives,
				tracked = def.id == trackedId,
			})
		end
	end
	return list
end

-- ---- Empezar / completar ----------------------------------------------

function QuestService.startQuest(player, questId)
	local ok, errorCode = QuestService.canStart(player, questId)
	if not ok then
		return false, errorCode
	end

	local playerQuests = questTable(player)
	if not playerQuests then
		return false, "offline"
	end

	local def = Quests.get(questId)
	local objectives = {}
	for _, objective in ipairs(def.objectives) do
		objectives[objective.id] = 0
	end

	playerQuests[questId] = { status = "active", objectives = objectives }

	notify(player, "Nueva misión: " .. def.name)
	pushUpdate(player, questId, "started")
	saveNow(player)
	-- Si el jugador no tenía nada trackeado, esta pasa a serlo (fallback de
	-- getTrackedQuest); si ya tenía otra trackeada, no se la pisa.
	QuestService.getTrackedQuest(player)
	return true
end

-- true si todos los objetivos ya están en su `amount` (los "deliver" se
-- validan en vivo contra el inventario acá, no contra el contador
-- guardado, porque el jugador puede haber gastado/tirado el item después
-- de que un evento lo hubiera contado).
function QuestService.canComplete(player, questId)
	local def = Quests.get(questId)
	local entry = QuestService.getProgress(player, questId)
	if not def or not entry or entry.status ~= "active" then
		return false
	end

	for _, objective in ipairs(def.objectives) do
		if objective.type == "deliver" then
			if PlayerService.getItemCount(player, objective.target) < objective.amount then
				return false
			end
		else
			if (entry.objectives[objective.id] or 0) < objective.amount then
				return false
			end
		end
	end
	return true
end

-- Entrega la quest: consume los items de los objetivos "deliver" y otorga
-- las recompensas. Falla limpio (sin tocar nada) si algo no está listo.
function QuestService.completeQuest(player, questId)
	if not QuestService.canComplete(player, questId) then
		return false, "not_ready"
	end

	local def = Quests.get(questId)

	-- Los "deliver" se consumen recién acá, todos juntos, después de haber
	-- confirmado (canComplete) que el jugador tiene lo necesario de cada
	-- uno — así una entrega parcial nunca deja la quest a medio consumir.
	for _, objective in ipairs(def.objectives) do
		if objective.type == "deliver" then
			PlayerService.removeItem(player, objective.target, objective.amount)
		end
	end

	local rewards = def.rewards or {}
	if rewards.xp then
		PlayerService.addXp(player, rewards.xp)
	end
	if rewards.gold then
		PlayerService.addGold(player, rewards.gold)
	end
	if rewards.items then
		for _, reward in ipairs(rewards.items) do
			PlayerService.addItem(player, reward.itemId, reward.quantity, true)
		end
	end

	local playerQuests = questTable(player)
	playerQuests[questId].status = "completed"
	notify(player, "Misión completada: " .. def.name)
	pushUpdate(player, questId, "completed")
	saveNow(player)
	-- Si `questId` era la trackeada, esto la reemplaza por otra activa (si
	-- hay) o limpia el tracker (si no) — nunca deja el HUD mostrando una
	-- quest ya completada.
	QuestService.getTrackedQuest(player)
	return true
end

-- ---- Tracking automático (kill / gather) -------------------------------

-- Suma 1 al objetivo `predicate` de toda quest activa del jugador que
-- matchee, y avisa (sin spamear: solo en los múltiplos de progreso reales).
local function bumpObjectives(player, objectiveType, target)
	local playerQuests = questTable(player)
	if not playerQuests then
		return
	end

	for questId, entry in pairs(playerQuests) do
		if entry.status == "active" then
			local def = Quests.get(questId)
			if def then
				for _, objective in ipairs(def.objectives) do
					if objective.type == objectiveType and objective.target == target then
						local current = entry.objectives[objective.id] or 0
						if current < objective.amount then
							current = math.min(current + 1, objective.amount)
							entry.objectives[objective.id] = current
							notify(
								player,
								string.format("%s: %d/%d", def.name, current, objective.amount)
							)
							pushUpdate(player, questId)
							local profile = PlayerService.get(player)
							if profile and profile.trackedQuestId == questId then
								pushTracked(player, questId, entry)
							end
						end
					end
				end
			end
		end
	end
end

local function onEnemyKilled(lootSource, _position, killer, _level)
	if killer and killer:IsA("Player") then
		bumpObjectives(killer, "kill", lootSource)
	end
end

local function onGathered(player, itemId, _amount, _position)
	bumpObjectives(player, "gather", itemId)
end

-- ---- NPC dador de quests ------------------------------------------------
-- Mismo patrón que VendorService: modelo low-poly vía ArtKit + ProximityPrompt.
-- Placement: authored maps usan marcadores QuestGiver_<giverId> (ver
-- shared/MapMarkers), QUEST_GIVER_DEFS es el fallback para places sin mapa.

local MAX_TALK_DISTANCE = 16

-- { giverId, name, position, facing? (degrees yaw; el modelo mira hacia -Z) }
local QUEST_GIVER_DEFS = {
	{ giverId = "quest_giver_village", name = "Elena la Anciana", position = Vector3.new(-8, 0, -34), facing = 160 },
}

local giverFolder
local giversById = {} -- [giverId] = { Vector3 positions, para el chequeo de distancia }
local openGiverRemote -- RemoteEvent, resolved in start()

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { giverFolder }
	local result = Workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -1000, 0), params)
	return result and result.Position.Y or 0
end

-- Texto + progreso actual de un objetivo, para la UI. Los "deliver" leen el
-- inventario en vivo (mismo criterio que canComplete); kill/gather leen el
-- contador guardado.

-- Arma el payload que ve el cliente al hablar con `giverId`: cada quest del
-- catálogo que ese NPC da, con su estado desde la perspectiva de este
-- jugador puntual (available / active / completed). Se reusa tanto al abrir
-- el panel como después de cada acción (start/complete), así el cliente
-- siempre re-renderiza con datos frescos del server.
local function buildGiverPayload(player, giverId)
	local quests = {}
	for _, def in ipairs(Quests.forGiver(giverId)) do
		local entry = QuestService.getProgress(player, def.id)
		local status
		if entry and entry.status == "active" then
			status = "active"
		elseif entry and entry.status == "completed" and not def.repeatable then
			status = "completed"
		elseif QuestService.canStart(player, def.id) then
			status = "available"
		end

		if status then
			local objectives = {}
			for _, objective in ipairs(def.objectives) do
				table.insert(objectives, describeObjective(player, objective, entry))
			end

			local rewardItems = {}
			for _, reward in ipairs((def.rewards and def.rewards.items) or {}) do
				local itemDef = Items.get(reward.itemId)
				table.insert(rewardItems, { name = itemDef and itemDef.name or reward.itemId, quantity = reward.quantity })
			end

			table.insert(quests, {
				id = def.id,
				name = def.name,
				description = def.description,
				status = status,
				objectives = objectives,
				canComplete = status == "active" and QuestService.canComplete(player, def.id) or false,
				rewards = { xp = def.rewards and def.rewards.xp, gold = def.rewards and def.rewards.gold, items = rewardItems },
			})
		end
	end
	return quests
end

local function buildGiver(def)
	local y = groundY(def.position.X, def.position.Z)
	local origin = CFrame.new(def.position.X, y, def.position.Z) * CFrame.Angles(0, math.rad(def.facing or 0), 0)

	-- Túnica azulada + capucha para leerse distinto del vendor (cuero/marrón).
	local model = ArtKit.build("QuestGiver_" .. def.giverId, origin, {
		{ name = "Robe", size = Vector3.new(1.9, 2.6, 1.1), offset = Vector3.new(0, 1.9, 0), color = "sapphire", primary = true },
		{ name = "ArmL", size = Vector3.new(0.5, 1.3, 0.5), offset = Vector3.new(-1.2, 2.2, 0), rot = Vector3.new(0, 0, 8), color = "sapphire" },
		{ name = "ArmR", size = Vector3.new(0.5, 1.3, 0.5), offset = Vector3.new(1.2, 2.2, 0), rot = Vector3.new(0, 0, -8), color = "sapphire" },
		{ name = "Head", size = Vector3.new(1.0, 1.0, 1.0), offset = Vector3.new(0, 3.7, 0), color = "skin" },
		{ name = "EyeL", size = Vector3.new(0.14, 0.2, 0.06), offset = Vector3.new(-0.22, 3.78, -0.53), color = "ink" },
		{ name = "EyeR", size = Vector3.new(0.14, 0.2, 0.06), offset = Vector3.new(0.22, 3.78, -0.53), color = "ink" },
		{ name = "Hood", size = Vector3.new(1.3, 0.5, 1.3), offset = Vector3.new(0, 4.25, 0), color = "steelDark" },
		{ name = "Staff", size = Vector3.new(0.18, 3.0, 0.18), offset = Vector3.new(1.5, 1.8, 0), color = "trunkDark" },
	})
	model.Parent = giverFolder

	giversById[def.giverId] = giversById[def.giverId] or {}
	table.insert(giversById[def.giverId], model.PrimaryPart.Position)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(player)
		openGiverRemote:FireClient(player, {
			giverId = def.giverId,
			giverName = def.name,
			position = model.PrimaryPart.Position,
			quests = buildGiverPayload(player, def.giverId),
		})
	end)
end

-- Si el jugador está a distancia de charla de algún NPC que dé `giverId`.
local function nearGiver(player, giverId)
	local positions = giversById[giverId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not positions or not root then
		return false
	end
	for _, position in ipairs(positions) do
		if (root.Position - position).Magnitude <= MAX_TALK_DISTANCE then
			return true
		end
	end
	return false
end

-- Verbo start/complete pedido por el cliente. Devuelve el payload del giver
-- ya refrescado, así el panel se re-renderiza sin un segundo viaje al server.
local function handleQuestAction(player, payload)
	if typeof(payload) ~= "table" or typeof(payload.giverId) ~= "string" or typeof(payload.questId) ~= "string" then
		return { ok = false, error = "bad_request" }
	end
	if not nearGiver(player, payload.giverId) then
		return { ok = false, error = "too_far" }
	end

	local ok, errorCode
	if payload.verb == "start" then
		ok, errorCode = QuestService.startQuest(player, payload.questId)
	elseif payload.verb == "complete" then
		ok, errorCode = QuestService.completeQuest(player, payload.questId)
	else
		return { ok = false, error = "bad_request" }
	end

	return { ok = ok, error = errorCode, quests = buildGiverPayload(player, payload.giverId) }
end

-- ---- Lifecycle -----------------------------------------------------------

function QuestService.start()
	notifyRemote = Remotes.get("Notify")
	questUpdatedRemote = Remotes.get("QuestUpdated")
	openGiverRemote = Remotes.get("OpenQuestGiver")
	trackedChangedRemote = Remotes.get("TrackedQuestChanged")

	EnemyService.onKilled(onEnemyKilled)
	GatheringService.onGathered(onGathered)

	giverFolder = Instance.new("Folder")
	giverFolder.Name = "QuestGivers"
	giverFolder.Parent = Workspace

	if MapMarkers.mapPresent() then
		local defsByGiver = {}
		for _, def in ipairs(QUEST_GIVER_DEFS) do
			defsByGiver[def.giverId] = def
		end
		local markers = MapMarkers.takeFor("QuestGiver_", defsByGiver)
		for giverId, def in pairs(defsByGiver) do
			for _, marker in ipairs(markers[giverId] or {}) do
				buildGiver({
					giverId = def.giverId,
					name = def.name,
					position = marker.cframe.Position,
					facing = MapMarkers.facing(marker),
				})
			end
		end
	else
		for _, def in ipairs(QUEST_GIVER_DEFS) do
			buildGiver(def)
		end
	end

	local questAction = Remotes.getFunction("QuestAction")
	questAction.OnServerInvoke = handleQuestAction

	-- Quest log panel (QuestLogUI): toda la lista del jugador.
	local requestQuestLog = Remotes.getFunction("RequestQuestLog")
	requestQuestLog.OnServerInvoke = function(player)
		waitForProfile(player)
		return buildQuestLogPayload(player)
	end

	-- Quest log panel: botón "Track". Devuelve el log ya refrescado, mismo
	-- patrón que QuestAction (evita un segundo viaje al server).
	local setTrackedQuest = Remotes.getFunction("SetTrackedQuest")
	setTrackedQuest.OnServerInvoke = function(player, questId)
		if typeof(questId) ~= "string" then
			return { ok = false }
		end
		local ok = QuestService.setTrackedQuest(player, questId)
		return { ok = ok, log = buildQuestLogPayload(player) }
	end

	-- HUD tracker (QuestTrackerUI): pedido único al arrancar, para no
	-- depender de haber estado conectado cuando se disparó el último
	-- TrackedQuestChanged (por ejemplo, si el jugador recién está cargando).
	local requestTrackedQuest = Remotes.getFunction("RequestTrackedQuest")
	requestTrackedQuest.OnServerInvoke = function(player)
		waitForProfile(player)
		local questId, entry = QuestService.getTrackedQuest(player)
		return buildTrackedPayload(questId, entry)
	end

	-- No cleanup needed on PlayerRemoving: questProgress vive dentro del
	-- profile de PlayerService, que ya se guarda y limpia solo (save() +
	-- cache[userId] = nil en su propio handler de PlayerRemoving).
end

return QuestService
