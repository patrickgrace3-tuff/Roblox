local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local dropEvent = Instance.new("RemoteEvent")
dropEvent.Name = "DropItem"
dropEvent.Parent = ReplicatedStorage

local heldItems = {} -- [player] = { part = Part, weld = WeldConstraint, prompt = ProximityPrompt }

local function createGrabbablePart(name, position, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(2, 2, 2)
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.Parent = Workspace

	part:SetAttribute("Grabbable", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 8
	prompt.Parent = part

	return part
end

createGrabbablePart("Crate", Vector3.new(10, 3, 0), Color3.fromRGB(150, 100, 60))
createGrabbablePart("Crate", Vector3.new(15, 3, 5), Color3.fromRGB(150, 100, 60))
createGrabbablePart("Ball", Vector3.new(-10, 3, 0), Color3.fromRGB(200, 50, 50))

local function dropItem(player)
	local held = heldItems[player]
	if not held then
		return
	end

	if held.weld then
		held.weld:Destroy()
	end
	if held.part then
		held.part.CanCollide = true
	end
	if held.prompt then
		held.prompt.Enabled = true
	end

	heldItems[player] = nil
end

local function grabItem(player, part, prompt)
	if heldItems[player] then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	part.Anchored = false
	part.CanCollide = false
	part.CFrame = rootPart.CFrame * CFrame.new(0, 0, -4)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part

	prompt.Enabled = false

	heldItems[player] = { part = part, weld = weld, prompt = prompt }
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local part = prompt.Parent
	if not part or not part:GetAttribute("Grabbable") then
		return
	end

	grabItem(player, part, prompt)
end)

dropEvent.OnServerEvent:Connect(function(player)
	dropItem(player)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		dropItem(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	dropItem(player)
end)
