-- Sonido de feedback al usar una habilidad. server/SpellService.lua dispara
-- SpellFeedback(spellId, ok) en CADA intento de cast — ok=true si el hechizo
-- salió (ya restó maná/cooldown), false si fue rechazado (no lo conocés,
-- sigue en cooldown, sin maná, sin objetivo válido, etc.).
--
-- El sonido de cast es UNO POR ESCUELA (las 12 de shared/Spells.lua): la
-- clave se arma como "spellCast_<schoolId>" y se busca en Sfx.lua. Una
-- escuela nueva sin sonido propio todavía cae en "spellCastDefault" (ver
-- Sfx.exists) en vez de quedar muda.
--
-- El rechazo (spellDenied) es un único sonido genérico — fallar no
-- necesita sabor por escuela, misma idea que el fallback de CombatSfx para
-- "enemyDeath".
--
-- Separado de HudUI (que hace el flash/shake visual del slot con el mismo
-- remote) para no mezclar audio con la lógica de layout del hotbar — mismo
-- espíritu que CombatSfx/PlayerFeedbackSfx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spells = require(Shared:WaitForChild("Spells"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local SpellFeedbackSfx = {}

local function castSoundFor(spellId)
	local def = Spells.get(spellId)
	local schoolId = def and def.school
	local soundName = schoolId and ("spellCast_" .. schoolId)
	if soundName and Sfx.exists(soundName) then
		return soundName
	end
	return "spellCastDefault"
end

function SpellFeedbackSfx.start()
	Remotes.get("SpellFeedback").OnClientEvent:Connect(function(spellId, ok)
		Sfx.play(ok and castSoundFor(spellId) or "spellDenied")
	end)
end

return SpellFeedbackSfx
