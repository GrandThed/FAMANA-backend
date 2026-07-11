-- Sonido de swing de arma/herramienta, distinto según el tipo (melee/
-- ranged/magic/tool). server/ToolService.lua ya dispara SwingRemote por
-- cada golpe válido (con su propio debounce de 0.4s ahí adentro —
-- SWING_COOLDOWN — así que este sonido ya viene naturalmente limitado sin
-- que tengamos que throttlear nada acá).
--
-- El daño en sí (dealDamage en EnemyService) todavía NO tiene ese mismo
-- límite — se puede spamear el click y pegar de más — así que el sonido de
-- IMPACTO (hit/critHit) vive en DamageIndicatorUI con Sfx.playThrottled en
-- vez de Sfx.play, como parche de audio hasta que exista un cooldown real
-- de combate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local CombatSfx = {}

-- styleName llega de ToolService.swingStyleFor: "slash" (espadas melee),
-- "draw" (arcos), "cast" (varitas/staffs mágicos) o "chop" (herramientas,
-- hacha/pico). Cada uno con su propio SFX registrado en Sfx.lua.
local SOUND_BY_STYLE = {
	slash = "swingMelee",
	draw = "swingRanged",
	cast = "swingMagic",
	chop = "swing",
}

-- lootSource llega de EnemyService (enemy.def.lootSource) — el mismo id que
-- ya usan para drops y objetivos de quest "kill", así que cualquier
-- enemigo nuevo que agreguen ya trae su lootSource de fábrica sin tocar
-- este archivo; solo hace falta sumarle una entrada acá (y su sonido en
-- Sfx.lua) para que deje de sonar con el fallback genérico.
local DEATH_SOUND_BY_LOOT_SOURCE = {
	slime = "slimeDeath",
	goblin = "goblinDeath",
}

function CombatSfx.start()
	Remotes.get("SwingRemote").OnClientEvent:Connect(function(styleName)
		Sfx.play(SOUND_BY_STYLE[styleName] or "swing")
	end)

	Remotes.get("EnemyDied").OnClientEvent:Connect(function(lootSource)
		Sfx.play(DEATH_SOUND_BY_LOOT_SOURCE[lootSource] or "enemyDeath")
	end)
end

return CombatSfx
