-- Guild Headquarters Plots Service.
-- Manages 100% peaceful Village Guild Plots ("parcelas_gremio") where guilds
-- establish their official Headquarters (HQ), display their Guild Banner, and
-- place the Guild Research Table ("mesa_investigacion_gremio").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ArtKit = require(Shared:WaitForChild("ArtKit"))
local PlayerService = require(script.Parent.PlayerService)
local GuildService = require(script.Parent.GuildService)

local GuildPlotService = {}

-- Defined Village Plots in the safe zone town (48x48 studs = 4x4 12-stud modular grid)
GuildPlotService.PLOTS = {
	plot_center_north = { id = "plot_center_north", name = "Parcela del Norte", position = Vector3.new(0, 0, -100), size = Vector3.new(48, 1, 48), costGold = 500 },
	plot_center_east = { id = "plot_center_east", name = "Parcela del Este", position = Vector3.new(100, 0, 0), size = Vector3.new(48, 1, 48), costGold = 500 },
	plot_center_south = { id = "plot_center_south", name = "Parcela del Sur", position = Vector3.new(0, 0, 100), size = Vector3.new(48, 1, 48), costGold = 500 },
	plot_center_west = { id = "plot_center_west", name = "Parcela del Oeste", position = Vector3.new(-100, 0, 0), size = Vector3.new(48, 1, 48), costGold = 500 },
}

-- [plotId] = { guildId, guildName, guildTag, bannerModel, signModel }
local claimedPlots = {}
local plotSignModels = {}

local function notify(player, message)
	Remotes.get("Notify"):FireClient(player, message)
end

function GuildPlotService.getPlotForGuild(guildId)
	if not guildId then
		return nil
	end
	for plotId, plotInfo in pairs(claimedPlots) do
		if plotInfo.guildId == guildId then
			return plotInfo
		end
	end
	return nil
end

function GuildPlotService.isPositionInGuildHQ(position, guildId)
	local plotInfo = GuildPlotService.getPlotForGuild(guildId)
	if not plotInfo then
		return false
	end
	local def = GuildPlotService.PLOTS[plotInfo.plotId]
	if not def then
		return false
	end
	local halfX = def.size.X / 2
	local halfZ = def.size.Z / 2
	return math.abs(position.X - def.position.X) <= halfX and math.abs(position.Z - def.position.Z) <= halfZ
end

function GuildPlotService.claimPlot(player, plotId)
	local guildId = player:GetAttribute("GuildId")
	local guildName = player:GetAttribute("GuildName") or "Gremio"
	local isLeader = player:GetAttribute("GuildLeader") == true

	if not guildId then
		notify(player, "Debes pertenecer a un gremio para reclamar una sede (usa /testgremio si estás probando).")
		return false
	end
	if not isLeader then
		notify(player, "Solo el Líder del gremio puede reclamar una parcela de sede.")
		return false
	end

	local plotDef = GuildPlotService.PLOTS[plotId]
	if not plotDef then
		notify(player, "Parcela no válida.")
		return false
	end

	if claimedPlots[plotId] then
		notify(player, "Esta parcela ya pertenece a otro gremio.")
		return false
	end

	if GuildPlotService.getPlotForGuild(guildId) then
		notify(player, "Tu gremio ya posee una sede reclamada.")
		return false
	end

	if not PlayerService.spendGold(player, plotDef.costGold) then
		notify(player, string.format("Necesitas %d de Oro para reclamar esta parcela.", plotDef.costGold))
		return false
	end

	-- Claim successful! Spawn Guild Banner
	local banner = Instance.new("Model")
	banner.Name = "GuildBanner_" .. guildId
	local pole = ArtKit.part("trunkDark")
	pole.Name = "Pole"
	pole.Size = Vector3.new(0.8, 8, 0.8)
	pole.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 4, 0))
	pole.Anchored = true
	pole.Parent = banner

	local flag = ArtKit.part("ruby")
	flag.Name = "Flag"
	flag.Size = Vector3.new(3, 2, 0.2)
	flag.CFrame = CFrame.new(plotDef.position + Vector3.new(1.8, 6, 0))
	flag.Anchored = true
	flag.Parent = banner

	banner.Parent = Workspace

	claimedPlots[plotId] = {
		plotId = plotId,
		guildId = guildId,
		guildName = guildName,
		guildTag = player:GetAttribute("GuildTag") or "GREMIO",
		bannerModel = banner,
	}

	-- Update sign GUI if present
	local sign = plotSignModels[plotId]
	if sign then
		local billboard = sign:FindFirstChildWhichIsA("BillboardGui", true)
		local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = string.format("🚩 Sede de %s", guildName)
			label.TextColor3 = Color3.fromRGB(255, 215, 0)
		end
	end

	notify(player, string.format("¡La %s ahora es la Sede Oficial de %s!", plotDef.name, guildName))
	return true
end

-- Builds physical 3D signposts for all plots
local function spawnPlotSigns()
	local folder = Workspace:FindFirstChild("GuildPlotSigns") or Instance.new("Folder", Workspace)
	folder.Name = "GuildPlotSigns"

	for plotId, plotDef in pairs(GuildPlotService.PLOTS) do
		local signModel = Instance.new("Model")
		signModel.Name = "PlotSign_" .. plotId

		local post = ArtKit.part("trunkDark")
		post.Name = "Post"
		post.Size = Vector3.new(0.6, 5, 0.6)
		post.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 2.5, 0))
		post.Anchored = true
		post.Parent = signModel

		local board = ArtKit.part("trunk")
		board.Name = "Board"
		board.Size = Vector3.new(3.5, 1.8, 0.3)
		board.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 4.2, 0))
		board.Anchored = true
		board.Parent = signModel
		signModel.PrimaryPart = board

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Reclamar Sede de Gremio"
		prompt.ObjectText = plotDef.name .. " (500 Oro)"
		prompt.HoldDuration = 0.15
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = board

		prompt.Triggered:Connect(function(triggeringPlayer)
			GuildPlotService.claimPlot(triggeringPlayer, plotId)
		end)

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 220, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = board

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 0.4
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Text = string.format("🏡 %s\n(Disponible - 500 Oro)", plotDef.name)
		label.TextScaled = true
		label.Font = Enum.Font.SourceSansBold
		label.Parent = billboard

		-- Draw visual 30x30 perimeter borders & ground pad
		local halfX, halfZ = plotDef.size.X / 2, plotDef.size.Z / 2
		local borderThick = 0.6

		local pad = Instance.new("Part")
		pad.Name = "PlotPad"
		pad.Size = Vector3.new(plotDef.size.X, 0.05, plotDef.size.Z)
		pad.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 0.02, 0))
		pad.Color = Color3.fromRGB(0, 180, 255)
		pad.Material = Enum.Material.SmoothPlastic
		pad.Transparency = 0.92
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanQuery = false
		pad.Parent = signModel

		local edgeN = ArtKit.part("stoneDark")
		edgeN.Size = Vector3.new(plotDef.size.X, 0.3, borderThick)
		edgeN.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 0.15, -halfZ))
		edgeN.Parent = signModel

		local edgeS = ArtKit.part("stoneDark")
		edgeS.Size = Vector3.new(plotDef.size.X, 0.3, borderThick)
		edgeS.CFrame = CFrame.new(plotDef.position + Vector3.new(0, 0.15, halfZ))
		edgeS.Parent = signModel

		local edgeE = ArtKit.part("stoneDark")
		edgeE.Size = Vector3.new(borderThick, 0.3, plotDef.size.Z)
		edgeE.CFrame = CFrame.new(plotDef.position + Vector3.new(halfX, 0.15, 0))
		edgeE.Parent = signModel

		local edgeW = ArtKit.part("stoneDark")
		edgeW.Size = Vector3.new(borderThick, 0.3, plotDef.size.Z)
		edgeW.CFrame = CFrame.new(plotDef.position + Vector3.new(-halfX, 0.15, 0))
		edgeW.Parent = signModel

		local corners = {
			Vector3.new(-halfX, 1, -halfZ),
			Vector3.new(halfX, 1, -halfZ),
			Vector3.new(-halfX, 1, halfZ),
			Vector3.new(halfX, 1, halfZ),
		}
		for _, cOffset in ipairs(corners) do
			local postCorner = ArtKit.part("gold")
			postCorner.Material = Enum.Material.Neon
			postCorner.Size = Vector3.new(1.2, 2, 1.2)
			postCorner.CFrame = CFrame.new(plotDef.position + cOffset)
			postCorner.Parent = signModel
		end

		signModel.Parent = folder
		plotSignModels[plotId] = signModel
	end
end

-- Command /testgremio for rapid developer testing
local function setupDevTestCommand(player)
	player.Chatted:Connect(function(msg)
		local cmd = msg:lower():gsub("^%s+", "")
		if cmd == "/testgremio" or cmd == "/gremio" or cmd == "/testplot" then
			-- Assign Test Guild attributes
			player:SetAttribute("GuildId", "guild_test_alfa")
			player:SetAttribute("GuildName", "Gremio Alfa")
			player:SetAttribute("GuildTag", "ALFA")
			player:SetAttribute("GuildLeader", true)

			-- Grant test gold & materials
			PlayerService.addGold(player, 1000)
			PlayerService.addItem(player, "wood", 100, true)
			PlayerService.addItem(player, "iron_ingot", 20, true)
			PlayerService.addItem(player, "plano_construccion", 1, true)
			PlayerService.addItem(player, "mesa_investigacion_gremio", 1, true)
			PlayerService.addItem(player, "silla_campamento", 2, true)

			-- Teleport to northern plot
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = CFrame.new(GuildPlotService.PLOTS.plot_center_north.position + Vector3.new(0, 4, 8))
			end

			notify(
				player,
				"✨ MODO TEST ACTIVADO: 1000 Oro, 100 Madera, Plano de Construcción y Gremio Alfa asignados. ¡Teletransportado a la Parcela del Norte!"
			)
		end
	end)
end

function GuildPlotService.start()
	spawnPlotSigns()

	Players.PlayerAdded:Connect(setupDevTestCommand)
	for _, p in ipairs(Players:GetPlayers()) do
		setupDevTestCommand(p)
	end

	local claimRemote = Remotes.getFunction("ClaimGuildPlot")
	local getPlotsRemote = Remotes.getFunction("GetGuildPlots")

	getPlotsRemote.OnServerInvoke = function(player)
		local list = {}
		for id, def in pairs(GuildPlotService.PLOTS) do
			local claimed = claimedPlots[id]
			table.insert(list, {
				id = id,
				name = def.name,
				position = def.position,
				costGold = def.costGold,
				claimed = claimed ~= nil,
				guildName = claimed and claimed.guildName or nil,
				guildTag = claimed and claimed.guildTag or nil,
			})
		end
		return list
	end

	claimRemote.OnServerInvoke = function(player, plotId)
		return GuildPlotService.claimPlot(player, plotId)
	end
end

return GuildPlotService
