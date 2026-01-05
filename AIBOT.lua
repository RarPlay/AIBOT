
-- Roblox RLUA Neural Network Client
-- Communicates with Python server at localhost:5000 (100 Hz)
-- Handles LiDAR sensing, player state, and action execution

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- ===================== CONFIG =====================
local CONFIG = {
	serverUrl = "http://localhost:5000",
	updateRate = 100, -- Hz (10ms per update)
	lidarRange = 100,
	lidarSamples = 5, -- forward, left, right, down, player detection
	debugMode = true
}

-- Track timing
local lastUpdateTime = tick()
local updateInterval = 1 / CONFIG.updateRate
local frameCount = 0
local failedRequests = 0

-- ===================== LIDAR SENSOR =====================
local LidarSensor = {}
LidarSensor.__index = LidarSensor

function LidarSensor.new(rootPart, range)
	local self = setmetatable({}, LidarSensor)
	self.rootPart = rootPart
	self.range = range
	return self
end

function LidarSensor:castRay(direction, range)
	if not self.rootPart then return range end
	
	local rayOrigin = self.rootPart.Position
	local rayDirection = direction * range
	
	local raycastParams = RaycastParams.new()
	raycastParams:AddToFilter(self.rootPart.Parent)
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if result then
		return (result.Position - rayOrigin).Magnitude
	else
		return range
	end
end

function LidarSensor:sense()
	if not self.rootPart then
		return {0.5, 0.5, 0.5, 0.5, 0.5}
	end
	
	local cf = self.rootPart.CFrame
	
	-- Cast rays in 5 directions
	local forward = self:castRay(cf.LookVector, self.range)
	local left = self:castRay(-cf.RightVector, self.range)
	local right = self:castRay(cf.RightVector, self.range)
	local down = self:castRay(-Vector3.new(0, 1, 0), self.range)
	local playerDist = 0.5 -- Placeholder
	
	-- Normalize to [0, 1]
	forward = math.min(forward / self.range, 1)
	left = math.min(left / self.range, 1)
	right = math.min(right / self.range, 1)
	down = math.min(down / self.range, 1)
	
	return {forward, left, right, down, playerDist}
end

-- ===================== PLAYER STATE =====================
local function getPlayerState()
	if not character or not humanoid or not rootPart then
		return nil
	end
	
	local pos = rootPart.Position
	local vel = rootPart.AssemblyLinearVelocity
	
	-- Get nearby parts/objects
	local touchingParts = {}
	local region = Region3.new(pos - Vector3.new(20, 20, 20), pos + Vector3.new(20, 20, 20))
	region = region:ExpandToGrid(4)
	
	local parts = workspace:FindPartBoundsInRadius(pos, 30)
	for _, part in ipairs(parts) do
		if part.Parent ~= character and part ~= rootPart then
			table.insert(touchingParts, {
				name = part.Name,
				distance = (part.Position - pos).Magnitude,
				canTouch = part.CanCollide
			})
		end
	end
	
	return {
		position = {pos.X, pos.Y, pos.Z},
		velocity = {vel.X, vel.Y, vel.Z},
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
		humanoidState = humanoid:GetState().Name,
		rotation = rootPart.Orientation.Y,
		touchingParts = touchingParts,
		isGrounded = humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
	}
end

-- ===================== ACTION EXECUTOR =====================
local ActionExecutor = {}
ActionExecutor.__index = ActionExecutor

function ActionExecutor.new(humanoid, rootPart)
	local self = setmetatable({}, ActionExecutor)
	self.humanoid = humanoid
	self.rootPart = rootPart
	self.currentAction = "IDLE"
	return self
end

function ActionExecutor:execute(actions)
	if not self.humanoid or self.humanoid.Health <= 0 then
		return
	end
	
	-- Decode action values (expecting -1 to 1 range from Python)
	local moveX = 0
	local moveZ = 0
	local shouldJump = false
	local actionStr = ""
	
	if actions.move_forward then
		if actions.move_forward > 0.3 then
			moveZ = -1
			actionStr = actionStr .. "FWD "
		elseif actions.move_forward < -0.3 then
			moveZ = 1
			actionStr = actionStr .. "BACK "
		end
	end
	
	if actions.move_left then
		if actions.move_left > 0.3 then
			moveX = -1
			actionStr = actionStr .. "LEFT "
		elseif actions.move_left < -0.3 then
			moveX = 1
			actionStr = actionStr .. "RIGHT "
		end
	end
	
	if actions.jump and actions.jump > 0.5 then
		shouldJump = true
		actionStr = actionStr .. "JUMP "
	end
	
	-- Apply movement
	self.humanoid:Move(Vector3.new(moveX, 0, moveZ), true)
	
	if shouldJump then
		self.humanoid:Jump()
	end
	
	self.currentAction = (actionStr ~= "" and string.sub(actionStr, 1, -2)) or "IDLE"
end

-- ===================== UI MANAGER =====================
local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
	local self = setmetatable({}, UIManager)
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NNClientUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0, 400, 0, 120)
	statusLabel.Position = UDim2.new(0, 10, 0, 10)
	statusLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	statusLabel.BorderColor3 = Color3.fromRGB(0, 200, 0)
	statusLabel.BorderSizePixel = 2
	statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = screenGui
	
	-- Action label
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(0, 400, 0, 60)
	actionLabel.Position = UDim2.new(0, 10, 0, 140)
	actionLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	actionLabel.BorderColor3 = Color3.fromRGB(100, 200, 255)
	actionLabel.BorderSizePixel = 2
	actionLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	actionLabel.TextSize = 16
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Parent = screenGui
	
	self.statusLabel = statusLabel
	self.actionLabel = actionLabel
	self.screenGui = screenGui
	
	return self
end

function UIManager:updateStatus(fps, latency, failed, score)
	local status = string.format(
		"[NN CLIENT - Python Server]\n" ..
		"FPS: %.1f | Latency: %.1fms\n" ..
		"Failed Requests: %d\n" ..
		"Score: %.1f\n" ..
		"Server: localhost:5000",
		fps, latency, failed, score
	)
	self.statusLabel.Text = status
end

function UIManager:updateAction(actionStr)
	self.actionLabel.Text = "Action: " .. actionStr
end

-- ===================== NETWORK CLIENT =====================
local NetworkClient = {}
NetworkClient.__index = NetworkClient

function NetworkClient.new(serverUrl)
	local self = setmetatable({}, NetworkClient)
	self.serverUrl = serverUrl
	self.lastLatency = 0
	self.totalScore = 0
	self.connected = false
	
	return self
end

function NetworkClient:sendSensorData(sensorData, playerState)
	local requestTime = tick()
	
	local payload = {
		sensors = sensorData,
		state = playerState,
		timestamp = requestTime
	}
	
	local success, response = pcall(function()
		return HttpService:PostAsync(
			self.serverUrl .. "/step",
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)
	
	if success then
		self.lastLatency = (tick() - requestTime) * 1000
		self.connected = true
		
		local decodedResponse = HttpService:JSONDecode(response)
		return decodedResponse
	else
		failedRequests = failedRequests + 1
		self.connected = false
		return nil
	end
end

function NetworkClient:connect()
	local success, response = pcall(function()
		return HttpService:PostAsync(
			self.serverUrl .. "/connect",
			HttpService:JSONEncode({timestamp = tick()}),
			Enum.HttpContentType.ApplicationJson,
			false
		)
	end)
	
	if success then
		self.connected = true
		if CONFIG.debugMode then
			print("[NN Client] Connected to Python server at " .. self.serverUrl)
		end
		return true
	else
		if CONFIG.debugMode then
			print("[NN Client] Failed to connect to server: " .. tostring(response))
		end
		return false
	end
end

-- ===================== MAIN CONTROLLER =====================
local Controller = {}
Controller.__index = Controller

function Controller.new()
	local self = setmetatable({}, Controller)
	
	self.lidar = LidarSensor.new(rootPart, CONFIG.lidarRange)
	self.executor = ActionExecutor.new(humanoid, rootPart)
	self.ui = UIManager.new()
	self.network = NetworkClient.new(CONFIG.serverUrl)
	
	self.isRunning = true
	self.frameCount = 0
	self.lastFpsTime = tick()
	self.currentFps = 0
	
	return self
end

function Controller:update()
	if not self.isRunning or not humanoid or humanoid.Health <= 0 then
		return
	end
	
	-- Get sensor data
	local sensorData = self.lidar:sense()
	
	-- Get player state
	local playerState = getPlayerState()
	if not playerState then
		return
	end
	
	-- Send to Python server and receive actions
	local response = self.network:sendSensorData(sensorData, playerState)
	
	if response then
		-- Execute actions from Python
		self.executor:execute(response.actions or {})
		self.network.totalScore = response.score or 0
	end
	
	-- Update UI
	self.frameCount = self.frameCount + 1
	local currentTime = tick()
	if currentTime - self.lastFpsTime >= 1 then
		self.currentFps = self.frameCount
		self.frameCount = 0
		self.lastFpsTime = currentTime
	end
	
	self.ui:updateStatus(self.currentFps, self.network.lastLatency, failedRequests, self.network.totalScore)
	self.ui:updateAction(self.executor.currentAction)
end

function Controller:start()
	print("[NN Client] Starting neural network client...")
	
	-- Try to connect to server
	if not self.network:connect() then
		self.ui:updateStatus(0, 0, 0, 0)
		print("[NN Client] WARNING: Could not connect to Python server!")
		return
	end
	
	-- Main loop at 100 Hz
	local lastUpdate = tick()
	
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not self.isRunning or not character or not humanoid or humanoid.Health <= 0 then
			connection:Disconnect()
			return
		end
		
		local currentTime = tick()
		if currentTime - lastUpdate >= updateInterval then
			lastUpdate = currentTime
			self:update()
		end
	end)
end

function Controller:stop()
	self.isRunning = false
	print("[NN Client] Stopped")
end

-- ===================== INITIALIZATION =====================
local controller = Controller.new()
controller:start()

-- Handle character respawn
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	
	controller.lidar.rootPart = rootPart
	controller.executor.humanoid = humanoid
	controller.executor.rootPart = rootPart
	
	print("[NN Client] Character respawned, resuming...")
end)

-- Cleanup
game:BindToClose(function()
	controller:stop()
end) 
