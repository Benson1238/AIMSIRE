--[[
    AIMSIRE - Modular Refactor
    Language: Lua (Roblox)
    Author: Gemini
    
    Version: 2.0 (Modular & Themed)
    
    Features:
    - Internes Modul-System (Core, UI, Visuals, Aimbot)
    - Custom UI Framework mit Theme-Support
    - Settings Save/Load System (via JSON)
    - Vollständige ESP & Aimlock Funktionalität
    
    Tasten:
    - Menü: Rechte Shift-Taste
    - Aimlock: Rechte Maustaste (Standard)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService") -- Für JSON
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- 1. CORE & THEME SYSTEM
--------------------------------------------------------------------------------

local AIMSIRE_App = {
    Modules = {},
    Settings = {},
    Theme = {
        Background = Color3.fromRGB(25, 25, 25),
        Foreground = Color3.fromRGB(35, 35, 35),
        AccentRed = Color3.fromRGB(255, 65, 65),
        AccentBlue = Color3.fromRGB(65, 160, 255),
        Text = Color3.fromRGB(240, 240, 240),
        TextDim = Color3.fromRGB(180, 180, 180),
        Outline = Color3.fromRGB(60, 60, 60)
    },
    Events = {} -- Einfacher Event-Bus
}

-- Settings Struktur (Standardwerte)
AIMSIRE_App.DefaultSettings = {
    Visuals = {
        Enabled = false,
        Box = false,
        Name = false,
        Health = false,
        Chams = false,
        TeamCheck = false
    },
    Aimlock = {
        Enabled = false,
        Smoothness = 0.5,
        FOV = 150,
        AimPart = "Head",
        ShowFOV = false
    }
}

-- Settings laden (Deep Copy der Defaults)
AIMSIRE_App.Settings = HttpService:JSONDecode(HttpService:JSONEncode(AIMSIRE_App.DefaultSettings))

--------------------------------------------------------------------------------
-- 2. UTILS MODULE
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Utils = {}
local Utils = AIMSIRE_App.Modules.Utils

function Utils.Animate(obj, props, time)
    local info = TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(obj, info, props):Play()
end

function Utils.CreateSignal()
    local sig = {}
    local callbacks = {}
    
    function sig:Connect(func)
        table.insert(callbacks, func)
    end
    
    function sig:Fire(...)
        for _, func in ipairs(callbacks) do
            func(...)
        end
    end
    
    return sig
end

-- Settings Manager Funktionen
function Utils.ExportSettings()
    local json = HttpService:JSONEncode(AIMSIRE_App.Settings)
    print("--- AIMSIRE SETTINGS EXPORT ---")
    print(json)
    print("-------------------------------")
    -- Hinweis für den Nutzer (da setclipboard oft Exploit-only ist)
    return json
end

function Utils.ImportSettings(json)
    local success, result = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if success then
        AIMSIRE_App.Settings = result
        print("AIMSIRE: Settings geladen!")
        -- Hier müsste man eigentlich die UI refreshen (TODO für V3)
    else
        warn("AIMSIRE: Fehler beim Laden der Settings!")
    end
end

--------------------------------------------------------------------------------
-- 3. UI FRAMEWORK MODULE
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.UI = {}
local UI = AIMSIRE_App.Modules.UI

UI.Elements = {}
UI.CurrentTab = nil

function UI:Init()
    self.ScreenGui = Instance.new("ScreenGui")
    self.ScreenGui.Name = "AIMSIRE_UI_v2"
    self.ScreenGui.ResetOnSpawn = false
    
    -- Versuche CoreGui, fallback auf PlayerGui
    pcall(function() self.ScreenGui.Parent = game:GetService("CoreGui") end)
    if not self.ScreenGui.Parent then self.ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    
    return self
end

function UI:CreateWindow(titleHtml)
    local frame = Instance.new("Frame")
    frame.Name = "MainFrame"
    frame.Size = UDim2.new(0, 450, 0, 320)
    frame.Position = UDim2.new(0.5, -225, 0.5, -160)
    frame.BackgroundColor3 = AIMSIRE_App.Theme.Background
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = self.ScreenGui
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = AIMSIRE_App.Theme.Outline
    stroke.Thickness = 1
    stroke.Parent = frame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 40)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = titleHtml or "UI"
    title.RichText = true
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.XAlignment = Enum.TextXAlignment.Left
    title.Parent = frame
    
    -- Container für Tabs
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(0, 110, 1, -50)
    tabContainer.Position = UDim2.new(0, 10, 0, 45)
    tabContainer.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
    tabContainer.BorderSizePixel = 0
    tabContainer.Parent = frame
    
    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 4)
    tabCorner.Parent = tabContainer
    
    local tabList = Instance.new("UIListLayout")
    tabList.Padding = UDim.new(0, 5)
    tabList.Parent = tabContainer
    
    -- Padding für Tab Container
    local tabPad = Instance.new("UIPadding")
    tabPad.PaddingTop = UDim.new(0, 5)
    tabPad.PaddingBottom = UDim.new(0, 5)
    tabPad.PaddingLeft = UDim.new(0, 5)
    tabPad.PaddingRight = UDim.new(0, 5)
    tabPad.Parent = tabContainer
    
    -- Container für Pages
    local pageContainer = Instance.new("Frame")
    pageContainer.Size = UDim2.new(1, -140, 1, -50)
    pageContainer.Position = UDim2.new(0, 130, 0, 45)
    pageContainer.BackgroundTransparency = 1
    pageContainer.Parent = frame
    
    self.MainFrame = frame
    self.TabContainer = tabContainer
    self.PageContainer = pageContainer
    
    return self
end

function UI:Tab(name)
    -- Page Frame
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "_Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = AIMSIRE_App.Theme.AccentBlue
    page.Visible = false
    page.Parent = self.PageContainer
    
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    
    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 5)
    padding.Parent = page

    -- Tab Button
    local btn = Instance.new("TextButton")
    btn.Name = name .. "_Btn"
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = AIMSIRE_App.Theme.Background
    btn.Text = name
    btn.TextColor3 = AIMSIRE_App.Theme.TextDim
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.Parent = self.TabContainer
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 4)
    btnCorner.Parent = btn
    
    -- Tab Switching Logic
    btn.MouseButton1Click:Connect(function()
        -- Reset alle Tabs
        for _, p in pairs(self.PageContainer:GetChildren()) do p.Visible = false end
        for _, b in pairs(self.TabContainer:GetChildren()) do 
            if b:IsA("TextButton") then
                Utils.Animate(b, {TextColor3 = AIMSIRE_App.Theme.TextDim, BackgroundColor3 = AIMSIRE_App.Theme.Background}, 0.2)
            end
        end
        
        -- Aktivieren
        page.Visible = true
        Utils.Animate(btn, {TextColor3 = AIMSIRE_App.Theme.Text, BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue}, 0.2)
    end)
    
    -- Erster Tab aktiv?
    if not self.CurrentTab then
        self.CurrentTab = page
        page.Visible = true
        btn.TextColor3 = AIMSIRE_App.Theme.Text
        btn.BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue
    end

    -- Return Methods for the Page
    local PageMethods = {}
    
    function PageMethods:Toggle(text, configTable, configKey, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 32)
        frame.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
        frame.BorderSizePixel = 0
        frame.Parent = page
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = frame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = AIMSIRE_App.Theme.Text
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(0, 40, 0, 20)
        toggleBtn.Position = UDim2.new(1, -50, 0.5, -10)
        toggleBtn.Text = ""
        toggleBtn.BackgroundColor3 = configTable[configKey] and AIMSIRE_App.Theme.AccentBlue or AIMSIRE_App.Theme.Background
        toggleBtn.Parent = frame
        
        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(1, 0)
        tCorner.Parent = toggleBtn
        
        toggleBtn.MouseButton1Click:Connect(function()
            configTable[configKey] = not configTable[configKey]
            
            local targetColor = configTable[configKey] and AIMSIRE_App.Theme.AccentBlue or AIMSIRE_App.Theme.Background
            Utils.Animate(toggleBtn, {BackgroundColor3 = targetColor}, 0.2)
            
            if callback then callback(configTable[configKey]) end
        end)
    end
    
    function PageMethods:Slider(text, configTable, configKey, min, max, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 50)
        frame.BackgroundColor3 = AIMSIRE_App.Theme.Foreground
        frame.BorderSizePixel = 0
        frame.Parent = page
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = frame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 0, 20)
        label.Position = UDim2.new(0, 10, 0, 5)
        label.BackgroundTransparency = 1
        label.Text = text .. ": " .. tostring(configTable[configKey])
        label.TextColor3 = AIMSIRE_App.Theme.Text
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = frame
        
        local slideBg = Instance.new("TextButton")
        slideBg.Size = UDim2.new(1, -20, 0, 6)
        slideBg.Position = UDim2.new(0, 10, 0, 32)
        slideBg.BackgroundColor3 = AIMSIRE_App.Theme.Background
        slideBg.Text = ""
        slideBg.AutoButtonColor = false
        slideBg.Parent = frame
        
        local sCorner = Instance.new("UICorner")
        sCorner.CornerRadius = UDim.new(1, 0)
        sCorner.Parent = slideBg
        
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((configTable[configKey] - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = AIMSIRE_App.Theme.AccentBlue
        fill.BorderSizePixel = 0
        fill.Parent = slideBg
        
        local fCorner = Instance.new("UICorner")
        fCorner.CornerRadius = UDim.new(1, 0)
        fCorner.Parent = fill
        
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
                local value = math.floor((min + (max - min) * percent) * 10) / 10
                
                configTable[configKey] = value
                fill.Size = UDim2.new(percent, 0, 1, 0)
                label.Text = text .. ": " .. value
                
                if callback then callback(value) end
            end
        end)
    end
    
    function PageMethods:Button(text, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = AIMSIRE_App.Theme.AccentRed
        btn.Text = text
        btn.TextColor3 = Color3.new(1,1,1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.Parent = page
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            Utils.Animate(btn, {BackgroundTransparency = 0.3}, 0.1)
            task.wait(0.1)
            Utils.Animate(btn, {BackgroundTransparency = 0}, 0.1)
            if callback then callback() end
        end)
    end
    
    return PageMethods
end

function UI:ToggleMenu()
    self.MainFrame.Visible = not self.MainFrame.Visible
end

--------------------------------------------------------------------------------
-- 4. VISUALS MODULE (ESP)
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Visuals = {}
local Visuals = AIMSIRE_App.Modules.Visuals
Visuals.Cache = {}

function Visuals:Init()
    Players.PlayerAdded:Connect(function(p) self:AddPlayer(p) end)
    Players.PlayerRemoving:Connect(function(p) self:RemovePlayer(p) end)
    
    for _, p in pairs(Players:GetPlayers()) do self:AddPlayer(p) end
    
    RunService.RenderStepped:Connect(function() self:Update() end)
end

function Visuals:AddPlayer(player)
    if player == LocalPlayer then return end
    self.Cache[player] = {
        Highlight = nil,
        Billboard = nil,
        Components = {}
    }
    
    player.CharacterAdded:Connect(function() task.wait(0.5) end) -- Refresh delay
end

function Visuals:RemovePlayer(player)
    if self.Cache[player] then
        if self.Cache[player].Highlight then self.Cache[player].Highlight:Destroy() end
        if self.Cache[player].Billboard then self.Cache[player].Billboard:Destroy() end
        self.Cache[player] = nil
    end
end

function Visuals:CreateDrawings(player, cache)
    -- Hier wird die tatsächliche BillboardGui erstellt (wie im alten Script, aber sauberer)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    -- Highlight
    local hl = Instance.new("Highlight")
    hl.Name = "AIMSIRE_ESP"
    hl.FillColor = AIMSIRE_App.Theme.AccentRed
    hl.OutlineColor = Color3.new(1,1,1)
    hl.FillTransparency = 0.6
    hl.Parent = char
    cache.Highlight = hl
    
    -- Billboard
    local bg = Instance.new("BillboardGui")
    bg.Adornee = root
    bg.Size = UDim2.new(4, 0, 5.5, 0)
    bg.AlwaysOnTop = true
    bg.Parent = UI.ScreenGui
    
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 1, 0)
    box.BackgroundTransparency = 1
    box.Parent = bg
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = AIMSIRE_App.Theme.AccentRed
    stroke.Parent = box
    
    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, 0, 0, 15)
    name.Position = UDim2.new(0, 0, -0.15, 0)
    name.BackgroundTransparency = 1
    name.TextColor3 = Color3.new(1,1,1)
    name.TextStrokeTransparency = 0
    name.TextSize = 11
    name.Text = player.DisplayName
    name.Parent = bg
    
    local hpBar = Instance.new("Frame")
    hpBar.Size = UDim2.new(0, 3, 1, 0)
    hpBar.Position = UDim2.new(-0.1, 0, 0, 0)
    hpBar.BackgroundColor3 = Color3.new(0,1,0)
    hpBar.BorderSizePixel = 0
    hpBar.Parent = bg
    
    cache.Billboard = bg
    cache.Components = {Box = box, Name = name, HP = hpBar}
end

function Visuals:Update()
    local s = AIMSIRE_App.Settings.Visuals
    if not s.Enabled then
        for _, c in pairs(self.Cache) do
            if c.Highlight then c.Highlight.Enabled = false end
            if c.Billboard then c.Billboard.Enabled = false end
        end
        return
    end
    
    for player, cache in pairs(self.Cache) do
        local char = player.Character
        local hum = char and char:FindFirstChild("Humanoid")
        
        -- Validitätscheck & Teamcheck
        local isTeammate = s.TeamCheck and player.Team == LocalPlayer.Team
        
        if char and hum and hum.Health > 0 and not isTeammate then
            -- Initialisieren falls nötig
            if not cache.Highlight or cache.Highlight.Parent ~= char then
                if cache.Highlight then cache.Highlight:Destroy() end
                if cache.Billboard then cache.Billboard:Destroy() end
                self:CreateDrawings(player, cache)
            end
            
            if cache.Highlight then
                cache.Highlight.Enabled = s.Chams
                cache.Highlight.FillColor = AIMSIRE_App.Theme.AccentRed
            end
            
            if cache.Billboard then
                cache.Billboard.Enabled = (s.Box or s.Name or s.Health)
                
                if cache.Components.Box then cache.Components.Box.Visible = s.Box end
                if cache.Components.Name then cache.Components.Name.Visible = s.Name end
                
                if cache.Components.HP then 
                    cache.Components.HP.Visible = s.Health
                    local hpP = hum.Health / hum.MaxHealth
                    cache.Components.HP.Size = UDim2.new(0, 3, hpP, 0)
                    cache.Components.HP.Position = UDim2.new(-0.1, 0, 1-hpP, 0)
                    cache.Components.HP.BackgroundColor3 = Color3.fromHSV(hpP*0.3, 1, 1)
                end
            end
        else
            -- Verstecken wenn tot oder invalid
            if cache.Highlight then cache.Highlight.Enabled = false end
            if cache.Billboard then cache.Billboard.Enabled = false end
        end
    end
end

--------------------------------------------------------------------------------
-- 5. AIMLOCK MODULE
--------------------------------------------------------------------------------

AIMSIRE_App.Modules.Aimlock = {}
local Aimlock = AIMSIRE_App.Modules.Aimlock

Aimlock.State = {
    Aiming = false,
    Target = nil
}

function Aimlock:Init()
    -- FOV Circle
    self.FOVGui = Instance.new("ImageLabel")
    self.FOVGui.Image = "rbxassetid://3570695787"
    self.FOVGui.BackgroundTransparency = 1
    self.FOVGui.ImageColor3 = Color3.new(1,1,1)
    self.FOVGui.AnchorPoint = Vector2.new(0.5, 0.5)
    self.FOVGui.Position = UDim2.new(0.5, 0, 0.5, 0)
    self.FOVGui.Visible = false
    self.FOVGui.Parent = UI.ScreenGui
    
    -- Input Handling
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then -- Hardcoded default for simplicity, can be dynamic
            self.State.Aiming = true
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.State.Aiming = false
            self.State.Target = nil
        end
    end)
    
    RunService.RenderStepped:Connect(function() self:Update() end)
end

function Aimlock:GetTarget()
    local s = AIMSIRE_App.Settings.Aimlock
    local mouse = UserInputService:GetMouseLocation()
    local closest, shortest = nil, s.FOV
    
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                if AIMSIRE_App.Settings.Visuals.TeamCheck and p.Team == LocalPlayer.Team then continue end
                
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
    end
    return closest
end

function Aimlock:Update()
    local s = AIMSIRE_App.Settings.Aimlock
    
    -- FOV Circle Visual
    if s.Enabled and s.ShowFOV then
        self.FOVGui.Visible = true
        self.FOVGui.Size = UDim2.new(0, s.FOV * 2, 0, s.FOV * 2)
    else
        self.FOVGui.Visible = false
    end
    
    -- Aiming Logic
    if s.Enabled and self.State.Aiming then
        self.State.Target = self:GetTarget()
        
        if self.State.Target and self.State.Target.Character then
            local part = self.State.Target.Character:FindFirstChild(s.AimPart)
            if part then
                local current = Camera.CFrame
                local target = CFrame.new(Camera.CFrame.Position, part.Position)
                
                -- Smoothness Inversion Logic (wie im alten Script)
                -- Slider 0.1 (Snappy) -> Alpha ~0.9
                -- Slider 1.0 (Slow) -> Alpha ~0.01
                local alpha = math.clamp(1 - s.Smoothness, 0.01, 1)
                Camera.CFrame = current:Lerp(target, alpha)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- 6. MAIN INITIALIZATION
--------------------------------------------------------------------------------

local function InitApp()
    -- 1. UI Bauen
    local Window = UI:Init():CreateWindow('<font color="rgb(255,65,65)">AIM</font><font color="rgb(65,160,255)">SIRE</font> <font color="rgb(150,150,150)" size="14">v2</font>')
    
    -- Visuals Tab
    local VisTab = Window:Tab("Visuals")
    local sVis = AIMSIRE_App.Settings.Visuals
    
    VisTab:Toggle("Enable Master Visuals", sVis, "Enabled")
    VisTab:Toggle("Draw Box", sVis, "Box")
    VisTab:Toggle("Draw Name", sVis, "Name")
    VisTab:Toggle("Draw Health", sVis, "Health")
    VisTab:Toggle("Chams (Highlight)", sVis, "Chams")
    VisTab:Toggle("Team Check", sVis, "TeamCheck")
    
    -- Aimlock Tab
    local AimTab = Window:Tab("Aimlock")
    local sAim = AIMSIRE_App.Settings.Aimlock
    
    AimTab:Toggle("Enable Aimlock", sAim, "Enabled")
    AimTab:Toggle("Draw FOV Circle", sAim, "ShowFOV")
    AimTab:Slider("FOV Radius", sAim, "FOV", 10, 800)
    AimTab:Slider("Smoothness", sAim, "Smoothness", 0.01, 1.0)
    
    -- Settings Tab (Neu!)
    local SetTab = Window:Tab("Settings")
    
    SetTab:Button("Export Settings (Console)", function()
        Utils.ExportSettings()
    end)
    
    SetTab:Button("Reload Default Settings", function()
        AIMSIRE_App.Settings = HttpService:JSONDecode(HttpService:JSONEncode(AIMSIRE_App.DefaultSettings))
        -- In einer echten App müssten hier die UI-Elemente neu synchronisiert werden.
        print("Settings reset!")
    end)

    -- 2. Module Starten
    Visuals:Init()
    Aimlock:Init()
    
    -- 3. Global Inputs
    UserInputService.InputBegan:Connect(function(input, gp)
        if not gp and input.KeyCode == Enum.KeyCode.RightShift then
            UI:ToggleMenu()
        end
    end)
    
    print("AIMSIRE v2 initialized successfully.")
end

InitApp()
