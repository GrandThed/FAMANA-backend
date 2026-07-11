-- Ding de feedback al aceptar/completar una quest. QuestService ya dispara
-- QuestUpdated en cada uno de estos momentos (y en cada bump de objetivo,
-- que acá se ignora a propósito — un "+1 kill" ya tiene su propio sonido de
-- combate/muerte, sonar de nuevo acá sería redundante y machacón en un
-- grind de matar 10 de algo).
--
-- Reusa sonidos que YA existen en Sfx.lua (uiClick, xpDing) — a diferencia
-- de las muertes de slime/goblin, esto no necesita ningún asset nuevo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local QuestSfx = {}

local SOUND_BY_EVENT = {
	started = "uiClick", -- sutil: aceptar una quest no es un "logro", solo confirma la acción
	completed = "xpDing", -- el mismo ding de recompensa que XP/gold — completar SÍ es un logro
}

function QuestSfx.start()
	Remotes.get("QuestUpdated").OnClientEvent:Connect(function(_questId, _entry, eventType)
		local soundName = SOUND_BY_EVENT[eventType]
		if soundName then
			Sfx.play(soundName)
		end
	end)
end

return QuestSfx
