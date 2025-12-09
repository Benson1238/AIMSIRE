-- AimRare_Reborn.lua
-- Complete rewrite with emphasis on stability, memory safety, and predictable performance

if _G.AimRareLoaded and typeof(_G.AimRareLoaded.Unload) == "function" then
    -- Unload previous instance safely
    pcall(function()
        _G.AimRareLoaded:Unload()
    end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// Utility: safe math helpers
local function isFiniteVector(v)
    return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end

local function safeLookAt(origin, target)
    if not (isFiniteVector(origin) and isFiniteVector(target)) then
        return Camera.CFrame
    end
    return CFrame.lookAt(origin, target)
end

--// Janitor for cleanup
local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
    return setmetatable({tasks = {}}, Janitor)
end

function Janitor:Add(object, method, key)
    local taskEntry = {object = object, method = method}
    self.tasks[key or #self.tasks + 1] = taskEntry
    return object
end

function Janitor:Cleanup()
    for key, taskEntry in pairs(self.tasks) do
        local obj = taskEntry.object
        local method = taskEntry.method
        if obj then
            local success, err = pcall(function()
                if typeof(obj) == "RBXScriptConnection" then
                    obj:Disconnect()
                elseif typeof(obj) == "function" then
                    obj()
                elseif method and obj[method] then
                    obj[method](obj)
                elseif typeof(obj.Destroy) == "function" then
                    obj:Destroy()
                end
            end)
            if not success then
                warn("Janitor cleanup error:", err)
            end
        end
        self.tasks[key] = nil
    end
end

function Janitor:Remove(key)
    local entry = self.tasks[key]
    if entry then
        local obj = entry.object
        local method = entry.method
        if obj then
            pcall(function()
                if typeof(obj) == "RBXScriptConnection" then
                    obj:Disconnect()
                elseif typeof(obj) == "function" then
                    obj()
                elseif method and obj[method] then
                    obj[method](obj)
                elseif typeof(obj.Destroy) == "function" then
                    obj:Destroy()
                end
            end)
        end
        self.tasks[key] = nil
    end
end

--// Service Manager
local ServiceManager = {}
ServiceManager.__index = ServiceManager

function ServiceManager.new(janitor)
    return setmetatable({services = {}, janitor = janitor}, ServiceManager)
end

function ServiceManager:Register(service)
    self.services[#self.services + 1] = service
end

function ServiceManager:Init()
    for _, service in ipairs(self.services) do
        if typeof(service.Init) == "function" then
            service:Init()
        end
    end
end

function ServiceManager:Start()
    for _, service in ipairs(self.services) do
        if typeof(service.Start) == "function" then
            service:Start()
        end
    end
end

function ServiceManager:Stop()
    for _, service in ipairs(self.services) do
        if typeof(service.Stop) == "function" then
            service:Stop()
        end
    end
end

--// Player Cache with weak keys to avoid leaks
local PlayerCache = {}
PlayerCache.__index = PlayerCache

function PlayerCache.new(janitor)
    local self = setmetatable({}, PlayerCache)
    self.Janitor = janitor
    self.players = setmetatable({}, { __mode = "k" })
    self.velocityHistory = setmetatable({}, { __mode = "k" })
    self.maxHistory = 60
    self.FilterChangedSignal = Instance.new("BindableEvent")
    janitor:Add(self.FilterChangedSignal, "Destroy")
    return self
end

function PlayerCache:Init()
    local playerAddedConn = Players.PlayerAdded:Connect(function(player)
        self:TrackPlayer(player)
    end)
    local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        self:UntrackPlayer(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            self:TrackPlayer(player)
        end
    end

    self.Janitor:Add(playerAddedConn)
    self.Janitor:Add(playerRemovingConn)
end

function PlayerCache:TrackPlayer(player)
    self.players[player] = {
        character = nil,
        rootPart = nil,
    }
    self.velocityHistory[player] = {}

    local function onCharacterAdded(char)
        self.players[player].character = char
        self.players[player].rootPart = char:WaitForChild("HumanoidRootPart", 5)
        self.FilterChangedSignal:Fire()
    end

    local charAddedConn = player.CharacterAdded:Connect(onCharacterAdded)
    local charRemovingConn = player.CharacterRemoving:Connect(function()
        self.players[player].character = nil
        self.players[player].rootPart = nil
        self.velocityHistory[player] = {}
        self.FilterChangedSignal:Fire()
    end)

    if player.Character then
        onCharacterAdded(player.Character)
    end

    self.Janitor:Add(charAddedConn)
    self.Janitor:Add(charRemovingConn)
end

function PlayerCache:UntrackPlayer(player)
    self.players[player] = nil
    self.velocityHistory[player] = nil
    self.FilterChangedSignal:Fire()
end

function PlayerCache:GetPlayers()
    return self.players
end

function PlayerCache:RecordVelocity(player)
    local data = self.players[player]
    if not data then
        return
    end
    local root = data.rootPart
    if root and root.Parent then
        local history = self.velocityHistory[player]
        if history then
            history[#history + 1] = root.Velocity
            if #history > self.maxHistory then
                table.remove(history, 1)
            end
        end
    end
end

function PlayerCache:GetAverageVelocity(player)
    local history = self.velocityHistory[player]
    if not history or #history == 0 then
        return Vector3.zero
    end
    local sum = Vector3.zero
    for _, vel in ipairs(history) do
        sum += vel
    end
    return sum / #history
end

--// Drawing object pooling
local function createDrawingSafe(drawType)
    local obj
    local ok, err = pcall(function()
        obj = Drawing.new(drawType)
    end)
    if not ok then
        warn("Drawing creation failed:", err)
        return nil
    end
    return obj
end

local function safeSet(obj, prop, value)
    if not obj then return end
    local ok, err = pcall(function()
        obj[prop] = value
    end)
    if not ok then
        warn("Drawing property set failed:", err)
    end
end

local EspService = {}
EspService.__index = EspService

function EspService.new(janitor, playerCache)
    local self = setmetatable({}, EspService)
    self.Janitor = janitor
    self.PlayerCache = playerCache
    self.poolSize = 32
    self.pool = {}
    self.frameCounter = 0
    self.enabled = true
    return self
end

function EspService:Init()
    for i = 1, self.poolSize do
        local box = createDrawingSafe("Square")
        local tracer = createDrawingSafe("Line")
        local nameText = createDrawingSafe("Text")

        if box then
            box.Filled = false
            box.Thickness = 1
            box.Color = Color3.fromRGB(0, 255, 120)
            box.Visible = false
        end
        if tracer then
            tracer.Thickness = 1
            tracer.Color = Color3.fromRGB(0, 255, 120)
            tracer.Visible = false
        end
        if nameText then
            nameText.Size = 14
            nameText.Center = true
            nameText.Outline = true
            nameText.Color = Color3.fromRGB(255, 255, 255)
            nameText.Visible = false
        end

        self.pool[i] = {
            busy = false,
            box = box,
            tracer = tracer,
            text = nameText,
            target = nil,
            skipFrames = 0,
        }

        self.Janitor:Add(function()
            safeSet(box, "Visible", false)
            safeSet(tracer, "Visible", false)
            safeSet(nameText, "Visible", false)
            if box and box.Remove then pcall(function() box:Remove() end) end
            if tracer and tracer.Remove then pcall(function() tracer:Remove() end) end
            if nameText and nameText.Remove then pcall(function() nameText:Remove() end) end
        end)
    end
end

function EspService:GetSlot(target)
    for _, slot in ipairs(self.pool) do
        if slot.target == target then
            return slot
        end
    end
    for _, slot in ipairs(self.pool) do
        if not slot.busy then
            slot.busy = true
            slot.target = target
            slot.skipFrames = 0
            return slot
        end
    end
    return nil
end

function EspService:ReleaseUnused(activeTargets)
    local activeSet = {}
    for _, target in ipairs(activeTargets) do
        activeSet[target] = true
    end

    for _, slot in ipairs(self.pool) do
        if slot.target and not activeSet[slot.target] then
            slot.busy = false
            slot.target = nil
            slot.skipFrames = 0
            safeSet(slot.box, "Visible", false)
            safeSet(slot.tracer, "Visible", false)
            safeSet(slot.text, "Visible", false)
        end
    end
end

function EspService:Update()
    if not self.enabled then
        return
    end

    self.frameCounter += 1

    local activeTargets = {}
    local cameraCFrame = Camera.CFrame
    local viewportSize = Camera.ViewportSize

    for player, data in pairs(self.PlayerCache:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = data.character
            local root = data.rootPart
            if char and root and root.Parent then
                local rootPos = root.Position
                local relative = cameraCFrame:PointToObjectSpace(rootPos)
                if relative.Z > 0 then
                    activeTargets[#activeTargets + 1] = player
                    local slot = self:GetSlot(player)
                    if slot then
                        local distance = (rootPos - cameraCFrame.Position).Magnitude
                        local throttle = 1
                        if distance >= 1000 then
                            throttle = 3
                        elseif distance <= 300 then
                            throttle = 1
                        else
                            throttle = 2
                        end

                        slot.skipFrames = (slot.skipFrames + 1) % throttle
                        if slot.skipFrames == 0 then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(rootPos)
                            if onScreen then
                                local boxSize = Vector2.new(50, 70) * math.clamp(1200 / math.max(distance, 0.1), 0.4, 1.2)
                                local boxPos = Vector2.new(screenPos.X - boxSize.X / 2, screenPos.Y - boxSize.Y / 2)

                                safeSet(slot.box, "Size", boxSize)
                                safeSet(slot.box, "Position", boxPos)
                                safeSet(slot.box, "Visible", true)

                                safeSet(slot.tracer, "From", Vector2.new(viewportSize.X / 2, viewportSize.Y))
                                safeSet(slot.tracer, "To", Vector2.new(screenPos.X, screenPos.Y))
                                safeSet(slot.tracer, "Visible", throttle == 1)

                                safeSet(slot.text, "Text", player.DisplayName)
                                safeSet(slot.text, "Position", Vector2.new(screenPos.X, boxPos.Y - 14))
                                safeSet(slot.text, "Visible", true)
                            else
                                safeSet(slot.box, "Visible", false)
                                safeSet(slot.tracer, "Visible", false)
                                safeSet(slot.text, "Visible", false)
                            end
                        end
                    end
                end
            end
        end
    end

    self:ReleaseUnused(activeTargets)
end

function EspService:Stop()
    self.enabled = false
    self:ReleaseUnused({})
end

--// Aimbot Service
local AimbotService = {}
AimbotService.__index = AimbotService

function AimbotService.new(janitor, playerCache)
    local self = setmetatable({}, AimbotService)
    self.Janitor = janitor
    self.PlayerCache = playerCache
    self.EspService = nil
    self.enabled = true
    self.aiming = false
    self.smoothing = 0.25
    self.predictionTime = 0.125
    self.maxDistance = 2000
    self.raycastParams = RaycastParams.new()
    self.raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    self.raycastParams.IgnoreWater = true
    self.filterObjects = {}
    return self
end

function AimbotService:Init()
    local function rebuildFilter()
        table.clear(self.filterObjects)
        if LocalPlayer.Character then
            self.filterObjects[#self.filterObjects + 1] = LocalPlayer.Character
        end
        self.filterObjects[#self.filterObjects + 1] = Camera
        self.raycastParams.FilterDescendantsInstances = self.filterObjects
    end

    rebuildFilter()
    self.Janitor:Add(self.PlayerCache.FilterChangedSignal.Event:Connect(rebuildFilter))

    self.Janitor:Add(LocalPlayer.CharacterAdded:Connect(function()
        rebuildFilter()
    end))
    self.Janitor:Add(LocalPlayer.CharacterRemoving:Connect(function()
        rebuildFilter()
    end))
end

function AimbotService:SetEspService(espService)
    self.EspService = espService
end

function AimbotService:GetClosestTarget()
    local closestPlayer = nil
    local closestDistance = self.maxDistance
    local camPos = Camera.CFrame.Position

    for player, data in pairs(self.PlayerCache:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = data.character
            local root = data.rootPart
            if char and root and root.Parent then
                local distance = (root.Position - camPos).Magnitude
                if distance < closestDistance then
                    local direction = (root.Position - camPos).Unit
                    local raycast = Workspace:Raycast(camPos, direction * distance, self.raycastParams)
                    if not raycast or (raycast.Instance and raycast.Instance:IsDescendantOf(char)) then
                        closestPlayer = player
                        closestDistance = distance
                    end
                end
            end
        end
    end

    return closestPlayer
end

function AimbotService:PredictPosition(player)
    local data = self.PlayerCache:GetPlayers()[player]
    if not data or not data.rootPart then
        return nil
    end
    local root = data.rootPart
    local avgVelocity = self.PlayerCache:GetAverageVelocity(player)
    local predicted = root.Position + (avgVelocity * self.predictionTime)
    if not isFiniteVector(predicted) then
        return root.Position
    end
    return predicted
end

function AimbotService:Start()
    local inputConn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.aiming = true
        elseif input.KeyCode == Enum.KeyCode.RightAlt then
            self.enabled = not self.enabled
            if self.EspService then
                self.EspService.enabled = self.enabled
            end
        end
    end)

    local inputEndConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.aiming = false
        end
    end)

    self.Janitor:Add(inputConn)
    self.Janitor:Add(inputEndConn)

    local renderConn = RunService.RenderStepped:Connect(function()
        if not self.enabled or not self.aiming then
            return
        end
        local targetPlayer = self:GetClosestTarget()
        if not targetPlayer then
            return
        end
        local predicted = self:PredictPosition(targetPlayer)
        if not predicted then
            return
        end

        local camPos = Camera.CFrame.Position
        local desired = safeLookAt(camPos, predicted)
        Camera.CFrame = Camera.CFrame:Lerp(desired, self.smoothing)
    end)

    self.Janitor:Add(renderConn)

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        for player in pairs(self.PlayerCache:GetPlayers()) do
            self.PlayerCache:RecordVelocity(player)
        end
    end)

    self.Janitor:Add(heartbeatConn)
end

function AimbotService:Stop()
    self.enabled = false
    self.aiming = false
end

--// UI Service with headless fallback
local UIService = {}
UIService.__index = UIService

function UIService.new(janitor, espService, aimbotService)
    local self = setmetatable({}, UIService)
    self.Janitor = janitor
    self.EspService = espService
    self.AimbotService = aimbotService
    self.statusText = nil
    self.fpsText = nil
    self.headless = false
    self.lastUpdate = 0
    return self
end

function UIService:Init()
    local ok, library = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Rayfield/main/source"))()
    end)

    if not ok or not library then
        self.headless = true
        warn("UI library failed to load, entering headless mode")
        return
    end

    local success, window = pcall(function()
        return library:CreateWindow({
            Name = "AimRare Reborn",
            LoadingTitle = "AimRare",
            LoadingSubtitle = "Reborn",
            ConfigurationSaving = false,
            Discord = {
                Enabled = false
            }
        })
    end)

    if not success or not window then
        self.headless = true
        warn("UI failed to initialize, headless mode active")
        return
    end

    local tab = window:CreateTab("Main")

    tab:CreateToggle({
        Name = "ESP",
        CurrentValue = true,
        Flag = "ESP_Toggle",
        Callback = function(value)
            self.EspService.enabled = value
        end,
    })

    tab:CreateToggle({
        Name = "Aimbot",
        CurrentValue = true,
        Flag = "Aimbot_Toggle",
        Callback = function(value)
            self.AimbotService.enabled = value
        end,
    })

    tab:CreateSlider({
        Name = "Smoothing",
        Range = {0.05, 0.6},
        Increment = 0.01,
        Suffix = "lerp",
        CurrentValue = self.AimbotService.smoothing,
        Flag = "Smoothing_Slider",
        Callback = function(value)
            self.AimbotService.smoothing = value
        end,
    })

    tab:CreateSlider({
        Name = "Prediction Time",
        Range = {0.05, 0.35},
        Increment = 0.01,
        Suffix = "s",
        CurrentValue = self.AimbotService.predictionTime,
        Flag = "Prediction_Slider",
        Callback = function(value)
            self.AimbotService.predictionTime = value
        end,
    })

    self.statusText = tab:CreateParagraph({ Title = "Status", Content = "Running" })
    self.fpsText = tab:CreateParagraph({ Title = "FPS", Content = "0" })
end

function UIService:Start()
    if self.headless then
        -- Headless mode uses hotkeys only
        local info = [[
[Headless Mode]
Right Alt - Toggle Aimbot/ESP
Right Mouse - Hold to aim
        ]]
        print(info)
        return
    end

    local running = true
    self.Janitor:Add(function()
        running = false
    end)

    task.spawn(function()
        local frameCount = 0
        local lastTime = os.clock()
        while running do
            local dt = RunService.Heartbeat:Wait()
            frameCount += 1
            local now = os.clock()
            if now - lastTime >= 0.5 then
                local fps = math.floor(frameCount / math.max(now - lastTime, dt))
                frameCount = 0
                lastTime = now

                if self.statusText then
                    self.statusText:Set({ Content = string.format("Aimbot: %s | ESP: %s", self.AimbotService.enabled and "On" or "Off", self.EspService.enabled and "On" or "Off") })
                end
                if self.fpsText then
                    self.fpsText:Set({ Content = tostring(fps) })
                end
            end
        end
    end)
end

--// Root AimRare controller
local AimRare = {}
AimRare.__index = AimRare

function AimRare.new()
    local self = setmetatable({}, AimRare)
    self.Janitor = Janitor.new()
    self.ServiceManager = ServiceManager.new(self.Janitor)

    self.PlayerCache = PlayerCache.new(self.Janitor)
    self.EspService = EspService.new(self.Janitor, self.PlayerCache)
    self.AimbotService = AimbotService.new(self.Janitor, self.PlayerCache)
    self.UIService = UIService.new(self.Janitor, self.EspService, self.AimbotService)

    self.AimbotService:SetEspService(self.EspService)

    self.ServiceManager:Register(self.PlayerCache)
    self.ServiceManager:Register(self.EspService)
    self.ServiceManager:Register(self.AimbotService)
    self.ServiceManager:Register(self.UIService)

    return self
end

function AimRare:Init()
    self.ServiceManager:Init()
end

function AimRare:Start()
    self.ServiceManager:Start()

    local renderConn = RunService.RenderStepped:Connect(function()
        self.EspService:Update()
    end)

    self.Janitor:Add(renderConn)
end

function AimRare:Unload()
    self.ServiceManager:Stop()
    self.Janitor:Cleanup()
end

local controller = AimRare.new()
controller:Init()
controller:Start()

_G.AimRareLoaded = controller

return controller
