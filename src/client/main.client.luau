local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local grabEvent = ReplicatedStorage:WaitForChild("GrabItem")
local throwEvent = ReplicatedStorage:WaitForChild("ThrowItem")
local pickupEvent = ReplicatedStorage:WaitForChild("PickupItem")

local GRAB_RANGE = 150

local function tryGrab()
	local character = player.Character
	local camera = Workspace.CurrentCamera
	if not character or not camera then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * GRAB_RANGE, params)
	if result and result.Instance:GetAttribute("Grabbable") then
		grabEvent:FireServer(result.Instance)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryGrab()
	elseif input.KeyCode == Enum.KeyCode.T then
		throwEvent:FireServer()
	elseif input.KeyCode == Enum.KeyCode.G then
		pickupEvent:FireServer()
	end
end)
