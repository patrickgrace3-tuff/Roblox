local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local grabEvent = Instance.new("RemoteEvent")
grabEvent.Name = "GrabItem"
grabEvent.Parent = ReplicatedStorage

local throwEvent = Instance.new("RemoteEvent")
throwEvent.Name = "ThrowItem"
throwEvent.Parent = ReplicatedStorage

local pickupEvent = Instance.new("RemoteEvent")
pickupEvent.Name = "PickupItem"
pickupEvent.Parent = ReplicatedStorage

local MAX_GRAB_DISTANCE = 150
local PULL_TIME = 0.35
local THROW_SPEED = 60
local HOLD_OFFSET = CFrame.new(0, 0, -4)
local ARM_PICKUP_RANGE = 6

local heldItems = {} -- [player] = { part = Part, weld = WeldConstraint }
local pulling = {} -- [part] = true while the gadget arm is reeling it in

local function createGrabbablePart(name, position, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(2, 2, 2)
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.Parent = Workspace
	part:SetAttribute("Grabbable", true)
	return part
end

createGrabbablePart("Crate", Vector3.new(10, 3, 0), Color3.fromRGB(150, 100, 60))
createGrabbablePart("Crate", Vector3.new(15, 3, 5), Color3.fromRGB(150, 100, 60))
createGrabbablePart("Ball", Vector3.new(-10, 3, 0), Color3.fromRGB(200, 50, 50))

local armPickups = {}

local function createArmPickup(position)
	local pickup = Instance.new("Part")
	pickup.Name = "ArmAttachment"
	pickup.Size = Vector3.new(2, 1, 1)
	pickup.Position = position
	pickup.Anchored = true
	pickup.CanCollide = false
	pickup.Material = Enum.Material.Metal
	pickup.Color = Color3.fromRGB(0, 200, 200)
	pickup.Parent = Workspace

	table.insert(armPickups, pickup)
end

createArmPickup(Vector3.new(0, 3, 5))

local function getHandPart(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function equipArmVisual(character)
	if character:FindFirstChild("GadgetArmAccessory") then
		return
	end

	local handPart = getHandPart(character)
	if not handPart then
		return
	end

	local accessory = Instance.new("Part")
	accessory.Name = "GadgetArmAccessory"
	accessory.Size = Vector3.new(0.6, 0.6, 1.4)
	accessory.Material = Enum.Material.Metal
	accessory.Color = Color3.fromRGB(0, 200, 200)
	accessory.CanCollide = false
	accessory.Massless = true
	accessory.CFrame = handPart.CFrame
	accessory.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handPart
	weld.Part1 = accessory
	weld.Parent = accessory
end

local function releaseItem(player, throwVelocity)
	local held = heldItems[player]
	if not held then
		return
	end

	if held.weld then
		held.weld:Destroy()
	end
	held.part.CanCollide = true

	if throwVelocity then
		held.part.AssemblyLinearVelocity = throwVelocity
	end

	heldItems[player] = nil
end

local function finishGrab(player, part)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		part.Anchored = false
		pulling[part] = nil
		return
	end

	part.Anchored = false
	part.CanCollide = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part

	heldItems[player] = { part = part, weld = weld }
	pulling[part] = nil
end

local function createGadgetArm(rootPart, part)
	local arm = Instance.new("Part")
	arm.Name = "GadgetArm"
	arm.Anchored = true
	arm.CanCollide = false
	arm.CanQuery = false
	arm.Material = Enum.Material.Neon
	arm.Color = Color3.fromRGB(255, 200, 0)
	arm.Parent = Workspace

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent or not rootPart.Parent then
			return
		end

		local startPos = rootPart.Position
		local endPos = part.Position
		local distance = math.max((endPos - startPos).Magnitude, 0.1)

		arm.Size = Vector3.new(0.3, 0.3, distance)
		arm.CFrame = CFrame.new(startPos:Lerp(endPos, 0.5), endPos)
	end)

	return arm, connection
end

local function grabItem(player, part)
	if heldItems[player] or pulling[part] then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	if (part.Position - rootPart.Position).Magnitude > MAX_GRAB_DISTANCE then
		return
	end

	pulling[part] = true
	part.Anchored = true
	part.CanCollide = false

	local armOrigin = getHandPart(character) or rootPart
	local arm, armConnection = createGadgetArm(armOrigin, part)

	local goalCFrame = rootPart.CFrame * HOLD_OFFSET
	local tween = TweenService:Create(part, TweenInfo.new(PULL_TIME, Enum.EasingStyle.Quad), { CFrame = goalCFrame })

	tween.Completed:Connect(function()
		armConnection:Disconnect()
		arm:Destroy()

		if pulling[part] then
			finishGrab(player, part)
		end
	end)

	tween:Play()
end

grabEvent.OnServerEvent:Connect(function(player, part)
	if not player:GetAttribute("HasGadgetArm") then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	if not part:GetAttribute("Grabbable") then
		return
	end

	grabItem(player, part)
end)

pickupEvent.OnServerEvent:Connect(function(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	for i, pickup in armPickups do
		if pickup.Parent and (pickup.Position - rootPart.Position).Magnitude <= ARM_PICKUP_RANGE then
			pickup:Destroy()
			table.remove(armPickups, i)
			player:SetAttribute("HasGadgetArm", true)
			equipArmVisual(character)
			break
		end
	end
end)

throwEvent.OnServerEvent:Connect(function(player)
	local held = heldItems[player]
	if not held then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local velocity = rootPart and (rootPart.CFrame.LookVector * THROW_SPEED + Vector3.new(0, 10, 0)) or nil

	releaseItem(player, velocity)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("HasGadgetArm") then
			equipArmVisual(character)
		end
	end)

	player.CharacterRemoving:Connect(function()
		releaseItem(player, nil)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	releaseItem(player, nil)
end)
