--Orginal Author: code.remixed on discord 
--Modified By: Ben 



-- Load NeoUI
local Neo = loadstring(game:HttpGet("https://raw.githubusercontent.com/Neo-223/NeoUi/refs/heads/main/Neo.lua"))()
local window = Neo:CreateWindow("Nebula | Arsenal Custom")
local aimTab = window:CreateTab("Aimbot")
local espTab = window:CreateTab("ESP")
local movementTab = window:CreateTab("Movement")

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

-- ===================== ESP SECTIONS ===================== --

local ESPSettings = {
    Boxes = true,
    Tracers = true,
    Names = true,
    HealthBars = true,
    Distances = true,
    MaxDistance = 1000 -- Default Max Distance
}

local ESPObjects = {}

-- Team check function
local function IsEnemy(player)
    local localTeam = LocalPlayer.Team
    local playerTeam = player.Team
    if localTeam and playerTeam then
        return localTeam.Name ~= playerTeam.Name
    end
    return true -- Default to true if no teams (Free For All)
end

local function CreateESP(player)
    if ESPObjects[player] then return end

    local box = Drawing.new("Square")
    box.Visible = false
    box.Color = Color3.new(1, 0, 0)
    box.Thickness = 1
    box.Filled = false

    local tracer = Drawing.new("Line")
    tracer.Visible = false
    tracer.Color = Color3.new(1, 1, 1)
    tracer.Thickness = 1

    local nameTag = Drawing.new("Text")
    nameTag.Visible = false
    nameTag.Color = Color3.new(1, 1, 1)
    nameTag.Center = true
    nameTag.Size = 14
    nameTag.Outline = true

    local healthBar = Drawing.new("Square")
    healthBar.Visible = false
    healthBar.Color = Color3.new(0, 1, 0)
    healthBar.Thickness = 1
    healthBar.Filled = true

    local distanceText = Drawing.new("Text")
    distanceText.Visible = false
    distanceText.Color = Color3.new(1, 1, 1)
    distanceText.Center = true
    distanceText.Size = 12
    distanceText.Outline = true

    ESPObjects[player] = {
        Box = box,
        Tracer = tracer,
        Name = nameTag,
        Health = healthBar,
        Distance = distanceText
    }
end

local function RemoveESP(player)
    if not ESPObjects[player] then return end
    for _, obj in pairs(ESPObjects[player]) do
        obj:Remove()
    end
    ESPObjects[player] = nil
end

-- ===================== ESP GUI ===================== --
espTab:CreateToggle("Boxes", function(state) ESPSettings.Boxes = state end)
espTab:CreateToggle("Tracers", function(state) ESPSettings.Tracers = state end)
espTab:CreateToggle("Names", function(state) ESPSettings.Names = state end)
espTab:CreateToggle("Health Bars", function(state) ESPSettings.HealthBars = state end)
espTab:CreateToggle("Distance Text", function(state) ESPSettings.Distances = state end)

-- New ESP Max Distance Slider
espTab:CreateSlider("Max ESP Distance", 100, 5000, 1000, function(value)
    ESPSettings.MaxDistance = value
end)

-- ===================== RenderStepped for ESP ===================== --
RunService.RenderStepped:Connect(function()
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local character = player.Character
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")

            if humanoid and humanoid.Health > 0 and hrp and head and IsEnemy(player) then
                local distance = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) 
                                and (LocalPlayer.Character.HumanoidRootPart.Position - hrp.Position).Magnitude 
                                or 9999

                -- Check against dynamic MaxDistance setting
                if distance <= ESPSettings.MaxDistance then
                    CreateESP(player)

                    local esp = ESPObjects[player]
                    local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local rootPos, rootOnScreen = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local onScreen = headOnScreen or rootOnScreen

                    if onScreen then
                        local topY = headPos.Y
                        local bottomY = rootPos.Y
                        local centerX = (headPos.X + rootPos.X) / 2
                        local height = math.abs(bottomY - topY)
                        local width = height / 1.5

                        esp.Box.Visible = ESPSettings.Boxes
                        esp.Box.Size = Vector2.new(width, height)
                        esp.Box.Position = Vector2.new(centerX - width / 2, topY)

                        esp.Tracer.Visible = ESPSettings.Tracers
                        esp.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        esp.Tracer.To = Vector2.new(centerX, bottomY)

                        esp.Name.Visible = ESPSettings.Names
                        esp.Name.Position = Vector2.new(centerX, topY - 14)
                        esp.Name.Text = player.Name

                        esp.Health.Visible = ESPSettings.HealthBars
                        esp.Health.Position = Vector2.new(centerX - width / 2 - 6, bottomY - height)
                        esp.Health.Size = Vector2.new(4, height * (humanoid.Health / humanoid.MaxHealth))
                        -- Color health bar based on health percentage
                        esp.Health.Color = Color3.fromHSV((humanoid.Health / humanoid.MaxHealth) * 0.3, 1, 1)

                        esp.Distance.Visible = ESPSettings.Distances
                        esp.Distance.Position = Vector2.new(centerX, bottomY + 2)
                        esp.Distance.Text = math.floor(distance) .. " studs"
                    else
                        -- Hide if offscreen but valid
                        for _, v in pairs(esp) do v.Visible = false end
                    end
                else
                    -- Remove if out of distance
                    RemoveESP(player)
                end
            else
                RemoveESP(player)
            end
        else
            RemoveESP(player)
        end
    end
end)

Players.PlayerRemoving:Connect(RemoveESP)


-- ===================== AIMBOT ===================== --

local AimSettings = {
    Enabled = false,
    Smoothness = 0.5, -- Lower is smoother, 1 is instant
    TPDelay = 0.1, -- Delay for TP Kill
    TPEnabled = false
}

local FOVSettings = {
    Enabled = false, 
    ShowCircle = false, 
    Radius = 150,
    Circle = Drawing.new("Circle")
}

-- FOV circle setup
FOVSettings.Circle.Visible = false
FOVSettings.Circle.Color = Color3.fromRGB(255, 255, 255)
FOVSettings.Circle.Thickness = 1
FOVSettings.Circle.Filled = false
FOVSettings.Circle.Radius = FOVSettings.Radius
FOVSettings.Circle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

-- Aimbot GUI
aimTab:CreateToggle("Enable Aimbot", function(state)
    AimSettings.Enabled = state
end)

-- New Smoothness Slider
aimTab:CreateSlider("Smoothness", 1, 10, 5, function(value)
    -- Converting 1-10 slider to 0.1-1.0 alpha for Lerp
    AimSettings.Smoothness = value / 10
end)

-- FOV GUI
aimTab:CreateToggle("Use FOV", function(state)
    FOVSettings.Enabled = state
end)

aimTab:CreateToggle("Draw FOV Circle", function(state)
    FOVSettings.ShowCircle = state
    FOVSettings.Circle.Visible = state
end)

aimTab:CreateSlider("FOV Radius", 50, 800, 150, function(value)
    FOVSettings.Radius = value
end)

-- ===================== KILL ALL (TP) LOGIC ===================== --

local tpConnection = nil 
local lastTPTime = 0 -- Timestamp for delay logic

aimTab:CreateToggle("Killall TP", function(state)
    AimSettings.TPEnabled = state
    
    local function GetClosestEnemyForTP()
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return nil end

        local closestEnemy = nil
        local closestDist = math.huge

        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and IsEnemy(plr) then 
                local enemyChar = plr.Character
                local enemyRoot = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
                local humanoid = enemyChar and enemyChar:FindFirstChild("Humanoid")
                
                if enemyRoot and humanoid and humanoid.Health > 0 then
                    local dist = (enemyRoot.Position - myRoot.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closestEnemy = plr
                    end
                end
            end
        end
        return closestEnemy
    end

    if state then
        tpConnection = RunService.Heartbeat:Connect(function()
            -- Check Team
            if LocalPlayer.Team and LocalPlayer.Team.Name == "Spectator" then return end
            
            -- Check Delay
            if tick() - lastTPTime < AimSettings.TPDelay then return end
            
            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if not myRoot then return end

            local enemy = GetClosestEnemyForTP()
            if not enemy then return end

            local enemyChar = enemy.Character
            local enemyRoot = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
            if not enemyRoot then return end

            -- Update Time
            lastTPTime = tick()

            -- Logic
            local targetPosition = enemyRoot.Position
            local offsetMagnitude = 3 

            local dirToMe = (myRoot.Position - enemyRoot.Position).Unit
            local enemyLook = enemyRoot.CFrame.LookVector
            local dot = enemyLook:Dot(dirToMe)
            local offsetVector

            if dot > 0.6 then
                -- Enemy looking at us, go side
                local sideDir = enemyRoot.CFrame.RightVector
                if math.random() < 0.5 then sideDir = -sideDir end
                offsetVector = sideDir * offsetMagnitude
            else
                -- Enemy looking away, go behind
                offsetVector = -enemyRoot.CFrame.LookVector * offsetMagnitude
            end

            local newPos = targetPosition + offsetVector
            myRoot.CFrame = CFrame.new(newPos, enemyRoot.Position)
        end)
    else
        if tpConnection then
            tpConnection:Disconnect()
            tpConnection = nil
        end
    end
end)

-- New TP Delay Slider
aimTab:CreateSlider("TP Delay (Seconds)", 0, 10, 1, function(value)
    -- Divide by 10 to get decimals (0.0 to 1.0)
    AimSettings.TPDelay = value / 10
end)

-- ===================== Helper Functions ===================== --

local function GetNearestPlayerToMouse()
    local nearestPlayer = nil
    local shortestDistance = math.huge
    local mousePos = UserInputService:GetMouseLocation()

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and IsEnemy(player) then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            local head = player.Character:FindFirstChild("Head")
            
            if humanoid and humanoid.Health > 0 and head then
                local headPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                
                if onScreen then
                    local dist = (Vector2.new(headPos.X, headPos.Y) - mousePos).Magnitude
                    
                    -- Check FOV Settings
                    if not FOVSettings.Enabled or dist <= FOVSettings.Radius then
                        if dist < shortestDistance then
                            shortestDistance = dist
                            nearestPlayer = player
                        end
                    end
                end
            end
        end
    end
    return nearestPlayer
end

-- ===================== RenderStepped for Aim & FOV Update ===================== --

RunService.RenderStepped:Connect(function()
    -- Update FOV Circle Position
    if FOVSettings.ShowCircle then
        FOVSettings.Circle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        FOVSettings.Circle.Radius = FOVSettings.Radius
    else
        FOVSettings.Circle.Visible = false
    end

    -- Aimbot Logic
    if AimSettings.Enabled and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local target = GetNearestPlayerToMouse()
        
        if target and target.Character then
            local head = target.Character:FindFirstChild("Head")
            if head then
                local currentCF = Camera.CFrame
                local targetCF = CFrame.new(currentCF.Position, head.Position)
                
                -- Apply Smoothness (Lerp)
                -- If Smoothness is 1 (Max), it's instant. If 0.1, it's slow.
                Camera.CFrame = currentCF:Lerp(targetCF, AimSettings.Smoothness)
            end
        end
    end
end)

-- ===================== Movement (Fly) ===================== --

local FlySettings = {
    Flying = false,
    Speed = 50
}

local bodyGyro, bodyVelocity
local flyConnection

local function StartFly()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end

    local hrp = character:FindFirstChild("HumanoidRootPart")

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.P = 9e4
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.CFrame = hrp.CFrame
    bodyGyro.Parent = hrp

    bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = Vector3.zero
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Parent = hrp

    flyConnection = RunService.RenderStepped:Connect(function()
        local cameraCF = Camera.CFrame
        local moveDirection = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDirection += cameraCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDirection -= cameraCF.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDirection -= cameraCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDirection += cameraCF.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDirection += cameraCF.UpVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDirection -= cameraCF.UpVector end

        if moveDirection.Magnitude > 0 then
            moveDirection = moveDirection.Unit * FlySettings.Speed
        else
            moveDirection = Vector3.zero
        end

        bodyVelocity.Velocity = moveDirection
        bodyGyro.CFrame = Camera.CFrame
    end)
end

local function StopFly()
    if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
    if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
    if flyConnection then flyConnection:Disconnect() flyConnection = nil end
    
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    if FlySettings.Flying then
        task.wait(1)
        StartFly()
    end
end)

movementTab:CreateToggle("Fly", function(state)
    FlySettings.Flying = state
    if state then StartFly() else StopFly() end
end)

movementTab:CreateSlider("Fly Speed", 20, 200, 50, function(value)
    FlySettings.Speed = value
end)
