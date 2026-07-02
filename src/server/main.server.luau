local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shootEvent = Instance.new("RemoteEvent")
shootEvent.Name = "ShootPlatform"
shootEvent.Parent = ReplicatedStorage

local MAX_PLATFORMS_PER_PLAYER = 8
local PLATFORM_SIZE = Vector3.new(6, 1, 6)
local MAX_SHOOT_DISTANCE = 300
local SHOOT_COOLDOWN = 0.15
local SHAFT_HEIGHT = 200
local JUMP_BOOST_MULTIPLIER = 15
local JUMP_BOOST_COUNT = 10

local platformQueues = {} -- [player] = { platform, platform, ... } oldest first
local lastShotTime = {} -- [player] = os.clock() of last shot
local jumpBoosts = {} -- [player] = { remaining, defaultJumpPower, connection }

local function createSpawnArea()
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(40, 1, 40)
	floor.Anchored = true
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(90, 160, 90)
	floor.CFrame = CFrame.new(0, 0, 20)
	floor.Parent = Workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.SmoothPlastic
	spawnLocation.Color = Color3.fromRGB(220, 220, 220)
	spawnLocation.CFrame = CFrame.new(0, 1, 30) * CFrame.Angles(0, math.pi, 0)
	spawnLocation.Parent = Workspace
end

local function endJumpBoost(player)
	local boost = jumpBoosts[player]
	if not boost then
		return
	end

	if boost.connection then
		boost.connection:Disconnect()
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = boost.defaultJumpPower
		humanoid.UseJumpPower = boost.defaultUseJumpPower
	end

	jumpBoosts[player] = nil
	player:SetAttribute("JumpsRemaining", nil)
end

local function applyJumpBoost(player, humanoid)
	endJumpBoost(player)

	-- Force the legacy JumpPower system on, since UseJumpPower may be false
	-- (JumpHeight-based) by default, in which case JumpPower has no effect.
	local defaultUseJumpPower = humanoid.UseJumpPower
	humanoid.UseJumpPower = true

	local defaultJumpPower = humanoid.JumpPower
	humanoid.JumpPower = defaultJumpPower * JUMP_BOOST_MULTIPLIER

	local boost = {
		remaining = JUMP_BOOST_COUNT,
		defaultJumpPower = defaultJumpPower,
		defaultUseJumpPower = defaultUseJumpPower,
	}
	jumpBoosts[player] = boost
	player:SetAttribute("JumpsRemaining", boost.remaining)

	boost.connection = humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Jumping then
			return
		end

		boost.remaining -= 1
		if boost.remaining <= 0 then
			endJumpBoost(player)
		else
			player:SetAttribute("JumpsRemaining", boost.remaining)
		end
	end)
end

local function createJumpSpring(position)
	local pad = Instance.new("Part")
	pad.Name = "JumpSpring"
	pad.Size = Vector3.new(6, 1, 6)
	pad.Anchored = true
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 140, 0)
	pad.CFrame = CFrame.new(position)
	pad.Parent = Workspace

	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not humanoid or not player then
			return
		end

		applyJumpBoost(player, humanoid)
	end)

	return pad
end

local function createClimbShaft()
	local wallSize = Vector3.new(2, SHAFT_HEIGHT, 40)

	local leftWall = Instance.new("Part")
	leftWall.Name = "ShaftWallLeft"
	leftWall.Size = wallSize
	leftWall.Anchored = true
	leftWall.Material = Enum.Material.Concrete
	leftWall.Color = Color3.fromRGB(120, 120, 130)
	leftWall.CFrame = CFrame.new(-7, wallSize.Y / 2, 0)
	leftWall.Parent = Workspace

	local rightWall = leftWall:Clone()
	rightWall.Name = "ShaftWallRight"
	rightWall.CFrame = CFrame.new(7, wallSize.Y / 2, 0)
	rightWall.Parent = Workspace

	local backWall = Instance.new("Part")
	backWall.Name = "ShaftWallBack"
	backWall.Size = Vector3.new(16, SHAFT_HEIGHT, 2)
	backWall.Anchored = true
	backWall.Material = Enum.Material.Concrete
	backWall.Color = Color3.fromRGB(100, 100, 110)
	backWall.CFrame = CFrame.new(0, SHAFT_HEIGHT / 2, -20)
	backWall.Parent = Workspace

	local goal = Instance.new("Part")
	goal.Name = "Goal"
	goal.Size = Vector3.new(12, 1, 16)
	goal.Anchored = true
	goal.Material = Enum.Material.Neon
	goal.Color = Color3.fromRGB(0, 255, 120)
	goal.CFrame = CFrame.new(0, SHAFT_HEIGHT + 1, 0)
	goal.Parent = Workspace
end

createSpawnArea()
createClimbShaft()
createJumpSpring(Vector3.new(0, 1, 18))

local function removeOldestPlatform(player)
	local queue = platformQueues[player]
	if not queue or #queue == 0 then
		return
	end

	local oldest = table.remove(queue, 1)
	if oldest then
		oldest:Destroy()
	end
end

local function shootPlatform(player, origin, direction)
	local now = os.clock()
	if lastShotTime[player] and now - lastShotTime[player] < SHOOT_COOLDOWN then
		return
	end
	lastShotTime[player] = now

	local character = player.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}

	local result = Workspace:Raycast(origin, direction.Unit * MAX_SHOOT_DISTANCE, params)
	if not result then
		return
	end

	local platformPosition = result.Position + result.Normal * (PLATFORM_SIZE.Y / 2 + 0.2)

	local platform = Instance.new("Part")
	platform.Name = "GunPlatform"
	platform.Size = PLATFORM_SIZE
	platform.Anchored = true
	platform.CanCollide = true
	platform.Material = Enum.Material.Neon
	platform.Color = Color3.fromRGB(0, 200, 255)
	platform.CFrame = CFrame.new(platformPosition)
	platform.Parent = Workspace

	local queue = platformQueues[player]
	if not queue then
		queue = {}
		platformQueues[player] = queue
	end

	table.insert(queue, platform)

	if #queue > MAX_PLATFORMS_PER_PLAYER then
		removeOldestPlatform(player)
	end
end

shootEvent.OnServerEvent:Connect(function(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end

	shootPlatform(player, origin, direction)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		endJumpBoost(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local queue = platformQueues[player]
	if queue then
		for _, platform in queue do
			platform:Destroy()
		end
	end

	platformQueues[player] = nil
	lastShotTime[player] = nil
	endJumpBoost(player)
end)
