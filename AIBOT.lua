-- =========================================
-- FIXED ULTRA-SMART AI BOT - Proper Learning & No Spinning
-- =========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- ================= CONFIGURATION =================
local CONFIG = {
	MOVEMENT_SPEED = 16,
	TURN_SPEED = 0.15,
	SAFE_DISTANCE = 8,
	DANGER_DISTANCE = 4,
	RAYCAST_DISTANCE = 30,
	MIN_MOVEMENT_SPEED = 1.5,
	STUCK_THRESHOLD = 2,
	STUCK_CHECK_INTERVAL = 0.5,
	INTERACTION_DISTANCE = 10,
	COIN_LOSS_PER_HIT = 5,
	LIDAR_UPDATE_INTERVAL = 0.15,
	LEARNING_RATE = 0.2,
	DISCOUNT_FACTOR = 0.85,
	EXPLORATION_RATE = 0.25,
	EXPLORATION_DECAY = 0.995,
	MIN_EXPLORATION = 0.05
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle"}

-- ================= BOT STATE =================
local botControl = {
	enabled = true,
	moveDirection = Vector3.new(0, 0, 1),
	status = "INITIALIZING",
	score = 0,
	coinsCollected = 0,
	distanceTraveled = 0,
	lastPosition = nil,
	lastMovementTime = tick(),
	lastStuckCheck = tick(),
	stuckCounter = 0,
	touchingWall = false,
	lastWallHit = 0,
	collisionCount = 0,
	currentPosition = Vector3.zero,
	positionHistory = {},
	visitedPositions = {},
	successfulMoves = 0,
	failedMoves = 0,
	lastAction = nil,
	lastState = nil,
	escapeMode = false,
	escapeStartTime = 0,
	targetDirection = nil,
	explorationRate = CONFIG.EXPLORATION_RATE
}

-- ================= Q-LEARNING TABLE =================
local qTable = {}
local actionList = {
	"forward",
	"forward_left",
	"forward_right",
	"sharp_left",
	"sharp_right",
	"backup_left",
	"backup_right"
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 FIXED ULTRA-SMART AI BOT")
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
local collisionDebounce = {}

local function setupCollisionDetection()
	rootPart.Touched:Connect(function(hit)
		if not botControl.enabled then return end
		if collisionDebounce[hit] and tick() - collisionDebounce[hit] < 0.5 then return end
		
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
			collisionDebounce[hit] = tick()
			
			if not botControl.touchingWall then
				botControl.touchingWall = true
				botControl.collisionCount = botControl.collisionCount + 1
				botControl.coinsCollected = math.max(0, botControl.coinsCollected - CONFIG.COIN_LOSS_PER_HIT)
				botControl.score = botControl.score - 15
				botControl.lastWallHit = tick()
				botControl.failedMoves = botControl.failedMoves + 1
				
				-- Enter escape mode
				botControl.escapeMode = true
				botControl.escapeStartTime = tick()
				
				print(string.format("💥 Collision! Lost %d coins. Total: %d", 
					CONFIG.COIN_LOSS_PER_HIT, botControl.coinsCollected))
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

-- ================= POSITION TRACKING =================
local function updatePositionHistory()
	botControl.currentPosition = rootPart.Position
	
	table.insert(botControl.positionHistory, 1, {
		position = botControl.currentPosition,
		time = tick()
	})
	
	if #botControl.positionHistory > 20 then
		table.remove(botControl.positionHistory)
	end
	
	local gridPos = Vector3.new(
		math.floor(botControl.currentPosition.X / 8) * 8,
		math.floor(botControl.currentPosition.Y / 8) * 8,
		math.floor(botControl.currentPosition.Z / 8) * 8
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	botControl.visitedPositions[key] = tick()
end

local function hasVisitedRecently(position, threshold)
	threshold = threshold or 30
	local gridPos = Vector3.new(
		math.floor(position.X / 8) * 8,
		math.floor(position.Y / 8) * 8,
		math.floor(position.Z / 8) * 8
	)
	local key = string.format("%.0f_%.0f_%.0f", gridPos.X, gridPos.Y, gridPos.Z)
	local lastVisit = botControl.visitedPositions[key]
	return lastVisit and (tick() - lastVisit) < threshold
end

-- ================= LIDAR SYSTEM =================
local cachedLidarData = nil
local lastLidarUpdate = 0

local function identifyObjectType(hit)
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			return tag
		end
	end
	
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
			return "Obstacle"
		end
	end
	
	if hit:IsA("BasePart") and hit.CanCollide then
		return "Unknown"
	end
	
	return "Empty"
end

local function performLiDARScan()
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	
	local beamAngles = {-0.9, -0.6, -0.3, 0, 0.3, 0.6, 0.9}
	local distances = {}
	local closestObstacle = {distance = CONFIG.RAYCAST_DISTANCE, angle = 0}
	local interactables = {}
	
	for i, angle in ipairs(beamAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * CONFIG.RAYCAST_DISTANCE
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(origin, rayDirection, rayParams)
		end)
		
		if success and rayResult then
			distances[i] = rayResult.Distance
			
			if rayResult.Distance < closestObstacle.distance then
				closestObstacle.distance = rayResult.Distance
				closestObstacle.angle = angle
				closestObstacle.position = rayResult.Position
			end
			
			local objType = identifyObjectType(rayResult.Instance)
			if objType ~= "Obstacle" and objType ~= "Unknown" and objType ~= "Empty" then
				if rayResult.Distance < CONFIG.INTERACTION_DISTANCE then
					table.insert(interactables, {
						object = rayResult.Instance,
						position = rayResult.Position,
						distance = rayResult.Distance,
						type = objType,
						angle = angle
					})
				end
			end
		else
			distances[i] = CONFIG.RAYCAST_DISTANCE
		end
	end
	
	-- Calculate safety metrics
	local leftClear = (distances[1] + distances[2]) / 2 > CONFIG.SAFE_DISTANCE
	local rightClear = (distances[6] + distances[7]) / 2 > CONFIG.SAFE_DISTANCE
	local centerClear = distances[4] > CONFIG.SAFE_DISTANCE
	
	return {
		distances = distances,
		closestObstacle = closestObstacle,
		interactables = interactables,
		leftClear = leftClear,
		rightClear = rightClear,
		centerClear = centerClear,
		minDistance = math.min(table.unpack(distances)),
		avgDistance = (distances[1] + distances[4] + distances[7]) / 3
	}
end

-- ================= Q-LEARNING SYSTEM =================
local function discretizeState(lidarData)
	-- Discretize distances into bins: close (0-4), medium (4-10), far (10+)
	local function getBin(distance)
		if distance < 4 then return "close"
		elseif distance < 10 then return "medium"
		else return "far"
		end
	end
	
	local left = getBin(lidarData.distances[2])
	local center = getBin(lidarData.distances[4])
	local right = getBin(lidarData.distances[6])
	local hasInteractable = #lidarData.interactables > 0 and "yes" or "no"
	local wallTouch = botControl.touchingWall and "yes" or "no"
	
	return string.format("%s_%s_%s_%s_%s", left, center, right, hasInteractable, wallTouch)
end

local function getQValue(state, action)
	if not qTable[state] then
		qTable[state] = {}
	end
	if not qTable[state][action] then
		qTable[state][action] = 0
	end
	return qTable[state][action]
end

local function getBestAction(state)
	local bestAction = actionList[1]
	local bestValue = getQValue(state, bestAction)
	
	for _, action in ipairs(actionList) do
		local value = getQValue(state, action)
		if value > bestValue then
			bestValue = value
			bestAction = action
		end
	end
	
	return bestAction, bestValue
end

local function chooseAction(state)
	-- Epsilon-greedy exploration
	if math.random() < botControl.explorationRate then
		return actionList[math.random(#actionList)]
	else
		return getBestAction(state)
	end
end

local function updateQValue(state, action, reward, nextState)
	local currentQ = getQValue(state, action)
	local _, maxNextQ = getBestAction(nextState)
	
	local newQ = currentQ + CONFIG.LEARNING_RATE * (reward + CONFIG.DISCOUNT_FACTOR * maxNextQ - currentQ)
	
	if not qTable[state] then
		qTable[state] = {}
	end
	qTable[state][action] = newQ
end

-- ================= ACTION EXECUTION =================
local function executeAction(action, lidarData)
	local moveVector = Vector3.zero
	local turnMultiplier = 0
	
	if action == "forward" then
		moveVector = rootPart.CFrame.LookVector
		turnMultiplier = 0
	elseif action == "forward_left" then
		moveVector = rootPart.CFrame.LookVector
		turnMultiplier = -0.5
	elseif action == "forward_right" then
		moveVector = rootPart.CFrame.LookVector
		turnMultiplier = 0.5
	elseif action == "sharp_left" then
		moveVector = rootPart.CFrame.LookVector * 0.5
		turnMultiplier = -1.5
	elseif action == "sharp_right" then
		moveVector = rootPart.CFrame.LookVector * 0.5
		turnMultiplier = 1.5
	elseif action == "backup_left" then
		moveVector = -rootPart.CFrame.LookVector * 0.7
		turnMultiplier = -1
	elseif action == "backup_right" then
		moveVector = -rootPart.CFrame.LookVector * 0.7
		turnMultiplier = 1
	end
	
	-- Apply turn
	if turnMultiplier ~= 0 then
		local turnAngle = turnMultiplier * CONFIG.TURN_SPEED
		rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, turnAngle, 0)
	end
	
	-- Move
	humanoid:Move(moveVector)
	
	return moveVector.Magnitude > 0
end

-- ================= ESCAPE BEHAVIOR =================
local function executeEscapeManeuver(lidarData)
	local escapeAction
	
	-- Choose escape direction based on clearest path
	if lidarData.leftClear and not lidarData.rightClear then
		escapeAction = math.random() < 0.5 and "sharp_left" or "backup_left"
	elseif lidarData.rightClear and not lidarData.leftClear then
		escapeAction = math.random() < 0.5 and "sharp_right" or "backup_right"
	elseif lidarData.leftClear and lidarData.rightClear then
		escapeAction = math.random() < 0.5 and "sharp_left" or "sharp_right"
	else
		-- Both blocked, back up
		escapeAction = math.random() < 0.5 and "backup_left" or "backup_right"
	end
	
	executeAction(escapeAction, lidarData)
	
	-- Exit escape mode after a short duration
	if tick() - botControl.escapeStartTime > 1.5 then
		botControl.escapeMode = false
		botControl.stuckCounter = 0
	end
end

-- ================= STUCK DETECTION =================
local function checkIfStuck()
	if #botControl.positionHistory < 3 then return false end
	
	local recentPositions = {}
	for i = 1, math.min(5, #botControl.positionHistory) do
		table.insert(recentPositions, botControl.positionHistory[i].position)
	end
	
	local totalMovement = 0
	for i = 2, #recentPositions do
		totalMovement = totalMovement + (recentPositions[i] - recentPositions[1]).Magnitude
	end
	
	return totalMovement < 3
end

-- ================= INTERACTION SYSTEM =================
local function attemptInteraction(interactable)
	if not interactable then return false end
	
	local obj = interactable.object
	local objType = interactable.type
	
	if objType == "Coin" or objType == "Collectible" then
		if obj:IsA("BasePart") and (rootPart.Position - obj.Position).Magnitude < 6 then
			botControl.coinsCollected = botControl.coinsCollected + 1
			botControl.score = botControl.score + 10
			return true
		end
	elseif objType == "Button" or objType == "Door" then
		if obj:FindFirstChild("ClickDetector") then
			fireclickdetector(obj.ClickDetector)
			botControl.score = botControl.score + 5
			return true
		elseif obj:FindFirstChild("ProximityPrompt") then
			fireproximityprompt(obj.ProximityPrompt)
			botControl.score = botControl.score + 5
			return true
		end
	end
	
	return false
end

-- ================= REWARD CALCULATION =================
local function calculateReward(lidarData, movementSpeed, interactionSuccess, wasMoving)
	local reward = 0
	
	-- Collision penalty
	if botControl.touchingWall then
		reward = reward - 20
	end
	
	-- Movement reward
	if movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		reward = reward + 3
		botControl.lastMovementTime = tick()
		botControl.successfulMoves = botControl.successfulMoves + 1
	else
		reward = reward - 2
	end
	
	-- Distance-based rewards
	if lidarData.minDistance < CONFIG.DANGER_DISTANCE then
		reward = reward - 10
	elseif lidarData.minDistance > CONFIG.SAFE_DISTANCE then
		reward = reward + 5
	end
	
	-- Exploration reward
	if not hasVisitedRecently(botControl.currentPosition, 20) then
		reward = reward + 2
	end
	
	-- Interaction reward
	if interactionSuccess then
		reward = reward + 15
	end
	
	-- Stuck penalty
	if checkIfStuck() then
		reward = reward - 8
		botControl.stuckCounter = botControl.stuckCounter + 1
	else
		botControl.stuckCounter = 0
	end
	
	return reward
end

-- ================= MOVEMENT TRACKING =================
local function getMovementSpeed()
	if not botControl.lastPosition then
		botControl.lastPosition = rootPart.Position
		return 0
	end
	
	local currentPos = rootPart.Position
	local distance = (currentPos - botControl.lastPosition).Magnitude
	botControl.distanceTraveled = botControl.distanceTraveled + distance
	botControl.lastPosition = currentPos
	
	return distance / 0.1  -- Speed per second (approximate)
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
	botControl.escapeMode = false
	
	updateRaycastFilter()
	setupCollisionDetection()
	
	if botControl.enabled then
		blockPlayerInput()
	end
	
	print("🔄 Character respawned")
end

player.CharacterAdded:Connect(setupCharacter)

-- ================= MAIN CONTROL LOOP =================
local lastUpdate = tick()
local frameCount = 0

RunService.Heartbeat:Connect(function(deltaTime)
	if not botControl.enabled then return end
	if not rootPart or not rootPart.Parent then return end
	if not humanoid or humanoid.Health <= 0 then return end
	
	frameCount = frameCount + 1
	local currentTime = tick()
	
	-- Update position tracking
	updatePositionHistory()
	
	-- Update LiDAR (throttled)
	if currentTime - lastLidarUpdate >= CONFIG.LIDAR_UPDATE_INTERVAL then
		cachedLidarData = performLiDARScan()
		lastLidarUpdate = currentTime
	end
	
	local lidarData = cachedLidarData or performLiDARScan()
	
	-- Check for stuck condition periodically
	if currentTime - botControl.lastStuckCheck >= CONFIG.STUCK_CHECK_INTERVAL then
		if checkIfStuck() then
			botControl.stuckCounter = botControl.stuckCounter + 1
			if botControl.stuckCounter > 3 then
				botControl.escapeMode = true
				botControl.escapeStartTime = currentTime
			end
		end
		botControl.lastStuckCheck = currentTime
	end
	
	-- Handle escape mode
	if botControl.escapeMode then
		executeEscapeManeuver(lidarData)
		botControl.status = "ESCAPING"
		return
	end
	
	-- Get current state
	local currentState = discretizeState(lidarData)
	
	-- Choose action
	local action = chooseAction(currentState)
	
	-- Execute action
	local wasMoving = executeAction(action, lidarData)
	
	-- Calculate movement
	local movementSpeed = getMovementSpeed()
	
	-- Try interaction
	local interactionSuccess = false
	if #lidarData.interactables > 0 then
		table.sort(lidarData.interactables, function(a, b) return a.distance < b.distance end)
		interactionSuccess = attemptInteraction(lidarData.interactables[1])
	end
	
	-- Calculate reward
	local reward = calculateReward(lidarData, movementSpeed, interactionSuccess, wasMoving)
	
	-- Get next state
	local nextState = discretizeState(lidarData)
	
	-- Update Q-value
	if botControl.lastState and botControl.lastAction then
		updateQValue(botControl.lastState, botControl.lastAction, reward, currentState)
	end
	
	-- Save state and action for next iteration
	botControl.lastState = currentState
	botControl.lastAction = action
	
	-- Decay exploration rate
	botControl.explorationRate = math.max(
		CONFIG.MIN_EXPLORATION,
		botControl.explorationRate * CONFIG.EXPLORATION_DECAY
	)
	
	-- Update status
	if interactionSuccess then
		botControl.status = "COLLECTING"
	elseif botControl.touchingWall then
		botControl.status = "COLLIDING"
	elseif movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		botControl.status = "NAVIGATING"
	else
		botControl.status = "THINKING"
	end
	
	-- Debug info (every 3 seconds)
	if currentTime - lastUpdate > 3 then
		local successRate = botControl.successfulMoves / math.max(1, botControl.successfulMoves + botControl.failedMoves) * 100
		print(string.format("🤖 %s | Coins: %d | Score: %d | Success: %.1f%% | Explore: %.2f", 
			botControl.status, botControl.coinsCollected, botControl.score, successRate, botControl.explorationRate))
		print(string.format("📊 States Learned: %d | Distance: %.1fm | Action: %s", 
			#qTable, botControl.distanceTraveled, action or "none"))
		lastUpdate = currentTime
	end
end)

print("✅ FIXED AI BOT INITIALIZED")
print("Press 'P' to toggle AI control")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
