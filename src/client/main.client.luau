local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local shootEvent = ReplicatedStorage:WaitForChild("ShootPlatform")
local chargeJumpEvent = ReplicatedStorage:WaitForChild("ChargeJump")
local toggleFlightEvent = ReplicatedStorage:WaitForChild("ToggleFlight")
local toggleAutoSwingEvent = ReplicatedStorage:WaitForChild("ToggleAutoSwing")
local activateShieldEvent = ReplicatedStorage:WaitForChild("ActivateShield")
local shootArrowEvent = ReplicatedStorage:WaitForChild("ShootArrow")

local MAX_CHARGE_TIME = 1.2
local JUMP_BOOST_MULTIPLIER = 5
local VERTICAL_FLY_SPEED = 40

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JumpBoostGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local jumpsLabel = Instance.new("TextLabel")
jumpsLabel.Name = "JumpsLeftLabel"
jumpsLabel.AnchorPoint = Vector2.new(0.5, 0)
jumpsLabel.Position = UDim2.new(0.5, 0, 0.02, 0)
jumpsLabel.Size = UDim2.new(0, 240, 0, 36)
jumpsLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
jumpsLabel.BackgroundTransparency = 0.3
jumpsLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
jumpsLabel.Font = Enum.Font.GothamBold
jumpsLabel.TextScaled = true
jumpsLabel.Text = ""
jumpsLabel.Visible = false
jumpsLabel.Parent = screenGui

local meterBackground = Instance.new("Frame")
meterBackground.Name = "ChargeMeterBackground"
meterBackground.AnchorPoint = Vector2.new(0.5, 0)
meterBackground.Position = UDim2.new(0.5, 0, 0.02, 44)
meterBackground.Size = UDim2.new(0, 240, 0, 18)
meterBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
meterBackground.BackgroundTransparency = 0.3
meterBackground.Visible = false
meterBackground.Parent = screenGui

local meterFill = Instance.new("Frame")
meterFill.Name = "ChargeMeterFill"
meterFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
meterFill.BorderSizePixel = 0
meterFill.Size = UDim2.new(0, 0, 1, 0)
meterFill.Parent = meterBackground

local function updateJumpsLabel()
	local remaining = player:GetAttribute("JumpsRemaining")
	if remaining and remaining > 0 then
		jumpsLabel.Text = "Jump Boost: " .. remaining
		jumpsLabel.Visible = true
	else
		jumpsLabel.Visible = false
		meterBackground.Visible = false
	end
end

player:GetAttributeChangedSignal("JumpsRemaining"):Connect(updateJumpsLabel)
updateJumpsLabel()

local flightLabel = Instance.new("TextLabel")
flightLabel.Name = "FlightLabel"
flightLabel.AnchorPoint = Vector2.new(0.5, 0)
flightLabel.Position = UDim2.new(0.5, 0, 0.02, 88)
flightLabel.Size = UDim2.new(0, 320, 0, 30)
flightLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
flightLabel.BackgroundTransparency = 0.3
flightLabel.TextColor3 = Color3.fromRGB(200, 120, 255)
flightLabel.Font = Enum.Font.GothamBold
flightLabel.TextScaled = true
flightLabel.Text = "Flying — Space/Shift: up/down"
flightLabel.Visible = false
flightLabel.Parent = screenGui

-- Applied locally (same reasoning as the charge jump): this client owns
-- physics for its own character, so overriding vertical velocity here
-- every frame reliably cancels gravity for a controllable hover/fly.
local flightConnection

local function stopFlightLoop()
	if flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
end

local function startFlightLoop()
	stopFlightLoop()

	flightConnection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local verticalInput = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			verticalInput += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			verticalInput -= 1
		end

		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, verticalInput * VERTICAL_FLY_SPEED, currentVelocity.Z)
	end)
end

local function updateFlightState()
	local flying = player:GetAttribute("IsFlying")
	flightLabel.Visible = flying == true

	if flying then
		startFlightLoop()
	else
		stopFlightLoop()
	end
end

player:GetAttributeChangedSignal("IsFlying"):Connect(updateFlightState)
updateFlightState()

local healthBarBackground = Instance.new("Frame")
healthBarBackground.Name = "HealthBarBackground"
healthBarBackground.AnchorPoint = Vector2.new(0, 1)
healthBarBackground.Position = UDim2.new(0.02, 0, 0.98, 0)
healthBarBackground.Size = UDim2.new(0, 240, 0, 26)
healthBarBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
healthBarBackground.BackgroundTransparency = 0.3
healthBarBackground.Parent = screenGui

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "HealthBarFill"
healthBarFill.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
healthBarFill.BorderSizePixel = 0
healthBarFill.Size = UDim2.new(1, 0, 1, 0)
healthBarFill.Parent = healthBarBackground

local healthLabel = Instance.new("TextLabel")
healthLabel.Name = "HealthLabel"
healthLabel.BackgroundTransparency = 1
healthLabel.Size = UDim2.new(1, 0, 1, 0)
healthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
healthLabel.Font = Enum.Font.GothamBold
healthLabel.TextScaled = true
healthLabel.Text = ""
healthLabel.Parent = healthBarBackground

local function updateHealthBar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local fraction = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth) or 0
	healthBarFill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	healthLabel.Text = math.ceil(humanoid.Health) .. " / " .. math.ceil(humanoid.MaxHealth)
end

local function hookHealthBar(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(updateHealthBar)
	updateHealthBar()
end

if player.Character then
	hookHealthBar(player.Character)
end
player.CharacterAdded:Connect(hookHealthBar)

-- WoW-style action bar: a row of numbered slots bottom-center, each
-- glowing while its ability is active.
local SLOT_SIZE = 64
local SLOT_GAP = 8

local actionBar = Instance.new("Frame")
actionBar.Name = "ActionBar"
actionBar.AnchorPoint = Vector2.new(0.5, 1)
actionBar.Position = UDim2.new(0.5, 0, 1, -16)
actionBar.Size = UDim2.new(0, SLOT_SIZE * 3 + SLOT_GAP * 2, 0, SLOT_SIZE)
actionBar.BackgroundTransparency = 1
actionBar.Parent = screenGui

local INACTIVE_BORDER_COLOR = Color3.fromRGB(90, 90, 90)

local function createActionSlot(index, keyText, nameText, iconColor)
	local slot = Instance.new("Frame")
	slot.Name = "Slot" .. index
	slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
	slot.Position = UDim2.new(0, (index - 1) * (SLOT_SIZE + SLOT_GAP), 0, 0)
	slot.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	slot.BackgroundTransparency = 0.15
	slot.BorderSizePixel = 0
	slot.Parent = actionBar

	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.Thickness = 2
	border.Color = INACTIVE_BORDER_COLOR
	border.Parent = slot

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, -8, 1, -24)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundColor3 = iconColor
	icon.BorderSizePixel = 0
	icon.Parent = slot

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Position = UDim2.new(0, 0, 1, -16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Text = nameText
	nameLabel.Parent = slot

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Size = UDim2.new(0, 18, 0, 18)
	keyLabel.Position = UDim2.new(0, 2, 0, 2)
	keyLabel.BackgroundTransparency = 1
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextScaled = true
	keyLabel.Text = keyText
	keyLabel.ZIndex = 2
	keyLabel.Parent = slot

	return border
end

local swordBorder = createActionSlot(1, "1", "SWORD", Color3.fromRGB(180, 180, 190))
local shieldBorder = createActionSlot(2, "2", "SHIELD", Color3.fromRGB(150, 40, 40))
local bowBorder = createActionSlot(3, "3", "BOW", Color3.fromRGB(150, 110, 60))

local ACTIVE_BORDER_THICKNESS = 3
local INACTIVE_BORDER_THICKNESS = 2
local SWORD_ACTIVE_COLOR = Color3.fromRGB(255, 220, 60)
local SHIELD_ACTIVE_COLOR = Color3.fromRGB(80, 200, 255)

local function updateActionBar()
	local autoSwinging = player:GetAttribute("IsAutoSwinging")
	swordBorder.Color = autoSwinging and SWORD_ACTIVE_COLOR or INACTIVE_BORDER_COLOR
	swordBorder.Thickness = autoSwinging and ACTIVE_BORDER_THICKNESS or INACTIVE_BORDER_THICKNESS

	local shieldActive = player:GetAttribute("ShieldActive")
	shieldBorder.Color = shieldActive and SHIELD_ACTIVE_COLOR or INACTIVE_BORDER_COLOR
	shieldBorder.Thickness = shieldActive and ACTIVE_BORDER_THICKNESS or INACTIVE_BORDER_THICKNESS
end

player:GetAttributeChangedSignal("IsAutoSwinging"):Connect(updateActionBar)
player:GetAttributeChangedSignal("ShieldActive"):Connect(updateActionBar)
updateActionBar()

local function flashBowSlot()
	bowBorder.Color = SWORD_ACTIVE_COLOR
	bowBorder.Thickness = ACTIVE_BORDER_THICKNESS
	task.delay(0.15, function()
		bowBorder.Color = INACTIVE_BORDER_COLOR
		bowBorder.Thickness = INACTIVE_BORDER_THICKNESS
	end)
end

local function shoot()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	shootEvent:FireServer(ray.Origin, ray.Direction)
end

local function shootArrow()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	shootArrowEvent:FireServer(ray.Origin, ray.Direction)
	flashBowSlot()
end

local isCharging = false
local chargeStartTime = 0
local chargeConnection

local function beginCharge()
	if isCharging then
		return
	end
	if not player:GetAttribute("JumpsRemaining") then
		return
	end

	isCharging = true
	chargeStartTime = os.clock()
	meterFill.Size = UDim2.new(0, 0, 1, 0)
	meterBackground.Visible = true

	chargeConnection = RunService.RenderStepped:Connect(function()
		local fraction = math.clamp((os.clock() - chargeStartTime) / MAX_CHARGE_TIME, 0, 1)
		meterFill.Size = UDim2.new(fraction, 0, 1, 0)
	end)
end

local function releaseCharge()
	if not isCharging then
		return
	end

	isCharging = false
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	meterBackground.Visible = false

	local fraction = math.clamp((os.clock() - chargeStartTime) / MAX_CHARGE_TIME, 0, 1)

	-- Applied locally: this client owns physics for its own character, so a
	-- server-set velocity here would just get fought/overridden.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and rootPart then
		local baseVelocity = humanoid.JumpPower > 0 and humanoid.JumpPower or 50
		local minVelocity = baseVelocity
		local maxVelocity = baseVelocity * JUMP_BOOST_MULTIPLIER
		local jumpVelocity = minVelocity + fraction * (maxVelocity - minVelocity)

		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, jumpVelocity, currentVelocity.Z)
	end

	chargeJumpEvent:FireServer()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		shoot()
	elseif input.KeyCode == Enum.KeyCode.Space then
		beginCharge()
	elseif input.KeyCode == Enum.KeyCode.F then
		toggleFlightEvent:FireServer()
	elseif input.KeyCode == Enum.KeyCode.One then
		toggleAutoSwingEvent:FireServer()
	elseif input.KeyCode == Enum.KeyCode.Two then
		activateShieldEvent:FireServer()
	elseif input.KeyCode == Enum.KeyCode.Three then
		shootArrow()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		releaseCharge()
	end
end)
