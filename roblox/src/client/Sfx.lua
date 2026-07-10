local SoundService = game:GetService("SoundService")

local Sfx = {}

local SOUNDS = {
	coin = { id = "rbxassetid://133570405319995", volume = 0.55 },
	xpDing = { id = "rbxassetid://98493415757122", volume = 0.4 },
	levelUp = { id = "rbxassetid://113596221936446", volume = 0.7 },
	uiClick = { id = "rbxassetid://6042053626", volume = 0.35 },
	itemPickup = { id = "rbxassetid://550210020", volume = 0.5 },
	equip = { id = "rbxassetid://133331985238497", volume = 0.3 },
	unequip = { id = "rbxassetid://125373488678088", volume = 1 },
	panelOpen = { id = "rbxassetid://134352981124286", volume = 0.2 },
	panelClose = { id = "rbxassetid://134352981124286", volume = 0.2 },
	swing = { id = "rbxassetid://138283030240531", volume = 0.45 }, -- herramientas (hacha/pico, styleName "chop")
	swingMelee = { id = "rbxassetid://135315310485417", volume = 0.45 }, -- espadas (styleName "slash")
	swingRanged = { id = "rbxassetid://123925235254965", volume = 0.5 }, -- arcos (styleName "draw") — placeholder
	swingMagic = { id = "rbxassetid://81276928984693", volume = 0.5 }, -- varitas/staffs (styleName "cast") — placeholder
	hit = { id = "rbxassetid://139520673393967", volume = 0.5 },
	critHit = { id = "rbxassetid://137392628136734", volume = 0.65 },
}

-- Cache de instancias reutilizables por nombre: para sonidos que pueden
-- pisarse (varios "+1 oro" seguidos) alcanza con Play() sobre una instancia
-- persistente en vez de crear/destruir un Sound por evento.
local pool = {}

local function ensure(name)
	local existing = pool[name]
	if existing then
		return existing
	end

	local def = SOUNDS[name]
	if not def then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.Parent = SoundService
	pool[name] = sound
	return sound
end

-- Reproduce un sonido registrado en SOUNDS. Si ya está sonando, lo reinicia
-- (PlaybackLoudness aparte, esto evita que un ding tape al siguiente).
function Sfx.play(name)
	local sound = ensure(name)
	if not sound then
		return
	end
	sound.TimePosition = 0
	sound:Play()
end

-- Igual que Sfx.play, pero con un piso de tiempo entre dos reproducciones
-- del MISMO nombre. Pensado para eventos que el server todavía no limita
-- (p. ej. golpes de arma sin cooldown real todavía — ver ToolService) y que
-- en la práctica pueden dispararse más rápido de lo que suena bien. Es un
-- parche solo de audio: el día que las armas tengan su cooldown real, esto
-- deja de hacer nada porque nunca vamos a pegarle al piso de tiempo.
local lastPlayed = {}

function Sfx.playThrottled(name, minGap)
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < (minGap or 0.08) then
		return
	end
	lastPlayed[name] = now
	Sfx.play(name)
end

return Sfx
