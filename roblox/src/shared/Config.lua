-- Shared, non-secret constants. Visible to client and server.
-- (The API key is NOT here — it lives server-only in Secret.lua.)

-- Note: which grid cell a Place represents now lives in GridConfig (derived
-- from PlaceId), not here.

return {
	-- The main inventory grid: fixed width, `height` rows for the basic
	-- backpack (bigger packs add rows later). MUST match backend items.js GRID.
	inventoryGrid = { width = 10, height = 30 },

	-- Reach (studs) now lives per-item as a `reach` stat on each weapon/tool def
	-- (see Items.lua). Server combat/gather and client focus all read that single
	-- value. This is the fallback for any equippable that forgot to set one.
	defaultReach = 9,

	HP = {
		max = 100,
		regenAmount = 1, -- HP restored per tick
		regenInterval = 2, -- seconds between regen ticks
		regenDelay = 5, -- seconds out of combat before regen starts
		respawnDelay = 5, -- seconds after death before respawning

		-- Downed state (a lethal hit downs instead of killing outright):
		downedBleedTime = 15, -- seconds before a downed player dies for real
		downedReviveTime = 4, -- seconds an ally must hold the revive prompt
		downedReviveHealPercent = 0.5, -- HP fraction restored on a full revive
		downedWalkSpeed = 4, -- crawl speed while downed
		downedVisibleRange = 30, -- studs: how close others must be to see you're downed
	},

	-- Mana: a live gameplay resource (not persisted) that powers ranged magic.
	-- Regenerates steadily; the staff spends it per cast (see Items manaCost).
	Mana = {
		max = 100,
		regenAmount = 3, -- mana restored per tick
		regenInterval = 1, -- seconds between regen ticks
	},

	-- How often the server persists HP/position to the backend.
	autosaveInterval = 60,

	-- Combat feel: chance for a weapon swing to land as a critical hit, and
	-- the damage multiplier applied when it does. Read by EnemyService.
	Combat = {
		critChance = 0.15, -- 15% of hits crit
		critMultiplier = 2, -- crits deal 2x damage

		-- Mob levels: each spawn rolls a random level in its def's
		-- [minLevel, maxLevel] range. Every level above 1 scales the mob's
		-- base hp/damage/xp reward by these fractions (linear, not compounding).
		mobLevel = {
			hpPerLevel = 0.15, -- +15% hp per level above 1
			damagePerLevel = 0.10, -- +10% damage per level above 1 (legacy)
			adPerLevel = 0.10, -- +10% AD per level above 1
			apPerLevel = 0.10, -- +10% AP per level above 1
			xpPerLevel = 0.20, -- +20% xp reward per level above 1
			armorPerLevel = 0.12, -- +12% armor per level above 1
			magicResistPerLevel = 0.12, -- +12% magic resist per level above 1
		},

		-- Telegraph de ataque enemigo: en vez de pegar apenas entra en rango y
		-- se cumple el cooldown, el enemigo "carga" el golpe por una fracción
		-- de su attackCooldown (ver EnemyService.lua) — durante esa ventana
		-- se le muestra una marca flotante ❗ con barrita de cuenta regresiva
		-- (mismo sistema que las marcas de stun/slow), para avisar que el
		-- golpe viene. No agrega tiempo extra entre ataques, solo lo reparte:
		-- el reloj de cooldown arranca al empezar la carga, no al conectar
		-- el golpe.
		attackWindupFraction = 0.35, -- % del attackCooldown gastado en la carga
		attackWindupMin = 0.2, -- segundos — piso, para que bichos rápidos no avisen "instantáneo"
		attackWindupMax = 0.6, -- segundos — techo, para que bichos lentos no tarden una eternidad
	},

	-- Player leveling curve. xpToNext(level) = baseXp + (level-1)*xpPerLevel.
	-- `level` drives HP/Mana/Armor/MR/AD/AP directly (see shared/Classes.lua
	-- statsAtLevel) — maxLevel here MUST match Classes.MAX_LEVEL.
	PlayerLeveling = {
		baseXp = 50, -- xp needed to go from level 1 -> 2
		xpPerLevel = 25, -- extra xp required per level after that
		maxLevel = 20, -- hard cap; xp stops accruing once reached
	},

	-- Parties: solo en la memoría del sv, no en la base de datos
	Party = {
		maxSize = 6,
		inviteTimeout = 30, -- las invitaciones sn validas por 30 segs
		xpShareRadius = 60, -- radio para compartir xp entre miembros de party
	},

	-- Gremios: persistidos en el backend (tabla `guilds`), a diferencia de
	-- Party. Roles son solo leader/member para el MVP — ver GuildService.
	Guild = {
		nameMinLen = 3,
		nameMaxLen = 24,
		tagMinLen = 2,
		tagMaxLen = 5,
		inviteTimeout = 30, -- mismo criterio que Party.inviteTimeout
	},

	-- Sfx.lua no tiene sonido posicional (sin rolloff por distancia real),
	-- así que el radio de "quién lo escucha" se controla acá: cualquier
	-- jugador con su HumanoidRootPart a esta distancia o menos del origen
	-- del sonido (swing, hit/crit, muerte de enemigo) lo recibe, no solo
	-- quien lo generó. Mismo orden de magnitud que xpShareRadius arriba.
	CombatSfxHearRadius = 60,

	-- Acampada: zona segura + respawn craftable por el jugador (ver
	-- shared/Recipes.lua y server/CampService.lua). Solo en memoria del
	-- server, no se persiste al backend — mismo criterio que Party.
	Camp = {
		duration = 60 * 60, -- la acampada dura 1 hora
		cooldown = 30 * 60, -- 30 min de cooldown tras expirar, por dueño
		zoneSize = 30, -- cuadrado de N x N studs, centrado en la fogata (tier 0 — ver tiers abajo)
		maxPlacementDistance = 20, -- distancia jugador -> punto de colocación (anti-exploit)
		nightRegenBonus = 3,

		-- Camp tiers (docs/CAMP_TIERS.md): mejora persistente por jugador
		-- (PlayerService.getCampTier/setCampTier), comprada una sola vez,
		-- separada del ciclo de craftear/plantar la Acampada en sí (que no
		-- cambia con el tier). Puro dato por ahora — CampService y
		-- CampFurnitureService todavía leen los campos planos de arriba;
		-- pasan a leer tiers[ownerTier] en el próximo paso.
		--
		-- zoneSize/nightRegenBonusMin duplican tier 0 arriba a propósito
		-- (mismo valor, dos lugares) para que la tabla sea autocontenida y
		-- CampService pueda indexar tiers[0..3] uniformemente sin un caso
		-- especial para "sin mejora". nightRegenBonusMin/Max son el piso y
		-- techo de coziness (§3 del doc): el piso es el bonus con la zona
		-- vacía, el techo el bonus con el máximo de piezas cosméticas
		-- plantadas para ese tier.
		maxTier = 3,
		tiers = {
			[0] = {
				zoneSize = 30,
				maxFurniture = 4,
				nightRegenBonusMin = 3,
				nightRegenBonusMax = 3,
				cozinessTarget = 0, -- min == max, no cosmetics unlock this early anyway
				cost = nil, -- tier inicial, no se compra
			},
			[1] = {
				zoneSize = 40,
				maxFurniture = 6,
				nightRegenBonusMin = 3,
				nightRegenBonusMax = 5,
				cozinessTarget = 3, -- plantar 3 piezas cosméticas ya toca el techo
				-- TODO: calibrar cantidad jugado (docs/CAMP_TIERS.md §8).
				cost = { copper_ingot = 15 },
			},
			[2] = {
				zoneSize = 50,
				maxFurniture = 8,
				nightRegenBonusMin = 4,
				nightRegenBonusMax = 7,
				cozinessTarget = 4,
				-- TODO: calibrar cantidad jugado (docs/CAMP_TIERS.md §8).
				cost = { iron_ingot = 20, copper_ingot = 10 },
			},
			[3] = {
				zoneSize = 65,
				maxFurniture = 10,
				nightRegenBonusMin = 5,
				nightRegenBonusMax = 10,
				cozinessTarget = 5,
				-- Bloqueado hasta que exista un material de mena tier 3
				-- (docs/CAMP_TIERS.md §8) — nil a propósito, no inventar
				-- un item que no existe en content/items.json todavía.
				cost = nil,
			},
		},

		-- Radio (studs) reservado alrededor del centro de la Acampada donde
		-- NUNCA se puede plantar un mueble, en NINGÚN tier — mide el
		-- footprint de la fogata más grande (tier 3), reservado desde tier 0
		-- para que subir de tier nunca puje/clipee muebles ya plantados
		-- (docs/CAMP_TIERS.md §6.1). Placeholder hasta tener el modelo de
		-- fogata tier 3 real.
		firePitRadius = 6,

		-- "Rested" (RestedService.lua): reworked coziness reward — banks
		-- while resting in a safe camp at night, converts to a temporary
		-- gathering yield buff on leaving. Replaces the old decoration-
		-- scaled HP regen bonus (see the comment where it used to live in
		-- CampFurnitureService.start()). Placeholders, calibrate jugado.
		rested = {
			-- Segundos de "banco" acumulados por cada segundo real quieto en
			-- zona segura de noche, ANTES del multiplicador de coziness.
			baseAccrualPerSecond = 1,
			-- Con coziness al máximo (cozinessRatio == 1) el banco crece
			-- accrualMultAtMaxCoziness veces más rápido que vacío — o sea,
			-- decorar sigue valiendo la pena: menos tiempo parado para la
			-- misma duración de buff eventual.
			accrualMultAtMaxCoziness = 2,
			-- Tope de cuánto tiempo de buff podés bankear de una sentada
			-- (evita el AFK-toda-la-noche = buff infinito).
			chargeCapSeconds = 20 * 60,
			-- Bonus de yield de gathering mientras el buff "Descansado" está
			-- activo (mismo hook que el bonus nocturno, GatheringService.
			-- registerYieldBonus).
			yieldBonus = 0.15,
		},
	},

	-- Muebles de campamento (cofre, carpa, ...): solo plantables dentro de
	-- una Acampada activa. Sin persistencia (misma filosofía que Camp) — ver
	-- server/CampFurnitureService.lua.
	CampFurniture = {
		minSpacing = 4, -- studs mínimos entre dos muebles del mismo campamento
		chestColumns = 6, -- ancho de la grilla del cofre (mismo componente ItemGrid)
		chestRows = 6,
	},

	-- Marcadores de ping (click medio sobre enemigo/loot/piso). En memoria
	-- del server, un marcador activo por jugador — ver server/MarkerService.lua.
	Markers = {
		maxDistance = 150, -- distancia máxima jugador -> punto marcado (anti-exploit)
		groundDuration = 8, -- segundos que dura un marcador de piso antes de expirar solo
	},
}