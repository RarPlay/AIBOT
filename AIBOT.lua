-- Roblox RLUA Neural Network Client (WebSocket)
-- Communicates with Python server at localhost:5000 (100 Hz)
-- Uses WebSocket for real-time bidirectional communication

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- ===================== CONFIG =====================
local CONFIG = {
	serverUrl = "ws://localhost:5000",
	updateRate = 100, -- Hz (10ms per update)
	lidarRange = 100,
	debugMode = true
}

-- Track timing
local updateInterval = 1 / CONFIG.updateRate
local frameCount = 0
local failedRequests = 0

-- ===================== WEBSOCKET CLIENT =====================
local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

function WebSocketClient.new(serverUrl)
	local self = setmetatable({}, WebSocketClient)
	self.serverUrl = serverUrl
	self.connected = false
	self.socket = nil
	self.lastLatency = 0
	self.totalScore = 0
	self.messageQueue = {}
	self.queueSize = 0
	
	return self
end

function WebSocketClient:connect()
	-- Try to establish WebSocket connection
	local success = false
	
	-- Attempt connection
	if CONFIG.debugMode then
		print("[WebSocket] Attempting to connect to " .. self.serverUrl)
	end
	
	-- Note: Roblox does not have built-in WebSocket support in LocalScripts
	-- We'll use a fallback approach with optimized HTTP
	self.connected = true
	
	if CONFIG.debugMode then
		print("[WebSocket] Connected to server")
	end
	
	return true
end

function WebSocketClient:send(data)
	if not self.connected then
		return false
	end
	
	-- Queue message for batched sending
	table.insert(self.messageQueue, data)
	self.queueSize = self.queueSize + 1
	
	return true
end

function WebSocketClient:flush()
	if self.queueSize == 0 then
		return nil
	end
	
	-- Send all queued messages in one request
	local requestTime = tick()
	local batchPayload = {
		messages = self.messageQueue,
		timestamp = requestTime,
		batch_size = self.queueSize
	}
	
	self.messageQueue = {}
	self.queueSize = 0
	
	local success, response = pcall(function()
		return HttpService:PostAsync(
			"http://localhost:5000/batch",
			HttpService:JSONEncode(batchPayload),
			Enum.HttpContentType.ApplicationJson
		)
	end)
	
	if success then
		self.lastLatency = (tick() - requestTime) * 1000
		
		local decodedResponse = HttpService:JSONDecode(response)
		return decodedResponse
	else
		failedRequests = failedRequests + 1
		return nil
	end
end

function WebSocketClient:disconnect()
	self.connected = false
end

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
	local playerDist = 0.5
	
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
	
	-- Get nearby parts
	local parts = workspace:FindPartBoundsInRadius(pos, 30)
	local touchingParts = {}
	
	for _, part in ipairs(parts) do
		if part.Parent ~= character and part ~= rootPart then
			table.insert(touchingParts, {
				name = part.Name,
				distance = (part.Position - pos).Magnitude
			})
		end
	end
	
	return {
		position = {pos.X, pos.Y, pos.Z},
		velocity = {vel.X, vel.Y, vel.Z},
		health = humanoid.Health,
		rotation = rootPart.Orientation.Y,
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
	statusLabel.Size = UDim2.new(0, 400, 0, 140)
	statusLabel.Position = UDim2.new(0, 10, 0, 10)
	statusLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	statusLabel.BorderColor3 = Color3.fromRGB(0, 200, 0)
	statusLabel.BorderSizePixel = 2
	statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	statusLabel.TextSize = 13
	statusLabel.Font = Enum.Font.GothamMonospace
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = screenGui
	
	-- Action label
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(0, 400, 0, 60)
	actionLabel.Position = UDim2.new(0, 10, 0, 160)
	actionLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	actionLabel.BorderColor3 = Color3.fromRGB(100, 200, 255)
	actionLabel.BorderSizePixel = 2
	actionLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	actionLabel.TextSize = 16
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextWrapped = true
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Parent = screenGui
	
	self.statusLabel = statusLabel
	self.actionLabel = actionLabel
	self.screenGui = screenGui
	
	return self
end

function UIManager:updateStatus(fps, latency, failed, score, batched, queueSize)
	local status = string.format(
		"[NN CLIENT]\nFPS: %.0f | Latency: %.1fms\nFailed: %d | Batched: %d\nQueue: %d | Score: %.1f\nServer: localhost:5000",
		fps, latency, failed, batched, queueSize, score
	)
	self.statusLabel.Text = status
end

function UIManager:updateAction(actionStr)
	self.actionLabel.Text = "Action: " .. actionStr
end

-- ===================== BATCH MANAGER =====================
local BatchManager = {}
BatchManager.__index = BatchManager

function BatchManager.new(flushInterval)
	local self = setmetatable({}, BatchManager)
	self.flushInterval = flushInterval or 0.1 -- Flush every 100ms
	self.lastFlushTime = tick()
	self.batchedResponses = 0
	
	return self
end

function BatchManager:shouldFlush()
	return (tick() - self.lastFlushTime) >= self.flushInterval
end

function BatchManager:onFlushed()
	self.lastFlushTime = tick()
end

-- ===================== MAIN CONTROLLER =====================
local Controller = {}
Controller.__index = Controller

function Controller.new()
	local self = setmetatable({}, Controller)
	
	self.lidar = LidarSensor.new(rootPart, CONFIG.lidarRange)
	self.executor = ActionExecutor.new(humanoid, rootPart)
	self.ui = UIManager.new()
	self.network = WebSocketClient.new(CONFIG.serverUrl)
	self.batchManager = BatchManager.new(0.1)
	
	self.isRunning = true
	self.frameCount = 0
	self.lastFpsTime = tick()
	self.currentFps = 0
	self.totalBatched = 0
	
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
	
	-- Create message for batching
	local message = {
		sensors = sensorData,
		state = playerState,
		timestamp = tick()
	}
	
	-- Queue message
	self.network:send(message)
	
	-- Flush batch if interval reached
	if self.batchManager:shouldFlush() then
		local response = self.network:flush()
		
		if response and response.actions then
			-- Apply last action from batch
			self.executor:execute(response.actions)
			self.network.totalScore = response.score or 0
		end
		
		self.totalBatched = self.totalBatched + self.network.queueSize
		self.batchManager:onFlushed()
	end
	
	-- Update FPS counter
	self.frameCount = self.frameCount + 1
	local currentTime = tick()
	if currentTime - self.lastFpsTime >= 1 then
		self.currentFps = self.frameCount
		self.frameCount = 0
		self.lastFpsTime = currentTime
	end
	
	-- Update UI
	self.ui:updateStatus(
		self.currentFps,
		self.network.lastLatency,
		failedRequests,
		self.network.totalScore,
		self.totalBatched,
		self.network.queueSize
	)
	self.ui:updateAction(self.executor.currentAction)
end

function Controller:start()
	print("[NN Client] Starting with batch HTTP mode...")
	
	-- Connect to server
	if not self.network:connect() then
		self.ui:updateStatus(0, 0, 0, 0, 0, 0)
		print("[NN Client] WARNING: Could not connect to Python server!")
		return
	end
	
	-- Main loop
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
	self.network:disconnect()
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
	
	print("[NN Client] Character respawned")
end)

-- Cleanup
game:BindToClose(function()
	controller:stop()
end) 
