local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local shootEvent = Instance.new("RemoteEvent")
shootEvent.Name = "ShootPlatform"
shootEvent.Parent = ReplicatedStorage

local chargeJumpEvent = Instance.new("RemoteEvent")
chargeJumpEvent.Name = "ChargeJump"
chargeJumpEvent.Parent = ReplicatedStorage

local MAX_PLATFORMS_PER_PLAYER = 8
local PLATFORM_SIZE = Vector3.new(6, 1, 6)
local MAX_SHOOT_DISTANCE = 300
local SHOOT_COOLDOWN = 0.15
local SHAFT_HEIGHT = 200
local JUMP_BOOST_MULTIPLIER = 5
local JUMP_BOOST_COUNT = 10
local BEACH_CENTER_X = 90

local platformQueues = {} -- [player] = { platform, platform, ... } oldest first
local lastShotTime = {} -- [player] = os.clock() of last shot
local jumpBoosts = {} -- [player] = { remaining }

local function setupJungleAtmosphere()
	Lighting.Ambient = Color3.fromRGB(55, 75, 45)
	Lighting.OutdoorAmbient = Color3.fromRGB(85, 105, 65)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 12.5
	Lighting.FogColor = Color3.fromRGB(140, 170, 120)
	Lighting.FogEnd = 900

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Haze = 1.6
	atmosphere.Color = Color3.fromRGB(150, 180, 130)
	atmosphere.Decay = Color3.fromRGB(70, 90, 60)
	atmosphere.Glare = 0.15
	atmosphere.Parent = Lighting
end

local function createGroundDecoration()
	for _ = 1, 14 do
		local isRock = math.random() > 0.5
		local decoration = Instance.new("Part")
		decoration.Shape = Enum.PartType.Ball
		decoration.Name = isRock and "Rock" or "Bush"
		local size = isRock and (1 + math.random() * 1.5) or (1.5 + math.random() * 1.5)
		decoration.Size = Vector3.new(size, size, size)

		local x = (math.random() - 0.5) * 34
		local z = (math.random() - 0.5) * 30 + 25
		decoration.CFrame = CFrame.new(x, size / 2, z)
		decoration.Anchored = true
		decoration.CanCollide = false
		decoration.Material = isRock and Enum.Material.Rock or Enum.Material.Grass
		decoration.Color = isRock and Color3.fromRGB(120, 120, 115) or Color3.fromRGB(40, 120, 45)
		decoration.Parent = Workspace
	end
end

local function createSpawnArea()
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(40, 1, 40)
	floor.Anchored = true
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(55, 120, 55)
	floor.CFrame = CFrame.new(0, 0, 20)
	floor.Parent = Workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Color = Color3.fromRGB(150, 110, 70)
	spawnLocation.CFrame = CFrame.new(0, 1, 30) * CFrame.Angles(0, math.pi, 0)
	spawnLocation.Parent = Workspace

	createGroundDecoration()
end

local function endJumpBoost(player)
	local boost = jumpBoosts[player]
	if not boost then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	jumpBoosts[player] = nil
	player:SetAttribute("JumpsRemaining", nil)
end

-- Grants JUMP_BOOST_COUNT charge-jumps. The built-in Jumping state is
-- disabled entirely so Roblox's default controller can't fire its own weak
-- jump on Space. The actual jump velocity is applied client-side (that
-- player owns physics for their own character); this just tracks the
-- remaining charge count and permission to use it.
local function applyJumpBoost(player, humanoid)
	endJumpBoost(player)

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local boost = {
		remaining = JUMP_BOOST_COUNT,
	}
	jumpBoosts[player] = boost
	player:SetAttribute("JumpsRemaining", boost.remaining)
end

local function performChargeJump(player)
	local boost = jumpBoosts[player]
	if not boost or boost.remaining <= 0 then
		return
	end

	boost.remaining -= 1
	if boost.remaining <= 0 then
		endJumpBoost(player)
	else
		player:SetAttribute("JumpsRemaining", boost.remaining)
	end
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

local TRUNK_CANOPY_COLORS = {
	Color3.fromRGB(34, 110, 40),
	Color3.fromRGB(45, 130, 50),
	Color3.fromRGB(28, 95, 35),
}

-- A climbable trunk (the actual shootable surface) plus a decorative,
-- non-collidable leafy canopy cluster near the top.
local function createTree(position, trunkHeight, trunkRadius)
	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(92, 64, 42)
	trunk.Parent = Workspace

	for _ = 1, 4 do
		local blob = Instance.new("Part")
		blob.Name = "TreeCanopy"
		blob.Shape = Enum.PartType.Ball
		local blobSize = trunkRadius * (5 + math.random() * 2)
		blob.Size = Vector3.new(blobSize, blobSize, blobSize)

		local offset = Vector3.new(
			(math.random() - 0.5) * trunkRadius * 4,
			trunkHeight - blobSize * 0.3,
			(math.random() - 0.5) * trunkRadius * 4
		)
		blob.CFrame = CFrame.new(position + offset)
		blob.Anchored = true
		blob.CanCollide = false
		blob.Material = Enum.Material.Grass
		blob.Color = TRUNK_CANOPY_COLORS[math.random(1, #TRUNK_CANOPY_COLORS)]
		blob.Parent = Workspace
	end

	return trunk
end

local function createJungleClimbArea()
	local treeHeight = SHAFT_HEIGHT
	local treeRadius = 2.5
	local treeSpacingZ = 10
	local numTreesPerSide = 5
	local sideX = 8

	for i = 1, numTreesPerSide do
		local z = (i - 1) * treeSpacingZ - ((numTreesPerSide - 1) * treeSpacingZ) / 2
		createTree(Vector3.new(-sideX, 0, z), treeHeight, treeRadius)
		createTree(Vector3.new(sideX, 0, z), treeHeight, treeRadius)
	end

	local cliff = Instance.new("Part")
	cliff.Name = "JungleCliff"
	cliff.Size = Vector3.new(16, SHAFT_HEIGHT, 2)
	cliff.Anchored = true
	cliff.Material = Enum.Material.Rock
	cliff.Color = Color3.fromRGB(90, 100, 70)
	cliff.CFrame = CFrame.new(0, SHAFT_HEIGHT / 2, -25)
	cliff.Parent = Workspace

	local goal = Instance.new("Part")
	goal.Name = "Goal"
	goal.Size = Vector3.new(12, 1, 16)
	goal.Anchored = true
	goal.Material = Enum.Material.Neon
	goal.Color = Color3.fromRGB(0, 255, 120)
	goal.CFrame = CFrame.new(0, SHAFT_HEIGHT + 1, 0)
	goal.Parent = Workspace
end

local function createPalmTree(position)
	local trunkHeight = 14 + math.random() * 4
	local trunk = Instance.new("Part")
	trunk.Name = "PalmTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, 1.4, 1.4)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(96))
	trunk.Anchored = true
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(150, 120, 80)
	trunk.Parent = Workspace

	local topPosition = position + Vector3.new(0, trunkHeight, 0)
	for i = 1, 6 do
		local frond = Instance.new("Part")
		frond.Name = "PalmFrond"
		frond.Size = Vector3.new(0.4, 0.3, 7)
		frond.Anchored = true
		frond.CanCollide = false
		frond.Material = Enum.Material.Grass
		frond.Color = Color3.fromRGB(60, 150, 70)

		local angle = (i / 6) * math.pi * 2
		frond.CFrame = CFrame.new(topPosition) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(20), 0, 0) * CFrame.new(0, 0, -3.5)
		frond.Parent = Workspace
	end
end

local function createRockPillar(position, height, radius)
	local pillar = Instance.new("Part")
	pillar.Name = "RockPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(height, radius * 2, radius * 2)
	pillar.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Anchored = true
	pillar.Material = Enum.Material.Sandstone
	pillar.Color = Color3.fromRGB(190, 150, 100)
	pillar.Parent = Workspace
	return pillar
end

local function createWaterfallOverlay(position, height, width)
	local waterfall = Instance.new("Part")
	waterfall.Name = "Waterfall"
	waterfall.Size = Vector3.new(width, height, 0.4)
	waterfall.Anchored = true
	waterfall.CanCollide = false
	waterfall.CanQuery = false
	waterfall.Material = Enum.Material.Glass
	waterfall.Color = Color3.fromRGB(120, 190, 220)
	waterfall.Transparency = 0.35
	waterfall.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0))
	waterfall.Parent = Workspace
	return waterfall
end

local function createBeachSpawnArea()
	local floor = Instance.new("Part")
	floor.Name = "SandFloor"
	floor.Size = Vector3.new(40, 1, 40)
	floor.Anchored = true
	floor.Material = Enum.Material.Sand
	floor.Color = Color3.fromRGB(230, 205, 150)
	floor.CFrame = CFrame.new(BEACH_CENTER_X, 0, 20)
	floor.Parent = Workspace

	local ocean = Instance.new("Part")
	ocean.Name = "Ocean"
	ocean.Size = Vector3.new(60, 1, 30)
	ocean.Anchored = true
	ocean.CanCollide = false
	ocean.Material = Enum.Material.Glass
	ocean.Color = Color3.fromRGB(40, 130, 180)
	ocean.Transparency = 0.2
	ocean.CFrame = CFrame.new(BEACH_CENTER_X, 0.5, 55)
	ocean.Parent = Workspace

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "BeachSpawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.Wood
	spawnLocation.Color = Color3.fromRGB(180, 150, 100)
	spawnLocation.CFrame = CFrame.new(BEACH_CENTER_X, 1, 30) * CFrame.Angles(0, math.pi, 0)
	spawnLocation.Parent = Workspace

	for _ = 1, 6 do
		local x = BEACH_CENTER_X + (math.random() - 0.5) * 30
		local z = (math.random() - 0.5) * 30 + 25
		createPalmTree(Vector3.new(x, 0, z))
	end

	for _ = 1, 10 do
		local shell = Instance.new("Part")
		shell.Shape = Enum.PartType.Ball
		shell.Name = "Shell"
		local size = 0.8 + math.random() * 0.8
		shell.Size = Vector3.new(size, size * 0.5, size)
		local x = BEACH_CENTER_X + (math.random() - 0.5) * 32
		local z = (math.random() - 0.5) * 30 + 25
		shell.CFrame = CFrame.new(x, size / 4, z)
		shell.Anchored = true
		shell.CanCollide = false
		shell.Material = Enum.Material.SmoothPlastic
		shell.Color = Color3.fromRGB(240, 230, 210)
		shell.Parent = Workspace
	end
end

local function createBeachClimbArea()
	local pillarHeight = SHAFT_HEIGHT
	local pillarRadius = 3
	local spacingZ = 10
	local numPerSide = 5
	local sideX = 9

	for i = 1, numPerSide do
		local z = (i - 1) * spacingZ - ((numPerSide - 1) * spacingZ) / 2
		createRockPillar(Vector3.new(BEACH_CENTER_X - sideX, 0, z), pillarHeight, pillarRadius)
		createRockPillar(Vector3.new(BEACH_CENTER_X + sideX, 0, z), pillarHeight, pillarRadius)
	end

	local backCliff = Instance.new("Part")
	backCliff.Name = "BeachCliff"
	backCliff.Size = Vector3.new(20, pillarHeight, 2)
	backCliff.Anchored = true
	backCliff.Material = Enum.Material.Sandstone
	backCliff.Color = Color3.fromRGB(200, 165, 115)
	backCliff.CFrame = CFrame.new(BEACH_CENTER_X, pillarHeight / 2, -25)
	backCliff.Parent = Workspace

	for i = 1, 3 do
		local waterfallX = BEACH_CENTER_X + (i - 2) * 6
		createWaterfallOverlay(Vector3.new(waterfallX, 0, -24), pillarHeight, 3)
	end

	local goal = Instance.new("Part")
	goal.Name = "BeachGoal"
	goal.Size = Vector3.new(12, 1, 16)
	goal.Anchored = true
	goal.Material = Enum.Material.Neon
	goal.Color = Color3.fromRGB(255, 220, 80)
	goal.CFrame = CFrame.new(BEACH_CENTER_X, pillarHeight + 1, 0)
	goal.Parent = Workspace
end

setupJungleAtmosphere()
createSpawnArea()
createJungleClimbArea()
createJumpSpring(Vector3.new(0, 1, 18))

createBeachSpawnArea()
createBeachClimbArea()
createJumpSpring(Vector3.new(BEACH_CENTER_X, 1, 18))

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

chargeJumpEvent.OnServerEvent:Connect(function(player)
	performChargeJump(player)
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
