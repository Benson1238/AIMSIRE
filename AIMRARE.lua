--[[
    AimRare Hub
    Version: 7.1 (Customization & Stability)
    Author: Ben
    Changelog:
    - Added multi-mode aim activation with secondary bind and prioritization controls.
    - Expanded prediction with multiple models, smoothing, and curve tuning plus ESP color profiles.
    - Swapped Fluent UI loader to a stable mirror to prevent 404 issues and restore UI availability.
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Locals & Micro-optimizations
local VERSION = "7.1 (Customization & Stability)"
local ACCENT_COLOR = Color3.fromRGB(255, 65, 65)
local DEFAULT_ESP_COLOR = ACCENT_COLOR
local DEFAULT_FOV_COLOR = Color3.new(1, 1, 1)
local DEFAULT_TEAM_COLOR = Color3.fromRGB(65, 170, 255)
local DEFAULT_LOW_HEALTH_COLOR = Color3.fromRGB(255, 200, 65)
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Vector2new = Vector2.new
local Color3new = Color3.new
local MathFloor = math.floor
local MathRandom = math.random

-- Check if Drawing API exists
if not Drawing then
    warn("AimRare Hub: Drawing API not found! Please use a better executor.")
    return
end

-- Settings
local Settings = {
    -- Visuals
    BoxESP = false,
    SkeletonESP = false,
    NameESP = false,
    HealthESP = false,
    TeamCheck = false,
    FPSSafeSkeleton = false,
    ESPUpdateRate = 60,
    LowHealthThreshold = 30,

    -- Aimbot Main
    AimbotEnabled = false,
    AimbotFOV = 100,
    AimbotSmooth = 0.2,
    AimbotHitChance = 100,
    AimPart = "Head",
    PredictionSpeed = 1000,
    PredictionMode = "Linear",
    PredictionCurve = 1,
    PredictionSmoothing = 0.2,
    AimMode = "Hold",
    TargetPriority = "Closest to crosshair",

    -- UI Control
    ShowWatermark = true,

    -- Checks
    WallCheck = false,
    AliveCheck = true,
    VisibilityDelay = 0,
    IgnoreAccessories = false,
}

-- Constants for Skeleton ESP (Moved out of loop for performance)
local R15_Connections = {
    {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"}, {"LowerTorso","LeftUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"}, {"LowerTorso","RightUpperLeg"},
    {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"}, {"UpperTorso","LeftUpperArm"},
    {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"}, {"UpperTorso","RightUpperArm"},
    {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"}
}
local R6_Connections = {
    {"Head","Torso"}, {"Torso","Left Arm"}, {"Torso","Right Arm"}, {"Torso","Left Leg"}, {"Torso","Right Leg"}
}

-- Cache & Globals
local ESP_Cache = {}
local FOV_Circle_Legit = nil
local LegitTarget = nil
local WatermarkText = nil
local RenderConnection = nil -- Handle for the loop
local RayParams = RaycastParams.new() -- Create once, reuse later
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true
local RayIgnore = {}
local LastVisibilityResult = {}
local LastVelocityCache = {}
local EspAccumulator = 0
local AimToggleState = false
local LastPrimaryState, LastSecondaryState = false, false

-- Initialize FOV Circle and Watermark
pcall(function()
    FOV_Circle_Legit = Drawing.new("Circle")
    FOV_Circle_Legit.Color = DEFAULT_FOV_COLOR
    FOV_Circle_Legit.Thickness = 1
    FOV_Circle_Legit.NumSides = 60
    FOV_Circle_Legit.Radius = Settings.AimbotFOV
    FOV_Circle_Legit.Visible = false
    FOV_Circle_Legit.Transparency = 0.7
    FOV_Circle_Legit.Filled = false
    FOV_Circle_Legit.Position = Vector2new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    WatermarkText = Drawing.new("Text")
    WatermarkText.Text = "AimRare Hub v" .. VERSION .. " | FPS: 60"
    WatermarkText.Size = 18
    WatermarkText.Position = Vector2new(Camera.ViewportSize.X - 200, 30)
    WatermarkText.Color = Color3new(1, 1, 1)
    WatermarkText.Outline = true
    WatermarkText.Visible = Settings.ShowWatermark
end)

local UPDATE_LOG = {
    "Advanced prediction modes with curve tuning and smoothing",
    "New aim activation modes, secondary bind, and target prioritization",
    "Fluent UI loader now uses a stable mirror to avoid 404 errors and restore the UI"
}

local function GetOptionValue(flag, fallback)
    if Fluent and Fluent.Options and Fluent.Options[flag] and Fluent.Options[flag].Value ~= nil then
        return Fluent.Options[flag].Value
    end
    return fallback
end

local function GetEspInterval()
    local hz = math.clamp(Settings.ESPUpdateRate or 60, 1, 240)
    return 1 / hz
end

local function GetBindState(flag)
    local opt = Fluent and Fluent.Options and Fluent.Options[flag]
    if opt and opt.GetState then
        return opt:GetState()
    end
    if opt and opt.Value ~= nil then
        return opt.Value
    end
    return false
end

local function UpdateAimToggle(primaryState, secondaryState)
    if Settings.AimMode ~= "Toggle" then
        AimToggleState = false
        LastPrimaryState = primaryState
        LastSecondaryState = secondaryState
        return
    end

    if primaryState and not LastPrimaryState then
        AimToggleState = not AimToggleState
    end
    if secondaryState and not LastSecondaryState then
        AimToggleState = not AimToggleState
    end

    LastPrimaryState = primaryState
    LastSecondaryState = secondaryState
end

local function ShouldAim(primaryState, secondaryState)
    if not Settings.AimbotEnabled then return false end

    if Settings.AimMode == "Always-On" then
        return true
    elseif Settings.AimMode == "Toggle" then
        UpdateAimToggle(primaryState, secondaryState)
        return AimToggleState
    end

    return primaryState or secondaryState
end

-------------------------------------------------------------------------
-- DRAWING HELPERS
-------------------------------------------------------------------------
local function createText()
    local text = Drawing.new("Text")
    text.Center = true
    text.Outline = true
    text.OutlineColor = Color3new(0,0,0)
    text.Color = Color3new(1,1,1)
    text.Size = 13
    text.Visible = false
    return text
end

local function createLine()
    local line = Drawing.new("Line")
    line.Thickness = 1.5
    line.Color = DEFAULT_ESP_COLOR
    line.Transparency = 1
    line.Visible = false
    return line
end

local function createBoxStructure()
    local objects = {
        BoxOutline = Drawing.new("Square"),
        Box = Drawing.new("Square"),
        HealthOutline = Drawing.new("Line"),
        HealthBar = Drawing.new("Line"),
        Name = createText(),
        Distance = createText()
    }

    objects.BoxOutline.Color = Color3new(0,0,0)
    objects.BoxOutline.Thickness = 3
    objects.BoxOutline.Filled = false
    objects.BoxOutline.Transparency = 1

    objects.Box.Thickness = 1
    objects.Box.Filled = false

    objects.HealthOutline.Color = Color3new(0,0,0)
    objects.HealthOutline.Thickness = 4

    objects.HealthBar.Color = Color3new(0, 1, 0)
    objects.HealthBar.Thickness = 2

    return objects
end

local function removeESP(player)
    if ESP_Cache[player] then
        if ESP_Cache[player].Objects then
            for _, obj in pairs(ESP_Cache[player].Objects) do
                if obj and obj.Remove then obj:Remove() end
            end
        end
        if ESP_Cache[player].SkeletonLines then
            for _, line in pairs(ESP_Cache[player].SkeletonLines) do
                if line and line.Remove then line:Remove() end
            end
        end
        ESP_Cache[player] = nil
    end
    LastVelocityCache[player] = nil
    LastVisibilityResult[player] = nil
end
Players.PlayerRemoving:Connect(removeESP)

local function IsESPEnabled()
    return Settings.BoxESP or Settings.SkeletonESP or Settings.NameESP or Settings.HealthESP
end

local function HideAllESP()
    for _, cache in pairs(ESP_Cache) do
        if cache.Objects then
            if cache.Objects.Box then cache.Objects.Box.Visible = false end
            if cache.Objects.BoxOutline then cache.Objects.BoxOutline.Visible = false end
            if cache.Objects.HealthBar then cache.Objects.HealthBar.Visible = false end
            if cache.Objects.HealthOutline then cache.Objects.HealthOutline.Visible = false end
            if cache.Objects.Name then cache.Objects.Name.Visible = false end
            if cache.Objects.Distance then cache.Objects.Distance.Visible = false end
        end
        if cache.SkeletonLines then
            for _, line in pairs(cache.SkeletonLines) do
                line.Visible = false
            end
        end
    end
end

-------------------------------------------------------------------------
-- TARGETING HELPERS
-------------------------------------------------------------------------
-- HELPER: Wall Check Raycast (Optimized)
local function IsVisible(target)
    if not target or not target.Character or not target.Character:FindFirstChild(Settings.AimPart) then return false end

    local now = tick()
    local last = LastVisibilityResult[target]
    if last and Settings.VisibilityDelay > 0 and (now - last.Time) < Settings.VisibilityDelay then
        return last.Visible
    end

    local origin = Camera.CFrame.Position
    local targetPos = target.Character[Settings.AimPart].Position
    local direction = targetPos - origin

    table.clear(RayIgnore)
    RayIgnore[1] = LocalPlayer.Character or Workspace.CurrentCamera
    RayIgnore[2] = target.Character

    if Settings.IgnoreAccessories and target.Character then
        local index = 3
        for _, accessory in ipairs(target.Character:GetChildren()) do
            if accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") then
                RayIgnore[index] = accessory
                index += 1
            end
        end
    end

    RayParams.FilterDescendantsInstances = RayIgnore

    local result = Workspace:Raycast(origin, direction, RayParams)
    local visible = result == nil

    LastVisibilityResult[target] = { Time = now, Visible = visible }
    return visible
end

-- Predict target movement for smoother aim leading
local function PredictAimPosition(target)
    local character = target and target.Character
    if not character then return nil end

    local aimPart = character:FindFirstChild(Settings.AimPart)
    if not aimPart then return nil end

    local root = character:FindFirstChild("HumanoidRootPart")
    local velocity = Vector3.zero

    if root and root.AssemblyLinearVelocity then
        velocity = root.AssemblyLinearVelocity
    elseif aimPart.AssemblyLinearVelocity then
        velocity = aimPart.AssemblyLinearVelocity
    end

    local cached = LastVelocityCache[target]
    if cached then
        velocity = cached:Lerp(velocity, math.clamp(Settings.PredictionSmoothing, 0, 1))
    end
    LastVelocityCache[target] = velocity

    local distance = (aimPart.Position - Camera.CFrame.Position).Magnitude
    local speedDivisor = Settings.PredictionSpeed > 0 and Settings.PredictionSpeed or 700
    local baseTime = math.clamp(distance / speedDivisor, 0, 1) -- distance-scaled leading
    local mode = Settings.PredictionMode
    local curve = math.max(Settings.PredictionCurve, 0.1)

    if mode == "Advanced" then
        local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * (baseTime * curve)
        local vertical = Vector3.new(0, velocity.Y, 0) * (baseTime * (curve * 0.5))
        return aimPart.Position + horizontal + vertical
    elseif mode == "High-Precision" then
        local adjustedTime = math.clamp(baseTime * curve * 1.5, 0, 1.5)
        local lead = velocity * adjustedTime
        return aimPart.Position + lead
    end

    return aimPart.Position + (velocity * baseTime * curve)
end

-- Updated Target Selector with FOV Argument
local function GetClosestPlayerToMouse(fovLimit)
    local closestPlayer = nil
    local bestScore = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local priority = Settings.TargetPriority

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(Settings.AimPart) then
            local hum = player.Character:FindFirstChild("Humanoid")

            if Settings.TeamCheck and player.Team == LocalPlayer.Team then continue end
            if Settings.AliveCheck and hum and hum.Health <= 0 then continue end
            if Settings.WallCheck and not IsVisible(player) then continue end

            local pos, onScreen = Camera:WorldToViewportPoint(player.Character[Settings.AimPart].Position)

            if onScreen then
                local cursorDistance = (Vector2new(pos.X, pos.Y) - mousePos).Magnitude
                if cursorDistance < fovLimit then
                    local score = cursorDistance

                    if priority == "Lowest distance" then
                        local root = player.Character:FindFirstChild("HumanoidRootPart")
                        score = root and (root.Position - Camera.CFrame.Position).Magnitude or score
                    elseif priority == "Lowest health" then
                        score = hum and hum.Health or score
                    elseif priority == "Highest threat" then
                        local root = player.Character:FindFirstChild("HumanoidRootPart")
                        if root then
                            local dirToLocal = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
                                and (LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Unit or Vector3.new(0,0,0)
                            local look = root.CFrame.LookVector
                            score = 1 - math.clamp(look:Dot(dirToLocal), -1, 1)
                        end
                    end

                    if score < bestScore then
                        closestPlayer = player
                        bestScore = score
                    end
                end
            end
        end
    end
    return closestPlayer
end

-------------------------------------------------------------------------
-- FLUENT UI
-------------------------------------------------------------------------
local Fluent
local FluentWindow
local function SetupUI()
    local success, lib = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/rewite12/FluentUIMirror/main/Library.lua"))()
    end)

    if success and lib then
        Fluent = lib
        FluentWindow = Fluent:CreateWindow({
            Title = "AimRare Hub",
            SubTitle = "v" .. VERSION,
            TabWidth = 160,
            Size = UDim2.fromOffset(580, 460),
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.RightShift
        })

        if Fluent.SetTheme then Fluent:SetTheme("Dark") end
        if Fluent.SetAccentColor then Fluent:SetAccentColor(ACCENT_COLOR) end

        local legitTab = FluentWindow:AddTab({Title = "Legit Aim", Icon = "target"})
        local visualsTab = FluentWindow:AddTab({Title = "Visuals", Icon = "eye"})
        local settingsTab = FluentWindow:AddTab({Title = "Settings", Icon = "settings"})

        FluentWindow:SelectTab(1)

        -- Legit Aim
        legitTab:AddToggle({
            Title = "Enabled",
            Default = Settings.AimbotEnabled,
            Callback = function(value)
                Settings.AimbotEnabled = value
                if FOV_Circle_Legit then FOV_Circle_Legit.Visible = value end
            end
        })

        legitTab:AddKeybind({
            Title = "AimBind",
            Default = Enum.UserInputType.MouseButton2,
            Mode = "Hold",
            Flag = "AimBind"
        })

        legitTab:AddSlider({
            Title = "FOV Radius",
            Default = Settings.AimbotFOV,
            Min = 10,
            Max = 800,
            Rounding = 0,
            Callback = function(value)
                Settings.AimbotFOV = value
            end
        })

        legitTab:AddSlider({
            Title = "Smoothness",
            Default = Settings.AimbotSmooth,
            Min = 0.1,
            Max = 1,
            Rounding = 2,
            Callback = function(value)
                Settings.AimbotSmooth = value
            end
        })

        legitTab:AddSlider({
            Title = "Hit Chance",
            Default = Settings.AimbotHitChance,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Callback = function(value)
                Settings.AimbotHitChance = value
            end
        })

        legitTab:AddSlider({
            Title = "Prediction Speed",
            Default = Settings.PredictionSpeed,
            Min = 100,
            Max = 5000,
            Rounding = 0,
            Callback = function(value)
                Settings.PredictionSpeed = value
            end
        })

        legitTab:AddDropdown({
            Title = "Aim Part",
            Values = {"Head", "UpperTorso", "HumanoidRootPart"},
            Default = Settings.AimPart,
            Callback = function(value)
                Settings.AimPart = value
            end
        })

        legitTab:AddColorpicker({
            Title = "FOV Circle Color",
            Default = DEFAULT_FOV_COLOR,
            Flag = "FOVCircleColor",
            Callback = function(value)
                if FOV_Circle_Legit then
                    FOV_Circle_Legit.Color = value
                end
            end
        })

        legitTab:AddKeybind({
            Title = "Secondary AimBind",
            Default = Enum.UserInputType.MouseButton3,
            Mode = "Hold",
            Flag = "AimBindSecondary"
        })

        legitTab:AddDropdown({
            Title = "Aim Mode",
            Values = {"Hold", "Toggle", "Always-On"},
            Default = Settings.AimMode,
            Callback = function(value)
                Settings.AimMode = value
            end
        })

        legitTab:AddDropdown({
            Title = "Target Priority",
            Values = {"Closest to crosshair", "Lowest distance", "Lowest health", "Highest threat"},
            Default = Settings.TargetPriority,
            Callback = function(value)
                Settings.TargetPriority = value
            end
        })

        legitTab:AddDropdown({
            Title = "Prediction Mode",
            Values = {"Linear", "Advanced", "High-Precision"},
            Default = Settings.PredictionMode,
            Callback = function(value)
                Settings.PredictionMode = value
            end
        })

        legitTab:AddSlider({
            Title = "Prediction Curve",
            Default = Settings.PredictionCurve,
            Min = 0.25,
            Max = 2.5,
            Rounding = 2,
            Callback = function(value)
                Settings.PredictionCurve = value
            end
        })

        legitTab:AddSlider({
            Title = "Prediction Smoothing",
            Default = Settings.PredictionSmoothing,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(value)
                Settings.PredictionSmoothing = value
            end
        })

        -- Visuals
        visualsTab:AddToggle({
            Title = "Box ESP",
            Default = Settings.BoxESP,
            Callback = function(value)
                Settings.BoxESP = value
            end
        })

        visualsTab:AddToggle({
            Title = "Skeleton ESP",
            Default = Settings.SkeletonESP,
            Callback = function(value)
                Settings.SkeletonESP = value
            end
        })

        visualsTab:AddToggle({
            Title = "Name ESP",
            Default = Settings.NameESP,
            Callback = function(value)
                Settings.NameESP = value
            end
        })

        visualsTab:AddToggle({
            Title = "Health ESP",
            Default = Settings.HealthESP,
            Callback = function(value)
                Settings.HealthESP = value
            end
        })

        visualsTab:AddToggle({
            Title = "Team Check",
            Default = Settings.TeamCheck,
            Callback = function(value)
                Settings.TeamCheck = value
            end
        })

        visualsTab:AddColorpicker({
            Title = "Enemy ESP Color",
            Default = DEFAULT_ESP_COLOR,
            Flag = "EnemyESPColor"
        })

        visualsTab:AddColorpicker({
            Title = "Teammate ESP Color",
            Default = DEFAULT_TEAM_COLOR,
            Flag = "TeamESPColor"
        })

        visualsTab:AddColorpicker({
            Title = "Low Health ESP Color",
            Default = DEFAULT_LOW_HEALTH_COLOR,
            Flag = "LowHealthESPColor"
        })

        visualsTab:AddSlider({
            Title = "Low Health Threshold",
            Default = Settings.LowHealthThreshold,
            Min = 5,
            Max = 75,
            Rounding = 0,
            Callback = function(value)
                Settings.LowHealthThreshold = value
            end
        })

        visualsTab:AddSlider({
            Title = "ESP Update Rate (Hz)",
            Default = Settings.ESPUpdateRate,
            Min = 30,
            Max = 120,
            Rounding = 0,
            Callback = function(value)
                Settings.ESPUpdateRate = value
            end
        })

        visualsTab:AddToggle({
            Title = "FPS Safe Skeleton",
            Default = Settings.FPSSafeSkeleton,
            Callback = function(value)
                Settings.FPSSafeSkeleton = value
            end
        })

        -- Settings
        settingsTab:AddToggle({
            Title = "Show Watermark",
            Default = Settings.ShowWatermark,
            Callback = function(value)
                Settings.ShowWatermark = value
                if WatermarkText then WatermarkText.Visible = value end
            end
        })

        settingsTab:AddSlider({
            Title = "Visibility Check Delay",
            Default = Settings.VisibilityDelay,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(value)
                Settings.VisibilityDelay = value
            end
        })

        settingsTab:AddToggle({
            Title = "Ignore Accessories in Raycast",
            Default = Settings.IgnoreAccessories,
            Callback = function(value)
                Settings.IgnoreAccessories = value
            end
        })

        settingsTab:AddButton({
            Title = "Unload Script",
            Callback = function()
                if RenderConnection then
                    RenderConnection:Disconnect()
                    RenderConnection = nil
                end

                HideAllESP()
                for player, cache in pairs(ESP_Cache) do
                    if cache.Objects then
                        for _, obj in pairs(cache.Objects) do if obj.Remove then obj:Remove() end end
                    end
                    if cache.SkeletonLines then
                        for _, line in pairs(cache.SkeletonLines) do if line.Remove then line:Remove() end end
                    end
                    ESP_Cache[player] = nil
                end

                if FOV_Circle_Legit then FOV_Circle_Legit:Remove() end
                if WatermarkText then WatermarkText:Remove() end
                if Fluent and Fluent.Destroy then Fluent:Destroy() end
            end
        })

        if Fluent.Notify then
            Fluent:Notify({
                Title = "AimRare Hub v" .. VERSION,
                Content = table.concat(UPDATE_LOG, "\n"),
                Duration = 8
            })
        end
    else
        warn("AimRare Hub: Failed to load Fluent UI library. UI will be unavailable.")
    end
end
SetupUI()

-------------------------------------------------------------------------
-- RENDER LOOP (OPTIMIZED)
-------------------------------------------------------------------------
RenderConnection = RunService.RenderStepped:Connect(function(dt)
    if Workspace.CurrentCamera ~= Camera then
        Camera = Workspace.CurrentCamera
    end
    local mouseLoc = UserInputService:GetMouseLocation()
    local enemyColor = GetOptionValue("EnemyESPColor", DEFAULT_ESP_COLOR)
    local teamColor = GetOptionValue("TeamESPColor", DEFAULT_TEAM_COLOR)
    local lowHealthColor = GetOptionValue("LowHealthESPColor", DEFAULT_LOW_HEALTH_COLOR)
    local fovColor = GetOptionValue("FOVCircleColor", DEFAULT_FOV_COLOR)
    local fps = Workspace:GetRealPhysicsFPS()

    -- Draw Legit Circle
    if FOV_Circle_Legit then
        FOV_Circle_Legit.Position = mouseLoc
        FOV_Circle_Legit.Radius = Settings.AimbotFOV
        FOV_Circle_Legit.Color = fovColor
        FOV_Circle_Legit.Visible = Settings.AimbotEnabled
    end

    -- Update Watermark FPS
    if WatermarkText then
        WatermarkText.Visible = Settings.ShowWatermark
        if Settings.ShowWatermark then
            local targetName = LegitTarget and LegitTarget.Name or "None"
            WatermarkText.Text = string.format(
                "AimRare Hub v%s | FPS: %d | Target: %s | Pred: %d",
                VERSION,
                MathFloor(fps),
                targetName,
                Settings.PredictionSpeed
            )
            WatermarkText.Position = Vector2new(Camera.ViewportSize.X - 320, 20)
        end
    end

    -- AIMBOT LOGIC
    local primaryState = GetBindState("AimBind")
    local secondaryState = GetBindState("AimBindSecondary")
    local shouldAim = ShouldAim(primaryState, secondaryState)

    if shouldAim then
        LegitTarget = GetClosestPlayerToMouse(Settings.AimbotFOV)

        if LegitTarget and LegitTarget.Character and LegitTarget.Character:FindFirstChild(Settings.AimPart) then
            if MathRandom(1, 100) <= Settings.AimbotHitChance then
                local predicted = PredictAimPosition(LegitTarget)
                local aimPos = predicted or LegitTarget.Character[Settings.AimPart].Position
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, aimPos)
                Camera.CFrame = currentCFrame:Lerp(targetCFrame, Settings.AimbotSmooth)
            end
        end
    end

    -- ESP LOOP
    local espActive = IsESPEnabled()
    if not espActive then
        HideAllESP()
        return
    end

    EspAccumulator = EspAccumulator + (dt or 0)
    local espInterval = GetEspInterval()
    if EspAccumulator < espInterval then
        return
    end
    EspAccumulator = EspAccumulator - espInterval

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local char = player.Character
        if not char then
            removeESP(player)
            continue
        end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")

        if not hrp or not hum then
            removeESP(player)
            continue
        end

        local isTeammate = player.Team == LocalPlayer.Team
        if Settings.TeamCheck and isTeammate then
            removeESP(player)
            continue
        end
        if hum.Health <= 0 then removeESP(player); continue end

        local vector, onScreen = Camera:WorldToViewportPoint(hrp.Position)

        if not ESP_Cache[player] then
            ESP_Cache[player] = { Objects = createBoxStructure(), SkeletonLines = {} }
        end
        local cache = ESP_Cache[player]
        local objs = cache.Objects

        if onScreen then
            local boxHeight = (Camera.ViewportSize.Y / vector.Z) * 7
            local boxWidth = boxHeight / 2
            local boxPos = Vector2new(vector.X - boxWidth / 2, vector.Y - boxHeight / 2)

            local colorProfile = enemyColor
            if hum.Health <= Settings.LowHealthThreshold then
                colorProfile = lowHealthColor
            elseif isTeammate then
                colorProfile = teamColor
            end

            if Settings.BoxESP and objs.Box and objs.BoxOutline then
                objs.BoxOutline.Size = Vector2new(boxWidth, boxHeight)
                objs.BoxOutline.Position = boxPos
                objs.BoxOutline.Visible = true

                objs.Box.Size = Vector2new(boxWidth, boxHeight)
                objs.Box.Position = boxPos
                objs.Box.Color = colorProfile
                objs.Box.Visible = true
            else
                if objs.Box then objs.Box.Visible = false end
                if objs.BoxOutline then objs.BoxOutline.Visible = false end
            end

            if Settings.HealthESP and objs.HealthBar then
                local healthPercent = hum.Health / hum.MaxHealth
                local barHeight = boxHeight * healthPercent

                objs.HealthOutline.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
                objs.HealthOutline.To = Vector2new(boxPos.X - 5, boxPos.Y)
                objs.HealthOutline.Visible = true

                objs.HealthBar.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
                objs.HealthBar.To = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight - barHeight)
                objs.HealthBar.Color = Color3new(1 - healthPercent, healthPercent, 0)
                objs.HealthBar.Visible = true
            else
                if objs.HealthBar then objs.HealthBar.Visible = false end
                if objs.HealthOutline then objs.HealthOutline.Visible = false end
            end

            if Settings.NameESP and objs.Name then
                objs.Name.Text = player.Name
                objs.Name.Position = Vector2new(vector.X, boxPos.Y - 15)
                objs.Name.Color = colorProfile
                objs.Name.Visible = true

                objs.Distance.Text = MathFloor(vector.Z) .. " studs"
                objs.Distance.Position = Vector2new(vector.X, boxPos.Y + boxHeight + 5)
                objs.Distance.Visible = true
            else
                if objs.Name then objs.Name.Visible = false end
                if objs.Distance then objs.Distance.Visible = false end
            end

            local skeletonEnabled = Settings.SkeletonESP and not (Settings.FPSSafeSkeleton and fps < 55)
            if skeletonEnabled then
                local connections = (hum.RigType == Enum.HumanoidRigType.R15) and R15_Connections or R6_Connections

                for i, pair in ipairs(connections) do
                    local pA = char:FindFirstChild(pair[1])
                    local pB = char:FindFirstChild(pair[2])

                    if pA and pB then
                        local vA, visA = Camera:WorldToViewportPoint(pA.Position)
                        local vB, visB = Camera:WorldToViewportPoint(pB.Position)

                        if visA and visB then
                            if not cache.SkeletonLines[i] then cache.SkeletonLines[i] = createLine() end
                            local line = cache.SkeletonLines[i]
                            line.From = Vector2new(vA.X, vA.Y)
                            line.To = Vector2new(vB.X, vB.Y)
                            line.Color = colorProfile
                            line.Visible = true
                        elseif cache.SkeletonLines[i] then
                            cache.SkeletonLines[i].Visible = false
                        end
                    elseif cache.SkeletonLines[i] then
                        cache.SkeletonLines[i].Visible = false
                    end
                end
            else
                for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
            end

        else
            if objs.Box then objs.Box.Visible = false end
            if objs.BoxOutline then objs.BoxOutline.Visible = false end
            if objs.HealthBar then objs.HealthBar.Visible = false end
            if objs.HealthOutline then objs.HealthOutline.Visible = false end
            if objs.Name then objs.Name.Visible = false end
            if objs.Distance then objs.Distance.Visible = false end
            for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
        end
    end
end)
