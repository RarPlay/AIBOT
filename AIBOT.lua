-- =========================================
-- ULTRA-SMART NEURAL AI - Full Spatial Awareness
-- LiDAR with coordinates, position tracking, 10x intelligence
-- =========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- ================= CONFIGURATION =================
local CONFIG = {
	MOVEMENT_SPEED = 18,
	TURN_SPEED = 0.2,
	SAFE_DISTANCE = 6,
	DANGER_DISTANCE = 3,
	RAYCAST_DISTANCE = 25,
	LEARNING_RATE = 0.15,
	EXPLORATION_RATE = 0.05,
	DIRECTION_SMOOTHING = 0.28,
	MIN_MOVEMENT_SPEED = 2,
	STUCK_THRESHOLD = 2.5,
	INTERACTION_DISTANCE = 8,
	DECISION_COOLDOWN = 0.4,
	COIN_LOSS_PER_HIT = 5,
	COIN_LOSS_PER_TOUCH = 2,
	MEMORY_SIZE = 50 -- Remember last 50 positions
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle"}

-- ================= ADVANCED BOT STATE =================
local botControl = {
	enabled = true,
	confidence = 1.0,
	moveDirection = Vector3.new(0, 0, 1),
	status = "INITIALIZING",
	score = 0,
	coinsCollected = 0,
	distanceTraveled = 0,
	lastPosition = nil,
	lastMovementTime = tick(),
	lastDecisionTime = tick(),
	stuckCounter = 0,
	health = 100,
	touchingWall = false,
	lastWallHit = 0,
	wallTouchStart = 0,
	collisionCount = 0,
	
	-- Spatial awareness
	currentPosition = Vector3.zero,
	targetPosition = nil,
	positionHistory = {},
	visitedPositions = {},
	
	-- Performance metrics
	successfulMoves = 0,
	failedMoves = 0,
	interactionsSuccessful = 0
}

-- ================= LIDAR DATA STRUCTURE =================
local lidarSystem = {
	beams = {}, -- Stores all beam data
	obstacles = {}, -- Detected obstacles with full info
	nearestObstacle = nil,
	safeDirections = {},
	dangerDirections = {}
}

-- Obstacle awareness zones
local obstacleZones = {
	farLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	left = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	center = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	right = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	farRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"}
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position
botControl.health = humanoid.Health

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 ULTRA-SMART AI - FULL SPATIAL AWARENESS")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
humanoid.JumpPower = 0
humanoid.AutoRotate = false

local function blockPlayerInput()
	UserInputService.ModalEnabled = true
end

local function restorePlayerInput()
	UserInputService.ModalEnabled = false
	humanoid.AutoRotate = true
	humanoid.JumpPower = 50
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.P then
		botControl.enabled = not botControl.enabled
		if botControl.enabled then
			print("🤖 AI CONTROL: ENABLED")
			blockPlayerInput()
		else
			print("👤 PLAYER CONTROL: ENABLED")
			restorePlayerInput()
			humanoid:Move(Vector3.zero)
		end
	end
end)

blockPlayerInput()

-- ================= COLLISION DETECTION =================
local function setupCollisionDetection()
	rootPart.Touched:Connect(function(hit)
		if not botControl.enabled then return end
		
		local isWall = false
		for _, tag in ipairs(OBSTACLE_TAGS) do
			if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
				isWall = true
				break
			end
		end
		
		if not isWall and hit:IsA("BasePart") and hit.CanCollide then
			local isInteractive = false
			for _, tag in ipairs(INTERACTIVE_TAGS) do
				if hit:HasTag(tag) or hit.Name:find(tag) then
					isInteractive = true
					break
				end
			end
			if not isInteractive then
				isWall = true
			end
		end
		
		if isWall then
			if not botControl.touchingWall then
				botControl.touchingWall = true
				botControl.wallTouchStart = tick()
				botControl.collisionCount = botControl.collisionCount + 1
				botControl.coinsCollected = math.max(0, botControl.coinsCollected - CONFIG.COIN_LOSS_PER_HIT)
				botControl.score = botControl.score - 10
				botControl.lastWallHit = tick()
				botControl.failedMoves = botControl.failedMoves + 1
				
				print(string.format("💥 Collision at (%.1f, %.1f, %.1f) - Lost %d coins!", 
					rootPart.Position.X, rootPart.Position.Y, rootPart.Position.Z,
					CONFIG.COIN_LOSS_PER_HIT))
			end
		end
	end)
	
	rootPart.TouchEnded:Connect(function(hit)
		task.wait(0.1)
		local touching = rootPart:GetTouchingParts()
		local stillTouchingWall = false
		
		for _, part in ipairs(touching) do
			for _, tag in ipairs(OBSTACLE_TAGS) do
				if part:HasTag(tag) or part.Name:find("Wall") or part.Name:find("Barrier") then
					stillTouchingWall = true
					break
				end
			end
		end
		
		if not stillTouchingWall then
			botControl.touchingWall = false
		end
	end)
end

setupCollisionDetection()

-- ================= RAYCAST SETUP =================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	rayParams.FilterDescendantsInstances = {character}
end
updateRaycastFilter()

-- ================= POSITION TRACKING SYSTEM =================
local function updatePositionHistory()
	botControl.currentPosition = rootPart.Position
	
	-- Add to history
	table.insert(botControl.positionHistory, 1, {
		position = botControl.currentPosition,
		time = tick(),
		coins = botControl.coinsCollected
	})
	
	-- Keep only recent history
	if #botControl.positionHistory > CONFIG.MEMORY_SIZE then
		table.remove(botControl.positionHistory, #botControl.positionHistory)
	end
	
	-- Mark as visited (rounded to grid for efficiency)
	local gridPos = Vector3.new(
		math.floor(botControl.currentPosition.X / 5) * 5,
		math.floor(botControl.currentPosition.Y / 5) * 5,
		math.floor(botControl.currentPosition.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	botControl.visitedPositions[key] = (botControl.visitedPositions[key] or 0) + 1
end

local function hasVisitedRecently(position)
	local gridPos = Vector3.new(
		math.floor(position.X / 5) * 5,
		math.floor(position.Y / 5) * 5,
		math.floor(position.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	return (botControl.visitedPositions[key] or 0) > 3
end

local function getRelativePosition(worldPos)
	-- Convert world position to relative position from bot
	local relative = worldPos - botControl.currentPosition
	return relative
end

-- ================= ADVANCED LIDAR SYSTEM =================
local function identifyObjectType(hit)
	-- Check interactive objects first
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			return tag
		end
	end
	
	-- Check obstacles
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
			return "Obstacle"
		end
	end
	
	-- Unknown solid object
	if hit:IsA("BasePart") and hit.CanCollide then
		return "Unknown"
	end
	
	return "Empty"
end

local function performUltraLiDARScan()
	-- Reset zones
	for _, zone in pairs(obstacleZones) do
		zone.distance = CONFIG.RAYCAST_DISTANCE
		zone.threat = 0
		zone.objectPos = nil
		zone.objectType = "none"
	end
	
	lidarSystem.beams = {}
	lidarSystem.obstacles = {}
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	
	-- 11 beams with precise angles
	local beamAngles = {
		-1.5, -1.2, -0.9,  -- Far left
		-0.7, -0.35,       -- Left
		0,                 -- Center
		0.35, 0.7,         -- Right
		0.9, 1.2, 1.5      -- Far right
	}
	
	local beamNames = {
		"FarLeft3", "FarLeft2", "FarLeft1",
		"Left2", "Left1",
		"Center",
		"Right1", "Right2",
		"FarRight1", "FarRight2", "FarRight3"
	}
	
	local zoneMapping = {
		[1] = "farLeft", [2] = "farLeft", [3] = "farLeft",
		[4] = "left", [5] = "centerLeft",
		[6] = "center",
		[7] = "centerRight", [8] = "right",
		[9] = "farRight", [10] = "farRight", [11] = "farRight"
	}
	
	local distances = {}
	local interactables = {}
	
	for i, angle in ipairs(beamAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * CONFIG.RAYCAST_DISTANCE
		local rayResult = Workspace:Raycast(origin, rayDirection, rayParams)
		
		local beamData = {
			name = beamNames[i],
			angle = math.deg(angle),
			direction = rayDirection.Unit,
			distance = CONFIG.RAYCAST_DISTANCE,
			hitPosition = origin + rayDirection,
			objectType = "none",
			objectName = "none",
			relativePosition = Vector3.zero
		}
		
		if rayResult then
			beamData.distance = rayResult.Distance
			beamData.hitPosition = rayResult.Position
			beamData.objectType = identifyObjectType(rayResult.Instance)
			beamData.objectName = rayResult.Instance.Name
			beamData.relativePosition = getRelativePosition(rayResult.Position)
			
			distances[i] = rayResult.Distance
			
			-- Update zone
			local zone = zoneMapping[i]
			if beamData.distance < obstacleZones[zone].distance then
				obstacleZones[zone].distance = beamData.distance
				obstacleZones[zone].objectPos = rayResult.Position
				obstacleZones[zone].objectType = beamData.objectType
				
				-- Calculate threat level
				if beamData.distance < CONFIG.DANGER_DISTANCE then
					obstacleZones[zone].threat = 1.0
				elseif beamData.distance < CONFIG.SAFE_DISTANCE then
					obstacleZones[zone].threat = 0.5
				else
					obstacleZones[zone].threat = 0.1
				end
			end
			
			-- Store obstacle data
			if beamData.objectType ~= "none" and beamData.objectType ~= "Empty" then
				table.insert(lidarSystem.obstacles, {
					position = rayResult.Position,
					worldPosition = rayResult.Position,
					relativePosition = beamData.relativePosition,
					distance = beamData.distance,
					type = beamData.objectType,
					name = beamData.objectName,
					angle = beamData.angle,
					beam = beamNames[i]
				})
			end
			
			-- Check for interactables
			if beamData.objectType ~= "Obstacle" and beamData.objectType ~= "Unknown" and beamData.distance < CONFIG.INTERACTION_DISTANCE then
				table.insert(interactables, {
					object = rayResult.Instance,
					position = rayResult.Position,
					distance = beamData.distance,
					type = beamData.objectType
				})
			end
		else
			distances[i] = CONFIG.RAYCAST_DISTANCE
		end
		
		lidarSystem.beams[i] = beamData
	end
	
	-- Find nearest obstacle
	lidarSystem.nearestObstacle = nil
	local minDist = math.huge
	for _, obstacle in ipairs(lidarSystem.obstacles) do
		if obstacle.distance < minDist then
			minDist = obstacle.distance
			lidarSystem.nearestObstacle = obstacle
		end
	end
	
	-- Find closest interactable
	local closestInteractable = nil
	minDist = math.huge
	for _, obj in ipairs(interactables) do
		if obj.distance < minDist then
			minDist = obj.distance
			closestInteractable = obj
		end
	end
	
	return {
		distances = distances,
		minDistance = math.min(table.unpack(distances)),
		maxDistance = math.max(table.unpack(distances)),
		closestInteractable = closestInteractable,
		obstacleCount = #lidarSystem.obstacles
	}
end

-- ================= ULTRA-ADVANCED NEURAL NETWORK =================
local neuralNet = {
	inputLayer = {},
	hiddenLayer1 = {},
	hiddenLayer2 = {},
	outputLayer = {},
	learningRate = CONFIG.LEARNING_RATE
}

local function initializeUltraNetwork()
	-- Input: 11 beams + 7 zones + 10 internal states + 6 position data = 34 inputs
	for i = 1, 34 do
		neuralNet.inputLayer[i] = math.random() * 0.6 - 0.3
	end
	
	-- Hidden layer 1: 20 neurons
	for i = 1, 20 do
		neuralNet.hiddenLayer1[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 34 do
			neuralNet.hiddenLayer1[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Hidden layer 2: 15 neurons
	for i = 1, 15 do
		neuralNet.hiddenLayer2[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 20 do
			neuralNet.hiddenLayer2[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Output: 4 outputs (turn, speed, interact, explore)
	for i = 1, 4 do
		neuralNet.outputLayer[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1
		}
		for j = 1, 15 do
			neuralNet.outputLayer[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
end

initializeUltraNetwork()

local function sigmoid(x)
	return 1 / (1 + math.exp(-math.clamp(x, -10, 10)))
end

local function relu(x)
	return math.max(0, x)
end

local function leakyRelu(x)
	return x > 0 and x or x * 0.01
end

-- ================= INTERNAL STATE =================
local function getAdvancedInternalState()
	local velocity = rootPart.AssemblyLinearVelocity
	local successRate = botControl.successfulMoves / math.max(1, botControl.successfulMoves + botControl.failedMoves)
	
	return {
		health = humanoid.Health / humanoid.MaxHealth,
		speed = velocity.Magnitude / CONFIG.MOVEMENT_SPEED,
		confidence = botControl.confidence,
		coinsNormalized = math.clamp(botControl.coinsCollected / 50, 0, 1),
		wallTouching = botControl.touchingWall and 1 or 0,
		successRate = successRate,
		explorationFactor = math.clamp(#botControl.positionHistory / CONFIG.MEMORY_SIZE, 0, 1),
		timeSinceHit = math.clamp((tick() - botControl.lastWallHit) / 10, 0, 1),
		distanceNormalized = math.clamp(botControl.distanceTraveled / 1000, 0, 1),
		interactionRate = math.clamp(botControl.interactionsSuccessful / 20, 0, 1)
	}
end

local function getPositionData()
	local nearestObstacle = lidarSystem.nearestObstacle
	return {
		myX = math.clamp(botControl.currentPosition.X / 100, -1, 1),
		myY = math.clamp(botControl.currentPosition.Y / 100, -1, 1),
		myZ = math.clamp(botControl.currentPosition.Z / 100, -1, 1),
		nearestObstacleX = nearestObstacle and math.clamp(nearestObstacle.relativePosition.X / 20, -1, 1) or 0,
		nearestObstacleY = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Y / 20, -1, 1) or 0,
		nearestObstacleZ = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Z / 20, -1, 1) or 0
	}
end

-- ================= ULTRA-SMART DECISION MAKING =================
local function ultraNeuralDecision(lidarData, internalState, positionData)
	-- Prepare 34 inputs
	local inputs = {}
	
	-- 11 beam distances (normalized)
	for i = 1, 11 do
		inputs[i] = 1 - math.clamp(lidarData.distances[i] / CONFIG.RAYCAST_DISTANCE, 0, 1)
	end
	
	-- 7 zone threats
	local zoneOrder = {"farLeft", "left", "centerLeft", "center", "centerRight", "right", "farRight"}
	for i, zoneName in ipairs(zoneOrder) do
		inputs[11 + i] = obstacleZones[zoneName].threat
	end
	
	-- 10 internal states
	inputs[19] = internalState.health
	inputs[20] = internalState.speed
	inputs[21] = internalState.confidence
	inputs[22] = internalState.coinsNormalized
	inputs[23] = internalState.wallTouching
	inputs[24] = internalState.successRate
	inputs[25] = internalState.explorationFactor
	inputs[26] = internalState.timeSinceHit
	inputs[27] = internalState.distanceNormalized
	inputs[28] = internalState.interactionRate
	
	-- 6 position data
	inputs[29] = positionData.myX
	inputs[30] = positionData.myY
	inputs[31] = positionData.myZ
	inputs[32] = positionData.nearestObstacleX
	inputs[33] = positionData.nearestObstacleY
	inputs[34] = positionData.nearestObstacleZ
	
	-- Forward pass - Layer 1
	for i = 1, 20 do
		local sum = neuralNet.hiddenLayer1[i].bias
		for j = 1, 34 do
			sum = sum + inputs[j] * neuralNet.hiddenLayer1[i].weights[j]
		end
		neuralNet.hiddenLayer1[i].activation = leakyRelu(sum)
	end
	
	-- Forward pass - Layer 2
	for i = 1, 15 do
		local sum = neuralNet.hiddenLayer2[i].bias
		for j = 1, 20 do
			sum = sum + neuralNet.hiddenLayer1[j].activation * neuralNet.hiddenLayer2[i].weights[j]
		end
		neuralNet.hiddenLayer2[i].activation = leakyRelu(sum)
	end
	
	-- Output layer
	local outputs = {}
	for i = 1, 4 do
		local sum = neuralNet.outputLayer[i].bias
		for j = 1, 15 do
			sum = sum + neuralNet.hiddenLayer2[j].activation * neuralNet.outputLayer[i].weights[j]
		end
		outputs[i] = math.tanh(sum)
	end
	
	return {
		turnDirection = outputs[1],
		forwardSpeed = math.clamp((outputs[2] + 1) / 2, 0.2, 1),
		shouldInteract = outputs[3] > 0.2,
		shouldExplore = outputs[4] > 0.3
	}
end

-- ================= INTERACTION SYSTEM =================
local function attemptInteraction(interactable)
	if not interactable then return false end
	
	local obj = interactable.object
	local objType = interactable.type
	
	if objType == "Coin" or objType == "Collectible" then
		if obj:IsA("BasePart") and (rootPart.Position - obj.Position).Magnitude < 5 then
			botControl.coinsCollected = botControl.coinsCollected + 1
			botControl.score = botControl.score + 10
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	elseif objType == "Button" or objType == "Door" then
		if obj:FindFirstChild("ClickDetector") then
			fireclickdetector(obj.ClickDetector)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		elseif obj:FindFirstChild("ProximityPrompt") then
			fireproximityprompt(obj.ProximityPrompt)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	end
	
	return false
end

-- ================= MOVEMENT TRACKING =================
local function getMovementSpeed()
	if not botControl.lastPosition then
		botControl.lastPosition = rootPart.Position
		return 0
	end
	
	local currentPos = rootPart.Position
	local distance = (currentPos - botControl.lastPosition).Magnitude
	botControl.lastPosition = currentPos
	
	return distance
end

local function isStuck()
	return (tick() - botControl.lastMovementTime) > CONFIG.STUCK_THRESHOLD
end

-- ================= ADVANCED LEARNING =================
local function updateUltraNetwork(reward)
	-- More sophisticated weight updates
	local learningFactor = neuralNet.learningRate * reward * 0.05
	
	-- Update hidden layer 1
	for i = 1, 20 do
		for j = 1, 34 do
			local gradient = learningFactor * neuralNet.hiddenLayer1[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer1[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer1[i].weights[j] + gradient,
				-3, 3
			)
		end
		neuralNet.hiddenLayer1[i].bias = math.clamp(
			neuralNet.hiddenLayer1[i].bias + learningFactor * 0.1,
			-1, 1
		)
	end
	
	-- Update hidden layer 2
	for i = 1, 15 do
		for j = 1, 20 do
			local gradient = learningFactor * neuralNet.hiddenLayer2[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer2[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer2[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
	
	-- Update output layer
	for i = 1, 4 do
		for j = 1, 15 do
			local gradient = learningFactor * (math.random() * 2 - 1)
			neuralNet.outputLayer[i].weights[j] = math.clamp(
				neuralNet.outputLayer[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
end

local function evaluateUltraPerformance(lidarData, movementSpeed, interactionSuccess)
	local reward = 0
	
	-- Wall touching penalty
	if botControl.touchingWall then
		local touchDuration = tick() - botControl.wallTouchStart
		if touchDuration > 0.5 then
			local coinsToLose = math.floor(touchDuration * CONFIG.COIN_LOSS_PER_TOUCH)
			botControl.coinsCollected = math.max(0, botControl.coinsCollected - coinsToLose)
			botControl.wallTouchStart = tick()
		end
		reward = reward - 15
	end
	
	-- Movement rewards
	if movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		reward = reward + 2
		botControl.lastMovementTime = tick()
		botControl.successfulMoves = botControl.successfulMoves + 1
	else
		reward = reward - 3
		botControl.failedMoves = botControl.failedMoves + 1
	end
	
	-- Distance-based rewards
	local centerDist = obstacleZones.center.distance
	if centerDist < CONFIG.DANGER_DISTANCE then
		reward = reward - 8
	elseif centerDist < CONFIG.SAFE_DISTANCE then
		reward = reward - 3
	elseif centerDist > CONFIG.SAFE_DISTANCE * 1.5 then
		reward = reward + 3
	end
	
	-- Side awareness
	if obstacleZones.left.threat > 0.5 or obstacleZones.right.threat > 0.5 then
		reward = reward - 2
	end
	
	-- Interaction rewards
	if interactionSuccess then
		reward = reward + 12
	end
	
	-- Exploration bonus
	if not hasVisitedRecently(botControl.currentPosition) then
		reward = reward + 1
	end
	
	-- Stuck penalty
	if isStuck() then
		reward = reward - 6
	end
	
	-- Update confidence
	botControl.confidence = math.clamp(botControl.confidence + reward * 0.005, 0.3, 1)
	
	-- Learn
	updateUltraNetwork(reward)
	
	return reward
end

-- ================= CHARACTER LIFECYCLE =================
local function setupCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	
	humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
	humanoid.AutoRotate = false
	humanoid.JumpPower = 0
	botControl.lastPosition = rootPart.Position
	botControl.currentPosition = rootPart.Position
	botControl.touchingWall = false
	
	updateRaycastFilter()
	setupCollisionDetection()
	
	if botControl.enabled then
		blockPlayerInput()
	end
	
	print("🔄 Character respawned")
end

player.CharacterAdded:Connect(setupCharacter)

humanoid.HealthChanged:Connect(function(health)
	botControl.health = health
end)

-- ================= MAIN ULTRA-SMART CONTROL LOOP =================
local lastUpdate = tick()
RunService.Heartbeat:Connect(function(deltaTime)
	if not botControl.enabled then return end
	if not rootPart or not rootPart.Parent then return end
	if not humanoid or humanoid.Health <= 0 then return end-- =========================================
-- ULTRA-SMART NEURAL AI - Full Spatial Awareness
-- LiDAR with coordinates, position tracking, 10x intelligence
-- =========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- ================= CONFIGURATION =================
local CONFIG = {
	MOVEMENT_SPEED = 18,
	TURN_SPEED = 0.2,
	SAFE_DISTANCE = 6,
	DANGER_DISTANCE = 3,
	RAYCAST_DISTANCE = 25,
	LEARNING_RATE = 0.15,
	EXPLORATION_RATE = 0.05,
	DIRECTION_SMOOTHING = 0.28,
	MIN_MOVEMENT_SPEED = 2,
	STUCK_THRESHOLD = 2.5,
	INTERACTION_DISTANCE = 8,
	DECISION_COOLDOWN = 0.4,
	COIN_LOSS_PER_HIT = 5,
	COIN_LOSS_PER_TOUCH = 2,
	MEMORY_SIZE = 50 -- Remember last 50 positions
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle"}

-- ================= ADVANCED BOT STATE =================
local botControl = {
	enabled = true,
	confidence = 1.0,
	moveDirection = Vector3.new(0, 0, 1),
	status = "INITIALIZING",
	score = 0,
	coinsCollected = 0,
	distanceTraveled = 0,
	lastPosition = nil,
	lastMovementTime = tick(),
	lastDecisionTime = tick(),
	stuckCounter = 0,
	health = 100,
	touchingWall = false,
	lastWallHit = 0,
	wallTouchStart = 0,
	collisionCount = 0,
	
	-- Spatial awareness
	currentPosition = Vector3.zero,
	targetPosition = nil,
	positionHistory = {},
	visitedPositions = {},
	
	-- Performance metrics
	successfulMoves = 0,
	failedMoves = 0,
	interactionsSuccessful = 0
}

-- ================= LIDAR DATA STRUCTURE =================
local lidarSystem = {
	beams = {}, -- Stores all beam data
	obstacles = {}, -- Detected obstacles with full info
	nearestObstacle = nil,
	safeDirections = {},
	dangerDirections = {}
}

-- Obstacle awareness zones
local obstacleZones = {
	farLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	left = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	center = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	right = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	farRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"}
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position
botControl.health = humanoid.Health

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 ULTRA-SMART AI - FULL SPATIAL AWARENESS")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
humanoid.JumpPower = 0
humanoid.AutoRotate = false

local function blockPlayerInput()
	UserInputService.ModalEnabled = true
end

local function restorePlayerInput()
	UserInputService.ModalEnabled = false
	humanoid.AutoRotate = true
	humanoid.JumpPower = 50
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.P then
		botControl.enabled = not botControl.enabled
		if botControl.enabled then
			print("🤖 AI CONTROL: ENABLED")
			blockPlayerInput()
		else
			print("👤 PLAYER CONTROL: ENABLED")
			restorePlayerInput()
			humanoid:Move(Vector3.zero)
		end
	end
end)

blockPlayerInput()

-- ================= COLLISION DETECTION =================
local function setupCollisionDetection()
	rootPart.Touched:Connect(function(hit)
		if not botControl.enabled then return end
		
		local isWall = false
		for _, tag in ipairs(OBSTACLE_TAGS) do
			if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
				isWall = true
				break
			end
		end
		
		if not isWall and hit:IsA("BasePart") and hit.CanCollide then
			local isInteractive = false
			for _, tag in ipairs(INTERACTIVE_TAGS) do
				if hit:HasTag(tag) or hit.Name:find(tag) then
					isInteractive = true
					break
				end
			end
			if not isInteractive then
				isWall = true
			end
		end
		
		if isWall then
			if not botControl.touchingWall then
				botControl.touchingWall = true
				botControl.wallTouchStart = tick()
				botControl.collisionCount = botControl.collisionCount + 1
				botControl.coinsCollected = math.max(0, botControl.coinsCollected - CONFIG.COIN_LOSS_PER_HIT)
				botControl.score = botControl.score - 10
				botControl.lastWallHit = tick()
				botControl.failedMoves = botControl.failedMoves + 1
				
				print(string.format("💥 Collision at (%.1f, %.1f, %.1f) - Lost %d coins!", 
					rootPart.Position.X, rootPart.Position.Y, rootPart.Position.Z,
					CONFIG.COIN_LOSS_PER_HIT))
			end
		end
	end)
	
	rootPart.TouchEnded:Connect(function(hit)
		task.wait(0.1)
		local touching = rootPart:GetTouchingParts()
		local stillTouchingWall = false
		
		for _, part in ipairs(touching) do
			for _, tag in ipairs(OBSTACLE_TAGS) do
				if part:HasTag(tag) or part.Name:find("Wall") or part.Name:find("Barrier") then
					stillTouchingWall = true
					break
				end
			end
		end
		
		if not stillTouchingWall then
			botControl.touchingWall = false
		end
	end)
end

setupCollisionDetection()

-- ================= RAYCAST SETUP =================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	rayParams.FilterDescendantsInstances = {character}
end
updateRaycastFilter()

-- ================= POSITION TRACKING SYSTEM =================
local function updatePositionHistory()
	botControl.currentPosition = rootPart.Position
	
	-- Add to history
	table.insert(botControl.positionHistory, 1, {
		position = botControl.currentPosition,
		time = tick(),
		coins = botControl.coinsCollected
	})
	
	-- Keep only recent history
	if #botControl.positionHistory > CONFIG.MEMORY_SIZE then
		table.remove(botControl.positionHistory, #botControl.positionHistory)
	end
	
	-- Mark as visited (rounded to grid for efficiency)
	local gridPos = Vector3.new(
		math.floor(botControl.currentPosition.X / 5) * 5,
		math.floor(botControl.currentPosition.Y / 5) * 5,
		math.floor(botControl.currentPosition.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	botControl.visitedPositions[key] = (botControl.visitedPositions[key] or 0) + 1
end

local function hasVisitedRecently(position)
	local gridPos = Vector3.new(
		math.floor(position.X / 5) * 5,
		math.floor(position.Y / 5) * 5,
		math.floor(position.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	return (botControl.visitedPositions[key] or 0) > 3
end

local function getRelativePosition(worldPos)
	-- Convert world position to relative position from bot
	local relative = worldPos - botControl.currentPosition
	return relative
end

-- ================= ADVANCED LIDAR SYSTEM =================
local function identifyObjectType(hit)
	-- Check interactive objects first
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			return tag
		end
	end
	
	-- Check obstacles
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
			return "Obstacle"
		end
	end
	
	-- Unknown solid object
	if hit:IsA("BasePart") and hit.CanCollide then
		return "Unknown"
	end
	
	return "Empty"
end

local function performUltraLiDARScan()
	-- Reset zones
	for _, zone in pairs(obstacleZones) do
		zone.distance = CONFIG.RAYCAST_DISTANCE
		zone.threat = 0
		zone.objectPos = nil
		zone.objectType = "none"
	end
	
	lidarSystem.beams = {}
	lidarSystem.obstacles = {}
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	
	-- 11 beams with precise angles
	local beamAngles = {
		-1.5, -1.2, -0.9,  -- Far left
		-0.7, -0.35,       -- Left
		0,                 -- Center
		0.35, 0.7,         -- Right
		0.9, 1.2, 1.5      -- Far right
	}
	
	local beamNames = {
		"FarLeft3", "FarLeft2", "FarLeft1",
		"Left2", "Left1",
		"Center",
		"Right1", "Right2",
		"FarRight1", "FarRight2", "FarRight3"
	}
	
	local zoneMapping = {
		[1] = "farLeft", [2] = "farLeft", [3] = "farLeft",
		[4] = "left", [5] = "centerLeft",
		[6] = "center",
		[7] = "centerRight", [8] = "right",
		[9] = "farRight", [10] = "farRight", [11] = "farRight"
	}
	
	local distances = {}
	local interactables = {}
	
	for i, angle in ipairs(beamAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * CONFIG.RAYCAST_DISTANCE
		local rayResult = Workspace:Raycast(origin, rayDirection, rayParams)
		
		local beamData = {
			name = beamNames[i],
			angle = math.deg(angle),
			direction = rayDirection.Unit,
			distance = CONFIG.RAYCAST_DISTANCE,
			hitPosition = origin + rayDirection,
			objectType = "none",
			objectName = "none",
			relativePosition = Vector3.zero
		}
		
		if rayResult then
			beamData.distance = rayResult.Distance
			beamData.hitPosition = rayResult.Position
			beamData.objectType = identifyObjectType(rayResult.Instance)
			beamData.objectName = rayResult.Instance.Name
			beamData.relativePosition = getRelativePosition(rayResult.Position)
			
			distances[i] = rayResult.Distance
			
			-- Update zone
			local zone = zoneMapping[i]
			if beamData.distance < obstacleZones[zone].distance then
				obstacleZones[zone].distance = beamData.distance
				obstacleZones[zone].objectPos = rayResult.Position
				obstacleZones[zone].objectType = beamData.objectType
				
				-- Calculate threat level
				if beamData.distance < CONFIG.DANGER_DISTANCE then
					obstacleZones[zone].threat = 1.0
				elseif beamData.distance < CONFIG.SAFE_DISTANCE then
					obstacleZones[zone].threat = 0.5
				else
					obstacleZones[zone].threat = 0.1
				end
			end
			
			-- Store obstacle data
			if beamData.objectType ~= "none" and beamData.objectType ~= "Empty" then
				table.insert(lidarSystem.obstacles, {
					position = rayResult.Position,
					worldPosition = rayResult.Position,
					relativePosition = beamData.relativePosition,
					distance = beamData.distance,
					type = beamData.objectType,
					name = beamData.objectName,
					angle = beamData.angle,
					beam = beamNames[i]
				})
			end
			
			-- Check for interactables
			if beamData.objectType ~= "Obstacle" and beamData.objectType ~= "Unknown" and beamData.distance < CONFIG.INTERACTION_DISTANCE then
				table.insert(interactables, {
					object = rayResult.Instance,
					position = rayResult.Position,
					distance = beamData.distance,
					type = beamData.objectType
				})
			end
		else
			distances[i] = CONFIG.RAYCAST_DISTANCE
		end
		
		lidarSystem.beams[i] = beamData
	end
	
	-- Find nearest obstacle
	lidarSystem.nearestObstacle = nil
	local minDist = math.huge
	for _, obstacle in ipairs(lidarSystem.obstacles) do
		if obstacle.distance < minDist then
			minDist = obstacle.distance
			lidarSystem.nearestObstacle = obstacle
		end
	end
	
	-- Find closest interactable
	local closestInteractable = nil
	minDist = math.huge
	for _, obj in ipairs(interactables) do
		if obj.distance < minDist then
			minDist = obj.distance
			closestInteractable = obj
		end
	end
	
	return {
		distances = distances,
		minDistance = math.min(table.unpack(distances)),
		maxDistance = math.max(table.unpack(distances)),
		closestInteractable = closestInteractable,
		obstacleCount = #lidarSystem.obstacles
	}
end

-- ================= ULTRA-ADVANCED NEURAL NETWORK =================
local neuralNet = {
	inputLayer = {},
	hiddenLayer1 = {},
	hiddenLayer2 = {},
	outputLayer = {},
	learningRate = CONFIG.LEARNING_RATE
}

local function initializeUltraNetwork()
	-- Input: 11 beams + 7 zones + 10 internal states + 6 position data = 34 inputs
	for i = 1, 34 do
		neuralNet.inputLayer[i] = math.random() * 0.6 - 0.3
	end
	
	-- Hidden layer 1: 20 neurons
	for i = 1, 20 do
		neuralNet.hiddenLayer1[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 34 do
			neuralNet.hiddenLayer1[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Hidden layer 2: 15 neurons
	for i = 1, 15 do
		neuralNet.hiddenLayer2[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 20 do
			neuralNet.hiddenLayer2[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Output: 4 outputs (turn, speed, interact, explore)
	for i = 1, 4 do
		neuralNet.outputLayer[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1
		}
		for j = 1, 15 do
			neuralNet.outputLayer[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
end

initializeUltraNetwork()

local function sigmoid(x)
	return 1 / (1 + math.exp(-math.clamp(x, -10, 10)))
end

local function relu(x)
	return math.max(0, x)
end

local function leakyRelu(x)
	return x > 0 and x or x * 0.01
end

-- ================= INTERNAL STATE =================
local function getAdvancedInternalState()
	local velocity = rootPart.AssemblyLinearVelocity
	local successRate = botControl.successfulMoves / math.max(1, botControl.successfulMoves + botControl.failedMoves)
	
	return {
		health = humanoid.Health / humanoid.MaxHealth,
		speed = velocity.Magnitude / CONFIG.MOVEMENT_SPEED,
		confidence = botControl.confidence,
		coinsNormalized = math.clamp(botControl.coinsCollected / 50, 0, 1),
		wallTouching = botControl.touchingWall and 1 or 0,
		successRate = successRate,
		explorationFactor = math.clamp(#botControl.positionHistory / CONFIG.MEMORY_SIZE, 0, 1),
		timeSinceHit = math.clamp((tick() - botControl.lastWallHit) / 10, 0, 1),
		distanceNormalized = math.clamp(botControl.distanceTraveled / 1000, 0, 1),
		interactionRate = math.clamp(botControl.interactionsSuccessful / 20, 0, 1)
	}
end

local function getPositionData()
	local nearestObstacle = lidarSystem.nearestObstacle
	return {
		myX = math.clamp(botControl.currentPosition.X / 100, -1, 1),
		myY = math.clamp(botControl.currentPosition.Y / 100, -1, 1),
		myZ = math.clamp(botControl.currentPosition.Z / 100, -1, 1),
		nearestObstacleX = nearestObstacle and math.clamp(nearestObstacle.relativePosition.X / 20, -1, 1) or 0,
		nearestObstacleY = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Y / 20, -1, 1) or 0,
		nearestObstacleZ = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Z / 20, -1, 1) or 0
	}
end

-- ================= ULTRA-SMART DECISION MAKING =================
local function ultraNeuralDecision(lidarData, internalState, positionData)
	-- Prepare 34 inputs
	local inputs = {}
	
	-- 11 beam distances (normalized)
	for i = 1, 11 do
		inputs[i] = 1 - math.clamp(lidarData.distances[i] / CONFIG.RAYCAST_DISTANCE, 0, 1)
	end
	
	-- 7 zone threats
	local zoneOrder = {"farLeft", "left", "centerLeft", "center", "centerRight", "right", "farRight"}
	for i, zoneName in ipairs(zoneOrder) do
		inputs[11 + i] = obstacleZones[zoneName].threat
	end
	
	-- 10 internal states
	inputs[19] = internalState.health
	inputs[20] = internalState.speed
	inputs[21] = internalState.confidence
	inputs[22] = internalState.coinsNormalized
	inputs[23] = internalState.wallTouching
	inputs[24] = internalState.successRate
	inputs[25] = internalState.explorationFactor
	inputs[26] = internalState.timeSinceHit
	inputs[27] = internalState.distanceNormalized
	inputs[28] = internalState.interactionRate
	
	-- 6 position data
	inputs[29] = positionData.myX
	inputs[30] = positionData.myY
	inputs[31] = positionData.myZ
	inputs[32] = positionData.nearestObstacleX
	inputs[33] = positionData.nearestObstacleY
	inputs[34] = positionData.nearestObstacleZ
	
	-- Forward pass - Layer 1
	for i = 1, 20 do
		local sum = neuralNet.hiddenLayer1[i].bias
		for j = 1, 34 do
			sum = sum + inputs[j] * neuralNet.hiddenLayer1[i].weights[j]
		end
		neuralNet.hiddenLayer1[i].activation = leakyRelu(sum)
	end
	
	-- Forward pass - Layer 2
	for i = 1, 15 do
		local sum = neuralNet.hiddenLayer2[i].bias
		for j = 1, 20 do
			sum = sum + neuralNet.hiddenLayer1[j].activation * neuralNet.hiddenLayer2[i].weights[j]
		end
		neuralNet.hiddenLayer2[i].activation = leakyRelu(sum)
	end
	
	-- Output layer
	local outputs = {}
	for i = 1, 4 do
		local sum = neuralNet.outputLayer[i].bias
		for j = 1, 15 do
			sum = sum + neuralNet.hiddenLayer2[j].activation * neuralNet.outputLayer[i].weights[j]
		end
		outputs[i] = math.tanh(sum)
	end
	
	return {
		turnDirection = outputs[1],
		forwardSpeed = math.clamp((outputs[2] + 1) / 2, 0.2, 1),
		shouldInteract = outputs[3] > 0.2,
		shouldExplore = outputs[4] > 0.3
	}
end

-- ================= INTERACTION SYSTEM =================
local function attemptInteraction(interactable)
	if not interactable then return false end
	
	local obj = interactable.object
	local objType = interactable.type
	
	if objType == "Coin" or objType == "Collectible" then
		if obj:IsA("BasePart") and (rootPart.Position - obj.Position).Magnitude < 5 then
			botControl.coinsCollected = botControl.coinsCollected + 1
			botControl.score = botControl.score + 10
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	elseif objType == "Button" or objType == "Door" then
		if obj:FindFirstChild("ClickDetector") then
			fireclickdetector(obj.ClickDetector)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		elseif obj:FindFirstChild("ProximityPrompt") then
			fireproximityprompt(obj.ProximityPrompt)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	end
	
	return false
end

-- ================= MOVEMENT TRACKING =================
local function getMovementSpeed()
	if not botControl.lastPosition then
		botControl.lastPosition = rootPart.Position
		return 0
	end
	
	local currentPos = rootPart.Position
	local distance = (currentPos - botControl.lastPosition).Magnitude
	botControl.lastPosition = currentPos
	
	return distance
end

local function isStuck()
	return (tick() - botControl.lastMovementTime) > CONFIG.STUCK_THRESHOLD
end

-- ================= ADVANCED LEARNING =================
local function updateUltraNetwork(reward)
	-- More sophisticated weight updates
	local learningFactor = neuralNet.learningRate * reward * 0.05
	
	-- Update hidden layer 1
	for i = 1, 20 do
		for j = 1, 34 do
			local gradient = learningFactor * neuralNet.hiddenLayer1[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer1[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer1[i].weights[j] + gradient,
				-3, 3
			)
		end
		neuralNet.hiddenLayer1[i].bias = math.clamp(
			neuralNet.hiddenLayer1[i].bias + learningFactor * 0.1,
			-1, 1
		)
	end
	
	-- Update hidden layer 2
	for i = 1, 15 do
		for j = 1, 20 do
			local gradient = learningFactor * neuralNet.hiddenLayer2[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer2[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer2[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
	
	-- Update output layer
	for i = 1, 4 do
		for j = 1, 15 do
			local gradient = learningFactor * (math.random() * 2 - 1)
			neuralNet.outputLayer[i].weights[j] = math.clamp(
				neuralNet.outputLayer[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
end

local function evaluateUltraPerformance(lidarData, movementSpeed, interactionSuccess)
	local reward = 0
	
	-- Wall touching penalty
	if botControl.touchingWall then
		local touchDuration = tick() - botControl.wallTouchStart
		if touchDuration > 0.5 then
			local coinsToLose = math.floor(touchDuration * CONFIG.COIN_LOSS_PER_TOUCH)
			botControl.coinsCollected = math.max(0, botControl.coinsCollected - coinsToLose)
			botControl.wallTouchStart = tick()
		end
		reward = reward - 15
	end
	
	-- Movement rewards
	if movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		reward = reward + 2
		botControl.lastMovementTime = tick()
		botControl.successfulMoves = botControl.successfulMoves + 1
	else
		reward = reward - 3
		botControl.failedMoves = botControl.failedMoves + 1
	end
	
	-- Distance-based rewards
	local centerDist = obstacleZones.center.distance
	if centerDist < CONFIG.DANGER_DISTANCE then
		reward = reward - 8
	elseif centerDist < CONFIG.SAFE_DISTANCE then
		reward = reward - 3
	elseif centerDist > CONFIG.SAFE_DISTANCE * 1.5 then
		reward = reward + 3
	end
	
	-- Side awareness
	if obstacleZones.left.threat > 0.5 or obstacleZones.right.threat > 0.5 then
		reward = reward - 2
	end
	
	-- Interaction rewards
	if interactionSuccess then
		reward = reward + 12
	end
	
	-- Exploration bonus
	if not hasVisitedRecently(botControl.currentPosition) then
		reward = reward + 1
	end
	
	-- Stuck penalty
	if isStuck() then
		reward = reward - 6
	end
	
	-- Update confidence
	botControl.confidence = math.clamp(botControl.confidence + reward * 0.005, 0.3, 1)
	
	-- Learn
	updateUltraNetwork(reward)
	
	return reward
end

-- ================= CHARACTER LIFECYCLE =================
local function setupCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	
	humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
	humanoid.AutoRotate = false
	humanoid.JumpPower = 0
	botControl.lastPosition = rootPart.Position
	botControl.currentPosition = rootPart.Position
	botControl.touchingWall = false
	
	updateRaycastFilter()
	setupCollisionDetection()
	
	if botControl.enabled then
		blockPlayerInput()
	end
	
	print("🔄 Character respawned")
end

player.CharacterAdded:Connect(setupCharacter)

humanoid.HealthChanged:Connect(function(health)
	botControl.health = health
end)

-- ================= MAIN ULTRA-SMART CONTROL LOOP =================
local lastUpdate = tick()
RunService.Heartbeat:Connect(function(deltaTime)
	if not botControl.enabled then return end
	if not rootPart or not rootPart.Pare-- =========================================
-- ULTRA-SMART NEURAL AI - Full Spatial Awareness
-- LiDAR with coordinates, position tracking, 10x intelligence
-- =========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- ================= CONFIGURATION =================
local CONFIG = {
	MOVEMENT_SPEED = 18,
	TURN_SPEED = 0.2,
	SAFE_DISTANCE = 6,
	DANGER_DISTANCE = 3,
	RAYCAST_DISTANCE = 25,
	LEARNING_RATE = 0.15,
	EXPLORATION_RATE = 0.05,
	DIRECTION_SMOOTHING = 0.28,
	MIN_MOVEMENT_SPEED = 2,
	STUCK_THRESHOLD = 2.5,
	INTERACTION_DISTANCE = 8,
	DECISION_COOLDOWN = 0.4,
	COIN_LOSS_PER_HIT = 5,
	COIN_LOSS_PER_TOUCH = 2,
	MEMORY_SIZE = 50 -- Remember last 50 positions
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle"}

-- ================= ADVANCED BOT STATE =================
local botControl = {
	enabled = true,
	confidence = 1.0,
	moveDirection = Vector3.new(0, 0, 1),
	status = "INITIALIZING",
	score = 0,
	coinsCollected = 0,
	distanceTraveled = 0,
	lastPosition = nil,
	lastMovementTime = tick(),
	lastDecisionTime = tick(),
	stuckCounter = 0,
	health = 100,
	touchingWall = false,
	lastWallHit = 0,
	wallTouchStart = 0,
	collisionCount = 0,
	
	-- Spatial awareness
	currentPosition = Vector3.zero,
	targetPosition = nil,
	positionHistory = {},
	visitedPositions = {},
	
	-- Performance metrics
	successfulMoves = 0,
	failedMoves = 0,
	interactionsSuccessful = 0
}

-- ================= LIDAR DATA STRUCTURE =================
local lidarSystem = {
	beams = {}, -- Stores all beam data
	obstacles = {}, -- Detected obstacles with full info
	nearestObstacle = nil,
	safeDirections = {},
	dangerDirections = {}
}

-- Obstacle awareness zones
local obstacleZones = {
	farLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	left = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerLeft = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	center = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	centerRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	right = {distance = 25, threat = 0, objectPos = nil, objectType = "none"},
	farRight = {distance = 25, threat = 0, objectPos = nil, objectType = "none"}
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position
botControl.health = humanoid.Health

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 ULTRA-SMART AI - FULL SPATIAL AWARENESS")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
humanoid.JumpPower = 0
humanoid.AutoRotate = false

local function blockPlayerInput()
	UserInputService.ModalEnabled = true
end

local function restorePlayerInput()
	UserInputService.ModalEnabled = false
	humanoid.AutoRotate = true
	humanoid.JumpPower = 50
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.P then
		botControl.enabled = not botControl.enabled
		if botControl.enabled then
			print("🤖 AI CONTROL: ENABLED")
			blockPlayerInput()
		else
			print("👤 PLAYER CONTROL: ENABLED")
			restorePlayerInput()
			humanoid:Move(Vector3.zero)
		end
	end
end)

blockPlayerInput()

-- ================= COLLISION DETECTION =================
local function setupCollisionDetection()
	rootPart.Touched:Connect(function(hit)
		if not botControl.enabled then return end
		
		local isWall = false
		for _, tag in ipairs(OBSTACLE_TAGS) do
			if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
				isWall = true
				break
			end
		end
		
		if not isWall and hit:IsA("BasePart") and hit.CanCollide then
			local isInteractive = false
			for _, tag in ipairs(INTERACTIVE_TAGS) do
				if hit:HasTag(tag) or hit.Name:find(tag) then
					isInteractive = true
					break
				end
			end
			if not isInteractive then
				isWall = true
			end
		end
		
		if isWall then
			if not botControl.touchingWall then
				botControl.touchingWall = true
				botControl.wallTouchStart = tick()
				botControl.collisionCount = botControl.collisionCount + 1
				botControl.coinsCollected = math.max(0, botControl.coinsCollected - CONFIG.COIN_LOSS_PER_HIT)
				botControl.score = botControl.score - 10
				botControl.lastWallHit = tick()
				botControl.failedMoves = botControl.failedMoves + 1
				
				print(string.format("💥 Collision at (%.1f, %.1f, %.1f) - Lost %d coins!", 
					rootPart.Position.X, rootPart.Position.Y, rootPart.Position.Z,
					CONFIG.COIN_LOSS_PER_HIT))
			end
		end
	end)
	
	rootPart.TouchEnded:Connect(function(hit)
		task.wait(0.1)
		local touching = rootPart:GetTouchingParts()
		local stillTouchingWall = false
		
		for _, part in ipairs(touching) do
			for _, tag in ipairs(OBSTACLE_TAGS) do
				if part:HasTag(tag) or part.Name:find("Wall") or part.Name:find("Barrier") then
					stillTouchingWall = true
					break
				end
			end
		end
		
		if not stillTouchingWall then
			botControl.touchingWall = false
		end
	end)
end

setupCollisionDetection()

-- ================= RAYCAST SETUP =================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	rayParams.FilterDescendantsInstances = {character}
end
updateRaycastFilter()

-- ================= POSITION TRACKING SYSTEM =================
local function updatePositionHistory()
	botControl.currentPosition = rootPart.Position
	
	-- Add to history
	table.insert(botControl.positionHistory, 1, {
		position = botControl.currentPosition,
		time = tick(),
		coins = botControl.coinsCollected
	})
	
	-- Keep only recent history
	if #botControl.positionHistory > CONFIG.MEMORY_SIZE then
		table.remove(botControl.positionHistory, #botControl.positionHistory)
	end
	
	-- Mark as visited (rounded to grid for efficiency)
	local gridPos = Vector3.new(
		math.floor(botControl.currentPosition.X / 5) * 5,
		math.floor(botControl.currentPosition.Y / 5) * 5,
		math.floor(botControl.currentPosition.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	botControl.visitedPositions[key] = (botControl.visitedPositions[key] or 0) + 1
end

local function hasVisitedRecently(position)
	local gridPos = Vector3.new(
		math.floor(position.X / 5) * 5,
		math.floor(position.Y / 5) * 5,
		math.floor(position.Z / 5) * 5
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	return (botControl.visitedPositions[key] or 0) > 3
end

local function getRelativePosition(worldPos)
	-- Convert world position to relative position from bot
	local relative = worldPos - botControl.currentPosition
	return relative
end

-- ================= ADVANCED LIDAR SYSTEM =================
local function identifyObjectType(hit)
	-- Check interactive objects first
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			return tag
		end
	end
	
	-- Check obstacles
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
			return "Obstacle"
		end
	end
	
	-- Unknown solid object
	if hit:IsA("BasePart") and hit.CanCollide then
		return "Unknown"
	end
	
	return "Empty"
end

local function performUltraLiDARScan()
	-- Reset zones
	for _, zone in pairs(obstacleZones) do
		zone.distance = CONFIG.RAYCAST_DISTANCE
		zone.threat = 0
		zone.objectPos = nil
		zone.objectType = "none"
	end
	
	lidarSystem.beams = {}
	lidarSystem.obstacles = {}
	
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	
	-- 11 beams with precise angles
	local beamAngles = {
		-1.5, -1.2, -0.9,  -- Far left
		-0.7, -0.35,       -- Left
		0,                 -- Center
		0.35, 0.7,         -- Right
		0.9, 1.2, 1.5      -- Far right
	}
	
	local beamNames = {
		"FarLeft3", "FarLeft2", "FarLeft1",
		"Left2", "Left1",
		"Center",
		"Right1", "Right2",
		"FarRight1", "FarRight2", "FarRight3"
	}
	
	local zoneMapping = {
		[1] = "farLeft", [2] = "farLeft", [3] = "farLeft",
		[4] = "left", [5] = "centerLeft",
		[6] = "center",
		[7] = "centerRight", [8] = "right",
		[9] = "farRight", [10] = "farRight", [11] = "farRight"
	}
	
	local distances = {}
	local interactables = {}
	
	for i, angle in ipairs(beamAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * CONFIG.RAYCAST_DISTANCE
		local rayResult = Workspace:Raycast(origin, rayDirection, rayParams)
		
		local beamData = {
			name = beamNames[i],
			angle = math.deg(angle),
			direction = rayDirection.Unit,
			distance = CONFIG.RAYCAST_DISTANCE,
			hitPosition = origin + rayDirection,
			objectType = "none",
			objectName = "none",
			relativePosition = Vector3.zero
		}
		
		if rayResult then
			beamData.distance = rayResult.Distance
			beamData.hitPosition = rayResult.Position
			beamData.objectType = identifyObjectType(rayResult.Instance)
			beamData.objectName = rayResult.Instance.Name
			beamData.relativePosition = getRelativePosition(rayResult.Position)
			
			distances[i] = rayResult.Distance
			
			-- Update zone
			local zone = zoneMapping[i]
			if beamData.distance < obstacleZones[zone].distance then
				obstacleZones[zone].distance = beamData.distance
				obstacleZones[zone].objectPos = rayResult.Position
				obstacleZones[zone].objectType = beamData.objectType
				
				-- Calculate threat level
				if beamData.distance < CONFIG.DANGER_DISTANCE then
					obstacleZones[zone].threat = 1.0
				elseif beamData.distance < CONFIG.SAFE_DISTANCE then
					obstacleZones[zone].threat = 0.5
				else
					obstacleZones[zone].threat = 0.1
				end
			end
			
			-- Store obstacle data
			if beamData.objectType ~= "none" and beamData.objectType ~= "Empty" then
				table.insert(lidarSystem.obstacles, {
					position = rayResult.Position,
					worldPosition = rayResult.Position,
					relativePosition = beamData.relativePosition,
					distance = beamData.distance,
					type = beamData.objectType,
					name = beamData.objectName,
					angle = beamData.angle,
					beam = beamNames[i]
				})
			end
			
			-- Check for interactables
			if beamData.objectType ~= "Obstacle" and beamData.objectType ~= "Unknown" and beamData.distance < CONFIG.INTERACTION_DISTANCE then
				table.insert(interactables, {
					object = rayResult.Instance,
					position = rayResult.Position,
					distance = beamData.distance,
					type = beamData.objectType
				})
			end
		else
			distances[i] = CONFIG.RAYCAST_DISTANCE
		end
		
		lidarSystem.beams[i] = beamData
	end
	
	-- Find nearest obstacle
	lidarSystem.nearestObstacle = nil
	local minDist = math.huge
	for _, obstacle in ipairs(lidarSystem.obstacles) do
		if obstacle.distance < minDist then
			minDist = obstacle.distance
			lidarSystem.nearestObstacle = obstacle
		end
	end
	
	-- Find closest interactable
	local closestInteractable = nil
	minDist = math.huge
	for _, obj in ipairs(interactables) do
		if obj.distance < minDist then
			minDist = obj.distance
			closestInteractable = obj
		end
	end
	
	return {
		distances = distances,
		minDistance = math.min(table.unpack(distances)),
		maxDistance = math.max(table.unpack(distances)),
		closestInteractable = closestInteractable,
		obstacleCount = #lidarSystem.obstacles
	}
end

-- ================= ULTRA-ADVANCED NEURAL NETWORK =================
local neuralNet = {
	inputLayer = {},
	hiddenLayer1 = {},
	hiddenLayer2 = {},
	outputLayer = {},
	learningRate = CONFIG.LEARNING_RATE
}

local function initializeUltraNetwork()
	-- Input: 11 beams + 7 zones + 10 internal states + 6 position data = 34 inputs
	for i = 1, 34 do
		neuralNet.inputLayer[i] = math.random() * 0.6 - 0.3
	end
	
	-- Hidden layer 1: 20 neurons
	for i = 1, 20 do
		neuralNet.hiddenLayer1[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 34 do
			neuralNet.hiddenLayer1[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Hidden layer 2: 15 neurons
	for i = 1, 15 do
		neuralNet.hiddenLayer2[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1,
			activation = 0
		}
		for j = 1, 20 do
			neuralNet.hiddenLayer2[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
	
	-- Output: 4 outputs (turn, speed, interact, explore)
	for i = 1, 4 do
		neuralNet.outputLayer[i] = {
			weights = {},
			bias = math.random() * 0.2 - 0.1
		}
		for j = 1, 15 do
			neuralNet.outputLayer[i].weights[j] = math.random() * 0.4 - 0.2
		end
	end
end

initializeUltraNetwork()

local function sigmoid(x)
	return 1 / (1 + math.exp(-math.clamp(x, -10, 10)))
end

local function relu(x)
	return math.max(0, x)
end

local function leakyRelu(x)
	return x > 0 and x or x * 0.01
end

-- ================= INTERNAL STATE =================
local function getAdvancedInternalState()
	local velocity = rootPart.AssemblyLinearVelocity
	local successRate = botControl.successfulMoves / math.max(1, botControl.successfulMoves + botControl.failedMoves)
	
	return {
		health = humanoid.Health / humanoid.MaxHealth,
		speed = velocity.Magnitude / CONFIG.MOVEMENT_SPEED,
		confidence = botControl.confidence,
		coinsNormalized = math.clamp(botControl.coinsCollected / 50, 0, 1),
		wallTouching = botControl.touchingWall and 1 or 0,
		successRate = successRate,
		explorationFactor = math.clamp(#botControl.positionHistory / CONFIG.MEMORY_SIZE, 0, 1),
		timeSinceHit = math.clamp((tick() - botControl.lastWallHit) / 10, 0, 1),
		distanceNormalized = math.clamp(botControl.distanceTraveled / 1000, 0, 1),
		interactionRate = math.clamp(botControl.interactionsSuccessful / 20, 0, 1)
	}
end

local function getPositionData()
	local nearestObstacle = lidarSystem.nearestObstacle
	return {
		myX = math.clamp(botControl.currentPosition.X / 100, -1, 1),
		myY = math.clamp(botControl.currentPosition.Y / 100, -1, 1),
		myZ = math.clamp(botControl.currentPosition.Z / 100, -1, 1),
		nearestObstacleX = nearestObstacle and math.clamp(nearestObstacle.relativePosition.X / 20, -1, 1) or 0,
		nearestObstacleY = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Y / 20, -1, 1) or 0,
		nearestObstacleZ = nearestObstacle and math.clamp(nearestObstacle.relativePosition.Z / 20, -1, 1) or 0
	}
end

-- ================= ULTRA-SMART DECISION MAKING =================
local function ultraNeuralDecision(lidarData, internalState, positionData)
	-- Prepare 34 inputs
	local inputs = {}
	
	-- 11 beam distances (normalized)
	for i = 1, 11 do
		inputs[i] = 1 - math.clamp(lidarData.distances[i] / CONFIG.RAYCAST_DISTANCE, 0, 1)
	end
	
	-- 7 zone threats
	local zoneOrder = {"farLeft", "left", "centerLeft", "center", "centerRight", "right", "farRight"}
	for i, zoneName in ipairs(zoneOrder) do
		inputs[11 + i] = obstacleZones[zoneName].threat
	end
	
	-- 10 internal states
	inputs[19] = internalState.health
	inputs[20] = internalState.speed
	inputs[21] = internalState.confidence
	inputs[22] = internalState.coinsNormalized
	inputs[23] = internalState.wallTouching
	inputs[24] = internalState.successRate
	inputs[25] = internalState.explorationFactor
	inputs[26] = internalState.timeSinceHit
	inputs[27] = internalState.distanceNormalized
	inputs[28] = internalState.interactionRate
	
	-- 6 position data
	inputs[29] = positionData.myX
	inputs[30] = positionData.myY
	inputs[31] = positionData.myZ
	inputs[32] = positionData.nearestObstacleX
	inputs[33] = positionData.nearestObstacleY
	inputs[34] = positionData.nearestObstacleZ
	
	-- Forward pass - Layer 1
	for i = 1, 20 do
		local sum = neuralNet.hiddenLayer1[i].bias
		for j = 1, 34 do
			sum = sum + inputs[j] * neuralNet.hiddenLayer1[i].weights[j]
		end
		neuralNet.hiddenLayer1[i].activation = leakyRelu(sum)
	end
	
	-- Forward pass - Layer 2
	for i = 1, 15 do
		local sum = neuralNet.hiddenLayer2[i].bias
		for j = 1, 20 do
			sum = sum + neuralNet.hiddenLayer1[j].activation * neuralNet.hiddenLayer2[i].weights[j]
		end
		neuralNet.hiddenLayer2[i].activation = leakyRelu(sum)
	end
	
	-- Output layer
	local outputs = {}
	for i = 1, 4 do
		local sum = neuralNet.outputLayer[i].bias
		for j = 1, 15 do
			sum = sum + neuralNet.hiddenLayer2[j].activation * neuralNet.outputLayer[i].weights[j]
		end
		outputs[i] = math.tanh(sum)
	end
	
	return {
		turnDirection = outputs[1],
		forwardSpeed = math.clamp((outputs[2] + 1) / 2, 0.2, 1),
		shouldInteract = outputs[3] > 0.2,
		shouldExplore = outputs[4] > 0.3
	}
end

-- ================= INTERACTION SYSTEM =================
local function attemptInteraction(interactable)
	if not interactable then return false end
	
	local obj = interactable.object
	local objType = interactable.type
	
	if objType == "Coin" or objType == "Collectible" then
		if obj:IsA("BasePart") and (rootPart.Position - obj.Position).Magnitude < 5 then
			botControl.coinsCollected = botControl.coinsCollected + 1
			botControl.score = botControl.score + 10
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	elseif objType == "Button" or objType == "Door" then
		if obj:FindFirstChild("ClickDetector") then
			fireclickdetector(obj.ClickDetector)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		elseif obj:FindFirstChild("ProximityPrompt") then
			fireproximityprompt(obj.ProximityPrompt)
			botControl.score = botControl.score + 5
			botControl.interactionsSuccessful = botControl.interactionsSuccessful + 1
			return true
		end
	end
	
	return false
end

-- ================= MOVEMENT TRACKING =================
local function getMovementSpeed()
	if not botControl.lastPosition then
		botControl.lastPosition = rootPart.Position
		return 0
	end
	
	local currentPos = rootPart.Position
	local distance = (currentPos - botControl.lastPosition).Magnitude
	botControl.lastPosition = currentPos
	
	return distance
end

local function isStuck()
	return (tick() - botControl.lastMovementTime) > CONFIG.STUCK_THRESHOLD
end

-- ================= ADVANCED LEARNING =================
local function updateUltraNetwork(reward)
	-- More sophisticated weight updates
	local learningFactor = neuralNet.learningRate * reward * 0.05
	
	-- Update hidden layer 1
	for i = 1, 20 do
		for j = 1, 34 do
			local gradient = learningFactor * neuralNet.hiddenLayer1[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer1[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer1[i].weights[j] + gradient,
				-3, 3
			)
		end
		neuralNet.hiddenLayer1[i].bias = math.clamp(
			neuralNet.hiddenLayer1[i].bias + learningFactor * 0.1,
			-1, 1
		)
	end
	
	-- Update hidden layer 2
	for i = 1, 15 do
		for j = 1, 20 do
			local gradient = learningFactor * neuralNet.hiddenLayer2[i].activation * (math.random() * 2 - 1)
			neuralNet.hiddenLayer2[i].weights[j] = math.clamp(
				neuralNet.hiddenLayer2[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
	
	-- Update output layer
	for i = 1, 4 do
		for j = 1, 15 do
			local gradient = learningFactor * (math.random() * 2 - 1)
			neuralNet.outputLayer[i].weights[j] = math.clamp(
				neuralNet.outputLayer[i].weights[j] + gradient,
				-3, 3
			)
		end
	end
end

local function evaluateUltraPerformance(lidarData, movementSpeed, interactionSuccess)
	local reward = 0
	
	-- Wall touching penalty
	if botControl.touchingWall then
		local touchDuration = tick() - botControl.wallTouchStart
		if touchDuration > 0.5 then
			local coinsToLose = math.floor(touchDuration * CONFIG.COIN_LOSS_PER_TOUCH)
			botControl.coinsCollected = math.max(0, botControl.coinsCollected - coinsToLose)
			botControl.wallTouchStart = tick()
		end
		reward = reward - 15
	end
	
	-- Movement rewards
	if movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		reward = reward + 2
		botControl.lastMovementTime = tick()
		botControl.successfulMoves = botControl.successfulMoves + 1
	else
		reward = reward - 3
		botControl.failedMoves = botControl.failedMoves + 1
	end
	
	-- Distance-based rewards
	local centerDist = obstacleZones.center.distance
	if centerDist < CONFIG.DANGER_DISTANCE then
		reward = reward - 8
	elseif centerDist < CONFIG.SAFE_DISTANCE then
		reward = reward - 3
	elseif centerDist > CONFIG.SAFE_DISTANCE * 1.5 then
		reward = reward + 3
	end
	
	-- Side awareness
	if obstacleZones.left.threat > 0.5 or obstacleZones.right.threat > 0.5 then
		reward = reward - 2
	end
	
	-- Interaction rewards
	if interactionSuccess then
		reward = reward + 12
	end
	
	-- Exploration bonus
	if not hasVisitedRecently(botControl.currentPosition) then
		reward = reward + 1
	end
	
	-- Stuck penalty
	if isStuck() then
		reward = reward - 6
	end
	
	-- Update confidence
	botControl.confidence = math.clamp(botControl.confidence + reward * 0.005, 0.3, 1)
	
	-- Learn
	updateUltraNetwork(reward)
	
	return reward
end

-- ================= CHARACTER LIFECYCLE =================
local function setupCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	rootPart = char:WaitForChild("HumanoidRootPart")
	
	humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
	humanoid.AutoRotate = false
	humanoid.JumpPower = 0
	botControl.lastPosition = rootPart.Position
	botControl.currentPosition = rootPart.Position
	botControl.touchingWall = false
	
	updateRaycastFilter()
	setupCollisionDetection()
	
	if botControl.enabled then
		blockPlayerInput()
	end
	
	print("🔄 Character respawned")
end

player.CharacterAdded:Connect(setupCharacter)

humanoid.HealthChanged:Connect(function(health)
	botControl.health = health
end)

-- ================= MAIN ULTRA-SMART CONTROL LOOP =================
local lastUpdate = tick()
RunService.Heartbeat:Connect(function(deltaTime)
	if not botControl.enabled then return end
	if not rootPart or not rootPart.Parent then return end
	if not humanoid or humanoid.Health <= 0 then return endnt then return end
	if not humanoid or humanoid.Health <= 0 then return end
