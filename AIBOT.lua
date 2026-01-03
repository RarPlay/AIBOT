-- =========================================
-- ULTRA-SMART AI BOT - Full 360° Awareness, Combat, Tool Usage
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
	RAYCAST_DISTANCE = 35,
	MIN_MOVEMENT_SPEED = 2,
	STUCK_THRESHOLD = 2,
	INTERACTION_DISTANCE = 12,
	PLAYER_DETECTION_DISTANCE = 50,
	COIN_LOSS_PER_HIT = 5,
	LIDAR_UPDATE_INTERVAL = 0.1,
	LEARNING_RATE = 0.25,
	DISCOUNT_FACTOR = 0.9,
	EXPLORATION_RATE = 0.5,  -- Start with MORE exploration
	EXPLORATION_DECAY = 0.999,  -- Decay slower
	MIN_EXPLORATION = 0.1,  -- Keep exploring at 10% minimum
	TOOL_USE_CONFIDENCE = 0.6,
	CLICK_CONFIDENCE = 0.55,
	DAMAGE_MEMORY_DURATION = 60
}

local INTERACTIVE_TAGS = {"Coin", "Collectible", "Button", "Door", "Chest", "Item", "Tool", "Weapon"}
local OBSTACLE_TAGS = {"Wall", "Barrier", "Obstacle"}
local DANGEROUS_TAGS = {"Spike", "Lava", "Trap", "Danger", "Kill"}

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
	explorationRate = CONFIG.EXPLORATION_RATE,
	isMoving = false,
	forceForward = 0,  -- Counter to force forward movement
	
	-- Damage tracking
	lastHealth = 100,
	dangerousObjects = {}, -- {id = {name, position, damage, lastSeen, timesHit}}
	lastDamageSource = nil,
	lastDamageTime = 0,
	totalDamageTaken = 0,
	
	-- Player tracking
	nearbyPlayers = {}, -- {userId = {name, position, distance, lastSeen, hostile, friendly}}
	rememberedPlayers = {}, -- Long-term player memory
	
	-- Object memory
	rememberedObjects = {}, -- {id = {name, type, position, interactions, lastSeen}}
	
	-- Tool usage
	currentTool = nil,
	toolUseConfidence = 0,
	lastToolUse = 0,
	clickConfidence = 0,
	lastClick = 0
}

-- ================= LIDAR SYSTEM =================
local lidarSystem = {
	forward = {}, -- 7 beams
	below = {},   -- 5 beams
	behind = {},  -- 5 beams
	allDetections = {},
	nearestObstacle = nil,
	nearestPlayer = nil,
	nearestInteractable = nil
}

-- ================= Q-LEARNING =================
local qTable = {}
local actionList = {
	"forward",
	"forward_left",
	"forward_right",
	"sharp_left",
	"sharp_right",
	"backup_left",
	"backup_right",
	"strafe_left",
	"strafe_right",
	"circle_left",
	"circle_right"
}

-- ================= CHARACTER SETUP =================
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

botControl.lastPosition = rootPart.Position
botControl.currentPosition = rootPart.Position
botControl.lastHealth = humanoid.Health

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🧠 ULTRA-SMART AI - 360° AWARENESS + COMBAT")
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

-- ================= DAMAGE TRACKING =================
humanoid.HealthChanged:Connect(function(health)
	if health < botControl.lastHealth then
		local damage = botControl.lastHealth - health
		botControl.lastDamageTime = tick()
		botControl.totalDamageTaken = botControl.totalDamageTaken + damage
		
		-- Try to identify damage source
		local touchingParts = rootPart:GetTouchingParts()
		for _, part in ipairs(touchingParts) do
			local isDangerous = false
			for _, tag in ipairs(DANGEROUS_TAGS) do
				if part:HasTag(tag) or part.Name:find(tag) then
					isDangerous = true
					break
				end
			end
			
			if isDangerous or part.Name:find("Damage") then
				local id = tostring(part:GetFullName())
				
				-- Update or create dangerous object entry
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
				
				print(string.format("⚠️ DAMAGE: -%d HP from '%s' (Hit #%d, Total: -%d HP)", 
					damage, part.Name, botControl.dangerousObjects[id].timesHit,
					botControl.dangerousObjects[id].damage))
				print(string.format("   ID: %s", id))
				
				-- Enter escape mode
				botControl.escapeMode = true
				botControl.escapeStartTime = tick()
			end
		end
		
		-- Check if a player might have damaged us
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude < 20 then
					local userId = tostring(otherPlayer.UserId)
					
					-- Mark player as potentially hostile
					if botControl.nearbyPlayers[userId] then
						botControl.nearbyPlayers[userId].hostile = true
						botControl.nearbyPlayers[userId].damageDealt = 
							(botControl.nearbyPlayers[userId].damageDealt or 0) + damage
					end
					
					-- Remember in long-term memory
					botControl.rememberedPlayers[userId] = {
						name = otherPlayer.Name,
						hostile = true,
						lastSeen = tick(),
						damageDealt = damage,
						encounters = (botControl.rememberedPlayers[userId] and 
							botControl.rememberedPlayers[userId].encounters or 0) + 1
					}
					
					print(string.format("🎯 Possible attacker: %s (ID: %s) - Marked as HOSTILE", 
						otherPlayer.Name, userId))
				end
			end
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
		distance = 0
	}
	
	-- Check if it's a player
	local humanoidCheck = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
	if humanoidCheck and hit.Parent ~= character then
		local playerCheck = Players:GetPlayerFromCharacter(hit.Parent)
		if playerCheck then
			info.isPlayer = true
			info.type = "Player"
			info.name = playerCheck.Name
			info.id = tostring(playerCheck.UserId)
			return info
		end
	end
	
	-- Check dangerous
	for _, tag in ipairs(DANGEROUS_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			info.isDangerous = true
			info.type = "Danger"
			return info
		end
	end
	
	-- Check if it's a known dangerous object
	if botControl.dangerousObjects[info.id] then
		info.isDangerous = true
		info.type = "DangerousObject"
		return info
	end
	
	-- Check interactive
	for _, tag in ipairs(INTERACTIVE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find(tag) then
			info.isInteractive = true
			info.type = tag
			return info
		end
	end
	
	-- Check obstacles
	for _, tag in ipairs(OBSTACLE_TAGS) do
		if hit:HasTag(tag) or hit.Name:find("Wall") or hit.Name:find("Barrier") then
			info.type = "Obstacle"
			return info
		end
	end
	
	if hit:IsA("BasePart") and hit.CanCollide then
		info.type = "Solid"
	else
		info.type = "Empty"
	end
	
	return info
end

-- ================= ADVANCED LIDAR SYSTEM =================
local cachedLidarData = nil
local lastLidarUpdate = 0

local function performFullLiDARScan()
	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local lookDir = rootPart.CFrame.LookVector
	local rightDir = rootPart.CFrame.RightVector
	
	lidarSystem.allDetections = {}
	local allObstacles = {}
	local allPlayers = {}
	local allInteractables = {}
	
	-- FORWARD BEAMS (7 beams, -90° to +90°)
	lidarSystem.forward = {}
	local forwardAngles = {-1.2, -0.8, -0.4, 0, 0.4, 0.8, 1.2}
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
			
			if objInfo.isPlayer then
				table.insert(allPlayers, objInfo)
				
				-- Remember this player
				botControl.rememberedObjects[objInfo.id] = {
					name = objInfo.name,
					type = "Player",
					position = objInfo.position,
					lastSeen = tick(),
					encounters = (botControl.rememberedObjects[objInfo.id] and 
						botControl.rememberedObjects[objInfo.id].encounters or 0) + 1
				}
			elseif objInfo.isInteractive then
				table.insert(allInteractables, objInfo)
				
				-- Remember interactive objects
				botControl.rememberedObjects[objInfo.id] = {
					name = objInfo.name,
					type = objInfo.type,
					position = objInfo.position,
					lastSeen = tick(),
					interactions = (botControl.rememberedObjects[objInfo.id] and 
						botControl.rememberedObjects[objInfo.id].interactions or 0)
				}
			elseif objInfo.type ~= "Empty" then
				table.insert(allObstacles, objInfo)
				
				-- Remember obstacles
				if not botControl.rememberedObjects[objInfo.id] then
					botControl.rememberedObjects[objInfo.id] = {
						name = objInfo.name,
						type = objInfo.type,
						position = objInfo.position,
						lastSeen = tick(),
						timesEncountered = 1
					}
				else
					botControl.rememberedObjects[objInfo.id].lastSeen = tick()
					botControl.rememberedObjects[objInfo.id].timesEncountered = 
						botControl.rememberedObjects[objInfo.id].timesEncountered + 1
				end
			end
		end
		
		lidarSystem.forward[i] = beamData
	end
	
	-- BELOW BEAMS (5 beams, checking ground)
	lidarSystem.below = {}
	local belowOrigin = rootPart.Position + Vector3.new(0, 1, 0)
	local belowAngles = {-0.6, -0.3, 0, 0.3, 0.6}
	for i, angle in ipairs(belowAngles) do
		local horizontalDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = (horizontalDir - Vector3.new(0, 1.5, 0)).Unit * 10
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(belowOrigin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = "below",
			angle = math.deg(angle),
			distance = 10,
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
				table.insert(allObstacles, objInfo)
			end
		end
		
		lidarSystem.below[i] = beamData
	end
	
	-- BEHIND BEAMS (5 beams, 180° coverage)
	lidarSystem.behind = {}
	local behindAngles = {-2.8, -2.4, -3.14159, 2.4, 2.8}
	for i, angle in ipairs(behindAngles) do
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angle) * lookDir
		local rayDirection = rotatedDir.Unit * (CONFIG.RAYCAST_DISTANCE * 0.7)
		
		local success, rayResult = pcall(function()
			return Workspace:Raycast(origin, rayDirection, rayParams)
		end)
		
		local beamData = {
			direction = "behind",
			angle = math.deg(angle),
			distance = CONFIG.RAYCAST_DISTANCE * 0.7,
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
			
			if objInfo.isPlayer then
				table.insert(allPlayers, objInfo)
			end
		end
		
		lidarSystem.behind[i] = beamData
	end
	
	-- Additional player detection (sphere check)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local distance = (otherRoot.Position - rootPart.Position).Magnitude
				if distance < CONFIG.PLAYER_DETECTION_DISTANCE then
					local userId = tostring(otherPlayer.UserId)
					local playerInfo = {
						type = "Player",
						name = otherPlayer.Name,
						id = userId,
						isPlayer = true,
						distance = distance,
						position = otherRoot.Position
					}
					table.insert(allPlayers, playerInfo)
					
					-- Track player with memory
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
					
					-- Update long-term memory
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
	
	-- Calculate metrics
	local forwardDistances = {}
	for _, beam in ipairs(lidarSystem.forward) do
		table.insert(forwardDistances, beam.distance)
	end
	
	local leftClear = (forwardDistances[1] + forwardDistances[2]) / 2 > CONFIG.SAFE_DISTANCE
	local rightClear = (forwardDistances[6] + forwardDistances[7]) / 2 > CONFIG.SAFE_DISTANCE
	local centerClear = forwardDistances[4] > CONFIG.SAFE_DISTANCE
	
	return {
		forwardDistances = forwardDistances,
		leftClear = leftClear,
		rightClear = rightClear,
		centerClear = centerClear,
		minDistance = math.min(table.unpack(forwardDistances)),
		hasPlayers = #allPlayers > 0,
		hasInteractables = #allInteractables > 0,
		hasDanger = lidarSystem.nearestObstacle and lidarSystem.nearestObstacle.isDangerous or false
	}
end

-- ================= TOOL MANAGEMENT =================
local function updateCurrentTool()
	botControl.currentTool = character:FindFirstChildOfClass("Tool")
	if not botControl.currentTool then
		-- Check backpack
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			local tool = backpack:FindFirstChildOfClass("Tool")
			if tool then
				humanoid:EquipTool(tool)
				botControl.currentTool = tool
			end
		end
	end
end

local function useToolClick(mouseButton)
	if not botControl.currentTool then return false end
	
	local now = tick()
	if now - botControl.lastToolUse < 0.5 then return false end
	
	if mouseButton == 1 then
		-- Left click
		if botControl.currentTool:FindFirstChild("Activated") or botControl.currentTool:FindFirstChild("Handle") then
			botControl.currentTool:Activate()
			botControl.lastToolUse = now
			return true
		end
	end
	
	return false
end

-- ================= Q-LEARNING =================
local function discretizeState(lidarData)
	local function getBin(distance)
		if distance < 4 then return "close"
		elseif distance < 10 then return "medium"
		else return "far"
		end
	end
	
	local left = getBin(lidarData.forwardDistances[2])
	local center = getBin(lidarData.forwardDistances[4])
	local right = getBin(lidarData.forwardDistances[6])
	local hasInteractable = lidarData.hasInteractables and "yes" or "no"
	local hasPlayer = lidarData.hasPlayers and "yes" or "no"
	local hasDanger = lidarData.hasDanger and "yes" or "no"
	local moving = botControl.isMoving and "yes" or "no"
	
	-- Check if we're near a remembered dangerous object
	local nearRememberedDanger = "no"
	if lidarSystem.nearestObstacle then
		local objId = lidarSystem.nearestObstacle.id
		if botControl.dangerousObjects[objId] then
			nearRememberedDanger = "yes"
		end
	end
	
	-- Check if hostile player nearby
	local hostileNearby = "no"
	for userId, playerData in pairs(botControl.nearbyPlayers) do
		if playerData.hostile and playerData.distance < 25 then
			hostileNearby = "yes"
			break
		end
	end
	
	return string.format("%s_%s_%s_%s_%s_%s_%s_%s_%s", 
		left, center, right, hasInteractable, hasPlayer, hasDanger, 
		moving, nearRememberedDanger, hostileNearby)
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

local function chooseAction(state)
	-- Force forward movement occasionally to prevent spinning
	if botControl.forceForward > 0 then
		botControl.forceForward = botControl.forceForward - 1
		return "forward"
	end
	
	-- If not moving for a while, force forward
	if not botControl.isMoving and tick() - botControl.lastMovementTime > 2 then
		botControl.forceForward = 5  -- Force forward for next 5 actions
		return "forward"
	end
	
	-- Epsilon-greedy exploration with bias towards forward movement
	if math.random() < botControl.explorationRate then
		-- 70% chance to pick a forward action during exploration
		if math.random() < 0.7 then
			local forwardActions = {"forward", "forward_left", "forward_right", "strafe_left", "strafe_right"}
			return forwardActions[math.random(#forwardActions)]
		else
			return actionList[math.random(#actionList)]
		end
	else
		return getBestAction(state)
	end
end

local function updateQValue(state, action, reward, nextState)
	local currentQ = getQValue(state, action)
	local _, maxNextQ = getBestAction(nextState)
	
	local newQ = currentQ + CONFIG.LEARNING_RATE * (reward + CONFIG.DISCOUNT_FACTOR * maxNextQ - currentQ)
	
	if not qTable[state] then qTable[state] = {} end
	qTable[state][action] = newQ
end

-- ================= ACTION EXECUTION =================
local function executeAction(action, lidarData)
	local moveVector = Vector3.zero
	local turnAngle = 0
	local moveSpeed = 1
	
	if action == "forward" then
		moveVector = rootPart.CFrame.LookVector
		turnAngle = 0
		moveSpeed = 1
	elseif action == "forward_left" then
		moveVector = rootPart.CFrame.LookVector * 0.9 + (-rootPart.CFrame.RightVector * 0.3)
		turnAngle = -0.08
		moveSpeed = 0.9
	elseif action == "forward_right" then
		moveVector = rootPart.CFrame.LookVector * 0.9 + (rootPart.CFrame.RightVector * 0.3)
		turnAngle = 0.08
		moveSpeed = 0.9
	elseif action == "sharp_left" then
		moveVector = rootPart.CFrame.LookVector * 0.7
		turnAngle = -0.15
		moveSpeed = 0.7
	elseif action == "sharp_right" then
		moveVector = rootPart.CFrame.LookVector * 0.7
		turnAngle = 0.15
		moveSpeed = 0.7
	elseif action == "backup_left" then
		moveVector = -rootPart.CFrame.LookVector * 0.6
		turnAngle = -0.12
		moveSpeed = 0.6
	elseif action == "backup_right" then
		moveVector = -rootPart.CFrame.LookVector * 0.6
		turnAngle = 0.12
		moveSpeed = 0.6
	elseif action == "strafe_left" then
		moveVector = -rootPart.CFrame.RightVector
		turnAngle = 0
		moveSpeed = 0.7
	elseif action == "strafe_right" then
		moveVector = rootPart.CFrame.RightVector
		turnAngle = 0
		moveSpeed = 0.7
	elseif action == "circle_left" then
		moveVector = rootPart.CFrame.LookVector * 0.8 + (-rootPart.CFrame.RightVector * 0.4)
		turnAngle = -0.1
		moveSpeed = 0.8
	elseif action == "circle_right" then
		moveVector = rootPart.CFrame.LookVector * 0.8 + (rootPart.CFrame.RightVector * 0.4)
		turnAngle = 0.1
		moveSpeed = 0.8
	end
	
	-- Normalize movement vector
	if moveVector.Magnitude > 0 then
		moveVector = moveVector.Unit
	end
	
	-- Apply turn ONLY if we have a turn angle
	if turnAngle ~= 0 then
		rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, turnAngle, 0)
	end
	
	-- Set WalkSpeed
	humanoid.WalkSpeed = CONFIG.MOVEMENT_SPEED * moveSpeed
	
	-- FORCE MOVEMENT - Use both methods
	humanoid:Move(moveVector, false)
	humanoid.WalkToPoint = rootPart.Position + (moveVector * 5)
	
	-- Additional force if still not moving
	if moveVector.Magnitude > 0 then
		local bodyVel = rootPart:FindFirstChild("AIVelocity")
		if not bodyVel then
			bodyVel = Instance.new("BodyVelocity")
			bodyVel.Name = "AIVelocity"
			bodyVel.MaxForce = Vector3.new(4000, 0, 4000)
			bodyVel.Parent = rootPart
		end
		bodyVel.Velocity = moveVector * CONFIG.MOVEMENT_SPEED * moveSpeed
		
		-- Remove after a moment
		task.delay(0.1, function()
			if bodyVel and bodyVel.Parent then
				bodyVel:Destroy()
			end
		end)
	end
	
	return moveVector.Magnitude > 0
end

-- ================= ESCAPE BEHAVIOR =================
local function executeEscapeManeuver(lidarData)
	local escapeAction
	
	-- Check if danger is nearby
	if lidarData.hasDanger and lidarSystem.nearestObstacle then
		-- Move away from danger
		local dangerPos = lidarSystem.nearestObstacle.position
		local awayDir = (rootPart.Position - dangerPos).Unit
		local currentLook = rootPart.CFrame.LookVector
		
		local dot = awayDir:Dot(currentLook)
		if dot < 0 then
			escapeAction = math.random() < 0.5 and "sharp_left" or "sharp_right"
		else
			escapeAction = "forward"
		end
	elseif lidarData.leftClear and not lidarData.rightClear then
		escapeAction = "sharp_left"
	elseif lidarData.rightClear and not lidarData.leftClear then
		escapeAction = "sharp_right"
	else
		escapeAction = math.random() < 0.5 and "backup_left" or "backup_right"
	end
	
	executeAction(escapeAction, lidarData)
	
	if tick() - botControl.escapeStartTime > 2 then
		botControl.escapeMode = false
	end
end

-- ================= INTERACTION SYSTEM =================
local function attemptInteraction(interactable)
	if not interactable then return false end
	
	-- Remember this interaction
	if botControl.rememberedObjects[interactable.id] then
		botControl.rememberedObjects[interactable.id].interactions = 
			botControl.rememberedObjects[interactable.id].interactions + 1
		botControl.rememberedObjects[interactable.id].lastSeen = tick()
	end
	
	if interactable.type == "Coin" or interactable.type == "Collectible" then
		botControl.coinsCollected = botControl.coinsCollected + 1
		botControl.score = botControl.score + 10
		print(string.format("💰 Collected %s! (Total: %d)", interactable.name, botControl.coinsCollected))
		return true
	elseif interactable.type == "Tool" or interactable.type == "Weapon" then
		-- Try to pick up tool
		botControl.toolUseConfidence = botControl.toolUseConfidence + 0.1
		print(string.format("🔧 Picked up tool: %s", interactable.name))
		return true
	end
	
	return false
end

-- ================= REWARD CALCULATION =================
local function calculateReward(lidarData, movementSpeed, interactionSuccess)
	local reward = 0
	
	-- CRITICAL: HUGE Movement rewards to force walking
	if botControl.isMoving and movementSpeed > CONFIG.MIN_MOVEMENT_SPEED then
		reward = reward + 10  -- MASSIVE reward for moving
		botControl.lastMovementTime = tick()
	else
		reward = reward - 5  -- BIG penalty for standing still
	end
	
	-- Extra penalty for spinning without moving forward
	if botControl.lastMoveDistance < 0.3 then
		reward = reward - 8  -- SEVERE penalty for just rotating
	end
	
	-- Collision penalty
	if tick() - botControl.lastDamageTime < 1 then
		reward = reward - 3  -- Penalty for collision/damage
	end
	
	-- Distance rewards
	if lidarData.minDistance < CONFIG.DANGER_DISTANCE then
		reward = reward - 5
	elseif lidarData.minDistance > CONFIG.SAFE_DISTANCE then
		reward = reward + 2
	end
	
	-- Danger avoidance - EXTRA penalty for remembered dangerous objects
	if lidarSystem.nearestObstacle and botControl.dangerousObjects[lidarSystem.nearestObstacle.id] then
		local dangerObj = botControl.dangerousObjects[lidarSystem.nearestObstacle.id]
		reward = reward - (10 + dangerObj.timesHit * 2)  -- Worse penalty for repeated hits
	elseif lidarData.hasDanger then
		reward = reward - 4
	end
	
	-- Hostile player avoidance
	for userId, playerData in pairs(botControl.nearbyPlayers) do
		if playerData.hostile and playerData.distance < 15 then
			reward = reward - 6  -- Avoid hostile players
		end
	end
	
	-- Interaction rewards
	if interactionSuccess then
		reward = reward + 15
	end
	
	-- Player awareness (neutral/friendly)
	if lidarData.hasPlayers then
		local hasHostile = false
		for userId, playerData in pairs(botControl.nearbyPlayers) do
			if playerData.hostile then
				hasHostile = true
				break
			end
		end
		if not hasHostile then
			reward = reward + 1  -- Slight bonus for detecting neutral players
		end
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
	botControl.lastMoveDistance = distance
	botControl.distanceTraveled = botControl.distanceTraveled + distance
	botControl.lastPosition = currentPos
	
	-- Update moving state
	botControl.isMoving = distance > 0.5
	
	return distance / 0.1
end

-- ================= POSITION TRACKING =================
local function updatePositionHistory()
	botControl.currentPosition = rootPart.Position
	
	table.insert(botControl.positionHistory, 1, {
		position = botControl.currentPosition,
		time = tick()
	})
	
	if #botControl.positionHistory > 15 then
		table.remove(botControl.positionHistory)
	end
end
		updateQValue(botControl.lastState, botControl.lastAction, reward, currentState)
	end
	
	-- Save state and action for next iteration
	botControl.lastState = currentState
	botControl.lastAction = action
	
	-- Track unique states learned
	if qTable[currentState] then
		statesLearned = 0
		for _ in pairs(qTable) do
			statesLearned = statesLearned + 1
		end
	end
	
	-- Decay exploration rate
	botControl.explorationRate = math.max(
		CONFIG.MIN_EXPLORATION,
		botControl.explorationRate * CONFIG.EXPLORATION_DECAY
	)
	
	-- Update confidence levels
	if reward > 0 then
		botControl.toolUseConfidence = math.min(1, botControl.toolUseConfidence + 0.01)
		botControl.clickConfidence = math.min(1, botControl.clickConfidence + 0.01)
		botControl.successfulMoves = botControl.successfulMoves + 1
	else
		botControl.toolUseConfidence = math.max(0, botControl.toolUseConfidence - 0.005)
		botControl.clickConfidence = math.max(0, botControl.clickConfidence - 0.005)
		botControl.failedMoves = botControl.failedMoves + 1
	end
	
	-- Update status
	if botControl.escapeMode then
		botControl.status = "ESCAPING"
	elseif interactionSuccess then
		botControl.status = "COLLECTING"
	elseif lidarData.hasPlayers then
		botControl.status = "PLAYER DETECTED"
	elseif lidarData.hasDanger then
		botControl.status = "DANGER NEARBY"
	elseif botControl.isMoving then
		botControl.status = "NAVIGATING"
	else
		botControl.status = "THINKING"
	end
	
	-- Debug info (every 2 seconds)
	if currentTime - lastUpdate > 2 then
		local successRate = botControl.successfulMoves / math.max(1, botControl.successfulMoves + botControl.failedMoves) * 100
		print(string.format("🤖 %s | Coins: %d | Score: %d | Moving: %s", 
			botControl.status, botControl.coinsCollected, botControl.score, 
			botControl.isMoving and "YES" or "NO"))
		print(string.format("📊 States: %d | Success: %.1f%% | Explore: %.2f | Tool: %.2f", 
			statesLearned, successRate, botControl.explorationRate, botControl.toolUseConfidence))
		
		if lidarSystem.nearestObstacle then
			print(string.format("🚧 Nearest: %s (%s) at %.1fm | ID: %s", 
				lidarSystem.nearestObstacle.name,
				lidarSystem.nearestObstacle.type,
				lidarSystem.nearestObstacle.distance,
				lidarSystem.nearestObstacle.id:sub(1, 25)))
		end
		
		if lidarSystem.nearestPlayer then
			local isHostile = botControl.rememberedPlayers[lidarSystem.nearestPlayer.id] and
				botControl.rememberedPlayers[lidarSystem.nearestPlayer.id].hostile or false
			print(string.format("👤 Player: %s (ID: %s) at %.1fm | %s", 
				lidarSystem.nearestPlayer.name,
				lidarSystem.nearestPlayer.id,
				lidarSystem.nearestPlayer.distance,
				isHostile and "⚔️ HOSTILE" or "😐 Neutral"))
		end
		
		if botControl.lastDamageSource and tick() - botControl.lastDamageTime < 10 then
			local dangerObj = botControl.dangerousObjects[botControl.lastDamageSource]
			if dangerObj then
				print(string.format("⚠️ Last damage from: %s (Hit #%d, -%d HP total)", 
					dangerObj.name, dangerObj.timesHit, dangerObj.damage))
			end
		end
		
		-- Show memory statistics
		local rememberedDangers = 0
		local rememberedObjects = 0
		local hostilePlayers = 0
		
		for _ in pairs(botControl.dangerousObjects) do
			rememberedDangers = rememberedDangers + 1
		end
		
		for _ in pairs(botControl.rememberedObjects) do
			rememberedObjects = rememberedObjects + 1
		end
		
		for _, plr in pairs(botControl.rememberedPlayers) do
			if plr.hostile then
				hostilePlayers = hostilePlayers + 1
			end
		end
		
		print(string.format("🧠 Memory: %d dangers, %d objects, %d hostile players, %d total damage taken",
			rememberedDangers, rememberedObjects, hostilePlayers, botControl.totalDamageTaken))
		
		-- Show detected objects summary
		local objectCounts = {obstacles = 0, players = 0, interactables = 0, dangers = 0}
		for _, detection in ipairs(lidarSystem.allDetections) do
			if detection.isPlayer then
				objectCounts.players = objectCounts.players + 1
			elseif detection.isDangerous then
				objectCounts.dangers = objectCounts.dangers + 1
			elseif detection.isInteractive then
				objectCounts.interactables = objectCounts.interactables + 1
			elseif detection.type == "Obstacle" or detection.type == "Solid" then
				objectCounts.obstacles = objectCounts.obstacles + 1
			end
		end
		
		print(string.format("🔍 Detected: %d obstacles, %d players, %d items, %d dangers",
			objectCounts.obstacles, objectCounts.players, 
			objectCounts.interactables, objectCounts.dangers))
		
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		
		lastUpdate = currentTime
	end
end)

-- ================= CLEANUP OLD DATA =================
task.spawn(function()
	while true do
		task.wait(30)
		
		-- Clean up old dangerous objects
		local now = tick()
		for id, obj in pairs(botControl.dangerousObjects) do
			if now - obj.lastSeen > CONFIG.DAMAGE_MEMORY_DURATION then
				botControl.dangerousObjects[id] = nil
			end
		end
		
		-- Clean up old player data
		for userId, playerData in pairs(botControl.nearbyPlayers) do
			if now - playerData.lastSeen > 30 then
				botControl.nearbyPlayers[userId] = nil
			end
		end
	end
end)

print("✅ ULTRA-SMART AI BOT INITIALIZED")
print("Features:")
print("  • 17 LiDAR beams (7 forward, 5 below, 5 behind)")
print("  • 360° awareness with object identification")
print("  • Player detection with name & ID tracking")
print("  • Damage source identification & memory")
print("  • Tool usage with confidence threshold")
print("  • Smart rewards: +5 moving, -1 standing, -3 collision")
print("  • 11 movement actions including strafing & circling")
print("Press 'P' to toggle AI control")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
