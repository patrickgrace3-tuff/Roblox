local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local shootEvent = ReplicatedStorage:WaitForChild("ShootPlatform")
local chargeJumpEvent = ReplicatedStorage:WaitForChild("ChargeJump")
local toggleFlightEvent = ReplicatedStorage:WaitForChild("ToggleFlight")

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

local function shoot()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	shootEvent:FireServer(ray.Origin, ray.Direction)
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
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		releaseCharge()
	end
end)
