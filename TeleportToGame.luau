-- Connected Discord-GitHub | Discord: shark_9x | Roblox: Shark9xDEV
--!strict

local TeleportToGame = {}
-- Services and modules used to improve development and system functionality.
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Players = game:GetService("Players")
const TeleportService = game:GetService("TeleportService")
const ColectionService = game:GetService("CollectionService")
const NetFunction = require(ReplicatedStorage.shared.Networking.NetFunction)
const ByteTeleport = require(ReplicatedStorage.shared.Networking.ByteTeleport)
const ByteLever = require(ReplicatedStorage.shared.Networking.ByteLever)
const Teleporters = ColectionService:GetTagged("Teleporter")

type CharacterEntry = {
	character: Model,
	player: Player,
}

-- Arrays that use the player's UserId as the index.
-- playerCount uses the teleporter itself as the index,
-- allowing each teleporter to have its own player count.
-- teleportersArry and Characters use the player's UserId
-- as the index, allowing each player to reference their
-- teleporter, character, and player data.
local teleportersArry: { [number]: BasePart } = {}
local Characters: { [number]: CharacterEntry } = {}
local playerCount: { [BasePart]: number } = {}

-- Updates the player count UI for the teleporter
-- without repeating the same logic every time it is needed,
-- making future maintenance easier.
local function GetPlayerCountLabel(teleporter: BasePart): TextLabel?
	const billboardGui = teleporter:FindFirstChild("BillboardGui")
	const label = billboardGui and billboardGui:FindFirstChild("PlayersConts")

	if label and label:IsA("TextLabel") then
		return label
	end

	return nil
end

-- Gets the player's elevator creation UI
-- to avoid repeating the same validation multiple times.
-- This function does not replace the need for validation
-- when called, as it may return nil.
local function GetElevatorGui(player: Player): ScreenGui?
	const gui = player.PlayerGui:FindFirstChild("CreateElevatorGui")

	if gui and gui:IsA("ScreenGui") then
		return gui
	end

	return nil
end

-- Updates the teleporter UI without having to
-- rewrite the same code every time.
-- Simply call this function when needed.
local function LoadScoreboard(teleporter: BasePart): ()
	const label = GetPlayerCountLabel(teleporter)
	if not label then
		return
	end

	const attributePlayerCount = teleporter:GetAttribute("PlayersToBeTeleported")
	const maxPlayers = teleporter:GetAttribute("MaxPlayers")

	if type(attributePlayerCount) ~= "number" or type(maxPlayers) ~= "number" then
		return
	end

	label.Text = `{attributePlayerCount}/{maxPlayers}`
end

-- Validates whether the current player count
-- is greater than or equal to the maximum allowed amount.
local function PlayerCountValidation(teleporter: BasePart): boolean
	const attributePlayerCount = teleporter:GetAttribute("PlayersToBeTeleported")
	const playerCountMax = teleporter:GetAttribute("MaxPlayers")

	if type(attributePlayerCount) ~= "number" or type(playerCountMax) ~= "number" then
		return false
	end

	return playerCountMax > 0 and attributePlayerCount >= playerCountMax
end

-- Validates and adds a player to the teleporter count
-- when called, returning whether the operation succeeded.
local function AddNumberOfPlayers(teleporter: BasePart): boolean
	const currentCount = teleporter:GetAttribute("PlayersToBeTeleported")
	const maxPlayers = teleporter:GetAttribute("MaxPlayers")

	if type(currentCount) ~= "number" or type(maxPlayers) ~= "number" then
		return false
	end

	if maxPlayers > 0 and currentCount >= maxPlayers then
		return false
	end

	playerCount[teleporter] = currentCount + 1
	teleporter:SetAttribute("PlayersToBeTeleported", currentCount + 1)

	return true
end

-- Removes the player from Characters to prevent memory leaks,
-- removes them from the player count, and updates the new count.
local function PlayerRemoved(player: Player, teleporter: BasePart): ()
	if not Characters[player.UserId] then
		return
	end

	Characters[player.UserId] = nil
	playerCount[teleporter] = math.max((playerCount[teleporter] or 0) - 1, 0)
	teleporter:SetAttribute("PlayersToBeTeleported", playerCount[teleporter])
	LoadScoreboard(teleporter)
end

-- Clears connections and tables to prevent
-- memory leaks and improve game performance.
local function ClearConnections(player: Player): ()
	const teleporter = teleportersArry[player.UserId]

	if not teleporter then
		return
	end

	PlayerRemoved(player, teleporter)
	teleportersArry[player.UserId] = nil
end

-- Validates and teleports all players
-- currently inside a full teleporter.
-- Uses pcall to safely handle teleportation errors.
local function Teleport(player: Player, teleporterKey: BasePart): ()
	if not player or not Characters[player.UserId] then
		return
	end

	local players: { Player } = {}

	for userId, characterEntry in Characters do
		if teleportersArry[userId] == teleporterKey then
			table.insert(players, characterEntry.player)
		end
	end

	if #players == 0 then
		return
	end

	const success, err = pcall(function()
		TeleportService:TeleportAsync(71836649202628, players)
	end)

	if not success then
		warn("Teleport failed: " .. tostring(err))
		teleporterKey:SetAttribute("isTeleporting", false)
		return
	end

	for _, teleportedPlayer in players do
		teleportedPlayer:SetAttribute("teleporterOfPlayer", nil)
		ClearConnections(teleportedPlayer)
	end

	playerCount[teleporterKey] = 0

	teleporterKey:SetAttribute("PlayersToBeTeleported", 0)
	LoadScoreboard(teleporterKey)
	teleporterKey:SetAttribute("isTeleporting", false)
end

-- Sends a request to the client to play the teleport cutscene
-- and waits for a response before continuing with the
-- player teleportation.
local function CutsceneTeleport(player: Player, teleporterKey: BasePart): ()
	if not PlayerCountValidation(teleporterKey) then
		return
	end

	const Elevator = teleporterKey:FindFirstChild("Elevator")
	if not Elevator or not Elevator:IsA("BasePart") then
		return
	end

	const remotFunction = NetFunction.Create("CutsceneTeleport") :: RemoteFunction
	teleporterKey:SetAttribute("isTeleporting", true)

	const success, result = pcall(function()
		return remotFunction:InvokeClient(player, Elevator)
	end)

	if not success or not result then
		teleporterKey:SetAttribute("isTeleporting", false)
		return
	end

	Teleport(player, teleporterKey)
end

-- Called by the parent script that initializes all
-- dependencies, systems, and game modules.
-- This makes it easier to disable the system in case
-- of a bug or if the feature needs to be disabled.
function TeleportToGame:Start(): ()
	-- Gets all teleporters tagged with "Teleporter"
	-- and validates that each one is a BasePart.
	for _, teleporter in Teleporters do
		if not teleporter:IsA("BasePart") then
			continue
		end

		teleporter:SetAttribute("isTeleporting", false)

		-- Handles all functionality required by the teleporter
		-- when a new player attempts to enter.
		-- The player is registered in everything related
		-- to the teleporter.
		teleporter.Touched:Connect(function(hit)
			if teleporter:GetAttribute("isTeleporting") then
				return
			end

			const character: Instance? = hit.Parent

			if not character or not character:IsA("Model") then
				return
			end

			const player = Players:GetPlayerFromCharacter(character)

			if not player or player:GetAttribute("teleporterOfPlayer") then
				return
			end

			const humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

			if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
				return
			end

			if not AddNumberOfPlayers(teleporter) then
				return
			end

			player:SetAttribute("teleporterOfPlayer", true)
			teleportersArry[player.UserId] = teleporter

			const elevatorGui = GetElevatorGui(player)

			if elevatorGui and teleporter:GetAttribute("PlayersToBeTeleported") == 1 then
				elevatorGui.Enabled = true
			end
			
			Characters[player.UserId] = {
				character = character,
				player = player,
			}

			LoadScoreboard(teleporter)

			humanoidRootPart.CFrame = teleporter.CFrame

			CutsceneTeleport(player, teleporter)
		end)
	end

	-- Sets the number of players that can enter,
	-- chosen by the player who created the room.
	ByteTeleport.teleportCount.listen(function(data: { currentCount: number? }, player: Player?)
		if not data.currentCount or not player or data.currentCount > 10 or data.currentCount < 1 then
			return
		end

		const teleporterKey = teleportersArry[player.UserId]

		if not teleporterKey then
			return
		end

		const elevatorGui = GetElevatorGui(player)
		if elevatorGui then
			elevatorGui.Enabled = false
		end

		teleporterKey:SetAttribute("MaxPlayers", data.currentCount)
		LoadScoreboard(teleporterKey)

		CutsceneTeleport(player, teleporterKey)
	end)

	-- Removes the player who clicked the exit button
	-- and clears them from all arrays and information
	-- related to the teleporter they were inside.
	ByteLever.leverClick.listen(function(_, player)
		if not player then
			return
		end

		const character = player.Character or player.CharacterAdded:Wait()
		const humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

		if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
			return
		end

		const SpawnLocation = workspace:WaitForChild("SpawnLocation")
		if not SpawnLocation:IsA("BasePart") then
			return
		end

		humanoidRootPart.CFrame = SpawnLocation.CFrame

		const teleporterKey = teleportersArry[player.UserId]

		ClearConnections(player)

		if teleporterKey then
			teleporterKey:SetAttribute("PlayersToBeTeleported", playerCount[teleporterKey])

			if playerCount[teleporterKey] <= 1 then
				teleporterKey:SetAttribute("MaxPlayers", 1)
			end

			LoadScoreboard(teleporterKey)
		end

		player:SetAttribute("teleporterOfPlayer", nil)
	end)

	-- Updates the character stored in the Characters array
	-- whenever the player respawns.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if not Characters[player.UserId] then
				return
			end
			Characters[player.UserId].character = character
		end)
	end)

	-- Clears everything related to the player when they leave
	-- to prevent memory leaks and teleporters getting stuck
	-- due to player count inconsistencies.
	Players.PlayerRemoving:Connect(function(player: Player)
		ClearConnections(player)
	end)
end

return TeleportToGame
