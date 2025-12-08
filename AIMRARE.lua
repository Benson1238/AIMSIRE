 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/AIMRARE.lua b/AIMRARE.lua
index 09274fae5da1a8ab95380e04c551db5d29510e88..6e1d9116eab35bc7902f10164182b3606490bd56 100644
--- a/AIMRARE.lua
+++ b/AIMRARE.lua
@@ -1,148 +1,174 @@
 --[[
     AimRare Hub
     Version: 7.3 (Wall Check UI Toggle)
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
 
-local VERSION = "7.3 (Wall Check UI Toggle)"
+local VERSION = "8.0 (Triggerbot & Optimizations)"
 local ACCENT_COLOR = Color3.fromRGB(255, 65, 65)
 local DEFAULT_ESP_COLOR = ACCENT_COLOR
 local DEFAULT_FOV_COLOR = Color3.new(1, 1, 1)
 local DEFAULT_TEAM_COLOR = Color3.fromRGB(65, 170, 255)
 local DEFAULT_LOW_HEALTH_COLOR = Color3.fromRGB(255, 200, 65)
+local OCCLUDED_COLOR = Color3.fromRGB(160, 160, 160)
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
+    AimSmoothingCurve = "Linear", -- Linear, Exponential, EaseInOut
     AimMode = "Hold",
     TargetPriority = "Closest to crosshair",
     AimBind = Enum.UserInputType.MouseButton2,
     AimBindSecondary = Enum.UserInputType.MouseButton3,
+    AntiJitterRadius = 6,
+    UseEasing = true,
 
     -- UI Control
     ShowWatermark = true,
 
     -- Checks
     WallCheck = false,
     AliveCheck = true,
     VisibilityDelay = 0,
     IgnoreAccessories = false,
+
+    -- Triggerbot
+    TriggerbotEnabled = false,
+    TriggerbotDelay = 50,
+    TriggerbotFireRate = 120,
+    TriggerbotHoldBind = Enum.UserInputType.MouseButton1,
+    TriggerbotHoldToFire = false,
+    TriggerbotRequiresAimbot = false,
+    TriggerbotTeamCheck = true,
+    TriggerbotWallCheck = true,
+    TriggerbotMaxDistance = 500,
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
-local RayParams = RaycastParams.new() -- Create once, reuse later
-RayParams.FilterType = Enum.RaycastFilterType.Exclude
-RayParams.IgnoreWater = true
+local RayParamsDefault = RaycastParams.new()
+RayParamsDefault.FilterType = Enum.RaycastFilterType.Exclude
+RayParamsDefault.IgnoreWater = true
+local RayParamsIgnoreAccessories = RaycastParams.new()
+RayParamsIgnoreAccessories.FilterType = Enum.RaycastFilterType.Exclude
+RayParamsIgnoreAccessories.IgnoreWater = true
+local RayParamsIgnoreTeam = RaycastParams.new()
+RayParamsIgnoreTeam.FilterType = Enum.RaycastFilterType.Exclude
+RayParamsIgnoreTeam.IgnoreWater = true
 local RayIgnore = {}
 local LastVisibilityResult = {}
 local LastVelocityCache = {}
+local AccessoryCache = {}
+local ViewportCache = {}
+local ViewportFrame = 0
 local EspAccumulator = 0
 local AimToggleState = false
 local LastPrimaryState, LastSecondaryState = false, false
+local LastTriggerTime = 0
+local LastShotTime = 0
 
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
@@ -287,144 +313,199 @@ local function IsESPEnabled()
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
-local function IsVisible(target)
-    if not target or not target.Character or not target.Character:FindFirstChild(Settings.AimPart) then return false end
+-- Raycast parameter provider to reduce allocations while supporting variations
+local function GetRayParams(ignoreAccessories, ignoreTeam)
+    local params
+    if ignoreTeam then
+        params = RayParamsIgnoreTeam
+    elseif ignoreAccessories then
+        params = RayParamsIgnoreAccessories
+    else
+        params = RayParamsDefault
+    end
+    table.clear(RayIgnore)
+    RayIgnore[1] = LocalPlayer.Character or Workspace.CurrentCamera
+    params.FilterDescendantsInstances = RayIgnore
+    return params, RayIgnore
+end
+
+-- Cache accessory lists per character to avoid repeated scans
+local function GetAccessoryList(character)
+    local cached = AccessoryCache[character]
+    if cached and cached.__instance == character then
+        return cached
+    end
+
+    local list = { __instance = character }
+    local index = 1
+    for _, accessory in ipairs(character:GetChildren()) do
+        if accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") then
+            list[index] = accessory
+            index += 1
+        end
+    end
+    AccessoryCache[character] = list
+    return list
+end
+
+-- Retrieves screen position with per-frame cache to limit WorldToViewport calls
+local function GetViewportPosition(part)
+    local frame = ViewportFrame
+    local cached = ViewportCache[part]
+    if cached and cached.Frame == frame then
+        return cached.Data[1], cached.Data[2]
+    end
+    local pos, visible = Camera:WorldToViewportPoint(part.Position)
+    ViewportCache[part] = { Frame = frame, Data = { pos, visible } }
+    return pos, visible
+end
+
+-- Performs wall/occlusion check respecting accessory filtering and teams
+-- @param target Player to test visibility against
+-- @param aimPart Base part used as target
+-- @param forceEnabled optional boolean override to force wall checking when true/false
+local function PerformWallCheck(target, aimPart, forceEnabled)
+    local shouldCheck = forceEnabled
+    if shouldCheck == nil then
+        shouldCheck = Settings.WallCheck
+    end
+
+    if not shouldCheck then
+        return true
+    end
 
     local now = tick()
     local last = LastVisibilityResult[target]
     if last and Settings.VisibilityDelay > 0 and (now - last.Time) < Settings.VisibilityDelay then
         return last.Visible
     end
 
-    local origin = Camera.CFrame.Position
-    local targetPos = target.Character[Settings.AimPart].Position
-    local direction = targetPos - origin
+    local character = target.Character
+    if not character or not aimPart then return false end
 
-    table.clear(RayIgnore)
-    RayIgnore[1] = LocalPlayer.Character or Workspace.CurrentCamera
-    RayIgnore[2] = target.Character
+    local params, ignoreList = GetRayParams(Settings.IgnoreAccessories, Settings.TeamCheck and target.Team == LocalPlayer.Team)
+    ignoreList[2] = character
 
-    if Settings.IgnoreAccessories and target.Character then
-        local index = 3
-        for _, accessory in ipairs(target.Character:GetChildren()) do
-            if accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") then
-                RayIgnore[index] = accessory
-                index += 1
-            end
+    if Settings.IgnoreAccessories then
+        local accessories = GetAccessoryList(character)
+        for i = 1, #accessories do
+            ignoreList[#ignoreList + 1] = accessories[i]
         end
     end
 
-    RayParams.FilterDescendantsInstances = RayIgnore
+    params.FilterDescendantsInstances = ignoreList
 
-    local result = Workspace:Raycast(origin, direction, RayParams)
+    local origin = Camera.CFrame.Position
+    local direction = aimPart.Position - origin
+    local result = Workspace:Raycast(origin, direction, params)
     local visible = result == nil
 
     LastVisibilityResult[target] = { Time = now, Visible = visible }
     return visible
 end
 
 -- Predict target movement for smoother aim leading
-local function PredictAimPosition(target)
+local function PredictMovement(target)
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
 
--- Updated Target Selector with FOV Argument
-local function GetClosestPlayerToMouse(fovLimit)
+-- Updated Target Selector with FOV Argument and cached viewport
+local function GetTarget(fovLimit)
     local closestPlayer = nil
     local bestScore = math.huge
     local mousePos = UserInputService:GetMouseLocation()
     local priority = Settings.TargetPriority
 
     for _, player in pairs(Players:GetPlayers()) do
         if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(Settings.AimPart) then
             local hum = player.Character:FindFirstChild("Humanoid")
 
             if Settings.TeamCheck and player.Team == LocalPlayer.Team then continue end
             if Settings.AliveCheck and hum and hum.Health <= 0 then continue end
-            if Settings.WallCheck and not IsVisible(player) then continue end
+            if Settings.WallCheck and not PerformWallCheck(player, player.Character[Settings.AimPart]) then continue end
 
-            local pos, onScreen = Camera:WorldToViewportPoint(player.Character[Settings.AimPart].Position)
+            local pos, onScreen = GetViewportPosition(player.Character[Settings.AimPart])
 
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
@@ -504,50 +585,80 @@ local function SetupUI()
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
 
+        registerOption("AimSmoothingCurve", legitTab:CreateDropdown({
+            Name = "Smoothing Curve",
+            Options = {"Linear", "Exponential", "EaseInOut"},
+            CurrentOption = {Settings.AimSmoothingCurve},
+            Flag = "AimSmoothingCurve",
+            Callback = function(value)
+                Settings.AimSmoothingCurve = type(value) == "table" and value[1] or value
+            end
+        }))
+
+        registerOption("UseEasing", legitTab:CreateToggle({
+            Name = "Ease Out Aim",
+            CurrentValue = Settings.UseEasing,
+            Flag = "UseEasing",
+            Callback = function(value)
+                Settings.UseEasing = value
+            end
+        }))
+
+        registerOption("AntiJitterRadius", legitTab:CreateSlider({
+            Name = "Anti-Jitter Radius",
+            Range = {0, 25},
+            Increment = 1,
+            CurrentValue = Settings.AntiJitterRadius,
+            Flag = "AntiJitterRadius",
+            Callback = function(value)
+                Settings.AntiJitterRadius = value
+            end
+        }))
+
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
@@ -610,50 +721,140 @@ local function SetupUI()
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
 
+        legitTab:CreateSection("Triggerbot")
+
+        registerOption("TriggerbotEnabled", legitTab:CreateToggle({
+            Name = "Triggerbot Enabled",
+            CurrentValue = Settings.TriggerbotEnabled,
+            Flag = "TriggerbotEnabled",
+            Callback = function(value)
+                Settings.TriggerbotEnabled = value
+            end
+        }))
+
+        registerOption("TriggerbotHoldBind", legitTab:CreateKeybind({
+            Name = "Triggerbot Bind",
+            CurrentKeybind = keybindToText(Settings.TriggerbotHoldBind, "MouseButton1"),
+            HoldToInteract = true,
+            Flag = "TriggerbotHoldBind",
+            Callback = function(key)
+                Settings.TriggerbotHoldBind = sanitizeEnum(key, Settings.TriggerbotHoldBind)
+            end
+        }))
+
+        registerOption("TriggerbotHoldToFire", legitTab:CreateToggle({
+            Name = "Require Hold Bind",
+            CurrentValue = Settings.TriggerbotHoldToFire,
+            Flag = "TriggerbotHoldToFire",
+            Callback = function(value)
+                Settings.TriggerbotHoldToFire = value
+            end
+        }))
+
+        registerOption("TriggerbotDelay", legitTab:CreateSlider({
+            Name = "Shot Delay (ms)",
+            Range = {0, 250},
+            Increment = 5,
+            CurrentValue = Settings.TriggerbotDelay,
+            Flag = "TriggerbotDelay",
+            Callback = function(value)
+                Settings.TriggerbotDelay = value
+            end
+        }))
+
+        registerOption("TriggerbotFireRate", legitTab:CreateSlider({
+            Name = "Fire Rate Limit (ms)",
+            Range = {50, 500},
+            Increment = 5,
+            CurrentValue = Settings.TriggerbotFireRate,
+            Flag = "TriggerbotFireRate",
+            Callback = function(value)
+                Settings.TriggerbotFireRate = value
+            end
+        }))
+
+        registerOption("TriggerbotRequiresAimbot", legitTab:CreateToggle({
+            Name = "Only Shoot When Aimbot Active",
+            CurrentValue = Settings.TriggerbotRequiresAimbot,
+            Flag = "TriggerbotRequiresAimbot",
+            Callback = function(value)
+                Settings.TriggerbotRequiresAimbot = value
+            end
+        }))
+
+        registerOption("TriggerbotTeamCheck", legitTab:CreateToggle({
+            Name = "Triggerbot Team Check",
+            CurrentValue = Settings.TriggerbotTeamCheck,
+            Flag = "TriggerbotTeamCheck",
+            Callback = function(value)
+                Settings.TriggerbotTeamCheck = value
+            end
+        }))
+
+        registerOption("TriggerbotWallCheck", legitTab:CreateToggle({
+            Name = "Triggerbot Wall Check",
+            CurrentValue = Settings.TriggerbotWallCheck,
+            Flag = "TriggerbotWallCheck",
+            Callback = function(value)
+                Settings.TriggerbotWallCheck = value
+            end
+        }))
+
+        registerOption("TriggerbotMaxDistance", legitTab:CreateSlider({
+            Name = "Triggerbot Max Distance",
+            Range = {50, 1000},
+            Increment = 10,
+            CurrentValue = Settings.TriggerbotMaxDistance,
+            Flag = "TriggerbotMaxDistance",
+            Callback = function(value)
+                Settings.TriggerbotMaxDistance = value
+            end
+        }))
+
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
             end
         }))
 
         registerOption("NameESP", visualsTab:CreateToggle({
             Name = "Name ESP",
             CurrentValue = Settings.NameESP,
             Flag = "NameESP",
             Callback = function(value)
                 Settings.NameESP = value
@@ -793,229 +994,384 @@ local function SetupUI()
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
         end
     else
         warn("AimRare Hub: Failed to load Rayfield UI library. UI will be unavailable.")
     end
 end
 SetupUI()
 
 -------------------------------------------------------------------------
--- RENDER LOOP (OPTIMIZED)
--------------------------------------------------------------------------
-RenderConnection = RunService.RenderStepped:Connect(function(dt)
-    if Workspace.CurrentCamera ~= Camera then
-        Camera = Workspace.CurrentCamera
+-- Simple easing helpers for aim smoothing
+local function easeOutQuad(t)
+    return 1 - (1 - t) * (1 - t)
+end
+
+local function resolveSmoothingAlpha(dt)
+    local base = math.clamp(Settings.AimbotSmooth, 0.01, 1)
+    local scaled = 1 - math.exp(-base * (dt * 60)) -- frame-rate independent blend
+
+    if Settings.AimSmoothingCurve == "Exponential" then
+        scaled = scaled * scaled
+    elseif Settings.AimSmoothingCurve == "EaseInOut" then
+        scaled = easeOutQuad(scaled)
     end
+
+    return math.clamp(scaled, 0, 1)
+end
+
+-- Anti-jitter guard for near-center targets
+local function IsNearCenter(position2d)
+    local viewportCenter = Camera.ViewportSize / 2
+    return (Vector2new(position2d.X, position2d.Y) - Vector2new(viewportCenter.X, viewportCenter.Y)).Magnitude <= Settings.AntiJitterRadius
+end
+
+-- UI refresh separated for clarity
+local LastFovColor, LastEnemyColor, LastTeamColor, LastLowHealthColor
+local function UpdateUI(dt)
     local mouseLoc = UserInputService:GetMouseLocation()
-    local enemyColor = Settings.EnemyESPColor or DEFAULT_ESP_COLOR
-    local teamColor = Settings.TeamESPColor or DEFAULT_TEAM_COLOR
-    local lowHealthColor = Settings.LowHealthESPColor or DEFAULT_LOW_HEALTH_COLOR
     local fovColor = Settings.FOVCircleColor or DEFAULT_FOV_COLOR
     local fps = Workspace:GetRealPhysicsFPS()
 
-    -- Draw Legit Circle
     if FOV_Circle_Legit then
         FOV_Circle_Legit.Position = mouseLoc
         FOV_Circle_Legit.Radius = Settings.AimbotFOV
-        FOV_Circle_Legit.Color = fovColor
+        if fovColor ~= LastFovColor then
+            FOV_Circle_Legit.Color = fovColor
+            LastFovColor = fovColor
+        end
         FOV_Circle_Legit.Visible = Settings.AimbotEnabled
     end
 
-    -- Update Watermark FPS
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
 
-    -- AIMBOT LOGIC
-    local primaryState = GetBindState("AimBind")
-    local secondaryState = GetBindState("AimBindSecondary")
+    return mouseLoc
+end
+
+-- Aimbot handler (frame)
+local function UpdateAimbot(dt, primaryState, secondaryState)
     local shouldAim = ShouldAim(primaryState, secondaryState)
+    if not shouldAim then
+        LegitTarget = nil
+        return shouldAim
+    end
 
-    if shouldAim then
-        LegitTarget = GetClosestPlayerToMouse(Settings.AimbotFOV)
+    LegitTarget = GetTarget(Settings.AimbotFOV)
+
+    if LegitTarget and LegitTarget.Character and LegitTarget.Character:FindFirstChild(Settings.AimPart) then
+        if MathRandom(1, 100) <= Settings.AimbotHitChance then
+            local aimPart
+            local aimChoices = { Settings.AimPart, "UpperTorso", "HumanoidRootPart" }
+            for _, partName in ipairs(aimChoices) do
+                local candidate = LegitTarget.Character:FindFirstChild(partName)
+                if candidate then
+                    if Settings.WallCheck and not PerformWallCheck(LegitTarget, candidate) then
+                        continue
+                    end
+                    aimPart = candidate
+                    break
+                end
+            end
 
-        if LegitTarget and Settings.WallCheck and not IsVisible(LegitTarget) then
-            LegitTarget = nil
+            if not aimPart then return shouldAim end
+
+            local pos, onScreen = GetViewportPosition(aimPart)
+            if Settings.AntiJitterRadius > 0 and onScreen and IsNearCenter(pos) then
+                return shouldAim
+            end
+
+            local predicted = PredictMovement(LegitTarget)
+            local aimPos = predicted or aimPart.Position
+            local currentCFrame = Camera.CFrame
+            local targetCFrame = CFrame.new(currentCFrame.Position, aimPos)
+            local alpha = resolveSmoothingAlpha(dt)
+
+            if Settings.UseEasing then
+                alpha = easeOutQuad(alpha)
+            end
+
+            Camera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)
         end
+    end
+    return shouldAim
+end
+
+-- Triggerbot implementation using camera->mouse raycast
+local function UpdateTriggerbot(dt, mouseLoc, aimingActive)
+    if not Settings.TriggerbotEnabled then return end
+    if Settings.TriggerbotRequiresAimbot and not aimingActive then return end
+    if Settings.TriggerbotHoldToFire and Settings.TriggerbotHoldBind and not GetBindState("TriggerbotHoldBind") then return end
+
+    local now = tick()
+    local delaySec = Settings.TriggerbotDelay / 1000
+    local rateSec = Settings.TriggerbotFireRate / 1000
+    if now - LastShotTime < rateSec or now - LastTriggerTime < delaySec then
+        return
+    end
+
+    local ray = Camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
+    local params, ignoreList = GetRayParams(Settings.IgnoreAccessories, false)
+    ignoreList[2] = LocalPlayer.Character
+    params.FilterDescendantsInstances = ignoreList
+
+    local result = Workspace:Raycast(ray.Origin, ray.Direction * Settings.TriggerbotMaxDistance, params)
+    if not result or not result.Instance then return end
+
+    local model = result.Instance:FindFirstAncestorWhichIsA("Model")
+    if not model then return end
+    local player = Players:GetPlayerFromCharacter(model)
+    if not player or player == LocalPlayer then return end
+
+    if Settings.TriggerbotTeamCheck and player.Team == LocalPlayer.Team then return end
 
-        if LegitTarget and LegitTarget.Character and LegitTarget.Character:FindFirstChild(Settings.AimPart) then
-            if MathRandom(1, 100) <= Settings.AimbotHitChance then
-                local predicted = PredictAimPosition(LegitTarget)
-                local aimPos = predicted or LegitTarget.Character[Settings.AimPart].Position
-                local currentCFrame = Camera.CFrame
-                local targetCFrame = CFrame.new(currentCFrame.Position, aimPos)
-                Camera.CFrame = currentCFrame:Lerp(targetCFrame, Settings.AimbotSmooth)
+    local hitPartName = result.Instance.Name
+    local important = hitPartName == "Head" or hitPartName == "HumanoidRootPart" or hitPartName == "UpperTorso"
+    if not important then return end
+
+    if Settings.TriggerbotWallCheck and not PerformWallCheck(player, result.Instance, true) then
+        return
+    end
+
+    local distance = (result.Position - Camera.CFrame.Position).Magnitude
+    if distance > Settings.TriggerbotMaxDistance then return end
+
+    -- Apply the shot after respecting delay and rate limits
+    LastTriggerTime = now
+    task.delay(delaySec, function()
+        if tick() - LastShotTime < rateSec then return end
+        LastShotTime = tick()
+        pcall(function()
+            mouse1press()
+            task.wait(0.02)
+            mouse1release()
+        end)
+    end)
+end
+
+-- ESP drawing helpers
+local function DrawBoxESP(objs, boxPos, boxWidth, boxHeight, color)
+    if objs.BoxOutline and objs.Box then
+        objs.BoxOutline.Size = Vector2new(boxWidth, boxHeight)
+        objs.BoxOutline.Position = boxPos
+        objs.BoxOutline.Visible = true
+
+        objs.Box.Size = Vector2new(boxWidth, boxHeight)
+        objs.Box.Position = boxPos
+        objs.Box.Color = color
+        objs.Box.Visible = true
+    end
+end
+
+local function DrawHealthESP(objs, boxPos, boxHeight, healthPercent)
+    if not (objs.HealthBar and objs.HealthOutline) then return end
+    local barHeight = boxHeight * healthPercent
+
+    objs.HealthOutline.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
+    objs.HealthOutline.To = Vector2new(boxPos.X - 5, boxPos.Y)
+    objs.HealthOutline.Visible = true
+
+    objs.HealthBar.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
+    objs.HealthBar.To = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight - barHeight)
+    objs.HealthBar.Color = Color3new(1 - healthPercent, healthPercent, 0)
+    objs.HealthBar.Visible = true
+end
+
+local function DrawSkeleton(char, hum, cache, color)
+    local connections = (hum.RigType == Enum.HumanoidRigType.R15) and R15_Connections or R6_Connections
+    for i, pair in ipairs(connections) do
+        local pA = char:FindFirstChild(pair[1])
+        local pB = char:FindFirstChild(pair[2])
+
+        if pA and pB then
+            local vA, visA = GetViewportPosition(pA)
+            local vB, visB = GetViewportPosition(pB)
+
+            if visA and visB then
+                if not cache.SkeletonLines[i] then cache.SkeletonLines[i] = createLine() end
+                local line = cache.SkeletonLines[i]
+                line.From = Vector2new(vA.X, vA.Y)
+                line.To = Vector2new(vB.X, vB.Y)
+                line.Color = color
+                line.Visible = true
+            elseif cache.SkeletonLines[i] then
+                cache.SkeletonLines[i].Visible = false
             end
+        elseif cache.SkeletonLines[i] then
+            cache.SkeletonLines[i].Visible = false
         end
     end
+end
 
-    -- ESP LOOP
+local function UpdateESP(dt, enemyColor, teamColor, lowHealthColor)
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
 
-        local vector, onScreen = Camera:WorldToViewportPoint(hrp.Position)
+        local vector, onScreen = GetViewportPosition(hrp)
 
         if not ESP_Cache[player] then
             ESP_Cache[player] = { Objects = createBoxStructure(), SkeletonLines = {} }
         end
         local cache = ESP_Cache[player]
         local objs = cache.Objects
 
-        if onScreen then
-            local boxHeight = (Camera.ViewportSize.Y / vector.Z) * 7
+        if onScreen and vector.Z > 0 then
+            local distance = vector.Z
+            if distance > 600 then
+                -- Skip expensive ESP for far targets
+                if objs.Box then objs.Box.Visible = false end
+                if objs.BoxOutline then objs.BoxOutline.Visible = false end
+                for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
+                continue
+            end
+
+            local boxHeight = (Camera.ViewportSize.Y / distance) * 7
             local boxWidth = boxHeight / 2
             local boxPos = Vector2new(vector.X - boxWidth / 2, vector.Y - boxHeight / 2)
 
             local colorProfile = enemyColor
             if hum.Health <= Settings.LowHealthThreshold then
                 colorProfile = lowHealthColor
             elseif isTeammate then
                 colorProfile = teamColor
             end
 
-            if Settings.BoxESP and objs.Box and objs.BoxOutline then
-                objs.BoxOutline.Size = Vector2new(boxWidth, boxHeight)
-                objs.BoxOutline.Position = boxPos
-                objs.BoxOutline.Visible = true
-
-                objs.Box.Size = Vector2new(boxWidth, boxHeight)
-                objs.Box.Position = boxPos
-                objs.Box.Color = colorProfile
-                objs.Box.Visible = true
+            if Settings.BoxESP then
+                DrawBoxESP(objs, boxPos, boxWidth, boxHeight, colorProfile)
             else
                 if objs.Box then objs.Box.Visible = false end
                 if objs.BoxOutline then objs.BoxOutline.Visible = false end
             end
 
-            if Settings.HealthESP and objs.HealthBar then
-                local healthPercent = hum.Health / hum.MaxHealth
-                local barHeight = boxHeight * healthPercent
-
-                objs.HealthOutline.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
-                objs.HealthOutline.To = Vector2new(boxPos.X - 5, boxPos.Y)
-                objs.HealthOutline.Visible = true
-
-                objs.HealthBar.From = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight)
-                objs.HealthBar.To = Vector2new(boxPos.X - 5, boxPos.Y + boxHeight - barHeight)
-                objs.HealthBar.Color = Color3new(1 - healthPercent, healthPercent, 0)
-                objs.HealthBar.Visible = true
+            if Settings.HealthESP then
+                DrawHealthESP(objs, boxPos, boxHeight, hum.Health / hum.MaxHealth)
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
 
-            local skeletonEnabled = Settings.SkeletonESP and not (Settings.FPSSafeSkeleton and fps < 55)
+            local skeletonEnabled = Settings.SkeletonESP and not (Settings.FPSSafeSkeleton and Workspace:GetRealPhysicsFPS() < 55)
             if skeletonEnabled then
-                local connections = (hum.RigType == Enum.HumanoidRigType.R15) and R15_Connections or R6_Connections
-
-                for i, pair in ipairs(connections) do
-                    local pA = char:FindFirstChild(pair[1])
-                    local pB = char:FindFirstChild(pair[2])
-
-                    if pA and pB then
-                        local vA, visA = Camera:WorldToViewportPoint(pA.Position)
-                        local vB, visB = Camera:WorldToViewportPoint(pB.Position)
-
-                        if visA and visB then
-                            if not cache.SkeletonLines[i] then cache.SkeletonLines[i] = createLine() end
-                            local line = cache.SkeletonLines[i]
-                            line.From = Vector2new(vA.X, vA.Y)
-                            line.To = Vector2new(vB.X, vB.Y)
-                            line.Color = colorProfile
-                            line.Visible = true
-                        elseif cache.SkeletonLines[i] then
-                            cache.SkeletonLines[i].Visible = false
-                        end
-                    elseif cache.SkeletonLines[i] then
-                        cache.SkeletonLines[i].Visible = false
-                    end
-                end
+                DrawSkeleton(char, hum, cache, colorProfile)
             else
                 for _, l in pairs(cache.SkeletonLines) do l.Visible = false end
             end
 
+            -- Occlusion ESP tinting
+            if Settings.WallCheck and Settings.BoxESP then
+                if not PerformWallCheck(player, hrp) then
+                    objs.Box.Color = OCCLUDED_COLOR
+                end
+            end
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
+end
+
+-- Main render connection
+RenderConnection = RunService.RenderStepped:Connect(function(dt)
+    if Workspace.CurrentCamera ~= Camera then
+        Camera = Workspace.CurrentCamera
+    end
+
+    ViewportFrame += 1
+    table.clear(ViewportCache)
+
+    local enemyColor = Settings.EnemyESPColor or DEFAULT_ESP_COLOR
+    local teamColor = Settings.TeamESPColor or DEFAULT_TEAM_COLOR
+    local lowHealthColor = Settings.LowHealthESPColor or DEFAULT_LOW_HEALTH_COLOR
+
+    if enemyColor ~= LastEnemyColor then LastEnemyColor = enemyColor end
+    if teamColor ~= LastTeamColor then LastTeamColor = teamColor end
+    if lowHealthColor ~= LastLowHealthColor then LastLowHealthColor = lowHealthColor end
+
+    local mouseLoc = UpdateUI(dt)
+
+    local primaryState = GetBindState("AimBind")
+    local secondaryState = GetBindState("AimBindSecondary")
+    local aimingActive = UpdateAimbot(dt, primaryState, secondaryState)
+
+    UpdateTriggerbot(dt, mouseLoc, aimingActive)
+    UpdateESP(dt, enemyColor, teamColor, lowHealthColor)
 end)
 
EOF
)
