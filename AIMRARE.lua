--[[
    AimRare Hub
    Version: 8.1 (generelly improvments and critical optimazion fixes)
    Author: Ben
    Changelog:
    - Added a visible Wall Check toggle to the UI so raycast filtering can be enabled without editing code.
    - Enforced wall checks inside the aimbot loop so targets behind cover are skipped in real time.
    - Normalized keybind detection so Rayfield string binds (e.g. "MB2") work with the aimbot toggles.
    - Added a Rayfield theme fallback and UI fixes to keep all tabs rendering when assets are missing.
]]

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local VERSION = "8.1 (Input & Resilience)"
local ACCENT_COLOR = Color3.fromRGB(255, 65, 65)
local DEFAULT_ESP_COLOR = ACCENT_COLOR
local DEFAULT_FOV_COLOR = Color3.new(1, 1, 1)
local DEFAULT_TEAM_COLOR = Color3.fromRGB(65, 170, 255)
local DEFAULT_LOW_HEALTH_COLOR = Color3.fromRGB(255, 200, 65)
local OCCLUDED_COLOR = Color3.fromRGB(160, 160, 160)
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Vector2new = Vector2.new
local Color3new = Color3.new
local MathFloor = math.floor
local MathRandom = math.random
local VirtualInputManager = game:FindService("VirtualInputManager") or game:GetService("VirtualInputManager")

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
    EnemyESPColor = DEFAULT_ESP_COLOR,
    TeamESPColor = DEFAULT_TEAM_COLOR,
    LowHealthESPColor = DEFAULT_LOW_HEALTH_COLOR,
    FOVCircleColor = DEFAULT_FOV_COLOR,

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
    AimSmoothingCurve = "Linear", -- Linear, Exponential, EaseInOut
    AimMode = "Hold",
    TargetPriority = "Closest to crosshair",
    AimBind = Enum.UserInputType.MouseButton2,
    AimBindSecondary = Enum.UserInputType.MouseButton3,
    AntiJitterRadius = 6,
    UseEasing = true,

    -- UI Control
    ShowWatermark = true,

    -- Checks
    WallCheck = false,
    AliveCheck = true,
    VisibilityDelay = 0,
    IgnoreAccessories = false,

}

local MOUSE_INPUT_ALIASES = {
    MouseButton1 = Enum.UserInputType.MouseButton1,
    MouseButton2 = Enum.UserInputType.MouseButton2,
    MouseButton3 = Enum.UserInputType.MouseButton3,
    MB1 = Enum.UserInputType.MouseButton1,
    MB2 = Enum.UserInputType.MouseButton2,
    MB3 = Enum.UserInputType.MouseButton3,
}

local function sanitizeEnum(value, fallback)
    if typeof(value) == "EnumItem" then
        return value
    elseif type(value) == "string" then
        return MOUSE_INPUT_ALIASES[value] or Enum.KeyCode[value] or Enum.UserInputType[value] or fallback
    end
    return fallback
end

-- Executor-agnostic mouse helpers
local function pressMouse1()
    local mousePos = UserInputService:GetMouseLocation()
    if VirtualInputManager and VirtualInputManager.SendMouseButtonEvent then
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)
    elseif typeof(mouse1press) == "function" then
        mouse1press()
    else
        warn("AimRare Hub: No compatible MouseButton1 press method available.")
    end
end

local function releaseMouse1()
    local mousePos = UserInputService:GetMouseLocation()
    if VirtualInputManager and VirtualInputManager.SendMouseButtonEvent then
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
    elseif typeof(mouse1release) == "function" then
        mouse1release()
    else
        warn("AimRare Hub: No compatible MouseButton1 release method available.")
    end
end

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
local RayParamsDefault = RaycastParams.new()
RayParamsDefault.FilterType = Enum.RaycastFilterType.Exclude
RayParamsDefault.IgnoreWater = true
local RayParamsIgnoreAccessories = RaycastParams.new()
RayParamsIgnoreAccessories.FilterType = Enum.RaycastFilterType.Exclude
RayParamsIgnoreAccessories.IgnoreWater = true
local RayParamsIgnoreTeam = RaycastParams.new()
RayParamsIgnoreTeam.FilterType = Enum.RaycastFilterType.Exclude
RayParamsIgnoreTeam.IgnoreWater = true
local RayIgnore = {}
local LastVisibilityResult = {}
local LastVelocityCache = {}
local AccessoryCache = {}
local ViewportCache = {}
local ViewportFrame = 0
local EspAccumulator = 0
local AimToggleState = false
local LastPrimaryState, LastSecondaryState = false, false

local function ensureSkeletonLineCache(cache, rigType)
    cache.SkeletonLines = cache.SkeletonLines or {}
    cache._lastRigType = cache._lastRigType or rigType
    cache._skeletonActive = cache._skeletonActive or false

    if cache._lastRigType ~= rigType then
        for i = #cache.SkeletonLines, 1, -1 do
            if cache.SkeletonLines[i] and cache.SkeletonLines[i].Remove then
                cache.SkeletonLines[i]:Remove()
            end
            cache.SkeletonLines[i] = nil
        end
        cache._lastRigType = rigType
    end

    local targetConnections = (rigType == Enum.HumanoidRigType.R15) and R15_Connections or R6_Connections
    for i = 1, #targetConnections do
        if not cache.SkeletonLines[i] then
            cache.SkeletonLines[i] = createLine()
        end
    end
end

local function clearSkeletonLines(cache)
    if not (cache and cache.SkeletonLines) then return end

    for i = #cache.SkeletonLines, 1, -1 do
        local line = cache.SkeletonLines[i]
        if line and line.Remove then
            line:Remove()
        end
        cache.SkeletonLines[i] = nil
    end

    cache._lastRigType = nil
    cache._skeletonActive = false
end

local function clearAllSkeletons()
    for _, cache in pairs(ESP_Cache) do
        clearSkeletonLines(cache)
    end
end

-- Initialize FOV Circle and Watermark
pcall(function()
    FOV_Circle_Legit = Drawing.new("Circle")
    FOV_Circle_Legit.Color = Settings.FOVCircleColor or DEFAULT_FOV_COLOR
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
    "Added a visible Wall Check toggle to enable/disable occlusion checks from the UI",
    "Enforced wall checks inside the aimbot loop to skip obstructed targets in real time",
    "Normalized keybind detection so Rayfield string binds and enums both work",
    "Rayfield theme fallback keeps the UI stable when preferred assets are missing",
    "Advanced prediction modes with curve tuning and smoothing",
    "New aim activation modes, secondary bind, and target prioritization",
    "Triggerbot removed because it made coding and debugging unnecessarily difficult",
}

local function GetEspInterval()
    local hz = math.clamp(Settings.ESPUpdateRate or 60, 1, 240)
    return 1 / hz
end

local function GetBindState(settingKey)
    local bind = Settings[settingKey]
    if type(bind) == "string" then
        local normalized = sanitizeEnum(bind)
        if normalized then
            Settings[settingKey] = normalized
            bind = normalized
        end
    end
    if typeof(bind) == "EnumItem" then
        if bind.EnumType == Enum.UserInputType then
            if bind == Enum.UserInputType.MouseButton1 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            elseif bind == Enum.UserInputType.MouseButton2 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            elseif bind == Enum.UserInputType.MouseButton3 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
            end
        elseif bind.EnumType == Enum.KeyCode then
            return UserInputService:IsKeyDown(bind)
        end
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
            if Settings.SkeletonESP then
                for _, line in pairs(cache.SkeletonLines) do
                    line.Visible = false
                end
            else
                clearSkeletonLines(cache)
            end
        end
    end
end

-------------------------------------------------------------------------
-- TARGETING HELPERS
-------------------------------------------------------------------------
-- HELPER: Wall Check Raycast (Optimized)
-- Raycast parameter provider to reduce allocations while supporting variations
local function GetRayParams(ignoreAccessories, ignoreTeam)
    local params
    if ignoreTeam then
        params = RayParamsIgnoreTeam
    elseif ignoreAccessories then
        params = RayParamsIgnoreAccessories
    else
        params = RayParamsDefault
    end
    table.clear(RayIgnore)
    RayIgnore[1] = LocalPlayer.Character or Workspace.CurrentCamera
    params.FilterDescendantsInstances = RayIgnore
    return params, RayIgnore
end

-- Cache accessory lists per character to avoid repeated scans
local function GetAccessoryList(character)
    local cached = AccessoryCache[character]
    if cached and cached.__instance == character then
        return cached
    end

    local list = { __instance = character }
    local index = 1
    for _, accessory in ipairs(character:GetChildren()) do
        if accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") then
            list[index] = accessory
            index += 1
        end
    end
    AccessoryCache[character] = list
    return list
end

-- Retrieves screen position with per-frame cache to limit WorldToViewport calls
local function GetViewportPosition(part)
    local frame = ViewportFrame
    local cached = ViewportCache[part]
    if cached and cached.Frame == frame then
        return cached.Data[1], cached.Data[2]
    end
    local pos, visible = Camera:WorldToViewportPoint(part.Position)
    ViewportCache[part] = { Frame = frame, Data = { pos, visible } }
    return pos, visible
end

-- Performs wall/occlusion check respecting accessory filtering and teams
-- @param target Player to test visibility against
-- @param aimPart Base part used as target
-- @param forceEnabled optional boolean override to force wall checking when true/false
local function PerformWallCheck(target, aimPart, forceEnabled)
    local shouldCheck = forceEnabled
    if shouldCheck == nil then
        shouldCheck = Settings.WallCheck
    end

    if not shouldCheck then
        return true
    end

    local now = tick()
    local last = LastVisibilityResult[target]
    if last and Settings.VisibilityDelay > 0 and (now - last.Time) < Settings.VisibilityDelay then
        return last.Visible
    end

    local character = target.Character
    if not character or not aimPart then return false end

    local params, ignoreList = GetRayParams(Settings.IgnoreAccessories, Settings.TeamCheck and target.Team == LocalPlayer.Team)
    ignoreList[2] = character

    if Settings.IgnoreAccessories then
        local accessories = GetAccessoryList(character)
        for i = 1, #accessories do
            ignoreList[#ignoreList + 1] = accessories[i]
        end
    end

    params.FilterDescendantsInstances = ignoreList

    local origin = Camera.CFrame.Position
    local direction = aimPart.Position - origin
    local result = Workspace:Raycast(origin, direction, params)
    local visible = result == nil

    LastVisibilityResult[target] = { Time = now, Visible = visible }
    return visible
end

-- Predict target movement for smoother aim leading
local function PredictMovement(target)
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

-- Updated Target Selector with FOV Argument and cached viewport
local function GetTarget(fovLimit)
    local closestPlayer = nil
    local bestScore = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local priority = Settings.TargetPriority

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(Settings.AimPart) then
            local hum = player.Character:FindFirstChild("Humanoid")

            if Settings.TeamCheck and player.Team == LocalPlayer.Team then continue end
            if Settings.AliveCheck and hum and hum.Health <= 0 then continue end
            if Settings.WallCheck and not PerformWallCheck(player, player.Character[Settings.AimPart]) then continue end

            local pos, onScreen = GetViewportPosition(player.Character[Settings.AimPart])

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
                            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            local dirToLocal = localRoot and (localRoot.Position - root.Position).Unit or Vector3.new(0, 0, 0)
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

-- RAYFIELD UI
--------------------------------------------------------------------------
local Rayfield
local RayfieldWindow
local RayfieldOptions = {}

local function createFallbackRayfield()
    local function makeControl(callback)
        return {
            Set = function(_, value)
                if callback then pcall(callback, value) end
            end
        }
    end

    local tabProto = {}
    function tabProto:CreateToggle(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateKeybind(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateSlider(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateDropdown(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateColorPicker(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateInput(props)
        return makeControl(props and props.Callback)
    end
    function tabProto:CreateParagraph()
        return makeControl(nil)
    end

    local function createTab()
        local tab = {}
        for key, fn in pairs(tabProto) do
            tab[key] = fn
        end
        return tab
    end

    local fallback = {}
    function fallback:CreateWindow()
        warn("AimRare Hub: Using offline fallback UI; Rayfield download unavailable.")
        return setmetatable({}, {
            __index = {
                CreateTab = function(_, _)
                    return createTab()
                end
            }
        })
    end

    function fallback:Notify(details)
        warn("AimRare Hub Notice: " .. (details and details.Title or "Notification"))
    end

    function fallback:Destroy() end

    return fallback
end

local function registerOption(flag, object)
    if flag then
        RayfieldOptions[flag] = object
    end
end

local function keybindToText(value, fallback)
    if typeof(value) == "EnumItem" then
        return value.Name
    elseif type(value) == "string" then
        return value
    end
    return fallback or "None"
end

local function SetupUI()
    local success, lib = pcall(function()
        return _G.AimRareRayfieldCache or loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)

    if not success or not lib then
        warn("AimRare Hub: Failed to download Rayfield UI. Falling back to cached or offline UI.")
        lib = _G.AimRareRayfieldCache or createFallbackRayfield()
    else
        _G.AimRareRayfieldCache = lib
    end

    if lib then
        Rayfield = lib

        local preferredTheme = "Dark"
        local resolvedTheme = (Rayfield.Theme and Rayfield.Theme[preferredTheme]) and preferredTheme or "Default"
        if resolvedTheme ~= preferredTheme then
            warn("AimRare Hub: Requested Rayfield theme '" .. preferredTheme .. "' missing, falling back to '" .. resolvedTheme .. "'.")
        end

        RayfieldWindow = Rayfield:CreateWindow({
            Name = "AimRare Hub",
            LoadingTitle = "AimRare Hub",
            LoadingSubtitle = "v" .. VERSION,
            Theme = resolvedTheme,
            DisableRayfieldPrompts = false,
            ConfigurationSaving = { Enabled = false },
        })

        local legitTab = RayfieldWindow:CreateTab("Legit Aim")
        local visualsTab = RayfieldWindow:CreateTab("Visuals")
        local settingsTab = RayfieldWindow:CreateTab("Settings")

        -- Legit Aim
        registerOption("AimbotEnabled", legitTab:CreateToggle({
            Name = "Enabled",
            CurrentValue = Settings.AimbotEnabled,
            Flag = "AimbotEnabled",
            Callback = function(value)
                Settings.AimbotEnabled = value
                if FOV_Circle_Legit then FOV_Circle_Legit.Visible = value end
            end
        }))

        registerOption("AimBind", legitTab:CreateKeybind({
            Name = "AimBind",
            CurrentKeybind = keybindToText(Settings.AimBind, "MouseButton2"),
            HoldToInteract = true,
            Flag = "AimBind",
            Callback = function(key)
                Settings.AimBind = sanitizeEnum(key, Settings.AimBind)
            end
        }))

        registerOption("AimbotFOV", legitTab:CreateSlider({
            Name = "FOV Radius",
            Range = {10, 800},
            Increment = 1,
            CurrentValue = Settings.AimbotFOV,
            Flag = "AimbotFOV",
            Callback = function(value)
                Settings.AimbotFOV = value
            end
        }))

        registerOption("AimbotSmooth", legitTab:CreateSlider({
            Name = "Smoothness",
            Range = {0.1, 1},
            Increment = 0.01,
            CurrentValue = Settings.AimbotSmooth,
            Flag = "AimbotSmooth",
            Callback = function(value)
                Settings.AimbotSmooth = value
            end
        }))

        registerOption("AimSmoothingCurve", legitTab:CreateDropdown({
            Name = "Smoothing Curve",
            Options = {"Linear", "Exponential", "EaseInOut"},
            CurrentOption = {Settings.AimSmoothingCurve},
            Flag = "AimSmoothingCurve",
            Callback = function(value)
                Settings.AimSmoothingCurve = type(value) == "table" and value[1] or value
            end
        }))

        registerOption("UseEasing", legitTab:CreateToggle({
            Name = "Ease Out Aim",
            CurrentValue = Settings.UseEasing,
            Flag = "UseEasing",
            Callback = function(value)
                Settings.UseEasing = value
            end
        }))

        registerOption("AntiJitterRadius", legitTab:CreateSlider({
            Name = "Anti-Jitter Radius",
            Range = {0, 25},
            Increment = 1,
            CurrentValue = Settings.AntiJitterRadius,
            Flag = "AntiJitterRadius",
            Callback = function(value)
                Settings.AntiJitterRadius = value
            end
        }))

        registerOption("AimbotHitChance", legitTab:CreateSlider({
            Name = "Hit Chance",
            Range = {0, 100},
            Increment = 1,
            CurrentValue = Settings.AimbotHitChance,
            Flag = "AimbotHitChance",
            Callback = function(value)
                Settings.AimbotHitChance = value
            end
        }))

        registerOption("PredictionSpeed", legitTab:CreateSlider({
            Name = "Prediction Speed",
            Range = {100, 5000},
            Increment = 10,
            CurrentValue = Settings.PredictionSpeed,
            Flag = "PredictionSpeed",
            Callback = function(value)
                Settings.PredictionSpeed = value
            end
        }))

        registerOption("AimPart", legitTab:CreateDropdown({
            Name = "Aim Part",
            Options = {"Head", "UpperTorso", "HumanoidRootPart"},
            CurrentOption = {Settings.AimPart},
            Flag = "AimPart",
            Callback = function(value)
                Settings.AimPart = type(value) == "table" and value[1] or value
            end
        }))

        registerOption("FOVCircleColor", legitTab:CreateColorPicker({
            Name = "FOV Circle Color",
            Color = Settings.FOVCircleColor,
            Flag = "FOVCircleColor",
            Callback = function(value)
                Settings.FOVCircleColor = value
                if FOV_Circle_Legit then
                    FOV_Circle_Legit.Color = value
                end
            end
        }))

        registerOption("AimBindSecondary", legitTab:CreateKeybind({
            Name = "Secondary AimBind",
            CurrentKeybind = keybindToText(Settings.AimBindSecondary, "MouseButton3"),
            HoldToInteract = true,
            Flag = "AimBindSecondary",
            Callback = function(key)
                Settings.AimBindSecondary = sanitizeEnum(key, Settings.AimBindSecondary)
            end
        }))

        registerOption("AimMode", legitTab:CreateDropdown({
            Name = "Aim Mode",
            Options = {"Hold", "Toggle", "Always-On"},
            CurrentOption = {Settings.AimMode},
            Flag = "AimMode",
            Callback = function(value)
                Settings.AimMode = type(value) == "table" and value[1] or value
            end
        }))

        registerOption("TargetPriority", legitTab:CreateDropdown({
            Name = "Target Priority",
            Options = {"Closest to crosshair", "Lowest distance", "Lowest health", "Highest threat"},
            CurrentOption = {Settings.TargetPriority},
            Flag = "TargetPriority",
            Callback = function(value)
                Settings.TargetPriority = type(value) == "table" and value[1] or value
            end
        }))

        registerOption("PredictionMode", legitTab:CreateDropdown({
            Name = "Prediction Mode",
            Options = {"Linear", "Advanced", "High-Precision"},
            CurrentOption = {Settings.PredictionMode},
            Flag = "PredictionMode",
            Callback = function(value)
                Settings.PredictionMode = type(value) == "table" and value[1] or value
            end
        }))

        registerOption("PredictionCurve", legitTab:CreateSlider({
            Name = "Prediction Curve",
            Range = {0.25, 2.5},
            Increment = 0.01,
            CurrentValue = Settings.PredictionCurve,
            Flag = "PredictionCurve",
            Callback = function(value)
                Settings.PredictionCurve = value
            end
        }))

        registerOption("PredictionSmoothing", legitTab:CreateSlider({
            Name = "Prediction Smoothing",
            Range = {0, 1},
            Increment = 0.01,
            CurrentValue = Settings.PredictionSmoothing,
            Flag = "PredictionSmoothing",
            Callback = function(value)
                Settings.PredictionSmoothing = value
            end
        }))

        -- Visuals
        registerOption("BoxESP", visualsTab:CreateToggle({
            Name = "Box ESP",
            CurrentValue = Settings.BoxESP,
            Flag = "BoxESP",
            Callback = function(value)
                Settings.BoxESP = value
            end
        }))

        registerOption("SkeletonESP", visualsTab:CreateToggle({
            Name = "Skeleton ESP",
            CurrentValue = Settings.SkeletonESP,
            Flag = "SkeletonESP",
            Callback = function(value)
                Settings.SkeletonESP = value
                clearAllSkeletons()
            end
        }))

        registerOption("NameESP", visualsTab:CreateToggle({
            Name = "Name ESP",
            CurrentValue = Settings.NameESP,
            Flag = "NameESP",
            Callback = function(value)
                Settings.NameESP = value
            end
        }))

        registerOption("HealthESP", visualsTab:CreateToggle({
            Name = "Health ESP",
            CurrentValue = Settings.HealthESP,
            Flag = "HealthESP",
            Callback = function(value)
                Settings.HealthESP = value
            end
        }))

        registerOption("TeamCheck", visualsTab:CreateToggle({
            Name = "Team Check",
            CurrentValue = Settings.TeamCheck,
            Flag = "TeamCheck",
            Callback = function(value)
                Settings.TeamCheck = value
            end
        }))

        registerOption("EnemyESPColor", visualsTab:CreateColorPicker({
            Name = "Enemy ESP Color",
            Color = Settings.EnemyESPColor,
            Flag = "EnemyESPColor",
            Callback = function(value)
                Settings.EnemyESPColor = value
            end
        }))

        registerOption("TeamESPColor", visualsTab:CreateColorPicker({
            Name = "Teammate ESP Color",
            Color = Settings.TeamESPColor,
            Flag = "TeamESPColor",
            Callback = function(value)
                Settings.TeamESPColor = value
            end
        }))

        registerOption("LowHealthESPColor", visualsTab:CreateColorPicker({
            Name = "Low Health ESP Color",
            Color = Settings.LowHealthESPColor,
            Flag = "LowHealthESPColor",
            Callback = function(value)
                Settings.LowHealthESPColor = value
            end
        }))

        registerOption("LowHealthThreshold", visualsTab:CreateSlider({
            Name = "Low Health Threshold",
            Range = {5, 75},
            Increment = 1,
            CurrentValue = Settings.LowHealthThreshold,
            Flag = "LowHealthThreshold",
            Callback = function(value)
                Settings.LowHealthThreshold = value
            end
        }))

        registerOption("ESPUpdateRate", visualsTab:CreateSlider({
            Name = "ESP Update Rate (Hz)",
            Range = {30, 120},
            Increment = 1,
            CurrentValue = Settings.ESPUpdateRate,
            Flag = "ESPUpdateRate",
            Callback = function(value)
                Settings.ESPUpdateRate = value
            end
        }))

        registerOption("FPSSafeSkeleton", visualsTab:CreateToggle({
            Name = "FPS Safe Skeleton",
            CurrentValue = Settings.FPSSafeSkeleton,
            Flag = "FPSSafeSkeleton",
            Callback = function(value)
                Settings.FPSSafeSkeleton = value
            end
        }))

        -- Settings
        registerOption("ShowWatermark", settingsTab:CreateToggle({
            Name = "Show Watermark",
            CurrentValue = Settings.ShowWatermark,
            Flag = "ShowWatermark",
            Callback = function(value)
                Settings.ShowWatermark = value
                if WatermarkText then WatermarkText.Visible = value end
            end
        }))

        registerOption("VisibilityDelay", settingsTab:CreateSlider({
            Name = "Visibility Check Delay",
            Range = {0, 1},
            Increment = 0.01,
            CurrentValue = Settings.VisibilityDelay,
            Flag = "VisibilityDelay",
            Callback = function(value)
                Settings.VisibilityDelay = value
            end
        }))

        registerOption("WallCheck", settingsTab:CreateToggle({
            Name = "Wall Check (raycast occlusion)",
            CurrentValue = Settings.WallCheck,
            Flag = "WallCheck",
            Callback = function(value)
                Settings.WallCheck = value
            end
        }))

        registerOption("IgnoreAccessories", settingsTab:CreateToggle({
            Name = "Ignore Accessories in Raycast",
            CurrentValue = Settings.IgnoreAccessories,
            Flag = "IgnoreAccessories",
            Callback = function(value)
                Settings.IgnoreAccessories = value
            end
        }))

        registerOption("UnloadButton", settingsTab:CreateButton({
            Name = "Unload Script",
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
                if Rayfield and Rayfield.Destroy then Rayfield:Destroy() end
            end
        }))

        if Rayfield and Rayfield.Notify then
            Rayfield:Notify({
                Title = "AimRare Hub v" .. VERSION,
                Content = table.concat(UPDATE_LOG, "\n"),
                Duration = 8
            })
            Rayfield:Notify({
                Title = "Triggerbot Removed",
                Content = "Triggerbot made coding and code debugging very hard so we deleted it.",
                Duration = 10
            })
        end
    else
        warn("AimRare Hub: Failed to load Rayfield UI library. UI will be unavailable.")
    end
end
SetupUI()

-------------------------------------------------------------------------
-- Simple easing helpers for aim smoothing
local function easeOutQuad(t)
    return 1 - (1 - t) * (1 - t)
end

local function resolveSmoothingAlpha(dt)
    local base = math.clamp(Settings.AimbotSmooth, 0.01, 1)
    local scaled = 1 - math.exp(-base * (dt * 60)) -- frame-rate independent blend

    if Settings.AimSmoothingCurve == "Exponential" then
        scaled = scaled * scaled
    elseif Settings.AimSmoothingCurve == "EaseInOut" then
        scaled = easeOutQuad(scaled)
    end

    return math.clamp(scaled, 0, 1)
end

-- Anti-jitter guard for near-center targets
local function IsNearCenter(position2d)
    local viewportCenter = Camera.ViewportSize / 2
    return (Vector2new(position2d.X, position2d.Y) - Vector2new(viewportCenter.X, viewportCenter.Y)).Magnitude <= Settings.AntiJitterRadius
end

-- UI refresh separated for clarity
local LastFovColor, LastEnemyColor, LastTeamColor, LastLowHealthColor
local function UpdateUI(dt)
    local mouseLoc = UserInputService:GetMouseLocation()
    local fovColor = Settings.FOVCircleColor or DEFAULT_FOV_COLOR
    local fps = Workspace:GetRealPhysicsFPS()

    if FOV_Circle_Legit then
        FOV_Circle_Legit.Position = mouseLoc
        FOV_Circle_Legit.Radius = Settings.AimbotFOV
        if fovColor ~= LastFovColor then
            FOV_Circle_Legit.Color = fovColor
            LastFovColor = fovColor
        end
        FOV_Circle_Legit.Visible = Settings.AimbotEnabled
    end

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

    return mouseLoc
end

-- Aimbot handler (frame)
local function UpdateAimbot(dt, primaryState, secondaryState)
    local shouldAim = ShouldAim(primaryState, secondaryState)
    if not shouldAim then
        LegitTarget = nil
        return shouldAim
    end

    LegitTarget = GetTarget(Settings.AimbotFOV)

    if LegitTarget and LegitTarget.Character and LegitTarget.Character:FindFirstChild(Settings.AimPart) then
        if MathRandom(1, 100) <= Settings.AimbotHitChance then
            local aimPart
            local aimChoices = { Settings.AimPart, "UpperTorso", "HumanoidRootPart" }
            for _, partName in ipairs(aimChoices) do
                local candidate = LegitTarget.Character:FindFirstChild(partName)
                if candidate then
                    if Settings.WallCheck and not PerformWallCheck(LegitTarget, candidate) then
                        continue
                    end
                    aimPart = candidate
                    break
                end
            end

            if not aimPart then return shouldAim end

            local pos, onScreen = GetViewportPosition(aimPart)
            if Settings.AntiJitterRadius > 0 and onScreen and IsNearCenter(pos) then
                return shouldAim
            end

            local predicted = PredictMovement(LegitTarget)
            local aimPos = predicted or aimPart.Position
            local currentCFrame = Camera.CFrame
            local targetCFrame = CFrame.new(currentCFrame.Position, aimPos)
            local alpha = resolveSmoothingAlpha(dt)

            if Settings.UseEasing then
                alpha = easeOutQuad(alpha)
            end

            Camera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)
        end
    end
    return shouldAim
end

-- ESP drawing helpers
local function DrawBoxESP(objs, boxPos, boxWidth, boxHeight, color)
    if objs.BoxOutline and objs.Box then
        objs.BoxOutline.Size = Vector2new(boxWidth, boxHeight)
        objs.BoxOutline.Position = boxPos
        objs.BoxOutline.Visible = true

        objs.Box.Size = Vector2new(boxWidth, boxHeight)
        objs.Box.Position = boxPos
        objs.Box.Color = color
        objs.Box.Visible = true
    end
end

local function DrawHealthESP(objs, boxPos, boxHeight, healthPercent)
    if not (objs.HealthBar and objs.HealthOutline) then return end
    local barHeight = boxHeight * healthPercent

    objs.HealthOutline.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
    objs.HealthOutline.To = Vector2new(boxPos.X - 5, boxPos.Y)
    objs.HealthOutline.Visible = true

    objs.HealthBar.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
    objs.HealthBar.To = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight - barHeight)
    objs.HealthBar.Color = Color3new(1 - healthPercent, healthPercent, 0)
    objs.HealthBar.Visible = true
end

local function DrawSkeleton(char, hum, cache, color)
    local rigType = hum.RigType
    ensureSkeletonLineCache(cache, rigType)
    cache._skeletonActive = true
    local connections = (rigType == Enum.HumanoidRigType.R15) and R15_Connections or R6_Connections
    local posCache = {}

    for _, pair in ipairs(connections) do
        for _, boneName in ipairs(pair) do
            if not posCache[boneName] then
                local bone = char:FindFirstChild(boneName)
                if bone then
                    local pos, vis = GetViewportPosition(bone)
                    posCache[boneName] = { pos = pos, visible = vis }
                else
                    posCache[boneName] = false
                end
            end
        end
    end

    for i, pair in ipairs(connections) do
        local boneA = posCache[pair[1]]
        local boneB = posCache[pair[2]]
        local line = cache.SkeletonLines[i]

        if boneA and boneB and line and boneA.visible and boneB.visible then
            line.From = Vector2new(boneA.pos.X, boneA.pos.Y)
            line.To = Vector2new(boneB.pos.X, boneB.pos.Y)
            line.Color = color
            line.Visible = true
        elseif line then
            line.Visible = false
        end
    end
end

local function UpdateESP(dt, enemyColor, teamColor, lowHealthColor)
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

        local vector, onScreen = GetViewportPosition(hrp)

        if not ESP_Cache[player] then
            ESP_Cache[player] = { Objects = createBoxStructure(), SkeletonLines = {} }
        end
        local cache = ESP_Cache[player]
        local objs = cache.Objects

        if onScreen and vector.Z > 0 then
            local distance = vector.Z
            if distance > 600 then
                -- Skip expensive ESP for far targets
                if objs.Box then objs.Box.Visible = false end
                if objs.BoxOutline then objs.BoxOutline.Visible = false end
                for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
                continue
            end

            local boxHeight = (Camera.ViewportSize.Y / distance) * 7
            local boxWidth = boxHeight / 2
            local boxPos = Vector2new(vector.X - boxWidth / 2, vector.Y - boxHeight / 2)

            local colorProfile = enemyColor
            if hum.Health <= Settings.LowHealthThreshold then
                colorProfile = lowHealthColor
            elseif isTeammate then
                colorProfile = teamColor
            end

            if Settings.BoxESP then
                DrawBoxESP(objs, boxPos, boxWidth, boxHeight, colorProfile)
            else
                if objs.Box then objs.Box.Visible = false end
                if objs.BoxOutline then objs.BoxOutline.Visible = false end
            end

            if Settings.HealthESP then
                DrawHealthESP(objs, boxPos, boxHeight, hum.Health / hum.MaxHealth)
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

            local skeletonEnabled = Settings.SkeletonESP and not (Settings.FPSSafeSkeleton and Workspace:GetRealPhysicsFPS() < 55)
            if skeletonEnabled then
                DrawSkeleton(char, hum, cache, colorProfile)
            else
                if cache._skeletonActive then
                    clearSkeletonLines(cache)
                end
            end

            -- Occlusion ESP tinting
            if Settings.WallCheck and Settings.BoxESP then
                if not PerformWallCheck(player, hrp) then
                    objs.Box.Color = OCCLUDED_COLOR
                end
            end
        else
            if objs.Box then objs.Box.Visible = false end
            if objs.BoxOutline then objs.BoxOutline.Visible = false end
            if objs.HealthBar then objs.HealthBar.Visible = false end
            if objs.HealthOutline then objs.HealthOutline.Visible = false end
            if objs.Name then objs.Name.Visible = false end
            if objs.Distance then objs.Distance.Visible = false end
            if Settings.SkeletonESP then
                for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
            elseif cache._skeletonActive then
                clearSkeletonLines(cache)
            end
        end
    end
end

-- Main render connection
RenderConnection = RunService.RenderStepped:Connect(function(dt)
    if Workspace.CurrentCamera ~= Camera then
        Camera = Workspace.CurrentCamera
    end

    ViewportFrame += 1
    table.clear(ViewportCache)

    local enemyColor = Settings.EnemyESPColor or DEFAULT_ESP_COLOR
    local teamColor = Settings.TeamESPColor or DEFAULT_TEAM_COLOR
    local lowHealthColor = Settings.LowHealthESPColor or DEFAULT_LOW_HEALTH_COLOR

    if enemyColor ~= LastEnemyColor then LastEnemyColor = enemyColor end
    if teamColor ~= LastTeamColor then LastTeamColor = teamColor end
    if lowHealthColor ~= LastLowHealthColor then LastLowHealthColor = lowHealthColor end

    local mouseLoc = UpdateUI(dt)

    local primaryState = GetBindState("AimBind")
    local secondaryState = GetBindState("AimBindSecondary")
    local aimingActive = UpdateAimbot(dt, primaryState, secondaryState)
    UpdateESP(dt, enemyColor, teamColor, lowHealthColor)
end)
