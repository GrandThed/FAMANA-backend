-- Parties: up to Config.Party.maxSize players, in-memory only (not persisted,
-- same philosophy as Mana — a live session concept, not save data).
--
-- Membership is surfaced to every client through Player attributes
-- (PartyId / PartyLeader / PartyOpen), which replicate automatically — no
-- roster-push remote needed, matching how Class/Level/Mana already work.
-- Remotes are only used for the action verbs (invite/respond/leave/kick/
-- setOpen) and for toasts, which reuse the existing "Notify" remote.
--
-- A party is "open" (default) or "closed": open lets any member invite,
-- closed restricts inviting to the leader. Only the leader can kick or
-- toggle open/closed. Leaving/kicking down to a single remaining member
-- disbands the party entirely (a party of one isn't a party).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MAX_SIZE = Config.Party.maxSize
local INVITE_TIMEOUT = Config.Party.inviteTimeout

-- Colores por miembro, para que cualquier HUD (PartyMarkerUI, MarkerUI) pueda
-- diferenciar de un vistazo quién es quién en el grupo. Se exponen como el
-- attribute "PartyColor" — mismo mecanismo que PartyId/PartyLeader/PartyOpen,
-- replica solo, sin remote nuevo. 8 colores > MAX_SIZE (6) de sobra.
local COLOR_PALETTE = {
	Color3.fromRGB(224, 76, 76), -- rojo
	Color3.fromRGB(230, 156, 52), -- naranja
	Color3.fromRGB(224, 200, 64), -- amarillo
	Color3.fromRGB(72, 196, 184), -- cian
	Color3.fromRGB(94, 150, 230), -- azul
	Color3.fromRGB(172, 108, 224), -- violeta
	Color3.fromRGB(232, 108, 176), -- rosa
	Color3.fromRGB(140, 196, 84), -- lima
}

local PartyService = {}

-- [partyId] = { leader = userId, members = { [userId] = true }, open = bool, colors = { [userId] = paletteIndex } }
local parties = {}
-- [userId] = partyId
local playerParty = {}
-- [targetUserId] = { fromUserId, partyId, expires }. One pending invite per
-- target at a time; a newer invite simply replaces an older, unanswered one.
local pendingInvites = {}

local nextPartyId = 1

local notifyRemote -- RemoteEvent, resolved in start()
local partyInviteReceivedRemote -- RemoteEvent, resolved in start()

local function notify(player, message)
	if player and notifyRemote then
		notifyRemote:FireClient(player, message)
	end
end

local function memberCount(party)
	local n = 0
	for _ in pairs(party.members) do
		n += 1
	end
	return n
end

local function memberIds(party)
	local ids = {}
	for userId in pairs(party.members) do
		table.insert(ids, userId)
	end
	return ids
end

-- Le da a `userId` el primer color de la paleta que ningún otro miembro
-- ACTUAL de `party` esté usando (así dos compañeros nunca comparten color,
-- aunque uno se haya ido y vuelto a entrar con otro índice). Si la party
-- llegara a tener más miembros que colores (no debería, MAX_SIZE <= 8), cae
-- a un hash estable por userId — se repite algún color, pero no rompe nada.
local function assignColor(party, userId)
	local used = {}
	for _, index in pairs(party.colors) do
		used[index] = true
	end
	for index = 1, #COLOR_PALETTE do
		if not used[index] then
			party.colors[userId] = index
			return
		end
	end
	party.colors[userId] = (userId % #COLOR_PALETTE) + 1
end

-- Re-applies PartyId/PartyLeader/PartyOpen to every currently-online member so
-- clients never see a stale roster. Cheap: parties are at most 6 players.
local function refreshAttributes(partyId)
	local party = parties[partyId]
	if not party then
		return
	end
	for userId in pairs(party.members) do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			plr:SetAttribute("PartyId", partyId)
			plr:SetAttribute("PartyLeader", party.leader == userId)
			plr:SetAttribute("PartyOpen", party.open)
			local colorIndex = party.colors[userId]
			plr:SetAttribute("PartyColor", colorIndex and COLOR_PALETTE[colorIndex] or nil)
		end
	end
end

local function clearAttributes(player)
	player:SetAttribute("PartyId", nil)
	player:SetAttribute("PartyLeader", nil)
	player:SetAttribute("PartyOpen", nil)
	player:SetAttribute("PartyColor", nil)
end

local function broadcast(party, message, exceptUserId)
	for userId in pairs(party.members) do
		if userId ~= exceptUserId then
			notify(Players:GetPlayerByUserId(userId), message)
		end
	end
end

-- Removes `userId` from `party` and updates bookkeeping. If that leaves the
-- party with a single member, the whole party disbands (no solo parties).
-- If the leader left and others remain, promotes an arbitrary survivor.
-- Returns nothing; caller is responsible for any "you left"-style toast to
-- the removed player themselves (this only handles the party's reaction).
local function removeMember(partyId, userId)
	local party = parties[partyId]
	if not party or not party.members[userId] then
		return
	end

	local wasLeader = party.leader == userId
	party.members[userId] = nil
	party.colors[userId] = nil
	playerParty[userId] = nil

	local removedPlayer = Players:GetPlayerByUserId(userId)
	if removedPlayer then
		clearAttributes(removedPlayer)
	end

	local remaining = memberIds(party)

	if #remaining == 0 then
		parties[partyId] = nil
		return
	end

	if #remaining == 1 then
		-- Down to one: disband entirely rather than leave a "party of one".
		local lastId = remaining[1]
		playerParty[lastId] = nil
		parties[partyId] = nil
		local lastPlayer = Players:GetPlayerByUserId(lastId)
		if lastPlayer then
			clearAttributes(lastPlayer)
			notify(lastPlayer, "Your party disbanded (not enough members left).")
		end
		return
	end

	if wasLeader then
		party.leader = remaining[1]
		local newLeader = Players:GetPlayerByUserId(party.leader)
		broadcast(party, (newLeader and newLeader.Name or "A member") .. " is now the party leader.")
	end

	refreshAttributes(partyId)
end

function PartyService.getPartyId(player)
	return playerParty[player.UserId]
end

-- Color3 asignado a `player` dentro de su party actual, o nil si no está en
-- ninguna. Server-side no necesita esto (todo pasa por el attribute
-- PartyColor, que ya replica solo) pero queda expuesto por si algún otro
-- service lo necesita sin leer attributes.
function PartyService.getPartyColor(player)
	local partyId = playerParty[player.UserId]
	local party = partyId and parties[partyId]
	local index = party and party.colors[player.UserId]
	return index and COLOR_PALETTE[index] or nil
end

function PartyService.isLeader(player)
	local partyId = playerParty[player.UserId]
	local party = partyId and parties[partyId]
	return party ~= nil and party.leader == player.UserId
end

-- Whether `player` is currently allowed to send invites (no party yet always
-- counts, since inviting someone with no party creates one).
function PartyService.canInvite(player)
	local partyId = playerParty[player.UserId]
	if not partyId then
		return true
	end
	local party = parties[partyId]
	return party ~= nil and (party.open or party.leader == player.UserId)
end

-- Other online party members within `radius` studs of `position` (excludes
-- `player` itself). Used by EnemyService to share kill XP. Returns {} if
-- `player` isn't in a party.
function PartyService.getNearbyPartyMembers(player, position, radius)
	local partyId = playerParty[player.UserId]
	local party = partyId and parties[partyId]
	if not party then
		return {}
	end
	local nearby = {}
	for userId in pairs(party.members) do
		if userId ~= player.UserId then
			local plr = Players:GetPlayerByUserId(userId)
			local character = plr and plr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude <= radius then
				table.insert(nearby, plr)
			end
		end
	end
	return nearby
end

function PartyService.invite(inviter, target)
	if target == inviter then
		return false, "self"
	end
	if playerParty[target.UserId] then
		notify(inviter, target.Name .. " is already in a party.")
		return false, "target_in_party"
	end
	if not PartyService.canInvite(inviter) then
		notify(inviter, "Only the party leader can invite (this party is closed).")
		return false, "not_leader"
	end

	local partyId = playerParty[inviter.UserId]
	if partyId then
		local party = parties[partyId]
		if memberCount(party) >= MAX_SIZE then
			notify(inviter, "Your party is full (" .. MAX_SIZE .. "/" .. MAX_SIZE .. ").")
			return false, "party_full"
		end
	else
		-- Inviter has no party yet: form a new one, led by them.
		partyId = nextPartyId
		nextPartyId += 1
		parties[partyId] = { leader = inviter.UserId, members = { [inviter.UserId] = true }, open = true, colors = {} }
		playerParty[inviter.UserId] = partyId
		assignColor(parties[partyId], inviter.UserId)
		refreshAttributes(partyId)
	end

	pendingInvites[target.UserId] = {
		fromUserId = inviter.UserId,
		partyId = partyId,
		expires = os.clock() + INVITE_TIMEOUT,
	}

	local received = partyInviteReceivedRemote
	received:FireClient(target, {
		fromUserId = inviter.UserId,
		fromName = inviter.Name,
		timeout = INVITE_TIMEOUT,
	})
	notify(inviter, "Invite sent to " .. target.Name .. ".")

	task.delay(INVITE_TIMEOUT, function()
		local pending = pendingInvites[target.UserId]
		if pending and pending.fromUserId == inviter.UserId and pending.partyId == partyId then
			pendingInvites[target.UserId] = nil
		end
	end)

	return true
end

function PartyService.respond(target, fromUserId, accept)
	local pending = pendingInvites[target.UserId]
	if not pending or pending.fromUserId ~= fromUserId or pending.expires < os.clock() then
		pendingInvites[target.UserId] = nil
		notify(target, "That invite is no longer valid.")
		return
	end
	pendingInvites[target.UserId] = nil

	local party = parties[pending.partyId]
	local inviter = Players:GetPlayerByUserId(fromUserId)

	if not accept then
		notify(inviter, target.Name .. " declined the invite.")
		return
	end

	if not party then
		notify(target, "That party no longer exists.")
		return
	end
	if playerParty[target.UserId] then
		notify(target, "You're already in a party.")
		return
	end
	if memberCount(party) >= MAX_SIZE then
		notify(target, "That party is full.")
		notify(inviter, "Party is full (" .. MAX_SIZE .. "/" .. MAX_SIZE .. ").")
		return
	end

	party.members[target.UserId] = true
	playerParty[target.UserId] = pending.partyId
	assignColor(party, target.UserId)
	refreshAttributes(pending.partyId)
	broadcast(party, target.Name .. " joined the party.", target.UserId)
	notify(target, "You joined " .. (inviter and inviter.Name or "the") .. "'s party.")
end

function PartyService.leave(player)
	local partyId = playerParty[player.UserId]
	if not partyId then
		return
	end
	local party = parties[partyId]
	removeMember(partyId, player.UserId)
	if party then
		broadcast(party, player.Name .. " left the party.", player.UserId)
	end
end

function PartyService.kick(leader, target)
	local partyId = playerParty[leader.UserId]
	local party = partyId and parties[partyId]
	if not party or party.leader ~= leader.UserId then
		notify(leader, "Only the leader can remove members.")
		return
	end
	if target.UserId == leader.UserId or not party.members[target.UserId] then
		return
	end
	removeMember(partyId, target.UserId)
	notify(target, "You were removed from the party.")
	if parties[partyId] then
		broadcast(parties[partyId], target.Name .. " was removed from the party.", target.UserId)
	end
end

function PartyService.setOpen(leader, isOpen)
	local partyId = playerParty[leader.UserId]
	local party = partyId and parties[partyId]
	if not party or party.leader ~= leader.UserId then
		return
	end
	party.open = isOpen and true or false
	refreshAttributes(partyId)
	broadcast(party, "Party is now " .. (party.open and "open (anyone can invite)." or "closed (only the leader can invite)."), leader.UserId)
end

function PartyService.start()
	notifyRemote = Remotes.get("Notify")
	partyInviteReceivedRemote = Remotes.get("PartyInviteReceived")

	local invite = Remotes.get("PartyInvite")
	invite.OnServerEvent:Connect(function(player, targetUserId)
		local target = Players:GetPlayerByUserId(tonumber(targetUserId))
		if target then
			PartyService.invite(player, target)
		end
	end)

	local respond = Remotes.get("PartyRespond")
	respond.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local fromUserId = tonumber(payload.fromUserId)
		if fromUserId then
			PartyService.respond(player, fromUserId, payload.accept == true)
		end
	end)

	local leave = Remotes.get("PartyLeave")
	leave.OnServerEvent:Connect(function(player)
		PartyService.leave(player)
	end)

	local kick = Remotes.get("PartyKick")
	kick.OnServerEvent:Connect(function(player, targetUserId)
		local target = Players:GetPlayerByUserId(tonumber(targetUserId))
		if target then
			PartyService.kick(player, target)
		end
	end)

	local setOpen = Remotes.get("PartySetOpen")
	setOpen.OnServerEvent:Connect(function(player, isOpen)
		PartyService.setOpen(player, isOpen == true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingInvites[player.UserId] = nil
		PartyService.leave(player)
	end)
end

return PartyService