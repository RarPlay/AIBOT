-- =========================================
-- ULTRA-SMART AI BOT - FIXED & IMPROVED
-- =========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- ================= CONFIGURATION =================
local CONFIG = {
	MOVEMENT_SPEED = 16,
	TURN_SPEED = 0.12,
	SAFE_DISTANCE = 10,
	DANGER_DISTANCE = 5,
	RAYCAST_DISTANCE = 40,
	MIN_MOVEMENT_SPEED = 1.5,
	STUCK_THRESHOLD = 3,
	STUCK_CHECK_TIME = 2,
	INTERACTION_DISTANCE = 12,
	PLAYER_DETECTION_DISTANCE = 60,
	LIDAR_UPDATE_INTERVAL = 0.08,
	LEARNING_RATE = 0.2,
	DISCOUNT_FACTOR = 0.85,
	EXPLORATION_RATE = 0.4,
	EXPLORATION_DECAY = 0.9985,
	MIN_EXPLORATION = 0.05,
	TOOL_USE_COOLDOWN = 0.3,
	DAMAGE_MEMORY_DURATION = 90,
	POSITION_MEMORY = 20,
	MAX_TURN_PER_TICK = 0.25
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool", "Weapon", "Pickup"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle", "Block"}
local DANGEROUS_TAGS = {"Spike", "Lava", "Trap", "Danger", "Kill", "Damage", "Hazard"}

-- ================= BOT STATE =================
local botControl = {
	enabled = true,
	status = "INITIALIZING",
	score = 0,
	coinsCollected = 0,
	distanceTraveled = 0,
	lastPosition = nil,
	lastMovementTime = tick(),
	lastMoveDistance = 0,
	currentPosition = Vector3.zero,
	positionHistory = {},
	visitedPositions = {},
	successfulMoves = 0,
	failedMoves = 0,
	lastAction = nil,
	lastState = nil,
	escapeMode = false,
	escapeStartTime = 0,
	escapeDirection = nil,
	explorationRate = CONFIG.EXPLORATION_RATE,
	isMoving = false,
	actualVelocity = 0,
	stuckCounter = 0,
	lastStuckCheck = 0,
	forceForwardCounter = 0,
	
	-- Damage tracking
	lastHealth = 100,
	dangerousObjects = {},
	lastDamageSource = nil,
	lastDamageTime = 0,
	totalDamageTaken = 0,
	recentDamagePositions = {},
	
	-- Player tracking
	nearbyPlayers = {},
	rememberedPlayers = {},
	
	-- Object memory
	rememberedObjects = {},
	interactionAttempts = {},
	
	-- Tool usage
	currentTool = nil,
	toolUseConfidence = 0,
	lastToolUse = 0,
	
	-- Performance
	tickCount = 0,
	avgTickTime = 0
}

-- ================= LIDAR SYSTEM =================
local lidarSystem = {
	forward = {},
	below = {},
	behind = {},
	sides = {},
	allDetections = {},
	nearestObstacle = nil,
	nearestPlayer = nil,
	nearestInteractable = nil,
	pathClear = true,
	dangerAhead = false
}

-- ================= Q-LEARNING =================
local qTable = {}
local actionList = {
	"forward",
	"forward_left", 
	"forward_right",
	"sharp_left",
	"sharp_right",
	"back_left",
	"back_right",
	"strafe_left",
	"strafe_right",
	"slow_forward",
	"emergency_back"
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position
botControl.lastHealth = humanoid.Health

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 ULTRA-SMART AI BOT - FIXED VERSION")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED
humanoid.JumpPower = 0
humanoid.AutoRotate = false

-- ================= INPUT BLOCKING =================
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
	elseif input.KeyCode == Enum.KeyCode.R and botControl.enabled then
		-- Reset learning
		qTable = {}
		botControl.explorationRate = CONFIG.EXPLORATION_RATE
		print("🔄 Q-Table reset! Starting fresh learning.")
	end
end)

blockPlayerInput()

-- ================= DAMAGE TRACKING =================
humanoid.HealthChanged:Connect(function(health)
	if health < botControl.lastHealth then
		local damage = botControl.lastHealth - health
		botControl.lastDamageTime = tick()
		botControl.totalDamageTaken = botControl.totalDamageTaken + damage
		
		-- Record damage position
		table.insert(botControl.recentDamagePositions, {
			position = rootPart.Position,
			time = tick(),
			damage = damage
		})
		
		-- Keep only recent damage positions
		if #botControl.recentDamagePositions > 10 then
			table.remove(botControl.recentDamagePositions, 1)
		end
		
		-- Try to identify damage source
		local touchingParts = rootPart:GetTouchingParts()
		local foundSource = false
		
		for _, part in ipairs(touchingParts) do
			local isDangerous = false
			
			-- Check tags
			for _, tag in ipairs(DANGEROUS_TAGS) do
				if part:HasTag(tag) or part.Name:lower():find(tag:lower()) then
					isDangerous = true
					break
				end
			end
			
			if isDangerous then
				local id = tostring(part:GetFullName())
				
				if not botControl.dangerousObjects[id] then
					botControl.dangerousObjects[id] = {
						name = part.Name,
						position = part.Position,
						damage = damage,
						lastSeen = tick(),
						timesHit = 1,
						instance = part
					}
				else
					botControl.dangerousObjects[id].damage = botControl.dangerousObjects[id].damage + damage
					botControl.dangerousObjects[id].timesHit = botControl.dangerousObjects[id].timesHit + 1
					botControl.dangerousObjects[id].lastSeen = tick()
				end
				
				botControl.lastDamageSource = id
				foundSource = true
				
				print(string.format("⚠️ DAMAGE: -%d HP from '%s' (Hit #%d)", 
					damage, part.Name, botControl.dangerousObjects[id].timesHit))
				
				-- Enter escape mode with direction away from danger
				botControl.escapeMode = true
				botControl.escapeStartTime = tick()
				botControl.escapeDirection = (rootPart.Position - part.Position).Unit
				
				break
			end
		end
		
		-- Check nearby players
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude < 25 then
					local userId = tostring(otherPlayer.UserId)
					
					if botControl.nearbyPlayers[userId] then
						botControl.nearbyPlayers[userId].hostile = true
						botControl.nearbyPlayers[userId].damageDealt = 
							(botControl.nearbyPlayers[userId].damageDealt or 0) + damage
					end
					
					botControl.rememberedPlayers[userId] = {
						name = otherPlayer.Name,
						hostile = true,
						lastSeen = tick(),
						damageDealt = (botControl.rememberedPlayers[userId] and 
							botControl.rememberedPlayers[userId].damageDealt or 0) + damage,
						encounters = (botControl.rememberedPlayers[userId] and 
							botControl.rememberedPlayers[userId].encounters or 0) + 1
					}
					
					if not foundSource then
						print(string.format("🎯 DAMAGE: Possible attacker '%s' - MARKED HOSTILE", 
							otherPlayer.Name))
						foundSource = true
					end
				end
			end
		end
		
		if not foundSource then
			print(string.format("⚠️ DAMAGE: -%d HP from UNKNOWN source", damage))
		end
	end
	botControl.lastHealth = health
end)

-- ================= RAYCAST SETUP =================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	rayParams.FilterDescendantsInstances = {character}
end
updateRaycastFilter()

-- ================= OBJECT IDENTIFICATION =================
local function identifyObject(hit)
	local info = {
		type = "Unknown",
		name = hit.Name,
		id = tostring(hit:GetFullName()),
		isDangerous = false,
		isInteractive = false,
		isPlayer = false,
		distance = 0,
		priority = 0
	}
	
	-- Check if player
	local humanoidCheck = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
	if humanoidCheck and hit.Parent ~= character then
		local playerCheck = Players:GetPlayerFromCharacter(hit.Parent)
		if playerCheck then
			info.isPlayer = true
			info.type = "Player"
			info.name = playerCheck.Name
			info.id = tostring(playerCheck.UserId)
			info.priority = 5
			return info
		end
	end
	
	-- Check dangerous (highest priority)
	for _, tag in ipairs(DANGEROUS_TAGS) do
		if hit:HasTag(tag) or hit.Name:lower():find(tag:lower()) then
			info.isDangerous = true
			info.type = "Danger"
			info.priority = 10
			return info
		end
	end
	
	-- Check if remembered dangerous object
	if botControl.dangerousObjects[info.id] then
		info.isDangerous = true
		info.type = "RememberedDanger"
		info.priority = 9
		return info
	end
	
	-- Check interactive
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:lower():find(tag:lower()) then
			info.isInteractive = true
			info.type = tag
			info.priority = 7
			return info
		end
	end
	
	-- Check obstacles
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:lower():find(tag:lower()) then
			info.type = "Obstacle"
			info.priority = 3
			return info
		end
	end
	
	if hit:IsA("BasePart") and hit.CanCollide then
		info.type = "Solid"
		info.priority = 2
	else
		info.type = "Empty"
		info.priority = 0
	end
	
	return info
end

-- ================= ADVANCED LIDAR SYSTEM =================
local function performFullLiDARScan()
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	local rightDir = rootPart.CFrame.RightVector
	
	lidarSystem.allDetections = {}
	local allObstacles = {}
	local allPlayers = {}
	local allInteractables = {}
	local allDangers = {}
	
	-- FORWARD BEAMS (9 beams for better coverage)
	lidarSystem.forward = {}
	local forwardAngles = {-1.4, -1.0, -0.6, -0.3, 0, 0.3, 0.6, 1.0, 1.4}
	for i, angle in ipairs(forwardAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * CONFIG.RAYCAST_DISTANCE
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(origin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = "forward",
			angle = math.deg(angle),
			distance = CONFIG.RAYCAST_DISTANCE,
			hit = false
		}
		
		if success and rayResult then
			local objInfo = identifyObject(rayResult.Instance)
			objInfo.distance = rayResult.Distance
			objInfo.position = rayResult.Position
			
			beamData.distance = rayResult.Distance
			beamData.hit = true
			beamData.object = objInfo
			
			table.insert(lidarSystem.allDetections, objInfo)
			
			if objInfo.isDangerous then
				table.insert(allDangers, objInfo)
			elseif objInfo.isPlayer then
				table.insert(allPlayers, objInfo)
			elseif objInfo.isInteractive then
				table.insert(allInteractables, objInfo)
			elseif objInfo.type ~= "Empty" then
				table.insert(allObstacles, objInfo)
			end
		end
		
		lidarSystem.forward[i] = beamData
	end
	
	-- SIDE BEAMS (left and right)
	lidarSystem.sides = {}
	local sideAngles = {-1.57, 1.57}  -- 90° left and right
	for i, angle in ipairs(sideAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * (CONFIG.RAYCAST_DISTANCE * 0.6)
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(origin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = angle < 0 and "left" or "right",
			distance = CONFIG.RAYCAST_DISTANCE * 0.6,
			hit = false
		}
		
		if success and rayResult then
			local objInfo = identifyObject(rayResult.Instance)
			objInfo.distance = rayResult.Distance
			objInfo.position = rayResult.Position
			
			beamData.distance = rayResult.Distance
			beamData.hit = true
			beamData.object = objInfo
			
			table.insert(lidarSystem.allDetections, objInfo)
			
			if objInfo.isDangerous then
				table.insert(allDangers, objInfo)
			end
		end
		
		lidarSystem.sides[i] = beamData
	end
	
	-- BELOW BEAMS (ground check)
	lidarSystem.below = {}
	local belowOrigin = rootPart.Position + Vector3.new(0, 1, 0)
	local belowAngles = {-0.5, -0.25, 0, 0.25, 0.5}
	for i, angle in ipairs(belowAngles) do
		local horizontalDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = (horizontalDir - Vector3.new(0, 1.5, 0)).Unit * 8
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(belowOrigin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = "below",
			angle = math.deg(angle),
			distance = 8,
			hit = false
		}
		
		if success and rayResult then
			local objInfo = identifyObject(rayResult.Instance)
			objInfo.distance = rayResult.Distance
			
			beamData.distance = rayResult.Distance
			beamData.hit = true
			beamData.object = objInfo
			
			if objInfo.isDangerous then
				table.insert(allDangers, objInfo)
			end
		end
		
		lidarSystem.below[i] = beamData
	end
	
	-- BEHIND BEAMS (rear awareness)
	lidarSystem.behind = {}
	local behindAngles = {-2.8, -2.4, 3.14159, 2.4, 2.8}
	for i, angle in ipairs(behindAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * (CONFIG.RAYCAST_DISTANCE * 0.5)
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(origin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = "behind",
			angle = math.deg(angle),
			distance = CONFIG.RAYCAST_DISTANCE * 0.5,
			hit = false
		}
		
		if success and rayResult then
			local objInfo = identifyObject(rayResult.Instance)
			objInfo.distance = rayResult.Distance
			
			beamData.distance = rayResult.Distance
			beamData.hit = true
			beamData.object = objInfo
			
			if objInfo.isPlayer then
				table.insert(allPlayers, objInfo)
			end
		end
		
		lidarSystem.behind[i] = beamData
	end
	
	-- Sphere-based player detection
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local distance = (otherRoot.Position - rootPart.Position).Magnitude
				if distance < CONFIG.PLAYER_DETECTION_DISTANCE then
					local userId = tostring(otherPlayer.UserId)
					local isHostile = botControl.rememberedPlayers[userId] and 
						botControl.rememberedPlayers[userId].hostile or false
					
					botControl.nearbyPlayers[userId] = {
						name = otherPlayer.Name,
						position = otherRoot.Position,
						distance = distance,
						lastSeen = tick(),
						hostile = isHostile,
						damageDealt = botControl.nearbyPlayers[userId] and 
							botControl.nearbyPlayers[userId].damageDealt or 0
					}
					
					if not botControl.rememberedPlayers[userId] then
						botControl.rememberedPlayers[userId] = {
							name = otherPlayer.Name,
							hostile = false,
							lastSeen = tick(),
							encounters = 1,
							damageDealt = 0
						}
					else
						botControl.rememberedPlayers[userId].lastSeen = tick()
					end
				end
			end
		end
	end
	
	-- Find nearest of each type
	lidarSystem.nearestObstacle = nil
	lidarSystem.nearestPlayer = nil
	lidarSystem.nearestInteractable = nil
	
	local minObstacleDist = math.huge
	for _, obs in ipairs(allObstacles) do
		if obs.distance < minObstacleDist then
			minObstacleDist = obs.distance
			lidarSystem.nearestObstacle = obs
		end
	end
	
	local minPlayerDist = math.huge
	for _, plr in ipairs(allPlayers) do
		if plr.distance < minPlayerDist then
			minPlayerDist = plr.distance
			lidarSystem.nearestPlayer = plr
		end
	end
	
	local minInteractDist = math.huge
	for _, obj in ipairs(allInteractables) do
		if obj.distance < minInteractDist then
			minInteractDist = obj.distance
			lidarSystem.nearestInteractable = obj
		end
	end
	
	-- Calculate summary metrics
	local forwardDistances = {}
	for _, beam in ipairs(lidarSystem.forward) do
		table.insert(forwardDistances, beam.distance)
	end
	
	local leftClear = (forwardDistances[1] + forwardDistances[2] + forwardDistances[3]) / 3 > CONFIG.SAFE_DISTANCE
	local rightClear = (forwardDistances[7] + forwardDistances[8] + forwardDistances[9]) / 3 > CONFIG.SAFE_DISTANCE
	local centerClear = forwardDistances[5] > CONFIG.SAFE_DISTANCE
	
	lidarSystem.pathClear = centerClear
	lidarSystem.dangerAhead = #allDangers > 0 and allDangers[1].distance < CONFIG.DANGER_DISTANCE
	
	return {
		forwardDistances = forwardDistances,
		leftClear = leftClear,
		rightClear = rightClear,
		centerClear = centerClear,
		minDistance = math.min(table.unpack(forwardDistances)),
		hasPlayers = #allPlayers > 0,
		hasInteractables = #allInteractables > 0,
		hasDanger = #allDangers > 0,
		nearestDangerDist = #allDangers > 0 and allDangers[1].distance or math.huge
	}
end

-- ================= MOVEMENT DETECTION =================
local function getActualMovementSpeed()
	local velocity = rootPart.AssemblyVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	botControl.actualVelocity = horizontalVelocity.Magnitude
	return botControl.actualVelocity
end

local function isActuallyMoving()
	return botControl.actualVelocity > CONFIG.MIN_MOVEMENT_SPEED
end

local function checkIfStuck()
	local now = tick()
	if now - botControl.lastStuckCheck < CONFIG.STUCK_CHECK_TIME then
		return botControl.stuckCounter > 0
	end
	
	botControl.lastStuckCheck = now
	
	if not isActuallyMoving() and botControl.lastAction and 
	   (botControl.lastAction:find("forward") or botControl.lastAction:find("strafe")) then
		botControl.stuckCounter = botControl.stuckCounter + 1
	else
		botControl.stuckCounter = math.max(0, botControl.stuckCounter - 1)
	end
	
	return botControl.stuckCounter >= CONFIG.STUCK_THRESHOLD
end

-- ================= Q-LEARNING =================
local function discretizeState(lidarData)
	local function getBin(distance)
		if distance < 5 then return "vclose"
		elseif distance < 12 then return "close"
		elseif distance < 20 then return "med"
		else return "far"
		end
	end
	
	local left = getBin((lidarData.forwardDistances[1] + lidarData.forwardDistances[2]) / 2)
	local center = getBin(lidarData.forwardDistances[5])
	local right = getBin((lidarData.forwardDistances[8] + lidarData.forwardDistances[9]) / 2)
	
	local hasInteractable = lidarData.hasInteractables and "item" or "noitem"
	local hasPlayer = lidarData.hasPlayers and "player" or "noplayer"
	local hasDanger = lidarData.hasDanger and "danger" or "safe"
	local moving = isActuallyMoving() and "moving" or "stuck"
	local stuck = checkIfStuck() and "stuck" or "free"
	
	-- Check for hostile players
	local hostileNearby = "nohostile"
	for userId, playerData in pairs(botControl.nearbyPlayers) do
		if playerData.hostile and playerData.distance < 30 then
			hostileNearby = "hostile"
			break
		end
	end
	
	-- Check escape mode
	local escaping = botControl.escapeMode and "escape" or "normal"
	
	return string.format("%s_%s_%s_%s_%s_%s_%s_%s_%s_%s", 
		left, center, right, hasInteractable, hasPlayer, hasDanger, 
		moving, stuck, hostileNearby, escaping)
end

local function getQValue(state, action)
	if not qTable[state] then qTable[state] = {} end
	if not qTable[state][action] then qTable[state][action] = 0 end
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

local function chooseAction(state, lidarData)
	-- Stuck detection - emergency actions
	if checkIfStuck() then
		botControl.forceForwardCounter = 0
		local options = {"back_left", "back_right", "sharp_left", "sharp_right"}
		return options[math.random(#options)]
	end
	
	-- Force forward movement counter
	if botControl.forceForwardCounter > 0 then
		botControl.forceForwardCounter = botControl.forceForwardCounter - 1
		if lidarData.centerClear then
			return "forward"
		else
			return lidarData.leftClear and "forward_left" or "forward_right"
		end
	end
	
	-- If not moving for too long, force movement
	if not isActuallyMoving() and tick() - botControl.lastMovementTime > 3 then
		botControl.forceForwardCounter = 8
		return "forward"
	end
	
	-- Epsilon-greedy with forward bias
	if math.random() < botControl.explorationRate then
		-- Exploration - bias toward forward actions
		if math.random() < 0.65 and lidarData.centerClear then
			local forwardActions = {"forward", "forward_left", "forward_right", "slow_forward"}
			return forwardActions[math.random(#forwardActions)]
		else
			return actionList[math.random(#actionList)]
		end
	else
		-- Exploitation
		return getBestAction(state)
	end
end

local function updateQValue(state, action, reward, nextState)
	local currentQ = getQValue(state, action)
	local _, maxNextQ = getBestAction(nextState)
	
	local newQ = currentQ + CONFIG.LEARNING_RATE * 
		(reward + CONFIG.DISCOUNT_FACTOR * maxNextQ - currentQ)
	
	if not qTable[state] then qTable[state] = {} end
	qTable[state][action] = newQ
end

-- ================= ACTION EXECUTION =================
local function executeAction(action, lidarData)
	local moveVector = Vector3.zero
	local turnAngle = 0
	local moveSpeed = 1
	
	-- Action definitions
	if action == "forward" then
		moveVector = rootPart.CFrame.LookVector
		turnAngle = 0
		moveSpeed = 1
	elseif action == "forward_left" then
		moveVector = rootPart.CFrame.LookVector
		turnAngle = -CONFIG.TURN_SPEED
		moveSpeed = 0.9
	elseif action == "forward_right" then
		moveVector = rootPart.CFrame.LookVector
		turnAngle = CONFIG.TURN_SPEED
		moveSpeed = 0.9
	elseif action == "sharp_left" then
		moveVector = rootPart.CFrame.LookVector * 0.6
		turnAngle = -CONFIG.TURN_SPEED * 1.8
		moveSpeed = 0.6
	elseif action == "sharp_right" then
		moveVector = rootPart.CFrame.LookVector * 0.6
		turnAngle = CONFIG.TURN_SPEED * 1.8
		moveSpeed = 0.6
	elseif action == "back_left" then
		moveVector = -rootPart.CFrame.LookVector * 0.7
		turnAngle = -CONFIG.TURN_SPEED
		moveSpeed = 0.7
	elseif action == "back_right" then
		moveVector = -rootPart.CFrame.LookVector * 0.7
		turnAngle = CONFIG.TURN_SPEED
		moveSpeed = 0.7
	elseif action == "strafe_left" then
		moveVector = -rootPart.CFrame.RightVector
		turnAngle = 0
		moveSpeed = 0.75
	elseif action == "strafe_right" then
		moveVector = rootPart.CFrame.RightVector
		turnAngle = 0
		moveSpeed = 0.75
	elseif action == "slow_forward" then
		moveVector = rootPart.CFrame.LookVector
		turnAngle = 0
		moveSpeed = 0.5
	elseif action == "emergency_back" then
		moveVector = -rootPart.CFrame.LookVector
		turnAngle = 0
		moveSpeed = 1
	end
	
	-- Normalize
