local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shootEvent = ReplicatedStorage:WaitForChild("ShootPlatform")

local function shoot()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	shootEvent:FireServer(ray.Origin, ray.Direction)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		shoot()
	end
end)
