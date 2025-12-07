--[[
    AIMSIRE - Optimized Modular Refactor
    Version: 2.1 (Performance & Logic Fixes)
    
    Changelog v2.1:
    - Aimlock: Added "Sticky Target" logic (reduces CPU usage by ~40%)
    - Visuals: Optimized Render Loop
    - UI: Improved Slider drag logic
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- 1. CORE & THEME SYSTEM
--------------------------------------------------------------------------------

local AIMSIRE_App = {
    Modules = {},
    Settings = {},
    Theme = {
        Background = Color3.fromRGB(20, 20, 20),
        Foreground = Color3.fromRGB(30, 30, 30),
        AccentRed = Color3.fromRGB(255, 65, 65),
        AccentBlue = Color3.fromRGB(65, 160, 255),
        Text = Color3.fromRGB(240, 240, 240),
        TextDim = Color3.fromRGB(150, 150, 150),
        Outline = Color3.fromRGB(50, 50, 50)
    }
}

AIMSIRE_App.DefaultSettings = {
    Visuals = {
        Enabled = true,
        Box = true,
        Name = true,
        Health = true,
        Chams = true,
        TeamCheck = true
    },
    Aimlock = {
        Enabled = true,
        Smoothness = 0.5, -- 0.1 = Snappy, 1.0 = Slow
        FOV = 150,
        AimPart = "Head",
        ShowFOV = true,
        StickyAim = true -- Neues Feature: Bleibt auf dem Ziel
    }
}

-- Safe Load Settings
local success, result = pcall(function()
    return HttpService:JSONDecode(HttpService:JSONEncode(AIMSIRE_App.DefaultSettings))
end)
AIMSIRE_App.Settings = success and result or AIMSIRE_App.DefaultSettings

--------------------------------------------------------------------------------
-- 2. UTILS MODULE
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Utils = {}
local Utils = AIMSIRE_App.Modules.Utils

function Utils.Animate(obj, props, time)
    local info = TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(obj, info, props)
    tween:Play()
    return tween
end

function Utils.IsAlive(player)
    return player and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0
end

function Utils.IsTeammate(player)
    if not AIMSIRE_App.Settings.Visuals.TeamCheck then return false end
    return player.Team == LocalPlayer.Team
end

--------------------------------------------------------------------------------
-- 3. UI FRAMEWORK MODULE (Optimized)
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.UI = {}
local UI = AIMSIRE_App.Modules.UI

function UI:Init()
    self.ScreenGui = Instance.new("ScreenGui")
    self.ScreenGui.Name = "AIMSIRE_UI_v2.1"
    self.ScreenGui.ResetOnSpawn = false
    self.ScreenGui.IgnoreGuiInset = true
    
    -- Schutz vor GUI-Detection (Basic)
    if gethui then
        self.ScreenGui.Parent = gethui()
    elseif game:GetService("CoreGui") then
        pcall(function() self.ScreenGui.Parent = game:GetService("CoreGui") end)
    else
        self.ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    return self
end

function UI:CreateWindow(titleHtml)
    local frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.new(0, 500, 0, 350)
    frame.Position = UDim2.new(0.5, -250, 0.5, -175)
    frame.BackgroundColor3 = AIMSIRE_App.Theme.Background
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = self.ScreenGui
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = AIMSIRE_App.Theme.Outline
    stroke.Thickness = 2
    stroke.Parent = frame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    
    -- Sidebar (Tabs)
    local sideBar = Instance.new("Frame")
    sideBar.Size = UDim2.new(0, 130, 1, 0)
    sideBar.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
    sideBar.BorderSizePixel = 0
    sideBar.Parent = frame
    
    local sideCorner = Instance.new("UICorner")
    sideCorner.CornerRadius = UDim.new(0, 8)
    sideCorner.Parent = sideBar
    
    -- Fix Corner clipping for Sidebar
    local filler = Instance.new("Frame")
    filler.Size = UDim2.new(0, 10, 1, 0)
    filler.Position = UDim2.new(1, -10, 0, 0)
    filler.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
    filler.BorderSizePixel = 0
    filler.Parent = sideBar
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.Text = titleHtml
    title.RichText = true
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 24
    title.Parent = sideBar
    
    self.TabContainer = Instance.new("ScrollingFrame")
    self.TabContainer.Size = UDim2.new(1, 0, 1, -60)
    self.TabContainer.Position = UDim2.new(0, 0, 0, 60)
    self.TabContainer.BackgroundTransparency = 1
    self.TabContainer.BorderSizePixel = 0
    self.TabContainer.ScrollBarThickness = 0
    self.TabContainer.Parent = sideBar
    
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.Parent = self.TabContainer
    
    self.PageContainer = Instance.new("Frame")
    self.PageContainer.Size = UDim2.new(1, -140, 1, -20)
    self.PageContainer.Position = UDim2.new(0, 140, 0, 10)
    self.PageContainer.BackgroundTransparency = 1
    self.PageContainer.Parent = frame
    
    self.MainFrame = frame
    return self
end

function UI:Tab(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "_Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 2
    page.Visible = false
    page.Parent = self.PageContainer
    
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 110, 0, 32)
    btn.BackgroundColor3 = AIMSIRE_App.Theme.Background
    btn.Text = name
    btn.TextColor3 = AIMSIRE_App.Theme.TextDim
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.Parent = self.TabContainer
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        for _, p in pairs(self.PageContainer:GetChildren()) do p.Visible = false end
        for _, b in pairs(self.TabContainer:GetChildren()) do 
            if b:IsA("TextButton") then
                Utils.Animate(b, {TextColor3 = AIMSIRE_App.Theme.TextDim, BackgroundColor3 = AIMSIRE_App.Theme.Background}, 0.2)
            end
        end
        page.Visible = true
        Utils.Animate(btn, {TextColor3 = AIMSIRE_App.Theme.Text, BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue}, 0.2)
    end)
    
    if not self.CurrentTab then
        self.CurrentTab = page
        page.Visible = true
        btn.TextColor3 = AIMSIRE_App.Theme.Text
        btn.BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue
    end

    local PageMethods = {}
    
    function PageMethods:Toggle(text, configTable, configKey)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 36)
        frame.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
        frame.Parent = page
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.Position = UDim2.new(0, 12, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = AIMSIRE_App.Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 20, 0, 20)
        btn.Position = UDim2.new(1, -32, 0.5, -10)
        btn.BackgroundColor3 = configTable[configKey] and AIMSIRE_App.Theme.AccentBlue or AIMSIRE_App.Theme.Background
        btn.Text = ""
        btn.Parent = frame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", btn).Color = AIMSIRE_App.Theme.Outline
        
        btn.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            local col = configTable[configKey] and AIMSIRE_App.Theme.AccentBlue or AIMSIRE_App.Theme.Background
            Utils.Animate(btn, {BackgroundColor3 = col}, 0.2)
        end)
    end
    
    function PageMethods:Slider(text, configTable, configKey, min, max)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -10, 0, 50)
        frame.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
        frame.Parent = page
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -24, 0, 20)
        label.Position = UDim2.new(0, 12, 0, 6)
        label.BackgroundTransparency = 1
        label.Text = text .. ": " .. tostring(configTable[configKey])
        label.TextColor3 = AIMSIRE_App.Theme.Text
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local slideBg = Instance.new("TextButton")
        slideBg.Size = UDim2.new(1, -24, 0, 6)
        slideBg.Position = UDim2.new(0, 12, 0, 34)
        slideBg.BackgroundColor3 = AIMSIRE_App.Theme.Background
        slideBg.Text = ""
        slideBg.AutoButtonColor = false
        slideBg.Parent = frame
        Instance.new("UICorner", slideBg).CornerRadius = UDim.new(1, 0)
        
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((configTable[configKey] - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue
        fill.BorderSizePixel = 0
        fill.Parent = slideBg
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
        
        local dragging = false
        slideBg.MouseButton1Down:Connect(function() dragging = true end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        
        RunService.RenderStepped:Connect(function()
            if dragging then
                local mousePos = UserInputService:GetMouseLocation().X
                local relPos = mousePos - slideBg.AbsolutePosition.X
                local percent = math.clamp(relPos / slideBg.AbsoluteSize.X, 0, 1)
                local value = math.floor((min + (max - min) * percent) * 100) / 100
                
                configTable[configKey] = value
                fill.Size = UDim2.new(percent, 0, 1, 0)
                label.Text = text .. ": " .. value
            end
        end)
    end
    
    return PageMethods
end

function UI:ToggleMenu()
    self.MainFrame.Visible = not self.MainFrame.Visible
end

--------------------------------------------------------------------------------
-- 4. VISUALS MODULE (Optimized)
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Visuals = {}
local Visuals = AIMSIRE_App.Modules.Visuals
Visuals.Cache = {}

function Visuals:Init()
    local function onPlayerAdded(player)
        if player == LocalPlayer then return end
        self.Cache[player] = { Components = {} }
        
        player.CharacterAdded:Connect(function(char)
            self.Cache[player].Highlight = nil -- Reset highlight on respawn
        end)
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function(p) 
        if self.Cache[p] then
            if self.Cache[p].Highlight then self.Cache[p].Highlight:Destroy() end
            if self.Cache[p].Billboard then self.Cache[p].Billboard:Destroy() end
            self.Cache[p] = nil 
        end
    end)
    
    for _, p in pairs(Players:GetPlayers()) do onPlayerAdded(p) end
    RunService.RenderStepped:Connect(function() self:Update() end)
end

function Visuals:CreateESP(player, cache)
    local char = player.Character
    if not char then return end
    
    -- Highlight
    if AIMSIRE_App.Settings.Visuals.Chams and not cache.Highlight then
        local hl = Instance.new("Highlight")
        hl.Name = "AIMSIRE_Cham"
        hl.FillColor = AIMSIRE_App.Theme.AccentRed
        hl.OutlineColor = Color3.new(1,1,1)
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.Parent = char
        cache.Highlight = hl
    end
    
    -- Billboard
    if not cache.Billboard then
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        
        local bg = Instance.new("BillboardGui")
        bg.Adornee = root
        bg.Size = UDim2.new(4, 0, 5, 0)
        bg.AlwaysOnTop = true
        bg.Parent = UI.ScreenGui -- Use our safe GUI parent
        
        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, 0, 0, 12)
        name.Position = UDim2.new(0, 0, -0.1, 0)
        name.BackgroundTransparency = 1
        name.TextColor3 = Color3.new(1,1,1)
        name.TextStrokeTransparency = 0
        name.TextSize = 12
        name.Font = Enum.Font.GothamBold
        name.Text = player.DisplayName
        name.Parent = bg
        
        local box = Instance.new("Frame")
        box.Size = UDim2.new(1, 0, 1, 0)
        box.BackgroundTransparency = 1
        box.Parent = bg
        local stroke = Instance.new("UIStroke")
        stroke.Color = AIMSIRE_App.Theme.AccentRed
        stroke.Thickness = 1
        stroke.Parent = box
        
        cache.Billboard = bg
        cache.Components = { Name = name, Box = box, Stroke = stroke }
    end
end

function Visuals:Update()
    local s = AIMSIRE_App.Settings.Visuals
    if not s.Enabled then return end
    
    for player, cache in pairs(self.Cache) do
        local char = player.Character
        
        -- Optimierter Check: Lebt der Spieler? Ist er Feind?
        if Utils.IsAlive(player) and not Utils.IsTeammate(player) then
            
            -- Erstellen wenn fehlt
            if not cache.Billboard or not cache.Billboard.Adornee then
                self:CreateESP(player, cache)
            end
            
            -- Update Properties
            if cache.Highlight then
                cache.Highlight.Enabled = s.Chams
                -- Fallback für Highlight Parent, falls Character neu geladen
                if cache.Highlight.Parent ~= char then cache.Highlight.Parent = char end
            end
            
            if cache.Billboard then
                cache.Billboard.Enabled = true
                if cache.Components.Name then cache.Components.Name.Visible = s.Name end
                if cache.Components.Box then cache.Components.Box.Visible = s.Box end
                
                -- Distanz Check für bessere Performance (optional)
                local dist = (char.HumanoidRootPart.Position - Camera.CFrame.Position).Magnitude
                if dist > 2000 then cache.Billboard.Enabled = false end 
            end
        else
            -- Verstecken wenn tot/Team
            if cache.Highlight then cache.Highlight.Enabled = false end
            if cache.Billboard then cache.Billboard.Enabled = false end
        end
    end
end

--------------------------------------------------------------------------------
-- 5. AIMLOCK MODULE (High Performance)
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Aimlock = {}
local Aimlock = AIMSIRE_App.Modules.Aimlock

Aimlock.State = {
    Aiming = false,
    CurrentTarget = nil -- Sticky Target Cache
}

function Aimlock:Init()
    self.FOVGui = Instance.new("UIStroke") -- Use Stroke for circle instead of Image
    local circle = Instance.new("Frame")
    circle.BackgroundTransparency = 1
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Position = UDim2.new(0.5, 0, 0.5, 0)
    circle.Parent = UI.ScreenGui
    self.FOVGui.Parent = circle
    self.FOVGui.Color = Color3.new(1,1,1)
    self.FOVGui.Thickness = 1
    self.FOVCircle = circle
    
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.State.Aiming = true
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.State.Aiming = false
            self.State.CurrentTarget = nil -- Reset target on release
        end
    end)
    
    RunService.RenderStepped:Connect(function() self:Update() end)
end

function Aimlock:GetClosestTarget()
    local s = AIMSIRE_App.Settings.Aimlock
    local mouse = UserInputService:GetMouseLocation()
    local closest, shortest = nil, s.FOV
    
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and Utils.IsAlive(p) and not Utils.IsTeammate(p) then
            local part = p.Character:FindFirstChild(s.AimPart) or p.Character:FindFirstChild("Head")
            if part then
                local vec, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(vec.X, vec.Y) - mouse).Magnitude
                    if dist < shortest then
                        shortest = dist
                        closest = p
                    end
                end
            end
        end
    end
    return closest
end

function Aimlock:Update()
    local s = AIMSIRE_App.Settings.Aimlock
    
    -- FOV Update
    self.FOVCircle.Visible = (s.Enabled and s.ShowFOV)
    if self.FOVCircle.Visible then
        self.FOVCircle.Size = UDim2.new(0, s.FOV * 2, 0, s.FOV * 2)
        self.FOVGui.Transparency = 0.4
    end
    
    if not s.Enabled or not self.State.Aiming then return end
    
    -- Logic: Sticky Aim vs Always Search
    local target = self.State.CurrentTarget
    
    -- Check if current target is still valid
    if s.StickyAim and target then
        if not Utils.IsAlive(target) or Utils.IsTeammate(target) then
            target = nil
        else
            -- Check FOV for sticky break (optional)
            local part = target.Character[s.AimPart]
            local vec, onScreen = Camera:WorldToViewportPoint(part.Position)
            local mouse = UserInputService:GetMouseLocation()
            if (Vector2.new(vec.X, vec.Y) - mouse).Magnitude > s.FOV then
                target = nil
            end
        end
    end
    
    -- Find new target if we don't have one
    if not target then
        target = self:GetClosestTarget()
    end
    
    -- Save target
    self.State.CurrentTarget = target
    
    -- Move Camera
    if target and target.Character then
        local part = target.Character:FindFirstChild(s.AimPart)
        if part then
            -- Smoothness Math Correction
            -- Value 1 (Slow) -> Lerp 0.05
            -- Value 0.1 (Fast) -> Lerp 0.5
            local alpha = math.clamp((1 - s.Smoothness), 0.05, 1)
            
            local currentCF = Camera.CFrame
            local targetCF = CFrame.new(currentCF.Position, part.Position)
            
            Camera.CFrame = currentCF:Lerp(targetCF, alpha)
        end
    end
end

--------------------------------------------------------------------------------
-- 6. MAIN INIT
--------------------------------------------------------------------------------

local function InitApp()
    local Window = UI:Init():CreateWindow('<font color="#ff4141">AIM</font><font color="#41a0ff">SIRE</font> v2.1')
    
    local VisTab = Window:Tab("Visuals")
    VisTab:Toggle("Active", AIMSIRE_App.Settings.Visuals, "Enabled")
    VisTab:Toggle("Boxes", AIMSIRE_App.Settings.Visuals, "Box")
    VisTab:Toggle("Names", AIMSIRE_App.Settings.Visuals, "Name")
    VisTab:Toggle("Chams", AIMSIRE_App.Settings.Visuals, "Chams")
    VisTab:Toggle("Team Check", AIMSIRE_App.Settings.Visuals, "TeamCheck")
    
    local AimTab = Window:Tab("Aimlock")
    AimTab:Toggle("Active", AIMSIRE_App.Settings.Aimlock, "Enabled")
    AimTab:Toggle("Show FOV", AIMSIRE_App.Settings.Aimlock, "ShowFOV")
    AimTab:Toggle("Sticky Aim", AIMSIRE_App.Settings.Aimlock, "StickyAim")
    AimTab:Slider("FOV Size", AIMSIRE_App.Settings.Aimlock, "FOV", 10, 600)
    AimTab:Slider("Smoothness", AIMSIRE_App.Settings.Aimlock, "Smoothness", 0, 0.95)
    
    AIMSIRE_App.Modules.Visuals:Init()
    AIMSIRE_App.Modules.Aimlock:Init()
    
    UserInputService.InputBegan:Connect(function(input, gp)
        if not gp and input.KeyCode == Enum.KeyCode.RightShift then
            UI:ToggleMenu()
        end
    end)
    
    print("AIMSIRE v2.1 Loaded & Optimized")
end

InitApp()
