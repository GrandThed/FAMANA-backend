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
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared:WaitForChild("Quests"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local MapMarkers = require(Shared:WaitForChild("MapMarkers"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local Items = require(Shared:WaitForChild("Items"))
local Recipes = require(Shared:WaitForChild("Recipes"))

local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local GatheringService = require(script.Parent.GatheringService)

local QuestService = {}

-- Fired as (player, questId) right after a quest's status flips to
-- "completed" (QuestService.completeQuest). Same decoupled-hook shape as
-- EnemyService.onKilled/GatheringService.onGathered — AchievementsService
-- is the only current subscriber (bumps the "questsCompleted" stat).
local completedHandlers = {}
function QuestService.onCompleted(fn)
	table.insert(completedHandlers, fn)
end

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

-- ---- Rotación de misiones ofrecidas ---------------------------------------
-- Cada NPC dador puede tener más quests en el catálogo (Quests.forGiver) de
-- las que ofrece en un momento dado — cada ROTATION_INTERVAL se sortean de
-- nuevo OFFERS_PER_GIVER al azar del pool completo. Solo afecta qué se
-- puede EMPEZAR de nuevo (status "available" en buildGiverPayload): una
-- quest que un jugador ya tiene activa o completada sigue viéndola igual
-- aunque haya salido de rotación mientras tanto — nunca le "roba" progreso.
-- Declarado ACÁ ARRIBA (antes de canStart/startQuest/etc.) para que esas
-- funciones puedan cerrar sobre isOffered/currentOffers como upvalues —
-- Lua resuelve locals por posición textual, no por orden de ejecución.
local ROTATION_INTERVAL = 30 * 60 -- 30 minutos
local OFFERS_PER_GIVER = 2

local currentOffers = {} -- [giverId] = { [questId] = true }

-- Todos los giverId presentes en el catálogo (Quests.defs), sin duplicados,
-- en el mismo orden que Quests.list() — no depende de qué NPCs ya se hayan
-- construido, así refreshOffers() puede correr antes o después de buildGiver.
local function giverIdsInCatalog()
	local seen, list = {}, {}
	for _, def in ipairs(Quests.list()) do
		if not seen[def.giver] then
			seen[def.giver] = true
			table.insert(list, def.giver)
		end
	end
	return list
end

-- Sortea, para cada giver, hasta OFFERS_PER_GIVER quests de su pool completo
-- para ofrecer AHORA. Si el pool tiene OFFERS_PER_GIVER o menos, no hay nada
-- que rotar — se ofrecen todas (mismo comportamiento que antes de esto
-- existir). Reemplaza currentOffers[giverId] entero en vez de acumular.
local function refreshOffers()
	for _, giverId in ipairs(giverIdsInCatalog()) do
		local pool = Quests.forGiver(giverId)
		local offered = {}
		if #pool <= OFFERS_PER_GIVER then
			for _, def in ipairs(pool) do
				offered[def.id] = true
			end
		else
			-- Fisher-Yates parcial: solo hace falta barajar los primeros
			-- OFFERS_PER_GIVER lugares, no el pool entero.
			local indices = {}
			for i = 1, #pool do
				indices[i] = i
			end
			for i = 1, OFFERS_PER_GIVER do
				local j = math.random(i, #indices)
				indices[i], indices[j] = indices[j], indices[i]
				offered[pool[indices[i]].id] = true
			end
		end
		currentOffers[giverId] = offered
	end
end

local function isOffered(giverId, questId)
	local offered = currentOffers[giverId]
	return offered ~= nil and offered[questId] == true
end

-- ---- Marcador "!" sobre la cabeza del NPC ---------------------------------
-- true si `giverId` tiene algo para ofrecerle/cobrarle a ESTE jugador ahora
-- mismo: una quest recién ofrecida (rotación actual) que puede empezar, o
-- una que ya tiene activa y está lista para entregar. Mismo criterio que
-- prioriza firstOffer (más abajo), pero como bool — dispara el ícono en
-- client/QuestMarkerUI.lua.
local function giverHasSomethingFor(player, giverId)
	for _, def in ipairs(Quests.forGiver(giverId)) do
		local entry = QuestService.getProgress(player, def.id)
		if entry and entry.status == "active" and QuestService.canComplete(player, def.id) then
			return true
		end
		if isOffered(giverId, def.id) and QuestService.canStart(player, def.id) then
			return true
		end
	end
	return false
end

local giverMarkersRemote -- RemoteEvent (QuestGiverMarkers), resolved in start()

-- Le manda a ESTE jugador (nada de broadcast — el resultado depende de su
-- propio progreso/nivel) qué giverId's deberían mostrarle el "!" ahora
-- mismo. Se llama después de cualquier cosa que pueda cambiar la respuesta:
-- empezar/completar una quest, progreso que habilita una entrega, rotación
-- de ofertas, y una vez al cargar el profile.
local function pushMarkers(player)
	if not giverMarkersRemote then
		return
	end
	local markers = {}
	for _, giverId in ipairs(giverIdsInCatalog()) do
		markers[giverId] = giverHasSomethingFor(player, giverId)
	end
	giverMarkersRemote:FireClient(player, markers)
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
	pushMarkers(player)
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
	if rewards.unlockRecipes then
		for _, recipeId in ipairs(rewards.unlockRecipes) do
			PlayerService.unlockRecipe(player, recipeId)
		end
	end

	local playerQuests = questTable(player)
	playerQuests[questId].status = "completed"
	notify(player, "Misión completada: " .. def.name)
	pushUpdate(player, questId, "completed")
	pushMarkers(player)
	saveNow(player)
	for _, fn in ipairs(completedHandlers) do
		task.spawn(fn, player, questId)
	end
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
							-- Este bump puede ser justo el que deja la quest lista para
							-- entregar (canComplete pasa a true) — refresca el "!" del
							-- giver por si acaba de encenderse.
							pushMarkers(player)
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

-- { giverId, name, position, facing? (degrees yaw; el modelo mira hacia -Z),
--   lines? (flavor pool para el fallback de "Hablar" cuando no hay quest
--   nueva ni una lista para entregar — ver NpcMenuUI/QuestOffer) }
local QUEST_GIVER_DEFS = {
	{
		giverId = "quest_giver_village",
		name = "Elena la Anciana",
		position = Vector3.new(-8, 0, -34),
		facing = 160,
		lines = {
			"Este pueblo ha visto tiempos mejores, pero seguimos en pie.",
			"Ve con cuidado, la noche trae cosas peores que slimes.",
			"Cuando tengas lo que te pedí, vuelve a verme.",
			"Los goblins se acercan cada vez más al pueblo. Alguien debería hacer algo.",
		},
	},
}

local giverFolder
local giversById = {} -- [giverId] = { Vector3 positions, para el chequeo de distancia }
local npcMenuRemote -- RemoteEvent (OpenNpcMenu), resolved in start() — shared with VendorService

-- Tag usado por el cliente (QuestMarkerUI.lua) para encontrar el part de
-- cada NPC dador vía CollectionService y colgarle el BillboardGui del "!"
-- sin que el server tenga que mandarle una referencia directa al modelo.
-- El attribute "GiverId" en ese mismo part es lo que el cliente usa para
-- mapear part -> giverId y decidir qué ícono prender/apagar según el remote
-- QuestGiverMarkers (ver pushMarkers más abajo).
local GIVER_NPC_TAG = "QuestGiverNPC"

-- Deja que OTRO servicio (VendorService, CampArchitectService, ...) cuyo NPC
-- también reparte quests registre su posición acá, para que nearGiver sepa
-- de ella — mismo mecanismo que buildGiver usa para sus propios NPCs. Sin
-- esto, un giverId "prestado" a otro NPC muestra la quest en el panel pero
-- start/complete siempre devuelven "too_far".
--
-- `part` es opcional (PrimaryPart del modelo del NPC): si se pasa, además
-- lo tagea/etiqueta para que el "!" de misión disponible pueda colgarse ahí
-- sin que cada servicio dueño del modelo tenga que implementar su propio
-- BillboardGui — un solo lugar (QuestMarkerUI.lua) para todos los NPCs
-- dadores, sea cual sea el servicio que los construyó.
function QuestService.registerGiverPosition(giverId, position, part)
	giversById[giverId] = giversById[giverId] or {}
	table.insert(giversById[giverId], position)

	if part then
		CollectionService:AddTag(part, GIVER_NPC_TAG)
		part:SetAttribute("GiverId", giverId)
	end
end

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
		elseif isOffered(giverId, def.id) and QuestService.canStart(player, def.id) then
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

			local rewardRecipes = {}
			for _, recipeId in ipairs((def.rewards and def.rewards.unlockRecipes) or {}) do
				local recipeDef = Recipes.get(recipeId)
				table.insert(rewardRecipes, recipeDef and recipeDef.name or recipeId)
			end

			table.insert(quests, {
				id = def.id,
				name = def.name,
				description = def.description,
				status = status,
				objectives = objectives,
				canComplete = status == "active" and QuestService.canComplete(player, def.id) or false,
				rewards = {
					xp = def.rewards and def.rewards.xp,
					gold = def.rewards and def.rewards.gold,
					items = rewardItems,
					recipes = rewardRecipes,
				},
			})
		end
	end
	return quests
end

-- Exposed so VendorService can build the same "quests" list for a vendor
-- that also has a giverId (see VENDOR_DEFS comment) — a menu's "Ver
-- misiones" button needs the full list, not just the one Talk surfaces.
QuestService.buildGiverPayload = buildGiverPayload

-- El "mejor" quest para mostrar cuando el jugador elige HABLAR: prioriza
-- una entrega lista (canComplete) sobre una oferta nueva, así el NPC no le
-- vuelve a ofrecer la MISMA quest que ya está por cerrar. nil si no hay
-- nada — el caller cae al texto predeterminado.
local function firstOffer(player, giverId)
	local quests = buildGiverPayload(player, giverId)
	local firstAvailable = nil
	for _, quest in ipairs(quests) do
		if quest.status == "active" and quest.canComplete then
			return quest
		elseif quest.status == "available" and not firstAvailable then
			firstAvailable = quest
		end
	end
	return firstAvailable
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

	QuestService.registerGiverPosition(def.giverId, model.PrimaryPart.Position, model.PrimaryPart)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(player)
		npcMenuRemote:FireClient(player, {
			kind = "giver",
			name = def.name,
			position = model.PrimaryPart.Position,
			giverId = def.giverId,
			quests = buildGiverPayload(player, def.giverId),
			lines = def.lines,
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
	-- Shared with VendorService: whichever service starts first creates it.
	npcMenuRemote = Remotes.get("OpenNpcMenu")
	trackedChangedRemote = Remotes.get("TrackedQuestChanged")
	giverMarkersRemote = Remotes.get("QuestGiverMarkers")

	EnemyService.onKilled(onEnemyKilled)
	GatheringService.onGathered(onGathered)

	-- Primer sorteo de qué ofrece cada NPC, antes de que nadie pueda
	-- hablarles — buildGiverPayload ya puede filtrar por rotación desde el
	-- primer frame.
	refreshOffers()

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
					lines = def.lines,
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

	-- "Hablar" en NpcMenuUI: si el giver tiene algo para ofrecer/entregar,
	-- lo devuelve (mismo shape que una entrada de buildGiverPayload) y el
	-- cliente abre el panel de quest ya enfocado en esa; si no, nil y el
	-- cliente cae al texto predeterminado (lines) que ya tiene en mano.
	local questOffer = Remotes.getFunction("QuestOffer")
	questOffer.OnServerInvoke = function(player, giverId)
		if typeof(giverId) ~= "string" or not nearGiver(player, giverId) then
			return nil
		end
		return firstOffer(player, giverId)
	end

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

	-- Marcadores "!": una vez que el profile de cada jugador está cargado
	-- (join normal o ya conectado al bootear el server), y de nuevo cada
	-- vez que la rotación cambia lo que hay para ofrecer.
	local function pushMarkersWhenReady(player)
		task.spawn(function()
			if waitForProfile(player) then
				pushMarkers(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(pushMarkersWhenReady)
	for _, player in ipairs(Players:GetPlayers()) do
		pushMarkersWhenReady(player)
	end

	-- Rotación de misiones ofrecidas: cada ROTATION_INTERVAL, nuevo sorteo
	-- por giver + reempuja marcadores a todos los conectados (lo que un NPC
	-- ofrece pudo haber cambiado sin que el jugador hiciera nada).
	task.spawn(function()
		while true do
			task.wait(ROTATION_INTERVAL)
			refreshOffers()
			for _, player in ipairs(Players:GetPlayers()) do
				pushMarkers(player)
			end
		end
	end)
end

return QuestService