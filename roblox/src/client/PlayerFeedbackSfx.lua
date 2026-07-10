-- Ding de feedback cuando suben los atributos Gold/Xp del jugador local
-- (los mismos que ya lee CharacterUI). No hace falta un remote nuevo: ambos
-- ya replican como atributos de Player, así que solo escuchamos los
-- GetAttributeChangedSignal y comparamos contra el último valor visto.
--
-- Solo suena en INCREMENTOS. Gastar oro en el vendor o el "reset" de Xp al
-- subir de nivel no deberían sonar como una ganancia — y el level up ya
-- tiene su propia fanfarria en LevelUpUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer

local PlayerFeedbackSfx = {}

local function watchIncrease(attributeName, soundName)
	-- Semilla inicial SIN sonar: si no hiciéramos esto, el primer valor que
	-- llega al hacer join (p. ej. 250 de oro guardado) se leería como una
	-- "ganancia" de 0 → 250 y sonaría apenas entrás al juego.
	local last = player:GetAttribute(attributeName)

	player:GetAttributeChangedSignal(attributeName):Connect(function()
		local current = player:GetAttribute(attributeName)
		if typeof(current) == "number" and typeof(last) == "number" and current > last then
			Sfx.play(soundName)
		end
		last = current
	end)
end

function PlayerFeedbackSfx.start()
	watchIncrease("Gold", "coin")
	watchIncrease("Xp", "xpDing")

	-- Fired by server/DropService.notifyPickup on every ground-drop pickup
	-- (tree/gather yields skip this — those already have their own sound in
	-- GatherFeedbackUI).
	Remotes.get("DropPickup").OnClientEvent:Connect(function(_itemId)
		Sfx.play("itemPickup")
	end)
end

return PlayerFeedbackSfx
