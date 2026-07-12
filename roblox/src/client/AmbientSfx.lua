-- Loop de ambiente que le da vida al mundo (pájaros/viento de día, grillos de
-- noche), crossfadeando en volumen a medida que Lighting.ClockTime cruza los
-- límites de dawn/dusk/nightStart (shared/DayNight.lua). El server
-- (DayNightService) es el único que mueve el reloj — Lighting replica solo,
-- así que esto solo lee el valor local, sin remotes.
--
-- Mismo espíritu que Sfx.lua: los ids de acá son placeholders sacados de
-- Toolbox > Audio, reemplazalos por lo que se elija para el mood final.
-- A diferencia de Sfx.lua (sonidos cortos, on-demand), estos dos suenan
-- SIEMPRE en loop; lo único que cambia es el volumen.

local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayNight = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayNight"))

local AmbientSfx = {}

local BEDS = {
	day = { id = "rbxassetid://131187945", volume = 0.35 }, -- viento + pájaros
	night = { id = "rbxassetid://7274920568", volume = 0.3 }, -- grillos + viento nocturno
}

-- Recalcular el crossfade cada frame es innecesario para algo que se mueve
-- tan lento (un ciclo completo dura minutos) — cada medio segundo alcanza y
-- sobra, y es gratis en términos de perf.
local UPDATE_INTERVAL = 0.5

local function makeBed(def, name)
	local sound = Instance.new("Sound")
	sound.Name = "Ambient_" .. name
	sound.SoundId = def.id
	sound.Looped = true
	sound.Volume = 0 -- el primer tick de Heartbeat lo corrige; arranca en silencio, no en golpe de audio
	sound.Parent = SoundService
	return sound
end

function AmbientSfx.start()
	local day = makeBed(BEDS.day, "Day")
	local night = makeBed(BEDS.night, "Night")
	day:Play()
	night:Play()

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < UPDATE_INTERVAL then
			return
		end
		accumulator = 0

		local dayWeight = DayNight.dayWeight(Lighting.ClockTime) -- 1 = full día, 0 = full noche
		day.Volume = BEDS.day.volume * dayWeight
		night.Volume = BEDS.night.volume * (1 - dayWeight)
	end)
end

return AmbientSfx
