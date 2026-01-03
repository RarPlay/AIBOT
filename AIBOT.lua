-- AI Bot Controller Script
-- Place in a LocalScript in StarterPlayerScripts

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

-- Local player reference
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Bot references
local bot = nil
local botHumanoid = nil
local botRootPart = nil
local botCamera = nil

-- Bot state
local botActive = true
local botAlive = true
local botTargetPlayer = nil
local movementDirection = 1  -- 1 for forward, -1 for backward
local lastPathUpdate = 0
local pathUpdateInterval = 0.3  -- Update path every 0.3 seconds
local avoidanceVector = Vector3.new(0, 0, 0)

-- UI elements
local screenGui = nil
local stopButton = nil
local startButton = nil
local statusLabel = nil

-- LiDAR Configuration
local RAY_COUNT = 5
local RAY_SPREAD = math.rad(70)  -- 70 degree total spread (35 left, 35 right)
local RAY_LENGTH = 20
local MIN_OBSTACLE_DISTANCE = 5
local TURN_SPEED = 0.15
local MOVEMENT_SPEED = 16
local STUCK_TIMER = 0
local STUCK_THRESHOLD = 3  -- Seconds before considering stuck

-- Create the UI
local function createUI()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BotControlUI_" .. HttpService:GenerateGUID(false):sub(1, 8)
    screenGui.Parent = playerGui
    
    -- Stop Button (Middle-Left)
    stopButton = Instance.new("TextButton")
    stopButton.Name = "StopBotButton"
    stopButton.Size = UDim2.new(0, 120, 0, 45)
    stopButton.Position = UDim2.new(0.05, 0, 0.5, -22.5)
    stopButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    stopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopButton.Text = "⏸️ Stop Bot"
    stopButton.Font = Enum.Font.SourceSansBold
    stopButton.TextSize = 18
    stopButton.ZIndex = 10
    stopButton.Parent = screenGui
    
    -- Start Button (Middle-Right)
    startButton = Instance.new("TextButton")
    startButton.Name = "StartBotButton"
    startButton.Size = UDim2.new(0, 120, 0, 45)
    startButton.Position = UDim2.new(0.95, -120, 0.5, -22.5)
    startButton.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
    startButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    startButton.Text = "▶️ Start Bot"
    startButton.Font = Enum.Font.SourceSansBold
    startButton.TextSize = 18
    startButton.ZIndex = 10
    startButton.Parent = screenGui
    
    -- Status Label
    statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "BotStatus"
    statusLabel.Size = UDim2.new(0, 200, 0, 30)
    statusLabel.Position = UDim2.new(0.5, -100, 0.1, 0)
    statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    statusLabel.BackgroundTransparency = 0.5
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.Text = "🤖 Bot: ACTIVE"
    statusLabel.Font = Enum.Font.SourceSansSemibold
    statusLabel.TextSize = 16
    statusLabel.ZIndex = 10
    statusLabel.Parent = screenGui
    
    -- Rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = stopButton
    
    local corner2 = Instance.new("UICorner")
    corner2.CornerRadius = UDim.new(0, 8)
    corner2.Parent = startButton
    
    local corner3 = Instance.new("UICorner")
    corner3.CornerRadius = UDim.new(0, 8)
    corner3.Parent = statusLabel
    
    -- Drop shadows
    local shadow1 = Instance.new("UIStroke")
    shadow1.Color = Color3.fromRGB(0, 0, 0)
    shadow1.Thickness = 2
    shadow1.Parent = stopButton
    
    local shadow2 = Instance.new("UIStroke")
    shadow2.Color = Color3.fromRGB(0, 0, 0)
    shadow2.Thickness = 2
    shadow2.Parent = startButton
    
    -- Button functionality
    stopButton.MouseButton1Click:Connect(function()
        botActive = false
        statusLabel.Text = "🤖 Bot: PAUSED"
        statusLabel.BackgroundColor3 = Color3.fromRGB(180, 120, 0)
    end)
    
    startButton.MouseButton1Click:Connect(function()
        botActive = true
        statusLabel.Text = "🤖 Bot: ACTIVE"
        statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end)
end

-- Initialize the bot character
local function initializeBot()
    -- Wait for player character
    local playerCharacter = player.Character
    if not playerCharacter then
        playerCharacter = player.CharacterAdded:Wait()
    end
    
    -- Clone player's character for the bot
    bot = playerCharacter:Clone()
    bot.Name = "AIBot_" .. player.Name .. "_" .. HttpService:GenerateGUID(false):sub(1, 6)
    
    -- Position bot near player
    local spawnPosition = playerCharacter:GetPivot().Position + Vector3.new(5, 0, 5)
    bot:PivotTo(CFrame.new(spawnPosition))
    
    -- Remove any existing scripts from bot
    for _, child in ipairs(bot:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") then
            child:Destroy()
        end
    end
    
    bot.Parent = Workspace
    
    -- Get bot components
    botHumanoid = bot:WaitForChild("Humanoid")
    botRootPart = bot:WaitForChild("HumanoidRootPart")
    
    -- Configure bot humanoid
    botHumanoid.WalkSpeed = MOVEMENT_SPEED
    botHumanoid.JumpPower = 50
    botHumanoid.AutoRotate = false
    
    -- Create bot camera
    botCamera = Instance.new("Camera")
    botCamera.Name = "BotCamera"
    botCamera.CFrame = botRootPart.CFrame * CFrame.new(0, 3, -8)
    botCamera.Parent = bot
    
    -- Set up damage detection
    botHumanoid.HealthChanged:Connect(function(health)
        if health < botHumanoid.MaxHealth and health > 0 then
            print("Damage - Bot health: " .. math.floor(health))
            
            -- Visual feedback for damage
            if botRootPart then
                local damageIndicator = Instance.new("Part")
                damageIndicator.Size = Vector3.new(1, 1, 1)
                damageIndicator.CFrame = botRootPart.CFrame
                damageIndicator.Color = Color3.fromRGB(255, 50, 50)
                damageIndicator.Material = Enum.Material.Neon
                damageIndicator.Transparency = 0.3
                damageIndicator.Anchored = true
                damageIndicator.CanCollide = false
                damageIndicator.Parent = Workspace
                
                game:GetService("Debris"):AddItem(damageIndicator, 0.3)
            end
        end
    end)
    
    -- Set up death detection
    botHumanoid.Died:Connect(function()
        botAlive = false
        print("Malfunction - Bot has been destroyed!")
        statusLabel.Text = "🤖 Bot: DESTROYED"
        statusLabel.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
        
        -- Reset bot after delay
        task.wait(3)
        botAlive = true
        initializeBot()
    end)
    
    -- Show launch notification
    StarterGui:SetCore("SendNotification", {
        Title = "🤖 AI Bot Activated",
        Text = "Bot is now under your control!",
        Icon = "rbxassetid://4483345998",
        Duration = 5
    })
    
    return bot
end

-- Perform LiDAR scan to detect obstacles
local function performLiDARScan()
    if not botRootPart or not botAlive then return {} end
    
    local scanResults = {
        leftObstacle = false,
        rightObstacle = false,
        centerObstacle = false,
        distances = {},
        averageDistance = RAY_LENGTH
    }
    
    local rootPosition = botRootPart.Position
    local lookVector = botRootPart.CFrame.LookVector
    
    -- Cast 5 rays in a spread pattern
    for i = 1, RAY_COUNT do
        -- Calculate ray direction with spread
        local angleOffset = ((i - 1) / (RAY_COUNT - 1) - 0.5) * RAY_SPREAD
        local rayDirection = (CFrame.fromEulerAnglesXYZ(0, angleOffset, 0) * lookVector).Unit
        
        -- Prepare raycast parameters
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {bot}
        raycastParams.IgnoreWater = true
        
        -- Cast the ray
        local rayResult = Workspace:Raycast(
            rootPosition + Vector3.new(0, 1, 0),  -- Start from chest height
            rayDirection * RAY_LENGTH,
            raycastParams
        )
        
        -- Process results
        local distance = RAY_LENGTH
        if rayResult then
            distance = (rayResult.Position - rootPosition).Magnitude
            
            -- Categorize obstacle based on ray angle
            if distance < MIN_OBSTACLE_DISTANCE then
                if angleOffset < -0.2 then  -- Left side
                    scanResults.leftObstacle = true
                elseif angleOffset > 0.2 then  -- Right side
                    scanResults.rightObstacle = true
                else  -- Center
                    scanResults.centerObstacle = true
                end
            end
        end
        
        -- Store distance for averaging
        scanResults.distances[i] = distance
    end
    
    -- Calculate average distance
    local totalDistance = 0
    for _, dist in ipairs(scanResults.distances) do
        totalDistance = totalDistance + dist
    end
    scanResults.averageDistance = totalDistance / RAY_COUNT
    
    return scanResults
end

-- Calculate avoidance vector based on LiDAR scan
local function calculateAvoidance(scanResults)
    if scanResults.averageDistance >= RAY_LENGTH then
        return Vector3.new(0, 0, 0)  -- No obstacles detected
    end
    
    local avoidance = Vector3.new(0, 0, 0)
    
    -- Determine turn direction based on obstacle positions
    if scanResults.centerObstacle then
        if scanResults.leftObstacle and not scanResults.rightObstacle then
            -- Obstacle on left, turn right
            avoidance = botRootPart.CFrame.RightVector * 2
        elseif scanResults.rightObstacle and not scanResults.leftObstacle then
            -- Obstacle on right, turn left
            avoidance = botRootPart.CFrame.RightVector * -2
        elseif scanResults.leftObstacle and scanResults.rightObstacle then
            -- Trapped, turn around
            movementDirection = movementDirection * -1
            avoidance = botRootPart.CFrame.LookVector * -2
        else
            -- Just center obstacle, slight random turn
            avoidance = botRootPart.CFrame.RightVector * (math.random() > 0.5 and 1 or -1) * 1.5
        end
    else
        -- Only side obstacles, slight adjustment
        if scanResults.leftObstacle then
            avoidance = avoidance + botRootPart.CFrame.RightVector * 1
        end
        if scanResults.rightObstacle then
            avoidance = avoidance + botRootPart.CFrame.RightVector * -1
        end
    end
    
    -- Add some randomness to avoid getting stuck
    avoidance = avoidance + Vector3.new(
        (math.random() - 0.5) * 0.3,
        0,
        (math.random() - 0.5) * 0.3
    )
    
    return avoidance
end

-- Plan movement path
local function planMovement()
    if not botActive or not botAlive then return nil end
    
    local currentTime = tick()
    if currentTime - lastPathUpdate < pathUpdateInterval then
        return nil
    end
    
    lastPathUpdate = currentTime
    
    -- Perform LiDAR scan
    local scanResults = performLiDARScan()
    
    -- Calculate avoidance
    avoidanceVector = calculateAvoidance(scanResults)
    
    -- Check if stuck (not moving for too long)
    if scanResults.averageDistance < 2 then
        STUCK_TIMER = STUCK_TIMER + pathUpdateInterval
        if STUCK_TIMER > STUCK_THRESHOLD then
            -- Random turn to escape
            movementDirection = movementDirection * -1
            avoidanceVector = botRootPart.CFrame.LookVector * -3 + botRootPart.CFrame.RightVector * (math.random() > 0.5 and 2 or -2)
            STUCK_TIMER = 0
        end
    else
        STUCK_TIMER = 0
    end
    
    -- Determine movement direction
    local moveDirection = botRootPart.CFrame.LookVector * movementDirection
    
    -- Apply avoidance
    if avoidanceVector.Magnitude > 0 then
        moveDirection = (moveDirection + avoidanceVector * 0.5).Unit
    end
    
    return moveDirection
end

-- Update bot movement
local function updateBotMovement()
    if not botActive or not botAlive or not botRootPart or not botHumanoid then return end
    
    -- Calculate movement
    local moveDirection = planMovement()
    
    if moveDirection then
        -- Move the bot
        botHumanoid:Move(moveDirection)
        
        -- Smoothly rotate bot towards movement direction
        if moveDirection.Magnitude > 0.1 then
            local goalCFrame = CFrame.lookAt(
                botRootPart.Position,
                botRootPart.Position + moveDirection,
                Vector3.new(0, 1, 0)
            )
            
            botRootPart.CFrame = botRootPart.CFrame:Lerp(goalCFrame, TURN_SPEED)
        end
        
        -- Update bot camera to follow
        if botCamera then
            local cameraOffset = CFrame.new(0, 3, -8)
            local targetCFrame = botRootPart.CFrame * cameraOffset
            botCamera.CFrame = botCamera.CFrame:Lerp(targetCFrame, 0.1)
        end
    end
end

-- Chat listener for "Bubble 1" command
local function setupChatListener()
    -- Listen for player chat messages
    local function processChatMessage(speaker, message)
        if string.lower(message) == "bubble 1" and speaker ~= player then
            botTargetPlayer = speaker
            print("🎯 Bot targeting: " .. speaker.Name)
            
            -- Visual indicator
            if statusLabel then
                statusLabel.Text = "🎯 Bot: TARGETING " .. speaker.Name
                statusLabel.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
            end
            
            -- Target for 10 seconds, then resume wandering
            task.wait(10)
            if botTargetPlayer == speaker then
                botTargetPlayer = nil
                if botActive then
                    statusLabel.Text = "🤖 Bot: ACTIVE"
                    statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                end
            end
        end
    end
    
    -- Create a simple chat listener
    -- Note: For a complete game, you should use the ChatService API
    local function onPlayerChatted(chatMessage)
        if chatMessage.Speaker then
            processChatMessage(chatMessage.Speaker, chatMessage.Message)
        end
    end
    
    -- Listen for chat events (simplified - in production use ChatService)
    local ChatService = game:GetService("Chat")
    
    -- This event might not exist in all games, so we'll also check manually
    if ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents") then
        local chatEvents = ReplicatedStorage.DefaultChatSystemChatEvents
        if chatEvents:FindFirstChild("OnMessageDoneFiltering") then
            chatEvents.OnMessageDoneFiltering.OnClientEvent:Connect(function(chatData)
                if chatData.FromSpeaker and chatData.Message then
                    processChatMessage(Players:FindFirstChild(chatData.FromSpeaker), chatData.Message)
                end
            end)
        end
    end
end

-- Update bot targeting
local function updateBotTargeting()
    if not botTargetPlayer or not botActive or not botAlive then return end
    
    local targetCharacter = botTargetPlayer.Character
    if not targetCharacter then
        botTargetPlayer = nil
        return
    end
    
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not botRootPart then return end
    
    -- Calculate direction to target
    local targetDirection = (targetRoot.Position - botRootPart.Position).Unit
    
    -- Move towards target
    botHumanoid:Move(targetDirection)
    
    -- Rotate towards target
    local goalCFrame = CFrame.lookAt(botRootPart.Position, targetRoot.Position)
    botRootPart.CFrame = botRootPart.CFrame:Lerp(goalCFrame, TURN_SPEED)
end

-- Main loop
local function main()
    -- Create UI
    createUI()
    
    -- Initialize bot
    task.wait(1)  -- Wait a moment for everything to load
    initializeBot()
    
    -- Setup chat listener
    setupChatListener()
    
    -- Main update loop
    local connection = RunService.Heartbeat:Connect(function(deltaTime)
        if botTargetPlayer then
            updateBotTargeting()
        else
            updateBotMovement()
        end
    end)
    
    -- Cleanup when player leaves
    player.CharacterRemoving:Connect(function()
        if bot then
            bot:Destroy()
        end
        if screenGui then
            screenGui:Destroy()
        end
        connection:Disconnect()
    end)
    
    print("🤖 AI Bot System Initialized Successfully!")
    print("Controls:")
    print("- UI buttons to start/stop bot")
    print("- Type 'Bubble 1' in chat to make bot follow you")
    print("- Bot uses LiDAR to avoid obstacles")
end

-- Start the system
main()
