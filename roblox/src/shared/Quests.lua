-- Catálogo de quests. 100% data-driven, mismo espíritu que shared/Recipes.lua:
-- este módulo solo define contenido, QuestService (server, próximo paso) es
-- quien trackea progreso y entrega recompensas.
--
-- Quest {
--   id:          string             -- también usado como key de progreso guardado
--   name:        string
--   description: string
--   giver:       string             -- id del NPC que la da/recibe (ver futuro NPC_DEFS en QuestService)
--   minLevel:    number?            -- nivel mínimo para que el NPC la ofrezca (nil = sin mínimo)
--   repeatable:  bool?              -- default false: una vez completada, no se puede repetir
--   objectives: {
--     { id, type = "kill",     target = <enemyId>, amount = <n>, label = <string> },
--     { id, type = "gather",   target = <itemId>,  amount = <n>, label = <string> },
--     { id, type = "deliver",  target = <itemId>,  amount = <n>, label = <string> },
--     ...
--   }
--   rewards: { xp = <n>?, gold = <n>?, items = { { itemId, quantity }, ... }? }
--
-- Diferencia importante entre "gather" y "deliver": "gather" trackea el
-- EVENTO de cosechar el recurso (GatheringService.onGathered) — cuenta
-- incluso si el jugador ya gastó/vendió lo cosechado después. "deliver"
-- en cambio NO trackea automáticamente: se valida contra el inventario
-- actual (PlayerService.getItemCount) recién al hablar con el NPC para
-- entregar la quest, y esa cantidad se consume (removeItem) en ese momento.
-- Sirve para pedir cosas que no vienen de gathering (drops de loot, items
-- crafteados, etc).
--
-- Cada objetivo puede tener más de una instancia por quest (ver
-- "goblin_menace" abajo: un kill + un deliver en la misma quest) — el
-- progreso de cada uno se trackea por separado con su propio `id`.
--
-- `label` es el texto que ve el jugador en la UI del NPC (ej. "Eliminar
-- Slimes"). Se escribe a mano en vez de derivarlo de Items/enemy defs para
-- que este catálogo no dependa de esos módulos — es contenido, no lógica.
--
-- Agregar una quest acá es suficiente para que exista en el catálogo;
-- falta un NPC (ProximityPrompt, patrón VendorService/CraftingService) que
-- la ofrezca y la UI que la muestre — próximos pasos.

local Quests = {}

Quests.defs = {
	pest_control = {
		id = "pest_control",
		name = "Control de Plagas",
		description = "Los slimes se están multiplicando cerca del pueblo. Elimina 5 para despejar la zona.",
		giver = "quest_giver_village",
		objectives = {
			{ id = "kill_slimes", type = "kill", target = "slime", amount = 5, label = "Eliminar Slimes" },
		},
		rewards = { xp = 50, gold = 20 },
	},

	raw_materials = {
		id = "raw_materials",
		name = "Materiales Crudos",
		description = "Necesitamos madera para reparar la empalizada. Junta 10 unidades.",
		giver = "quest_giver_village",
		objectives = {
			{ id = "gather_wood", type = "gather", target = "wood", amount = 10, label = "Recolectar Madera" },
		},
		rewards = { xp = 30, gold = 15 },
	},

	goblin_menace = {
		id = "goblin_menace",
		name = "La Amenaza Goblin",
		description = "Los goblins son más peligrosos que los slimes. Cázalos y trae pruebas de la cacería.",
		giver = "quest_giver_village",
		minLevel = 2,
		objectives = {
			{ id = "kill_goblins", type = "kill", target = "goblin", amount = 3, label = "Eliminar Goblins" },
			{ id = "deliver_ears", type = "deliver", target = "goblin_ear", amount = 3, label = "Entregar Orejas de Goblin" },
		},
		rewards = {
			xp = 60,
			gold = 40,
			items = { { itemId = "helmet_leather", quantity = 1 } },
		},
	},
}

function Quests.get(questId)
	return Quests.defs[questId]
end

-- Orden en el que se muestran en la UI (lista de quests del NPC / quest log).
local order = { "pest_control", "raw_materials", "goblin_menace" }

function Quests.list()
	local list = {}
	for _, id in ipairs(order) do
		local def = Quests.defs[id]
		if def then
			table.insert(list, def)
		end
	end
	-- las que no estén en `order` se agregan al final (no deberían existir igual)
	for id, def in pairs(Quests.defs) do
		if not table.find(order, id) then
			table.insert(list, def)
		end
	end
	return list
end

-- Quests que un NPC puntual puede ofrecer, en el orden del catálogo.
-- Usado por el futuro NPC de quests para armar su lista sin que QuestService
-- tenga que filtrar el catálogo entero cada vez.
function Quests.forGiver(giverId)
	local list = {}
	for _, def in ipairs(Quests.list()) do
		if def.giver == giverId then
			table.insert(list, def)
		end
	end
	return list
end

return Quests
