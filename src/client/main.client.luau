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

local abilityLabel = Instance.new("TextLabel")
abilityLabel.Name = "AbilityLabel"
abilityLabel.AnchorPoint = Vector2.new(1, 1)
abilityLabel.Position = UDim2.new(0.98, 0, 0.98, 0)
abilityLabel.Size = UDim2.new(0, 260, 0, 30)
abilityLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
abilityLabel.BackgroundTransparency = 0.3
abilityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
abilityLabel.Font = Enum.Font.GothamBold
abilityLabel.TextScaled = true
abilityLabel.Text = ""
abilityLabel.Visible = false
abilityLabel.Parent = screenGui

local function updateAbilityLabel()
	local autoSwinging = player:GetAttribute("IsAutoSwinging")
	local shieldActive = player:GetAttribute("ShieldActive")

	if autoSwinging and shieldActive then
		abilityLabel.Text = "Auto-Swing: ON | Shield: Active"
		abilityLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
	elseif autoSwinging then
		abilityLabel.Text = "Auto-Swing: ON (press 1 to stop)"
		abilityLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	elseif shieldActive then
		abilityLabel.Text = "Shield: Active"
		abilityLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
	end

	abilityLabel.Visible = autoSwinging == true or shieldActive == true
end

player:GetAttributeChangedSignal("IsAutoSwinging"):Connect(updateAbilityLabel)
player:GetAttributeChangedSignal("ShieldActive"):Connect(updateAbilityLabel)
updateAbilityLabel()

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
