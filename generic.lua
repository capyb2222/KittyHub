-- Kitty Hub Generic
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Compatibility layer
local env = (pcall(getgenv) and getgenv()) or _G
local GUI_Parent = (pcall(gethui) and gethui()) or (LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")) or game:GetService("CoreGui")
local hasDrawing = pcall(function() return Drawing.new("Text") end)

if hasDrawing then
    local dbg = Drawing.new("Text")
    dbg.Text = "Kitty Hub Generic loaded — Press X"
    dbg.Size = 18
    dbg.Position = Vector2.new(10, 10)
    dbg.Color = Color3.new(0, 1, 0)
    dbg.Center = false
    dbg.Visible = true
    task.delay(5, function() if dbg and dbg.Remove then dbg:Remove() end end)
end

-- Settings
env.CatSettings = env.CatSettings or {
    ESP = {
        Enabled = true, Boxes = true, Names = true, Chams = true, Tracers = true, Distance = true
    },
    Movement = {
        SpeedEnabled = false, SpeedValue = 16,
        JumpEnabled = false, JumpValue = 50
    },
    Misc = {
        Noclip = false, Fly = false
    }
}

local S = env.CatSettings

-- GUI
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
ScreenGui.Parent = GUI_Parent
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local Window = Instance.new("Frame")
Window.Size = UDim2.new(0, 620, 0, 420)
Window.Position = UDim2.new(0.5, -310, 0.5, -210)
Window.BackgroundColor3 = UI.Bg
Window.BackgroundTransparency = 0.2
Window.BorderSizePixel = 0
Window.Parent = ScreenGui
Window.Visible = false
Instance.new("UICorner", Window).CornerRadius = UDim.new(0, 12)

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
Subtitle.Text = "generic"
Subtitle.TextColor3 = UI.TextDim
Subtitle.TextSize = 12
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = TitleBar

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

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 170, 1, -40)
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = UI.Surface
Sidebar.BackgroundTransparency = 0.3
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Window
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 8)

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(0, 3, 1, -20)
AccentLine.Position = UDim2.new(0, 0, 0, 10)
AccentLine.BackgroundColor3 = UI.Accent
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Sidebar
Instance.new("UICorner", AccentLine).CornerRadius = UDim.new(0, 2)
table.insert(AccentElements, {obj = AccentLine, kind = "accent"})

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

-- Tab system
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

local function CreateTab(tabName)
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
    CreateToggle(page, "Chams", S.ESP, "Chams")
    CreateToggle(page, "Tracers", S.ESP, "Tracers")
    CreateToggle(page, "Distance", S.ESP, "Distance")
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

-- === Misc Tab ===
do
    local page = CreateTab("Misc")
    CreateToggle(page, "Noclip", S.Misc, "Noclip", function(v)
        if v then EnableNoclip() else DisableNoclip() end
    end)
    CreateToggle(page, "Fly", S.Misc, "Fly", function(v)
        if v then EnableFly() else DisableFly() end
    end)
end

SwitchTab("ESP")

-- ESP System
local ESPObjects = {}
local ChamsObjects = {}
local ESPColor = Color3.new(1, 1, 1)

local function CreateESP(player)
    if player == LocalPlayer then return end
    local objs = {
        Box = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        Tracer = Drawing.new("Line")
    }
    objs.Box.Visible = false
    objs.Box.Thickness = 2
    objs.Box.Filled = false
    objs.Name.Visible = false
    objs.Name.Size = 14
    objs.Name.Center = true
    objs.Name.Font = 2
    objs.Tracer.Visible = false
    objs.Tracer.Thickness = 1.5
    objs.Tracer.Transparency = 0.6
    ESPObjects[player] = objs
end

local function CreateChams(player)
    if player == LocalPlayer or ChamsObjects[player] then return end
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = ESPColor
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.Parent = ScreenGui
    ChamsObjects[player] = hl
    local function update()
        if player.Character then
            hl.Adornee = player.Character
        end
    end
    update()
    player.CharacterAdded:Connect(update)
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function()
            if S.ESP.Chams then
                CreateChams(player)
            end
        end)
    end
end)

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
    if S.Misc.Noclip then
        S.Misc.Noclip = false
        DisableNoclip()
    else
        S.Misc.Noclip = true
        EnableNoclip()
    end
end

-- Fly
local FlyConnection = nil
local FlyBodyVelocity = nil

local function EnableFly()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    FlyBodyVelocity = Instance.new("BodyVelocity")
    FlyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
    FlyBodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
    FlyBodyVelocity.Parent = hrp

    if FlyConnection then FlyConnection:Disconnect() end
    FlyConnection = RunService.RenderStepped:Connect(function()
        if not FlyBodyVelocity or not FlyBodyVelocity.Parent then return end
        local moveDir = Vector3.new(0, 0, 0)
        local speed = 50

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + Camera.CFrame.LookVector * Vector3.new(1, 0, 1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - Camera.CFrame.LookVector * Vector3.new(1, 0, 1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - Camera.CFrame.RightVector * Vector3.new(1, 0, 1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + Camera.CFrame.RightVector * Vector3.new(1, 0, 1)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir + Vector3.new(0, -1, 0)
        end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit * speed
        end

        FlyBodyVelocity.Velocity = moveDir
    end)
end

local function DisableFly()
    if FlyConnection then
        FlyConnection:Disconnect()
        FlyConnection = nil
    end
    if FlyBodyVelocity then
        FlyBodyVelocity:Destroy()
        FlyBodyVelocity = nil
    end
end

local function ToggleFly()
    if S.Misc.Fly then
        S.Misc.Fly = false
        DisableFly()
    else
        S.Misc.Fly = true
        EnableFly()
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
    elseif input.KeyCode == Enum.KeyCode.F then
        ToggleFly()
    end
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    -- ESP
    if S.ESP.Enabled then
        for player, objs in pairs(ESPObjects) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                local dist = (Camera.CFrame.Position - hrp.Position).Magnitude

                if onScreen then
                    if S.ESP.Boxes then
                        objs.Box.Visible = true
                        objs.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35)
                        objs.Box.Size = Vector2.new(50, 70)
                        objs.Box.Color = ESPColor
                    else
                        objs.Box.Visible = false
                    end

                    if S.ESP.Names then
                        objs.Name.Visible = true
                        objs.Name.Position = Vector2.new(pos.X, pos.Y - 45)
                        if S.ESP.Distance then
                            objs.Name.Text = player.Name .. " [" .. math.floor(dist) .. "]"
                        else
                            objs.Name.Text = player.Name
                        end
                        objs.Name.Color = ESPColor
                    else
                        objs.Name.Visible = false
                    end

                    if S.ESP.Tracers then
                        objs.Tracer.Visible = true
                        local viewSize = Camera.ViewportSize
                        objs.Tracer.From = Vector2.new(viewSize.X / 2, viewSize.Y)
                        objs.Tracer.To = Vector2.new(pos.X, pos.Y)
                        objs.Tracer.Color = ESPColor
                    else
                        objs.Tracer.Visible = false
                    end
                else
                    objs.Box.Visible = false
                    objs.Name.Visible = false
                    objs.Tracer.Visible = false
                end
            else
                objs.Box.Visible = false
                objs.Name.Visible = false
                objs.Tracer.Visible = false
            end
        end
    else
        for _, objs in pairs(ESPObjects) do
            objs.Box.Visible = false
            objs.Name.Visible = false
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
            hl.Enabled = S.ESP.Chams
            hl.Adornee = player.Character
        end
    end
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
end)

print("Kitty Hub Generic Loaded!")
print("[X] = GUI | [N] = Noclip | [F] = Fly")
print("Features: ESP | Noclip | Speed | Jump | Fly")
