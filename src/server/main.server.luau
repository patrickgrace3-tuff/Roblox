local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local shootEvent = Instance.new("RemoteEvent")
shootEvent.Name = "ShootPlatform"
shootEvent.Parent = ReplicatedStorage

local chargeJumpEvent = Instance.new("RemoteEvent")
chargeJumpEvent.Name = "ChargeJump"
chargeJumpEvent.Parent = ReplicatedStorage

local toggleFlightEvent = Instance.new("RemoteEvent")
toggleFlightEvent.Name = "ToggleFlight"
toggleFlightEvent.Parent = ReplicatedStorage

local toggleAutoSwingEvent = Instance.new("RemoteEvent")
toggleAutoSwingEvent.Name = "ToggleAutoSwing"
toggleAutoSwingEvent.Parent = ReplicatedStorage

local activateShieldEvent = Instance.new("RemoteEvent")
activateShieldEvent.Name = "ActivateShield"
activateShieldEvent.Parent = ReplicatedStorage

local shootArrowEvent = Instance.new("RemoteEvent")
shootArrowEvent.Name = "ShootArrow"
shootArrowEvent.Parent = ReplicatedStorage

local MAX_PLATFORMS_PER_PLAYER = 8
local PLATFORM_SIZE = Vector3.new(6, 1, 6)
local MAX_SHOOT_DISTANCE = 300
local SHOOT_COOLDOWN = 0.15
local SHAFT_HEIGHT = 200
local JUMP_BOOST_MULTIPLIER = 5
local JUMP_BOOST_COUNT = 10
local BEACH_CENTER_X = 90
local DEFAULT_WALK_SPEED = 16
local FLY_WALK_SPEED = 50
local DUNGEON_CENTER_X = 180

local MOB_HEALTH = 30
local MOB_DAMAGE = 8
local MOB_SPEED = 12
local MOB_DETECT_RANGE = 60
local MOB_ATTACK_RANGE = 4
local MOB_ATTACK_COOLDOWN = 1.2

local BOSS_HEALTH = 150
local BOSS_DAMAGE = 20
local BOSS_SPEED = 12
local BOSS_ATTACK_RANGE = 6

local SWORD_DAMAGE = 15
local SWORD_RANGE = 7
local AUTO_SWING_INTERVAL = 0.6
local SHIELD_DURATION = 3
local BOW_DAMAGE = 12
local BOW_RANGE = 200

local platformQueues = {} -- [player] = { platform, platform, ... } oldest first
local lastShotTime = {} -- [player] = os.clock() of last shot
local jumpBoosts = {} -- [player] = { remaining }
local flyingPlayers = {} -- [player] = true while actively flying
local mobs = {} -- [mobModel] = { health, maxHealth, damage, speed, attackRange, detectRange, attackCooldown, lastAttackTime, isBoss }
local autoSwingPlayers = {} -- [player] = os.clock() of last auto-swing
local shieldExpiry = {} -- [player] = os.clock() the shield buff ends

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

local function attachCarpetVisual(character)
	if character:FindFirstChild("MagicCarpetVisual") then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local carpet = Instance.new("Part")
	carpet.Name = "MagicCarpetVisual"
	carpet.Size = Vector3.new(6, 0.4, 4)
	carpet.Material = Enum.Material.Fabric
	carpet.Color = Color3.fromRGB(120, 40, 160)
	carpet.CanCollide = false
	carpet.Massless = true
	carpet.CFrame = rootPart.CFrame * CFrame.new(0, -3, 0)
	carpet.Parent = character

	local trim = Instance.new("Part")
	trim.Name = "MagicCarpetTrim"
	trim.Size = Vector3.new(6.2, 0.1, 4.2)
	trim.Material = Enum.Material.Neon
	trim.Color = Color3.fromRGB(255, 215, 0)
	trim.CanCollide = false
	trim.Massless = true
	trim.CFrame = carpet.CFrame * CFrame.new(0, 0.25, 0)
	trim.Parent = character

	local carpetWeld = Instance.new("WeldConstraint")
	carpetWeld.Part0 = rootPart
	carpetWeld.Part1 = carpet
	carpetWeld.Parent = carpet

	local trimWeld = Instance.new("WeldConstraint")
	trimWeld.Part0 = rootPart
	trimWeld.Part1 = trim
	trimWeld.Parent = trim
end

local function detachCarpetVisual(character)
	local carpet = character:FindFirstChild("MagicCarpetVisual")
	if carpet then
		carpet:Destroy()
	end

	local trim = character:FindFirstChild("MagicCarpetTrim")
	if trim then
		trim:Destroy()
	end
end

local function setFlying(player, flying)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end

	if flying then
		flyingPlayers[player] = true
		attachCarpetVisual(character)
		humanoid.WalkSpeed = FLY_WALK_SPEED
	else
		flyingPlayers[player] = nil
		detachCarpetVisual(character)
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end

	player:SetAttribute("IsFlying", flying or nil)
end

local function createMagicCarpetPickup(position)
	local pad = Instance.new("Part")
	pad.Name = "MagicCarpetPickup"
	pad.Size = Vector3.new(6, 0.4, 4)
	pad.Anchored = true
	pad.Material = Enum.Material.Fabric
	pad.Color = Color3.fromRGB(120, 40, 160)
	pad.CFrame = CFrame.new(position)
	pad.Parent = Workspace

	pad.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		player:SetAttribute("HasCarpet", true)
	end)

	return pad
end

local function findNearestPlayer(position, maxDistance)
	local nearestPlayer, nearestDistance = nil, maxDistance

	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if rootPart and humanoid and humanoid.Health > 0 then
			local distance = (rootPart.Position - position).Magnitude
			if distance < nearestDistance then
				nearestPlayer = plr
				nearestDistance = distance
			end
		end
	end

	return nearestPlayer, nearestDistance
end

local function damagePlayer(player, amount)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local expiry = shieldExpiry[player]
	if expiry and os.clock() < expiry then
		return
	end

	humanoid:TakeDamage(amount)
end

local function createVictoryPedestal(position)
	local pedestal = Instance.new("Part")
	pedestal.Name = "VictoryPedestal"
	pedestal.Size = Vector3.new(8, 1, 8)
	pedestal.Anchored = true
	pedestal.Material = Enum.Material.Neon
	pedestal.Color = Color3.fromRGB(255, 215, 0)
	pedestal.CFrame = CFrame.new(position.X, 0.5, position.Z)
	pedestal.Parent = Workspace
end

local function damageMob(model, amount)
	local data = mobs[model]
	if not data then
		return
	end

	data.health = math.max(data.health - amount, 0)

	if data.health <= 0 then
		mobs[model] = nil
		local position = model.PrimaryPart and model.PrimaryPart.Position or Vector3.new()
		local isBoss = data.isBoss
		model:Destroy()

		if isBoss then
			createVictoryPedestal(position)
		end
	elseif data.healthBarFill then
		data.healthBarFill.Size = UDim2.new(data.health / data.maxHealth, 0, 1, 0)
	end
end

-- Mobs are Anchored so they're simple to move via CFrame each tick (no
-- physics/collision fighting), and never fall or get stuck.
local function createMob(position, isBoss)
	local model = Instance.new("Model")
	model.Name = isBoss and "AngryChefBoss" or "Mob"

	local bodySize = isBoss and Vector3.new(6, 9, 4) or Vector3.new(3, 5, 2)
	local bodyColor = isBoss and Color3.fromRGB(210, 70, 70) or Color3.fromRGB(90, 30, 30)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = bodySize
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = bodyColor
	body.CFrame = CFrame.new(position + Vector3.new(0, bodySize.Y / 2, 0))
	body.Parent = model

	local headSize = bodySize.X * 0.9
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(headSize, headSize, headSize)
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(230, 190, 160)
	head.CFrame = body.CFrame * CFrame.new(0, bodySize.Y / 2 + headSize / 2 - 0.5, 0)
	head.Parent = model

	if isBoss then
		local handle = Instance.new("Part")
		handle.Name = "SpoonHandle"
		handle.Size = Vector3.new(0.6, 6, 0.6)
		handle.Anchored = true
		handle.CanCollide = false
		handle.Material = Enum.Material.Metal
		handle.Color = Color3.fromRGB(200, 200, 210)
		handle.CFrame = body.CFrame * CFrame.new(bodySize.X / 2 + 1, 1, 0)
		handle.Parent = model

		local bowl = Instance.new("Part")
		bowl.Name = "SpoonBowl"
		bowl.Shape = Enum.PartType.Ball
		bowl.Size = Vector3.new(2, 1.2, 1.6)
		bowl.Anchored = true
		bowl.CanCollide = false
		bowl.Material = Enum.Material.Metal
		bowl.Color = Color3.fromRGB(200, 200, 210)
		bowl.CFrame = handle.CFrame * CFrame.new(0, 3.5, 0)
		bowl.Parent = model
	end

	local billboardHeight = isBoss and 46 or 24
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBarGui"
	billboard.Size = UDim2.new(0, 200, 0, billboardHeight)
	billboard.StudsOffset = Vector3.new(0, bodySize.Y / 2 + headSize / 2 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = body

	if isBoss then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0, 20)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.Text = "Nonna Fury"
		nameLabel.Parent = billboard
	end

	local healthBarBackground = Instance.new("Frame")
	healthBarBackground.Name = "HealthBarBackground"
	healthBarBackground.Position = UDim2.new(0, 0, 0, isBoss and 22 or 0)
	healthBarBackground.Size = UDim2.new(1, 0, 0, isBoss and 18 or 20)
	healthBarBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	healthBarBackground.BackgroundTransparency = 0.3
	healthBarBackground.BorderSizePixel = 0
	healthBarBackground.Parent = billboard

	local healthBarFill = Instance.new("Frame")
	healthBarFill.Name = "HealthBarFill"
	healthBarFill.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
	healthBarFill.BorderSizePixel = 0
	healthBarFill.Size = UDim2.new(1, 0, 1, 0)
	healthBarFill.Parent = healthBarBackground

	model.PrimaryPart = body
	model.Parent = Workspace

	local maxHealth = isBoss and BOSS_HEALTH or MOB_HEALTH
	mobs[model] = {
		health = maxHealth,
		maxHealth = maxHealth,
		damage = isBoss and BOSS_DAMAGE or MOB_DAMAGE,
		speed = isBoss and BOSS_SPEED or MOB_SPEED,
		attackRange = isBoss and BOSS_ATTACK_RANGE or MOB_ATTACK_RANGE,
		detectRange = MOB_DETECT_RANGE,
		attackCooldown = MOB_ATTACK_COOLDOWN,
		lastAttackTime = 0,
		isBoss = isBoss,
		healthBarFill = healthBarFill,
	}

	return model
end

RunService.Heartbeat:Connect(function(deltaTime)
	for model, data in pairs(mobs) do
		if not model.Parent or not model.PrimaryPart then
			mobs[model] = nil
			continue
		end

		local mobPosition = model.PrimaryPart.Position
		local targetPlayer, distance = findNearestPlayer(mobPosition, data.detectRange)
		if not targetPlayer then
			continue
		end

		local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not targetRoot then
			continue
		end

		if distance > data.attackRange then
			local direction = targetRoot.Position - mobPosition
			direction = Vector3.new(direction.X, 0, direction.Z)
			if direction.Magnitude > 0.1 then
				direction = direction.Unit
				local newPosition = mobPosition + direction * data.speed * deltaTime
				model:PivotTo(CFrame.new(newPosition, newPosition + direction))
			end
		else
			local now = os.clock()
			if now - data.lastAttackTime >= data.attackCooldown then
				data.lastAttackTime = now
				damagePlayer(targetPlayer, data.damage)
			end
		end
	end
end)

local function getHandParts(character)
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	return rightHand, leftHand
end

local function equipWeapons(character)
	if character:FindFirstChild("SwordVisual") then
		return
	end

	local rightHand, leftHand = getHandParts(character)
	if not rightHand or not leftHand then
		return
	end

	local sword = Instance.new("Part")
	sword.Name = "SwordVisual"
	sword.Size = Vector3.new(0.6, 4, 0.3)
	sword.Material = Enum.Material.Metal
	sword.Color = Color3.fromRGB(210, 210, 220)
	sword.CanCollide = false
	sword.Massless = true
	sword.CFrame = rightHand.CFrame * CFrame.new(0, -2, 0)
	sword.Parent = character

	local swordWeld = Instance.new("WeldConstraint")
	swordWeld.Part0 = rightHand
	swordWeld.Part1 = sword
	swordWeld.Parent = sword

	local shield = Instance.new("Part")
	shield.Name = "ShieldVisual"
	shield.Size = Vector3.new(0.3, 3, 2.4)
	shield.Material = Enum.Material.Metal
	shield.Color = Color3.fromRGB(120, 30, 30)
	shield.CanCollide = false
	shield.Massless = true
	shield.CFrame = leftHand.CFrame * CFrame.new(0, -1, 0)
	shield.Parent = character

	local shieldWeld = Instance.new("WeldConstraint")
	shieldWeld.Part0 = leftHand
	shieldWeld.Part1 = shield
	shieldWeld.Parent = shield
end

local function createWeaponRack(position)
	local rack = Instance.new("Part")
	rack.Name = "WeaponRack"
	rack.Size = Vector3.new(4, 5, 1)
	rack.Anchored = true
	rack.Material = Enum.Material.Wood
	rack.Color = Color3.fromRGB(90, 60, 40)
	rack.CFrame = CFrame.new(position)
	rack.Parent = Workspace

	rack.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		if not player:GetAttribute("HasSword") then
			player:SetAttribute("HasSword", true)
			equipWeapons(character)
		end
	end)

	return rack
end

local function performSwordSwing(player)
	if not player:GetAttribute("HasSword") then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local facing = rootPart.CFrame.LookVector

	for model, _ in pairs(mobs) do
		if not model.PrimaryPart then
			continue
		end

		local toMob = model.PrimaryPart.Position - rootPart.Position
		local distance = toMob.Magnitude
		if distance <= SWORD_RANGE and distance > 0 then
			local direction = toMob.Unit
			if direction:Dot(facing) > 0.2 then
				damageMob(model, SWORD_DAMAGE)
			end
		end
	end
end

local function stopAutoSwing(player)
	autoSwingPlayers[player] = nil
	player:SetAttribute("IsAutoSwinging", nil)
end

local function toggleAutoSwing(player)
	if not player:GetAttribute("HasSword") then
		return
	end

	if autoSwingPlayers[player] then
		stopAutoSwing(player)
	else
		autoSwingPlayers[player] = 0
		player:SetAttribute("IsAutoSwinging", true)
	end
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, lastSwingTime in pairs(autoSwingPlayers) do
		if now - lastSwingTime >= AUTO_SWING_INTERVAL then
			autoSwingPlayers[player] = now
			performSwordSwing(player)
		end
	end
end)

local function activateShield(player)
	if not player:GetAttribute("HasSword") then
		return
	end

	local expiry = os.clock() + SHIELD_DURATION
	shieldExpiry[player] = expiry
	player:SetAttribute("ShieldActive", true)

	task.delay(SHIELD_DURATION, function()
		if shieldExpiry[player] == expiry then
			shieldExpiry[player] = nil
			player:SetAttribute("ShieldActive", nil)
		end
	end)
end

local function createArrowVisual(startPosition, endPosition)
	local arrow = Instance.new("Part")
	arrow.Name = "Arrow"
	arrow.Size = Vector3.new(0.3, 0.3, 4)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.Material = Enum.Material.Neon
	arrow.Color = Color3.fromRGB(255, 200, 60)
	arrow.CFrame = CFrame.new(startPosition, endPosition)
	arrow.Parent = Workspace

	local distance = (endPosition - startPosition).Magnitude
	local duration = math.clamp(distance / 120, 0.15, 0.6)

	local tween = TweenService:Create(
		arrow,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(endPosition, endPosition + (endPosition - startPosition)) }
	)
	tween.Completed:Connect(function()
		arrow:Destroy()
	end)
	tween:Play()
end

local function performBowShot(player, origin, direction)
	if not player:GetAttribute("HasSword") then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not rootPart then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(origin, direction.Unit * BOW_RANGE, params)
	local endPosition = origin + direction.Unit * BOW_RANGE

	if result then
		endPosition = result.Position

		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
		if hitModel and mobs[hitModel] then
			damageMob(hitModel, BOW_DAMAGE)
		end
	end

	-- Visually starts from the character (not the raw camera position, which
	-- can be behind/above the player and easy to miss) so the shot is
	-- clearly visible flying from the player toward the impact point.
	local visualStart = rootPart.Position + Vector3.new(0, 1, 0)
	createArrowVisual(visualStart, endPosition)
end

local function createTorch(position)
	local torch = Instance.new("Part")
	torch.Name = "Torch"
	torch.Size = Vector3.new(0.6, 1.2, 0.6)
	torch.Anchored = true
	torch.CanCollide = false
	torch.Material = Enum.Material.Neon
	torch.Color = Color3.fromRGB(255, 140, 40)
	torch.CFrame = CFrame.new(position)
	torch.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 20
	light.Brightness = 2
	light.Parent = torch
end

local function createDungeonLevel()
	local corridorLength = 400
	local corridorWidth = 24
	local wallHeight = 20

	local floor = Instance.new("Part")
	floor.Name = "DungeonFloor"
	floor.Size = Vector3.new(corridorWidth, 1, corridorLength)
	floor.Anchored = true
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(60, 58, 62)
	floor.CFrame = CFrame.new(DUNGEON_CENTER_X, 0, corridorLength / 2)
	floor.Parent = Workspace

	local leftWall = Instance.new("Part")
	leftWall.Name = "DungeonWallLeft"
	leftWall.Size = Vector3.new(1, wallHeight, corridorLength)
	leftWall.Anchored = true
	leftWall.Material = Enum.Material.Slate
	leftWall.Color = Color3.fromRGB(45, 43, 48)
	leftWall.CFrame = CFrame.new(DUNGEON_CENTER_X - corridorWidth / 2, wallHeight / 2, corridorLength / 2)
	leftWall.Parent = Workspace

	local rightWall = leftWall:Clone()
	rightWall.Name = "DungeonWallRight"
	rightWall.CFrame = CFrame.new(DUNGEON_CENTER_X + corridorWidth / 2, wallHeight / 2, corridorLength / 2)
	rightWall.Parent = Workspace

	local ceiling = Instance.new("Part")
	ceiling.Name = "DungeonCeiling"
	ceiling.Size = Vector3.new(corridorWidth, 1, corridorLength)
	ceiling.Anchored = true
	ceiling.Material = Enum.Material.Slate
	ceiling.Color = Color3.fromRGB(35, 33, 38)
	ceiling.CFrame = CFrame.new(DUNGEON_CENTER_X, wallHeight, corridorLength / 2)
	ceiling.Parent = Workspace

	local entranceGate = Instance.new("Part")
	entranceGate.Name = "DungeonEntrance"
	entranceGate.Size = Vector3.new(corridorWidth + 4, 1, 4)
	entranceGate.Anchored = true
	entranceGate.Material = Enum.Material.Cobblestone
	entranceGate.Color = Color3.fromRGB(80, 78, 82)
	entranceGate.CFrame = CFrame.new(DUNGEON_CENTER_X, 0, -2)
	entranceGate.Parent = Workspace

	for z = 0, corridorLength, 30 do
		createTorch(Vector3.new(DUNGEON_CENTER_X - corridorWidth / 2 + 0.5, 8, z))
		createTorch(Vector3.new(DUNGEON_CENTER_X + corridorWidth / 2 - 0.5, 8, z))
	end

	local bossRoomLength = 70
	local bossRoomWidth = 50
	local bossWallHeight = 30

	local bossFloor = Instance.new("Part")
	bossFloor.Name = "BossRoomFloor"
	bossFloor.Size = Vector3.new(bossRoomWidth, 1, bossRoomLength)
	bossFloor.Anchored = true
	bossFloor.Material = Enum.Material.Slate
	bossFloor.Color = Color3.fromRGB(70, 40, 40)
	bossFloor.CFrame = CFrame.new(DUNGEON_CENTER_X, 0, corridorLength + bossRoomLength / 2)
	bossFloor.Parent = Workspace

	local bossBackWall = Instance.new("Part")
	bossBackWall.Name = "BossRoomBackWall"
	bossBackWall.Size = Vector3.new(bossRoomWidth, bossWallHeight, 1)
	bossBackWall.Anchored = true
	bossBackWall.Material = Enum.Material.Slate
	bossBackWall.Color = Color3.fromRGB(45, 43, 48)
	bossBackWall.CFrame = CFrame.new(DUNGEON_CENTER_X, bossWallHeight / 2, corridorLength + bossRoomLength)
	bossBackWall.Parent = Workspace

	local bossLeftWall = Instance.new("Part")
	bossLeftWall.Name = "BossRoomWallLeft"
	bossLeftWall.Size = Vector3.new(1, bossWallHeight, bossRoomLength)
	bossLeftWall.Anchored = true
	bossLeftWall.Material = Enum.Material.Slate
	bossLeftWall.Color = Color3.fromRGB(45, 43, 48)
	bossLeftWall.CFrame = CFrame.new(DUNGEON_CENTER_X - bossRoomWidth / 2, bossWallHeight / 2, corridorLength + bossRoomLength / 2)
	bossLeftWall.Parent = Workspace

	local bossRightWall = bossLeftWall:Clone()
	bossRightWall.Name = "BossRoomWallRight"
	bossRightWall.CFrame = CFrame.new(DUNGEON_CENTER_X + bossRoomWidth / 2, bossWallHeight / 2, corridorLength + bossRoomLength / 2)
	bossRightWall.Parent = Workspace

	createTorch(Vector3.new(DUNGEON_CENTER_X - bossRoomWidth / 2 + 0.5, 10, corridorLength + bossRoomLength / 2))
	createTorch(Vector3.new(DUNGEON_CENTER_X + bossRoomWidth / 2 - 0.5, 10, corridorLength + bossRoomLength / 2))

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "DungeonSpawn"
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.Anchored = true
	spawnLocation.Material = Enum.Material.Cobblestone
	spawnLocation.Color = Color3.fromRGB(90, 88, 92)
	spawnLocation.CFrame = CFrame.new(DUNGEON_CENTER_X, 1, 4)
	spawnLocation.Parent = Workspace

	createWeaponRack(Vector3.new(DUNGEON_CENTER_X - 5, 2.5, 6))

	local mobSpacing = 35
	for z = 25, corridorLength - 25, mobSpacing do
		local xOffset = (math.random() - 0.5) * (corridorWidth - 4)
		createMob(Vector3.new(DUNGEON_CENTER_X + xOffset, 0, z), false)
	end

	createMob(Vector3.new(DUNGEON_CENTER_X, 0, corridorLength + bossRoomLength / 2), true)
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
createMagicCarpetPickup(Vector3.new(14, 1, 30))

createBeachSpawnArea()
createBeachClimbArea()
createJumpSpring(Vector3.new(BEACH_CENTER_X, 1, 18))

createDungeonLevel()

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

toggleFlightEvent.OnServerEvent:Connect(function(player)
	if not player:GetAttribute("HasCarpet") then
		return
	end

	setFlying(player, not flyingPlayers[player])
end)

toggleAutoSwingEvent.OnServerEvent:Connect(function(player)
	toggleAutoSwing(player)
end)

activateShieldEvent.OnServerEvent:Connect(function(player)
	activateShield(player)
end)

shootArrowEvent.OnServerEvent:Connect(function(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end

	performBowShot(player, origin, direction)
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasSword", true)

	player.CharacterAdded:Connect(function(character)
		equipWeapons(character)
	end)

	player.CharacterRemoving:Connect(function()
		endJumpBoost(player)
		flyingPlayers[player] = nil
		stopAutoSwing(player)
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
	flyingPlayers[player] = nil
	shieldExpiry[player] = nil
	endJumpBoost(player)
	stopAutoSwing(player)
end)
