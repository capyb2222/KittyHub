-- MM2 Aimbot & ESP v3
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Settings
getgenv().CatSettings = {
    ESP = {
        Enabled = true, Boxes = true, Names = true, Roles = true,
        Chams = true, Tracers = true, Distance = true, MaxDistance = 1000
    },
    Aimbot = {
        AutoShoot = true, AimbotKey = "C", Prediction = true,
        LeadTime = 0.15, AimPart = "Head", OffScreen = true,
        FOVCircle = true, FOVRadius = 200, FOVColor = "#C864FF"
    },
    MM2 = {
        GunESP = true, Noclip = false, NoclipKey = "N", AutoCollect = true
    },
    Movement = {
        SpeedEnabled = false, SpeedValue = 16,
        JumpEnabled = false, JumpValue = 50
    },
    Visuals = {
        RainbowMode = false, RainbowSpeed = 1
    },
    Crosshair = {
        Enabled = true, Style = "Cross", Size = 10, Thickness = 2
    },
    Misc = {
        SpectatorList = true
    }
}

local S = getgenv().CatSettings

-- Role Detection
local RoleCache = {}
local RemoteCache = {}

local RoleColors = {
    Murderer = Color3.fromRGB(255, 50, 50),
    Sheriff = Color3.fromRGB(50, 120, 255),
    Innocent = Color3.fromRGB(120, 255, 120)
}

local function GetPlayerRole(player)
    local cached = RoleCache[player]
    if cached then return cached end
    local char = player.Character
    if char then
        if char:FindFirstChild("Knife") then RoleCache[player] = "Murderer"; return "Murderer" end
        if char:FindFirstChild("Gun") then RoleCache[player] = "Sheriff"; return "Sheriff" end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then RoleCache[player] = "Murderer"; return "Murderer" end
        if bp:FindFirstChild("Gun") then RoleCache[player] = "Sheriff"; return "Sheriff" end
    end
    RoleCache[player] = "Innocent"
    return "Innocent"
end

local function OnCharacterAdded(player)
    RoleCache[player] = nil
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function() OnCharacterAdded(player) end)
end)

-- AetherHub-style GUI
local UI = {
    Bg = Color3.fromRGB(25, 25, 35),
    Surface = Color3.fromRGB(35, 35, 45),
    Accent = Color3.fromRGB(200, 100, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(150, 150, 150),
    Border = Color3.fromRGB(70, 65, 85)
}

local AccentElements = {}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KittyHub"
ScreenGui.Parent = game:GetService("CoreGui")
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Main Window
local Window = Instance.new("Frame")
Window.Size = UDim2.new(0, 620, 0, 420)
Window.Position = UDim2.new(0.5, -310, 0.5, -210)
Window.BackgroundColor3 = UI.Bg
Window.BackgroundTransparency = 0.2
Window.BorderSizePixel = 0
Window.Parent = ScreenGui
Window.Visible = false
Instance.new("UICorner", Window).CornerRadius = UDim.new(0, 12)

-- Shadow
local Shadow = Instance.new("ImageLabel")
Shadow.Size = UDim2.new(1, 60, 1, 60)
Shadow.Position = UDim2.new(0, -30, 0, -30)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://1316045217"
Shadow.ImageScale = 1.2
Shadow.ImageColor3 = Color3.new(0, 0, 0)
Shadow.ImageTransparency = 0.6
Shadow.Parent = ScreenGui
Shadow.ZIndex = -1
Window:GetPropertyChangedSignal("Position"):Connect(function()
    Shadow.Position = UDim2.new(0, Window.Position.X.Offset - 30, 0, Window.Position.Y.Offset - 30)
end)
Window:GetPropertyChangedSignal("Size"):Connect(function()
    Shadow.Size = UDim2.new(0, Window.AbsoluteSize.X + 60, 0, Window.AbsoluteSize.Y + 60)
end)
task.spawn(function()
    repeat task.wait() until Window.AbsoluteSize.X > 0
    Shadow.Size = UDim2.new(0, Window.AbsoluteSize.X + 60, 0, Window.AbsoluteSize.Y + 60)
end)

-- Dragging
local function MakeDraggable(frame)
    local dragging, dragInput, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = Window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            TweenService:Create(Window, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = newPos}):Play()
        end
    end)
end

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundTransparency = 1
TitleBar.Parent = Window
MakeDraggable(TitleBar)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 150, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Kitty Hub"
Title.TextColor3 = UI.Accent
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar
table.insert(AccentElements, {obj = Title, kind = "accent"})

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(0, 150, 1, 0)
Subtitle.Position = UDim2.new(0, 140, 0, 0)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "v3"
Subtitle.TextColor3 = UI.TextDim
Subtitle.TextSize = 12
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = TitleBar
table.insert(AccentElements, {obj = Subtitle, kind = "subtitle"})

-- Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -38, 0, 5)
CloseBtn.BackgroundColor3 = UI.Surface
CloseBtn.BackgroundTransparency = 0.5
CloseBtn.Text = "X"
CloseBtn.TextColor3 = UI.Text
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Window
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
CloseBtn.MouseButton1Click:Connect(function()
    Window.Visible = false
    Shadow.Visible = false
end)

-- Toggle Button (floating)
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0.02, 0, 0.5, -25)
ToggleBtn.BackgroundColor3 = UI.Accent
ToggleBtn.BackgroundTransparency = 0.15
ToggleBtn.Text = "Kitty"
ToggleBtn.TextSize = 14
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextColor3 = UI.Text
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Parent = ScreenGui
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)
table.insert(AccentElements, {obj = ToggleBtn, kind = "accent"})
ToggleBtn.MouseButton1Click:Connect(function()
    Window.Visible = not Window.Visible
    if Window.Visible then
        Shadow.Visible = true
    end
end)
Window:GetPropertyChangedSignal("Visible"):Connect(function()
    Shadow.Visible = Window.Visible
end)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 170, 1, -40)
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = UI.Surface
Sidebar.BackgroundTransparency = 0.3
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Window
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 8)

-- Sidebar accent line
local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(0, 3, 1, -20)
AccentLine.Position = UDim2.new(0, 0, 0, 10)
AccentLine.BackgroundColor3 = UI.Accent
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Sidebar
Instance.new("UICorner", AccentLine).CornerRadius = UDim.new(0, 2)
table.insert(AccentElements, {obj = AccentLine, kind = "accent"})

-- Tabs container
local TabsContainer = Instance.new("ScrollingFrame")
TabsContainer.Size = UDim2.new(1, -10, 1, -10)
TabsContainer.Position = UDim2.new(0, 10, 0, 10)
TabsContainer.BackgroundTransparency = 1
TabsContainer.BorderSizePixel = 0
TabsContainer.ScrollBarThickness = 0
TabsContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
TabsContainer.Parent = Sidebar

local TabsListLayout = Instance.new("UIListLayout")
TabsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabsListLayout.Padding = UDim.new(0, 4)
TabsListLayout.Parent = TabsContainer

-- Content area
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -180, 1, -50)
Content.Position = UDim2.new(0, 175, 0, 45)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.Parent = Window

local Pages = Instance.new("Frame")
Pages.Size = UDim2.new(1, 0, 1, 0)
Pages.BackgroundTransparency = 1
Pages.Parent = Content

-- Control factories
local function CreateToggle(page, name, settingRef, settingName, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 38)
    frame.BackgroundColor3 = Color3.fromRGB(32, 30, 38)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = page
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Border
    stroke.Transparency = 0.5
    stroke.Thickness = 1
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, -10, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = UI.Text
    label.TextSize = 13
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 40, 0, 20)
    knob.Position = UDim2.new(1, -50, 0.5, -10)
    knob.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    knob.BorderSizePixel = 0
    knob.Parent = frame
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    table.insert(AccentElements, {obj = knob, ref = settingRef, name = settingName, kind = "toggle"})

    local knobInner = Instance.new("Frame")
    knobInner.Size = UDim2.new(0, 16, 0, 16)
    knobInner.Position = UDim2.new(0, 2, 0.5, -8)
    knobInner.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
    knobInner.BorderSizePixel = 0
    knobInner.Parent = knob
    Instance.new("UICorner", knobInner).CornerRadius = UDim.new(1, 0)

    local function updateVisuals()
        if settingRef[settingName] then
            knob.BackgroundColor3 = UI.Accent
            knobInner.BackgroundColor3 = Color3.new(1, 1, 1)
            knobInner:TweenPosition(UDim2.new(1, -18, 0.5, -8), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        else
            knob.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            knobInner.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
            knobInner:TweenPosition(UDim2.new(0, 2, 0.5, -8), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
        end
    end
    updateVisuals()

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            settingRef[settingName] = not settingRef[settingName]
            updateVisuals()
            stroke.Color = UI.Accent
            task.delay(0.1, function() stroke.Color = UI.Border end)
            if callback then callback(settingRef[settingName]) end
        end
    end)

    return frame
end

local function CreateSlider(page, name, settingRef, settingName, minVal, maxVal, callback)
    minVal = minVal or 0
    maxVal = maxVal or 100

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 45)
    frame.BackgroundColor3 = Color3.fromRGB(32, 30, 38)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = page
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Border
    stroke.Transparency = 0.5
    stroke.Thickness = 1
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, -10, 0.5, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = UI.Text
    label.TextSize = 13
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.3, 0, 0.5, 0)
    valueLabel.Position = UDim2.new(0.7, 0, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(settingRef[settingName])
    valueLabel.TextColor3 = UI.Accent
    valueLabel.TextSize = 13
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = frame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 4)
    track.Position = UDim2.new(0, 12, 1, -12)
    track.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    track.BorderSizePixel = 0
    track.Parent = frame
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 2)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = UI.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)
    table.insert(AccentElements, {obj = fill, kind = "fill"})
    table.insert(AccentElements, {obj = valueLabel, kind = "valuelabel"})

    local function updateSlider()
        local percent = (settingRef[settingName] - minVal) / (maxVal - minVal)
        fill.Size = UDim2.new(math.clamp(percent, 0, 1), 0, 1, 0)
        valueLabel.Text = tostring(math.floor(settingRef[settingName]))
    end
    updateSlider()

    local dragging = false
    local dragConnection = nil

    local function moveSlider(inputPos)
        local pos = inputPos.X - track.AbsolutePosition.X
        local percent = math.clamp(pos / track.AbsoluteSize.X, 0, 1)
        local rawValue = minVal + (maxVal - minVal) * percent
        local snapped = math.floor(rawValue + 0.5)
        settingRef[settingName] = math.clamp(snapped, minVal, maxVal)
        updateSlider()
        if callback then callback(settingRef[settingName]) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            moveSlider(input.Position)
            stroke.Color = UI.Accent
            task.delay(0.1, function() stroke.Color = UI.Border end)
            dragConnection = UserInputService.InputChanged:Connect(function(ci)
                if ci.UserInputType == Enum.UserInputType.MouseMovement and dragging then
                    moveSlider(UserInputService:GetMouseLocation())
                end
            end)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            if dragConnection then
                dragConnection:Disconnect()
                dragConnection = nil
            end
        end
    end)

    return frame
end

local function CreateCycle(page, name, settingRef, settingName, options)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 38)
    frame.BackgroundColor3 = Color3.fromRGB(32, 30, 38)
    frame.BackgroundTransparency = 0.5
    frame.BorderSizePixel = 0
    frame.Parent = page
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Border
    stroke.Transparency = 0.5
    stroke.Thickness = 1
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, -10, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = UI.Text
    label.TextSize = 13
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local currentIdx = 1
    for i, opt in ipairs(options) do
        if opt == settingRef[settingName] then currentIdx = i; break end
    end

    local valueBtn = Instance.new("TextButton")
    valueBtn.Size = UDim2.new(0, 70, 0, 26)
    valueBtn.Position = UDim2.new(1, -80, 0.5, -13)
    valueBtn.BackgroundColor3 = UI.Accent
    valueBtn.BackgroundTransparency = 0.2
    valueBtn.Text = settingRef[settingName]
    valueBtn.TextColor3 = UI.Text
    valueBtn.TextSize = 12
    valueBtn.Font = Enum.Font.GothamBold
    valueBtn.BorderSizePixel = 0
    valueBtn.Parent = frame
    Instance.new("UICorner", valueBtn).CornerRadius = UDim.new(0, 6)
    table.insert(AccentElements, {obj = valueBtn, kind = "cyclebtn"})

    valueBtn.MouseButton1Click:Connect(function()
        currentIdx = (currentIdx % #options) + 1
        local newVal = options[currentIdx]
        settingRef[settingName] = newVal
        valueBtn.Text = newVal
        stroke.Color = UI.Accent
        task.delay(0.1, function() stroke.Color = UI.Border end)
    end)

    return frame
end

-- Build Tab Pages
local TabButtons = {}
local currentTab = nil
local pages = {}

local function SwitchTab(tabName)
    if currentTab then
        if pages[currentTab] then
            pages[currentTab].Visible = false
        end
        if TabButtons[currentTab] then
            local btn = TabButtons[currentTab]
            btn.BackgroundTransparency = 1
            btn.UIStroke.Transparency = 1
            btn.TextColor3 = UI.TextDim
        end
    end
    currentTab = tabName
    if pages[tabName] then
        pages[tabName].Visible = true
    end
    if TabButtons[tabName] then
        local btn = TabButtons[tabName]
        btn.BackgroundTransparency = 0.85
        btn.UIStroke.Transparency = 0.5
        btn.TextColor3 = UI.Text
    end
end

local function CreateTab(tabName, icon)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = UI.Surface
    btn.BackgroundTransparency = 1
    btn.Text = "  " .. tabName
    btn.TextColor3 = UI.TextDim
    btn.TextSize = 13
    btn.Font = Enum.Font.Gotham
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.Parent = TabsContainer
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Border
    stroke.Transparency = 1
    stroke.Thickness = 1
    stroke.Parent = btn

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = UI.Accent
    page.ScrollBarImageTransparency = 0.5
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Parent = Pages
    page.Visible = false

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = page

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = page

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end)

    TabButtons[tabName] = btn
    pages[tabName] = page
    table.insert(AccentElements, {obj = page, kind = "scrollbar"})

    btn.MouseButton1Click:Connect(function()
        SwitchTab(tabName)
    end)

    return page
end

-- === ESP Tab ===
do
    local page = CreateTab("ESP")
    CreateToggle(page, "Enabled", S.ESP, "Enabled")
    CreateToggle(page, "Boxes", S.ESP, "Boxes")
    CreateToggle(page, "Names", S.ESP, "Names")
    CreateToggle(page, "Roles", S.ESP, "Roles")
    CreateToggle(page, "Chams", S.ESP, "Chams")
    CreateToggle(page, "Tracers", S.ESP, "Tracers")
    CreateToggle(page, "Distance", S.ESP, "Distance")
end

-- === Aimbot Tab ===
do
    local page = CreateTab("Aimbot")
    CreateToggle(page, "Auto Shoot", S.Aimbot, "AutoShoot")
    CreateToggle(page, "Prediction", S.Aimbot, "Prediction")
    CreateToggle(page, "FOV Circle", S.Aimbot, "FOVCircle")
    CreateToggle(page, "Off-Screen Aim", S.Aimbot, "OffScreen")
    CreateSlider(page, "FOV Radius", S.Aimbot, "FOVRadius", 50, 400)
end

-- === MM2 Tab ===
do
    local page = CreateTab("MM2")
    CreateToggle(page, "Gun ESP", S.MM2, "GunESP")
    CreateToggle(page, "Noclip", S.MM2, "Noclip", function(v)
        if v then EnableNoclip() else DisableNoclip() end
    end)
    CreateToggle(page, "Auto Collect", S.MM2, "AutoCollect")
end

-- === Movement Tab ===
do
    local page = CreateTab("Movement")
    CreateToggle(page, "Speed Hack", S.Movement, "SpeedEnabled", function(v)
        ApplyMovementSettings()
    end)
    CreateSlider(page, "Speed Value", S.Movement, "SpeedValue", 16, 100, function(v)
        ApplyMovementSettings()
    end)
    CreateToggle(page, "Jump Hack", S.Movement, "JumpEnabled", function(v)
        ApplyMovementSettings()
    end)
    CreateSlider(page, "Jump Value", S.Movement, "JumpValue", 50, 200, function(v)
        ApplyMovementSettings()
    end)
end

-- === Visuals Tab ===
do
    local page = CreateTab("Visuals")
    CreateToggle(page, "Rainbow Mode", S.Visuals, "RainbowMode")
    CreateSlider(page, "Rainbow Speed", S.Visuals, "RainbowSpeed", 0.5, 5)
    CreateToggle(page, "Crosshair", S.Crosshair, "Enabled")
    CreateCycle(page, "Crosshair Style", S.Crosshair, "Style", {"Dot", "Cross", "Circle"})
    CreateSlider(page, "Crosshair Size", S.Crosshair, "Size", 5, 30)
    CreateSlider(page, "Crosshair Thickness", S.Crosshair, "Thickness", 1, 5)
end

-- === Misc Tab ===
do
    local page = CreateTab("Misc")
    CreateToggle(page, "Spectator List", S.Misc, "SpectatorList")
end

-- Default tab
SwitchTab("ESP")

-- ESP System
local ESPObjects = {}
local ChamsObjects = {}

local function CreateESP(player)
    if player == LocalPlayer then return end
    local objs = {
        Box = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        Role = Drawing.new("Text"),
        Tracer = Drawing.new("Line")
    }
    objs.Box.Visible = false
    objs.Box.Thickness = 2
    objs.Box.Filled = false
    objs.Name.Visible = false
    objs.Name.Size = 14
    objs.Name.Center = true
    objs.Name.Font = 2
    objs.Role.Visible = false
    objs.Role.Size = 13
    objs.Role.Center = true
    objs.Role.Font = 2
    objs.Tracer.Visible = false
    objs.Tracer.Thickness = 1.5
    objs.Tracer.Transparency = 0.6
    ESPObjects[player] = objs
end

-- Chams
local function CreateChams(player)
    if player == LocalPlayer or ChamsObjects[player] then return end
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = ScreenGui
    ChamsObjects[player] = hl
    local function update()
        if player.Character then
            hl.Adornee = player.Character
            hl.FillColor = RoleColors[GetPlayerRole(player)]
            hl.OutlineColor = Color3.new(1, 1, 1)
        end
    end
    update()
    player.CharacterAdded:Connect(update)
end

-- Chams via PlayerAdded (fix: no per-frame polling)
Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function()
            if S.ESP.Chams then
                CreateChams(player)
            end
        end)
    end
end)

-- Gun ESP (throttled)
local GunESPObjects = {}
local GunESPThrottle = 0

local function UpdateGunESP()
    local now = tick()
    if now - GunESPThrottle < 1 then return end
    GunESPThrottle = now
    for _, obj in pairs(GunESPObjects) do
        if obj.Remove then obj:Remove() end
    end
    GunESPObjects = {}
    if not S.MM2.GunESP then return end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "GunDrop" and obj:FindFirstChild("Handle") then
            local text = Drawing.new("Text")
            text.Text = "GUN"
            text.Size = 16
            text.Color = Color3.fromRGB(255, 215, 0)
            text.Center = true
            text.Font = 2
            GunESPObjects[obj] = text
        end
    end
end

-- Aimbot
local lastShot = 0
local aimbotActive = false
local FOVCircle

local function InitFOVCircle()
    if FOVCircle then return end
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = false
    FOVCircle.Thickness = 1.5
    FOVCircle.Filled = false
    FOVCircle.NumSides = 64
    FOVCircle.Transparency = 0.7
end

local function UpdateFOVCircle()
    if not S.Aimbot.FOVCircle then
        if FOVCircle then FOVCircle.Visible = false end
        return
    end
    InitFOVCircle()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    FOVCircle.Radius = S.Aimbot.FOVRadius
    local color = S.Visuals.RainbowMode and UI.Accent or Color3.fromRGB(200, 100, 255)
    FOVCircle.Color = aimbotActive and Color3.fromRGB(100, 200, 255) or color
    FOVCircle.Visible = true
end

local function GetMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and GetPlayerRole(player) == "Murderer" then
            return player
        end
    end
    return nil
end

local function FindGunRemote(gun)
    local cached = RemoteCache[gun]
    if cached then return cached end
    local remote = gun:FindFirstChild("Shoot") or gun:FindFirstChild("Fire")
    if not remote then
        remote = gun:FindFirstChildOfClass("RemoteEvent")
    end
    if not remote then
        for _, child in ipairs(gun:GetDescendants()) do
            if child:IsA("RemoteEvent") then
                remote = child
                break
            end
        end
    end
    RemoteCache[gun] = remote
    return remote
end

local function InvalidateRemoteCache(gun)
    RemoteCache[gun] = nil
end

local function GetAimPart(character)
    if not character then return nil end
    local partName = S.Aimbot.AimPart
    local part = character:FindFirstChild(partName)
    if part then return part end
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
end

local function PredictPosition(part)
    if not S.Aimbot.Prediction then return part.Position end
    local hrp = part.Parent and part.Parent:FindFirstChild("HumanoidRootPart")
    if hrp and typeof(hrp.Velocity) == "Vector3" and hrp.Velocity.Magnitude > 0.5 then
        return part.Position + (hrp.Velocity * S.Aimbot.LeadTime)
    end
    return part.Position
end

local function FindGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    local gun = char:FindFirstChild("Gun")
    if gun then return gun end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        gun = bp:FindFirstChild("Gun")
        return gun
    end
    return nil
end

local function EquipGun()
    local gun = FindGun()
    if not gun then return nil end
    local char = LocalPlayer.Character
    if not char then return nil end
    local inHand = char:FindFirstChild("Gun")
    if inHand then return inHand end
    local hum = char:FindFirstChild("Humanoid")
    if hum then
        pcall(function() hum:EquipTool(gun) end)
        task.wait()
        return char:FindFirstChild("Gun") or gun
    end
    return gun
end

local function ShootMurderer(murderer)
    if not murderer or not murderer.Character then return false end
    local part = GetAimPart(murderer.Character)
    if not part then return false end
    local gun = EquipGun()
    if not gun then return false end
    local targetPos = PredictPosition(part)
    local remote = FindGunRemote(gun)
    if not remote then
        local char = LocalPlayer.Character
        if char then
            gun = char:FindFirstChild("Gun")
            if gun then
                InvalidateRemoteCache(gun)
                remote = FindGunRemote(gun)
            end
        end
    end
    if remote then
        pcall(function() remote:FireServer(targetPos, part) end)
        return true
    end
    local success = pcall(function()
        if gun.Shoot then
            gun.Shoot:FireServer(targetPos, part)
        elseif gun.Fire then
            gun.Fire:FireServer(targetPos, part)
        end
    end)
    return success
end

local function ExecuteAimbot()
    local murderer = GetMurderer()
    if not murderer then return end
    if not S.Aimbot.OffScreen then
        local part = GetAimPart(murderer.Character)
        if part then
            local onScreen = Camera:WorldToViewportPoint(part.Position)
            if not onScreen[3] then return end
        end
    end
    aimbotActive = true
    ShootMurderer(murderer)
end

local function StopAimbot()
    aimbotActive = false
end

-- Auto-Collect (Teleport)
local AutoCollectThrottle = 0

local function DoAutoCollect()
    local now = tick()
    if now - AutoCollectThrottle < 0.3 then return end
    AutoCollectThrottle = now

    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local nearestGun = nil
    local nearestDist = math.huge

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "GunDrop" and obj:FindFirstChild("Handle") then
            local dist = (obj.Handle.Position - hrp.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearestGun = obj
            end
        end
    end

    -- Skip if already have gun in hand
    local charGun = char:FindFirstChild("Gun")
    if charGun and nearestDist <= 3 then return end

    if nearestGun then
        local targetPos = nearestGun.Handle.Position + Vector3.new(0, 3, 0)
        if nearestDist > 5 then
            hrp.CFrame = CFrame.new(targetPos)
        end
        if nearestDist <= 20 then
            local gun = FindGun()
            if not gun then
                local bp = LocalPlayer:FindFirstChild("Backpack")
                if bp then
                    gun = bp:FindFirstChild("Gun")
                end
            end
            if gun then
                local hum = char:FindFirstChild("Humanoid")
                if hum then
                    pcall(function() hum:EquipTool(gun) end)
                end
            end
        end
    end
end

-- Crosshair
local CrosshairDrawings = {}

local function RebuildCrosshair()
    for _, d in pairs(CrosshairDrawings) do
        if d.Remove then d:Remove() end
    end
    CrosshairDrawings = {}

    if not S.Crosshair.Enabled then return end

    local size = S.Crosshair.Size
    local thick = S.Crosshair.Thickness
    local color = S.Visuals.RainbowMode and UI.Accent or Color3.new(1, 1, 1)

    if S.Crosshair.Style == "Cross" then
        local h = Drawing.new("Line")
        h.From = Vector2.new(0, 0)
        h.To = Vector2.new(0, 0)
        h.Color = color
        h.Thickness = thick
        h.Transparency = 0.8
        h.Visible = true
        table.insert(CrosshairDrawings, h)

        local v = Drawing.new("Line")
        v.From = Vector2.new(0, 0)
        v.To = Vector2.new(0, 0)
        v.Color = color
        v.Thickness = thick
        v.Transparency = 0.8
        v.Visible = true
        table.insert(CrosshairDrawings, v)
    elseif S.Crosshair.Style == "Dot" then
        local d = Drawing.new("Circle")
        d.Radius = math.max(thick, 2)
        d.Color = color
        d.Thickness = thick
        d.Filled = true
        d.Transparency = 0.7
        d.Visible = true
        table.insert(CrosshairDrawings, d)
    elseif S.Crosshair.Style == "Circle" then
        local c = Drawing.new("Circle")
        c.Radius = size
        c.Color = color
        c.Thickness = thick
        c.Filled = false
        c.Transparency = 0.6
        c.Visible = true
        table.insert(CrosshairDrawings, c)
    end
end

local function UpdateCrosshair()
    local pos = UserInputService:GetMouseLocation()
    local size = S.Crosshair.Size
    local thick = S.Crosshair.Thickness
    local color = S.Visuals.RainbowMode and UI.Accent or Color3.new(1, 1, 1)

    if S.Crosshair.Style == "Cross" then
        if #CrosshairDrawings >= 2 then
            -- Horizontal line
            CrosshairDrawings[1].From = Vector2.new(pos.X - size, pos.Y)
            CrosshairDrawings[1].To = Vector2.new(pos.X + size, pos.Y)
            CrosshairDrawings[1].Color = color
            CrosshairDrawings[1].Thickness = thick
            -- Vertical line
            CrosshairDrawings[2].From = Vector2.new(pos.X, pos.Y - size)
            CrosshairDrawings[2].To = Vector2.new(pos.X, pos.Y + size)
            CrosshairDrawings[2].Color = color
            CrosshairDrawings[2].Thickness = thick
        end
    elseif S.Crosshair.Style == "Dot" then
        if #CrosshairDrawings >= 1 then
            CrosshairDrawings[1].Position = pos
            CrosshairDrawings[1].Radius = math.max(thick, 2)
            CrosshairDrawings[1].Color = color
        end
    elseif S.Crosshair.Style == "Circle" then
        if #CrosshairDrawings >= 1 then
            CrosshairDrawings[1].Position = pos
            CrosshairDrawings[1].Radius = size
            CrosshairDrawings[1].Color = color
            CrosshairDrawings[1].Thickness = thick
        end
    end
end

-- Spectator List
local SpectatorFrame = nil
local SpectatorLabels = {}

local function SetupSpectatorList()
    if SpectatorFrame then
        SpectatorFrame:Destroy()
        SpectatorFrame = nil
    end

    SpectatorFrame = Instance.new("Frame")
    SpectatorFrame.Size = UDim2.new(0, 180, 0, 24)
    SpectatorFrame.Position = UDim2.new(1, -190, 0.5, 0)
    SpectatorFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    SpectatorFrame.BackgroundTransparency = 0.3
    SpectatorFrame.BorderSizePixel = 0
    SpectatorFrame.Parent = ScreenGui
    Instance.new("UICorner", SpectatorFrame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Accent
    stroke.Transparency = 0.6
    stroke.Thickness = 1
    stroke.Parent = SpectatorFrame
    table.insert(AccentElements, {obj = stroke, kind = "uistroke"})

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -10, 0, 20)
    title.Position = UDim2.new(0, 5, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "Spectators"
    title.TextColor3 = UI.Accent
    title.TextSize = 11
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = SpectatorFrame
    table.insert(AccentElements, {obj = title, kind = "accent"})

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = SpectatorFrame
end

local function UpdateSpectatorList()
    if not S.Misc.SpectatorList then
        if SpectatorFrame then
            SpectatorFrame.Visible = false
        end
        return
    end

    if not SpectatorFrame then
        SetupSpectatorList()
    end
    SpectatorFrame.Visible = true

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")

    local specs = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.CameraSubject == hum then
            table.insert(specs, player.Name)
        end
    end

    -- Remove old labels beyond count
    local labelKeys = {}
    for k in pairs(SpectatorLabels) do
        table.insert(labelKeys, k)
    end
    for _, key in ipairs(labelKeys) do
        if not table.find(specs, key) then
            if SpectatorLabels[key] then
                SpectatorLabels[key]:Destroy()
            end
            SpectatorLabels[key] = nil
        end
    end

    for i, name in ipairs(specs) do
        if not SpectatorLabels[name] then
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -10, 0, 16)
            lbl.Position = UDim2.new(0, 5, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = name
            lbl.TextColor3 = UI.Text
            lbl.TextSize = 11
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = SpectatorFrame
            SpectatorLabels[name] = lbl
        end
    end

    -- Resize frame based on content
    local count = #specs
    local height = math.max(24, 24 + count * 18)
    SpectatorFrame.Size = UDim2.new(0, 180, 0, height)
end

local RainbowHue = 0

-- Movement
local function ApplyMovementSettings()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    if S.Movement.SpeedEnabled then
        hum.WalkSpeed = S.Movement.SpeedValue
    else
        hum.WalkSpeed = 16
    end
    if S.Movement.JumpEnabled then
        hum.JumpPower = S.Movement.JumpValue
    else
        hum.JumpPower = 50
    end
end

local function OnLocalCharacterAdded(char)
    task.wait(0.5)
    ApplyMovementSettings()
end

LocalPlayer.CharacterAdded:Connect(OnLocalCharacterAdded)
if LocalPlayer.Character then
    ApplyMovementSettings()
end

-- Noclip
local NoclipConnection = nil

local function EnableNoclip()
    if NoclipConnection then NoclipConnection:Disconnect() end
    NoclipConnection = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end)
end

local function DisableNoclip()
    if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
end

local function ToggleNoclip()
    if S.MM2.Noclip then
        S.MM2.Noclip = false
        DisableNoclip()
    else
        S.MM2.Noclip = true
        EnableNoclip()
    end
end

-- Keybinds
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.X then
        Window.Visible = not Window.Visible
        Shadow.Visible = Window.Visible
    elseif input.KeyCode == Enum.KeyCode.N then
        ToggleNoclip()
    end
    local key = S.Aimbot.AimbotKey
    local keyCode = Enum.KeyCode[key]
    if keyCode and input.KeyCode == keyCode then
        ExecuteAimbot()
    end
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    -- Rainbow Mode (apply before all color-dependent rendering)
    if S.Visuals.RainbowMode then
        RainbowHue = (tick() * S.Visuals.RainbowSpeed * 0.15) % 1
        UI.Accent = Color3.fromHSV(RainbowHue, 0.9, 1)
        Subtitle.TextColor3 = UI.Accent
    else
        UI.Accent = Color3.fromRGB(200, 100, 255)
        Subtitle.TextColor3 = UI.TextDim
    end

    -- Update all accent-colored elements for rainbow mode
    for _, el in ipairs(AccentElements) do
        if el.kind == "toggle" then
            if el.ref[el.name] then
                el.obj.BackgroundColor3 = UI.Accent
            end
        elseif el.kind == "fill" or el.kind == "cyclebtn" or el.kind == "accent" then
            el.obj.BackgroundColor3 = UI.Accent
        elseif el.kind == "valuelabel" then
            el.obj.TextColor3 = UI.Accent
        elseif el.kind == "scrollbar" then
            el.obj.ScrollBarImageColor3 = UI.Accent
        elseif el.kind == "uistroke" then
            el.obj.Color = UI.Accent
        elseif el.kind == "subtitle" then
            el.obj.TextColor3 = S.Visuals.RainbowMode and UI.Accent or UI.TextDim
        end
    end

    -- ESP
    if S.ESP.Enabled then
        for player, objs in pairs(ESPObjects) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                local role = GetPlayerRole(player)
                local color = RoleColors[role]
                local dist = (Camera.CFrame.Position - hrp.Position).Magnitude

                if onScreen then
                    -- Box
                    if S.ESP.Boxes then
                        objs.Box.Visible = true
                        objs.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35)
                        objs.Box.Size = Vector2.new(50, 70)
                        objs.Box.Color = color
                    else
                        objs.Box.Visible = false
                    end

                    -- Name (with optional distance)
                    if S.ESP.Names then
                        objs.Name.Visible = true
                        objs.Name.Position = Vector2.new(pos.X, pos.Y - 45)
                        if S.ESP.Distance then
                            objs.Name.Text = player.Name .. " [" .. math.floor(dist) .. "]"
                        else
                            objs.Name.Text = player.Name
                        end
                        objs.Name.Color = color
                    else
                        objs.Name.Visible = false
                    end

                    -- Role
                    if S.ESP.Roles then
                        objs.Role.Visible = true
                        objs.Role.Position = Vector2.new(pos.X, pos.Y + 35)
                        objs.Role.Text = role
                        objs.Role.Color = color
                    else
                        objs.Role.Visible = false
                    end

                    -- Tracer
                    if S.ESP.Tracers then
                        objs.Tracer.Visible = true
                        local viewSize = Camera.ViewportSize
                        objs.Tracer.From = Vector2.new(viewSize.X / 2, viewSize.Y)
                        objs.Tracer.To = Vector2.new(pos.X, pos.Y)
                        objs.Tracer.Color = color
                    else
                        objs.Tracer.Visible = false
                    end
                else
                    objs.Box.Visible = false
                    objs.Name.Visible = false
                    objs.Role.Visible = false
                    objs.Tracer.Visible = false
                end
            else
                objs.Box.Visible = false
                objs.Name.Visible = false
                objs.Role.Visible = false
                objs.Tracer.Visible = false
            end
        end
    else
        for _, objs in pairs(ESPObjects) do
            objs.Box.Visible = false
            objs.Name.Visible = false
            objs.Role.Visible = false
            objs.Tracer.Visible = false
        end
    end

    -- Chams
    if S.ESP.Chams then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and not ChamsObjects[player] then
                local char = player.Character
                if char then
                    CreateChams(player)
                end
            end
        end
    end
    for player, hl in pairs(ChamsObjects) do
        if player and player.Character then
            if S.ESP.Chams then
                hl.Enabled = true
                hl.Adornee = player.Character
                hl.FillColor = RoleColors[GetPlayerRole(player)]
            else
                hl.Enabled = false
            end
        end
    end

    -- Gun ESP
    if S.MM2.GunESP then
        UpdateGunESP()
        for obj, text in pairs(GunESPObjects) do
            if obj and obj:FindFirstChild("Handle") then
                local pos, onScreen = Camera:WorldToViewportPoint(obj.Handle.Position)
                if onScreen then
                    text.Visible = true
                    text.Position = Vector2.new(pos.X, pos.Y - 20)
                else
                    text.Visible = false
                end
            else
                text.Visible = false
            end
        end
    else
        for _, text in pairs(GunESPObjects) do
            text.Visible = false
        end
    end

    -- Auto Collect
    if S.MM2.AutoCollect then
        DoAutoCollect()
    end

    -- Auto Shoot
    if S.Aimbot.AutoShoot then
        local now = tick()
        if now - lastShot > 0.35 then
            lastShot = now
            ExecuteAimbot()
        end
    else
        StopAimbot()
    end

    -- FOV Circle (now independent of AutoShoot - fixed bug)
    UpdateFOVCircle()

    -- Crosshair
    if S.Crosshair.Enabled then
        if #CrosshairDrawings == 0 then
            RebuildCrosshair()
        end
        UpdateCrosshair()
    else
        for _, d in pairs(CrosshairDrawings) do
            d.Visible = false
        end
    end

    -- Spectator List
    UpdateSpectatorList()

end)

-- Player tracking
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        CreateESP(player)
        if player.Character then
            CreateChams(player)
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        CreateESP(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if ESPObjects[player] then
        for _, objs in pairs(ESPObjects[player]) do
            if objs.Remove then objs:Remove() end
        end
        ESPObjects[player] = nil
    end
    if ChamsObjects[player] then
        ChamsObjects[player]:Destroy()
        ChamsObjects[player] = nil
    end
    RoleCache[player] = nil
end)

-- Crosshair rebuild on style change
local lastCrosshairStyle = S.Crosshair.Style
RunService.Heartbeat:Connect(function()
    if S.Crosshair.Style ~= lastCrosshairStyle then
        lastCrosshairStyle = S.Crosshair.Style
        RebuildCrosshair()
    end
end)

print("Kitty Hub v3 (AetherHub Style) Loaded!")
print("[X] = GUI | [N] = Noclip | [" .. S.Aimbot.AimbotKey .. "] = Auto Aim")
print("Features: ESP | Tracers | AutoShoot | Prediction | Rainbow | Crosshair | SpectatorList | AutoCollect")
