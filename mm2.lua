-- Kitty Hub — MM2 (native Roblox UI build)
-- Menu and ESP are built from real Instances (ScreenGui/Frame/TextButton/...),
-- no Drawing API. Works on executors that expose gethui()/CoreGui (e.g. Xeno).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local env = (pcall(getgenv) and getgenv()) or _G

-- Re-running the script? Tear the previous instance down first so we don't stack
-- a second render loop / duplicate GUI on top of the old one.
if type(env.KittyHubCleanup) == "function" then
    pcall(env.KittyHubCleanup)
end

-- Connections + instances created this run, collected for cleanup.
local Connections = {}
local function track(conn)
    table.insert(Connections, conn)
    return conn
end

-- ============================================================ SETTINGS
env.CatSettings = env.CatSettings or {
    ESP = {
        Enabled = false, Boxes = true, Names = true, Roles = true,
        Chams = false, Tracers = false, Distance = false, MaxDistance = 1000
    },
    Aimbot = {
        Enabled = true, AutoShoot = false, AimbotKey = "C", OffScreen = true
    },
    MM2 = {
        GunESP = false, AutoCollect = false, Noclip = false, NoclipKey = "N"
    },
    Movement = {
        SpeedEnabled = false, SpeedValue = 16,
        JumpEnabled = false, JumpValue = 50
    }
}
local S = env.CatSettings

-- Backfill / strip keys for users whose CatSettings was cached by an older build.
do
    local defaults = {
        ESP = {Enabled=false, Boxes=true, Names=true, Roles=true, Chams=false, Tracers=false, Distance=false, MaxDistance=1000},
        Aimbot = {Enabled=true, AutoShoot=false, AimbotKey="C", OffScreen=true},
        MM2 = {GunESP=false, AutoCollect=false, Noclip=false, NoclipKey="N"},
        Movement = {SpeedEnabled=false, SpeedValue=16, JumpEnabled=false, JumpValue=50}
    }
    for group, keys in pairs(defaults) do
        S[group] = S[group] or {}
        for k, v in pairs(keys) do
            if S[group][k] == nil then S[group][k] = v end
        end
    end
end

-- ============================================================ ROLES
local RoleCache = {}
local RemoteCache = {}

local RoleColors = {
    Murderer = Color3.fromRGB(255, 60, 60),
    Sheriff = Color3.fromRGB(70, 140, 255),
    Innocent = Color3.fromRGB(120, 235, 120)
}
local GUN_YELLOW = Color3.fromRGB(255, 230, 40)

local GunToolNames = {"Gun", "Revolver", "Pistol", "Shotgun", "Rifle"}

local function isGunTool(tool)
    if not tool:IsA("Tool") then return false end
    if tool:FindFirstChild("Shoot") or tool:FindFirstChild("Fire") then return true end
    if tool:FindFirstChildOfClass("RemoteEvent") or tool:FindFirstChildOfClass("RemoteFunction") then return true end
    if tool:FindFirstChild("Handle") then
        for _, name in ipairs(GunToolNames) do
            if tool.Name == name then return true end
        end
    end
    return false
end

local function HasGun(container)
    if not container then return false end
    for _, child in ipairs(container:GetChildren()) do
        if isGunTool(child) then return true end
    end
    return false
end

local function GetPlayerRole(player)
    local cached = RoleCache[player]
    if cached then return cached end
    local char = player.Character
    local bp = player:FindFirstChild("Backpack")
    if (char and char:FindFirstChild("Knife")) or (bp and bp:FindFirstChild("Knife")) then
        RoleCache[player] = "Murderer"; return "Murderer"
    end
    if HasGun(char) or HasGun(bp) then
        RoleCache[player] = "Sheriff"; return "Sheriff"
    end
    RoleCache[player] = "Innocent"
    return "Innocent"
end

local function watchPlayer(player)
    if player == LocalPlayer then return end
    local function clear() RoleCache[player] = nil end
    track(player.CharacterAdded:Connect(function(char)
        clear()
        track(char.ChildAdded:Connect(clear))
        track(char.ChildRemoved:Connect(clear))
    end))
    if player.Character then
        track(player.Character.ChildAdded:Connect(clear))
        track(player.Character.ChildRemoved:Connect(clear))
    end
    track(player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            track(child.ChildAdded:Connect(clear))
            track(child.ChildRemoved:Connect(clear))
        end
    end))
    local bp = player:FindFirstChild("Backpack")
    if bp then
        track(bp.ChildAdded:Connect(clear))
        track(bp.ChildRemoved:Connect(clear))
    end
end

-- ============================================================ GUI HELPERS
local function guiParent()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function make(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, c in ipairs(children or {}) do
        c.Parent = inst
    end
    return inst
end

local function corner(radius, parent)
    return make("UICorner", {CornerRadius = UDim.new(0, radius or 6), Parent = parent})
end

local function stroke(color, thickness, parent)
    return make("UIStroke", {
        Color = color, Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent
    })
end

local function tween(obj, t, props)
    local tw = TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

-- Palette
local C = {
    Bg       = Color3.fromRGB(20, 20, 28),
    Surface  = Color3.fromRGB(28, 28, 40),
    Row      = Color3.fromRGB(34, 34, 48),
    RowHover = Color3.fromRGB(42, 42, 58),
    Accent   = Color3.fromRGB(170, 110, 255),
    Text     = Color3.fromRGB(240, 240, 245),
    TextDim  = Color3.fromRGB(150, 150, 165),
    Off      = Color3.fromRGB(55, 55, 70)
}

local UIState = { capturing = false } -- true while a keybind picker is listening

-- ============================================================ BUILD WINDOW
local guiName = "_kh" .. tostring(math.random(100000, 999999))
local ScreenGui = make("ScreenGui", {
    Name = guiName,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999
})
pcall(function() ScreenGui.Parent = guiParent() end)

local WIN_W, WIN_H = 560, 384
local SIDEBAR_W = 134
local TOPBAR_H = 42

local Window = make("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = C.Bg,
    BorderSizePixel = 0,
    Visible = false,
    Parent = ScreenGui
})
corner(10, Window)
stroke(Color3.fromRGB(60, 58, 78), 1, Window)

-- Top bar (drag handle)
local TopBar = make("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, TOPBAR_H),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
    Parent = Window
})
corner(10, TopBar)
make("Frame", { -- square off the bottom corners of the top bar
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = C.Surface, BorderSizePixel = 0, Parent = TopBar
})

make("TextLabel", {
    Text = "Kitty Hub", Font = Enum.Font.GothamBold, TextSize = 18,
    TextColor3 = C.Accent, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 120, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left, Parent = TopBar
})
make("TextLabel", {
    Text = "MM2", Font = Enum.Font.Gotham, TextSize = 13,
    TextColor3 = C.TextDim, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(116, 1), Size = UDim2.new(0, 60, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Left, Parent = TopBar
})

local CloseBtn = make("TextButton", {
    Text = "✕", Font = Enum.Font.GothamBold, TextSize = 16,
    TextColor3 = C.TextDim, BackgroundTransparency = 1, AutoButtonColor = false,
    Size = UDim2.fromOffset(34, TOPBAR_H), Position = UDim2.new(1, -38, 0, 0),
    Parent = TopBar
})
CloseBtn.MouseEnter:Connect(function() CloseBtn.TextColor3 = Color3.fromRGB(255, 90, 90) end)
CloseBtn.MouseLeave:Connect(function() CloseBtn.TextColor3 = C.TextDim end)

-- Sidebar
local Sidebar = make("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, -TOPBAR_H),
    Position = UDim2.fromOffset(0, TOPBAR_H),
    BackgroundColor3 = C.Surface, BorderSizePixel = 0, Parent = Window
})
make("UIListLayout", {
    Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = Sidebar
})
make("UIPadding", {PaddingTop = UDim.new(0, 10), Parent = Sidebar})

-- Content host
local Content = make("Frame", {
    Name = "Content",
    Size = UDim2.new(1, -SIDEBAR_W, 1, -TOPBAR_H),
    Position = UDim2.fromOffset(SIDEBAR_W, TOPBAR_H),
    BackgroundTransparency = 1, Parent = Window
})

-- Floating open button
local OpenBtn = make("TextButton", {
    Name = "Open",
    Text = "Kitty",
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.Text,
    BackgroundColor3 = C.Accent, BorderSizePixel = 0, AutoButtonColor = true,
    Size = UDim2.fromOffset(96, 40), Position = UDim2.new(0, 18, 1, -58),
    Parent = ScreenGui
})
corner(10, OpenBtn)

-- ---- Window open/close
local function setOpen(open)
    Window.Visible = open
    OpenBtn.Visible = not open
end
CloseBtn.MouseButton1Click:Connect(function() setOpen(false) end)
OpenBtn.MouseButton1Click:Connect(function() setOpen(true) end)

-- ---- Dragging
do
    local dragging, dragStart, startPos
    track(TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Window.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            Window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

-- ============================================================ TABS + CONTROLS
local tabs = {}        -- name -> ScrollingFrame
local tabButtons = {}  -- name -> TextButton
local activeTab = nil

local function selectTab(name)
    activeTab = name
    for n, frame in pairs(tabs) do
        frame.Visible = (n == name)
    end
    for n, btn in pairs(tabButtons) do
        local on = (n == name)
        tween(btn, 0.12, {BackgroundColor3 = on and C.Accent or C.Surface})
        btn.TextColor3 = on and C.Text or C.TextDim
        btn.BackgroundTransparency = on and 0 or 1
    end
end

local function addTab(name)
    local btn = make("TextButton", {
        Name = name, Text = name, Font = Enum.Font.GothamSemibold, TextSize = 14,
        TextColor3 = C.TextDim, BackgroundColor3 = C.Accent, BackgroundTransparency = 1,
        BorderSizePixel = 0, AutoButtonColor = false,
        Size = UDim2.new(1, -16, 0, 34), Parent = Sidebar
    })
    corner(7, btn)
    local scroller = make("ScrollingFrame", {
        Name = name, Visible = false,
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 4, ScrollBarImageColor3 = C.Accent,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Content
    })
    make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller})
    make("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), Parent = scroller
    })
    tabs[name] = scroller
    tabButtons[name] = btn
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    return scroller
end

local function rowBase(parent, height)
    local row = make("Frame", {
        Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = C.Row,
        BorderSizePixel = 0, Parent = parent
    })
    corner(7, row)
    return row
end

local function addToggle(parent, label, ref, key, callback)
    local row = rowBase(parent, 40)
    make("TextLabel", {
        Text = label, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.Text,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -80, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = row
    })
    local track_ = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(44, 22), BackgroundColor3 = C.Off, BorderSizePixel = 0, Parent = row
    })
    corner(11, track_)
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.fromRGB(230, 230, 235), BorderSizePixel = 0, Parent = track_
    })
    corner(9, knob)

    local function refresh(animate)
        local on = ref[key]
        local pos = on and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
        local col = on and C.Accent or C.Off
        if animate then
            tween(knob, 0.14, {Position = pos})
            tween(track_, 0.14, {BackgroundColor3 = col})
        else
            knob.Position = pos
            track_.BackgroundColor3 = col
        end
    end
    refresh(false)

    local hit = make("TextButton", {
        Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = row
    })
    hit.MouseButton1Click:Connect(function()
        ref[key] = not ref[key]
        refresh(true)
        if callback then callback(ref[key]) end
    end)
    return row
end

local function addSlider(parent, label, ref, key, minV, maxV, callback)
    local row = rowBase(parent, 52)
    make("TextLabel", {
        Text = label, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.Text,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6),
        Size = UDim2.new(1, -80, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = row
    })
    local valLabel = make("TextLabel", {
        Text = tostring(math.floor(ref[key])), Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = C.Accent, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6),
        Size = UDim2.fromOffset(60, 18), TextXAlignment = Enum.TextXAlignment.Right, Parent = row
    })
    local track_ = make("Frame", {
        Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 6),
        BackgroundColor3 = C.Off, BorderSizePixel = 0, Parent = row
    })
    corner(3, track_)
    local fill = make("Frame", {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, BorderSizePixel = 0, Parent = track_
    })
    corner(3, fill)
    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(240, 240, 245),
        BorderSizePixel = 0, Parent = fill
    })
    corner(7, knob)

    local function setFromScale(scale)
        scale = math.clamp(scale, 0, 1)
        local val = math.floor(minV + (maxV - minV) * scale + 0.5)
        ref[key] = val
        local realScale = (val - minV) / (maxV - minV)
        fill.Size = UDim2.new(realScale, 0, 1, 0)
        knob.Position = UDim2.fromScale(1, 0.5)
        valLabel.Text = tostring(val)
        if callback then callback(val) end
    end
    setFromScale((ref[key] - minV) / (maxV - minV))

    local dragging = false
    local function update(x)
        setFromScale((x - track_.AbsolutePosition.X) / track_.AbsoluteSize.X)
    end
    local hit = make("TextButton", {
        Text = "", BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 26), Parent = row
    })
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    return row
end

local function addKeybind(parent, label, ref, key)
    local row = rowBase(parent, 40)
    make("TextLabel", {
        Text = label, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = C.Text,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -100, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = row
    })
    local btn = make("TextButton", {
        Text = ref[key], Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.Text,
        BackgroundColor3 = C.Surface, BorderSizePixel = 0, AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(72, 26), Parent = row
    })
    corner(6, btn)
    local listening = false
    btn.MouseButton1Click:Connect(function()
        listening = true
        UIState.capturing = true
        btn.Text = "..."
        btn.TextColor3 = C.Accent
    end)
    track(UserInputService.InputBegan:Connect(function(input)
        if not listening then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then
                ref[key] = input.KeyCode.Name
            end
            btn.Text = ref[key]
            btn.TextColor3 = C.Text
            listening = false
            UIState.capturing = false
        end
    end))
    return row
end

local function addLabel(parent, text)
    make("TextLabel", {
        Text = text:upper(), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.TextDim,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = parent
    })
end

-- ============================================================ DECLARE LOGIC FNS
-- (defined later; referenced by control callbacks via forward locals)
local EnableNoclip, DisableNoclip, ApplyMovementSettings

-- ============================================================ POPULATE TABS
local espTab = addTab("ESP")
addToggle(espTab, "ESP Enabled", S.ESP, "Enabled")
addToggle(espTab, "Boxes", S.ESP, "Boxes")
addToggle(espTab, "Names", S.ESP, "Names")
addToggle(espTab, "Roles", S.ESP, "Roles")
addToggle(espTab, "Tracers", S.ESP, "Tracers")
addToggle(espTab, "Chams", S.ESP, "Chams")
addToggle(espTab, "Show Distance", S.ESP, "Distance")

local aimTab = addTab("Aimbot")
addLabel(aimTab, "Locks onto the murderer & fires your gun")
addToggle(aimTab, "Aimbot Enabled", S.Aimbot, "Enabled")
addToggle(aimTab, "Auto Shoot", S.Aimbot, "AutoShoot")
addToggle(aimTab, "Off-Screen Aim", S.Aimbot, "OffScreen")
addKeybind(aimTab, "Aim Key (tap)", S.Aimbot, "AimbotKey")

local mm2Tab = addTab("MM2")
addToggle(mm2Tab, "Gun ESP", S.MM2, "GunESP")
addToggle(mm2Tab, "Auto Collect Gun", S.MM2, "AutoCollect")
addToggle(mm2Tab, "Noclip", S.MM2, "Noclip", function(v)
    if v then EnableNoclip() else DisableNoclip() end
end)
addKeybind(mm2Tab, "Noclip Key", S.MM2, "NoclipKey")

local moveTab = addTab("Movement")
addToggle(moveTab, "Speed Hack", S.Movement, "SpeedEnabled", function() ApplyMovementSettings() end)
addSlider(moveTab, "Walk Speed", S.Movement, "SpeedValue", 16, 200, function() ApplyMovementSettings() end)
addToggle(moveTab, "Jump Hack", S.Movement, "JumpEnabled", function() ApplyMovementSettings() end)
addSlider(moveTab, "Jump Power", S.Movement, "JumpValue", 50, 300, function() ApplyMovementSettings() end)

selectTab("ESP")

-- ============================================================ ESP (native)
local EspGui = make("ScreenGui", {
    Name = guiName .. "esp", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 9998
})
pcall(function() EspGui.Parent = guiParent() end)

local ESPObjects = {}   -- player -> {box, name, role, tracer}
local ChamsObjects = {} -- player -> Highlight

local function createESP(player)
    if player == LocalPlayer or ESPObjects[player] then return end
    local box = make("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = EspGui
    })
    local boxStroke = stroke(Color3.new(1, 1, 1), 1.5, box)
    local name = make("TextLabel", {
        Font = Enum.Font.GothamSemibold, TextSize = 13, BackgroundTransparency = 1,
        TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(200, 16), Visible = false, Parent = EspGui
    })
    local role = make("TextLabel", {
        Font = Enum.Font.Gotham, TextSize = 12, BackgroundTransparency = 1,
        TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0),
        Size = UDim2.fromOffset(200, 14), Visible = false, Parent = EspGui
    })
    local tracer = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Visible = false,
        Size = UDim2.fromOffset(0, 1), Parent = EspGui
    })
    ESPObjects[player] = {box = box, boxStroke = boxStroke, name = name, role = role, tracer = tracer}
end

local function removeESP(player)
    local o = ESPObjects[player]
    if o then
        o.box:Destroy(); o.name:Destroy(); o.role:Destroy(); o.tracer:Destroy()
        ESPObjects[player] = nil
    end
    if ChamsObjects[player] then
        ChamsObjects[player]:Destroy()
        ChamsObjects[player] = nil
    end
end

local function createChams(player)
    if player == LocalPlayer or ChamsObjects[player] then return end
    local hl = make("Highlight", {
        FillTransparency = 0.55, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = EspGui
    })
    ChamsObjects[player] = hl
end

local function hideESP(o)
    o.box.Visible = false
    o.name.Visible = false
    o.role.Visible = false
    o.tracer.Visible = false
end

local function updateESP()
    if not S.ESP.Enabled then
        for _, o in pairs(ESPObjects) do hideESP(o) end
        for _, hl in pairs(ChamsObjects) do hl.Enabled = false end
        return
    end
    local vs = Camera.ViewportSize
    for player, o in pairs(ESPObjects) do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        if hrp then
            local role = GetPlayerRole(player)
            local color = RoleColors[role]
            local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
            local topPos = (head and head.Position or hrp.Position) + Vector3.new(0, 0.8, 0)
            local botPos = hrp.Position - Vector3.new(0, 3, 0)
            local topV, onScreen = Camera:WorldToViewportPoint(topPos)
            local botV = Camera:WorldToViewportPoint(botPos)
            if onScreen and dist <= S.ESP.MaxDistance then
                local height = math.abs(topV.Y - botV.Y)
                local width = height * 0.55
                local cx = (topV.X + botV.X) / 2

                if S.ESP.Boxes then
                    o.box.Visible = true
                    o.box.Position = UDim2.fromOffset(cx - width / 2, topV.Y)
                    o.box.Size = UDim2.fromOffset(width, height)
                    o.boxStroke.Color = color
                else
                    o.box.Visible = false
                end

                if S.ESP.Names then
                    o.name.Visible = true
                    o.name.Text = S.ESP.Distance
                        and string.format("%s  [%dm]", player.Name, math.floor(dist))
                        or player.Name
                    o.name.TextColor3 = color
                    o.name.Position = UDim2.fromOffset(cx, topV.Y - 2)
                else
                    o.name.Visible = false
                end

                if S.ESP.Roles then
                    o.role.Visible = true
                    o.role.Text = role
                    o.role.TextColor3 = color
                    o.role.Position = UDim2.fromOffset(cx, botV.Y + 2)
                else
                    o.role.Visible = false
                end

                if S.ESP.Tracers then
                    local from = Vector2.new(vs.X / 2, vs.Y)
                    local to = Vector2.new(cx, botV.Y)
                    local d = to - from
                    o.tracer.Visible = true
                    o.tracer.BackgroundColor3 = color
                    o.tracer.Size = UDim2.fromOffset(d.Magnitude, 1)
                    o.tracer.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
                    o.tracer.Rotation = math.deg(math.atan2(d.Y, d.X))
                else
                    o.tracer.Visible = false
                end
            else
                hideESP(o)
            end
        else
            hideESP(o)
        end
    end

    -- Chams
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and S.ESP.Chams and not ChamsObjects[player] then
            createChams(player)
        end
    end
    for player, hl in pairs(ChamsObjects) do
        if S.ESP.Chams and player.Character then
            hl.Enabled = true
            if hl.Adornee ~= player.Character then hl.Adornee = player.Character end
            hl.FillColor = RoleColors[GetPlayerRole(player)]
            hl.OutlineColor = Color3.new(1, 1, 1)
        else
            hl.Enabled = false
        end
    end
end

-- ============================================================ GUN ESP (yellow)
local GunDropNames = {"GunDrop", "Gun_Drop", "Gun_Giver", "Giver"}
local function isGunDrop(obj)
    for _, n in ipairs(GunDropNames) do
        if obj.Name == n then return true end
    end
    if obj:IsA("Tool") and (obj:FindFirstChild("Handle") or obj:FindFirstChild("Gun")
        or obj:FindFirstChild("Shoot") or obj:FindFirstChild("Fire")) then
        return true
    end
    if (obj:IsA("BasePart")) and obj.Name:lower():find("gun") then return true end
    return false
end

local GunESPObjects = {} -- obj -> BillboardGui

local function gunPart(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
end

local function updateGunESP()
    if not S.MM2.GunESP then
        for _, bb in pairs(GunESPObjects) do bb:Destroy() end
        GunESPObjects = {}
        return
    end
    local seen = {}
    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if isGunDrop(obj) then
                local part = gunPart(obj)
                if part then
                    seen[obj] = true
                    if not GunESPObjects[obj] then
                        local bb = make("BillboardGui", {
                            Adornee = part, Size = UDim2.fromOffset(60, 20),
                            StudsOffset = Vector3.new(0, 2, 0), AlwaysOnTop = true,
                            MaxDistance = 600, Parent = EspGui
                        })
                        make("TextLabel", {
                            Text = "GUN", Font = Enum.Font.GothamBold, TextSize = 15,
                            TextColor3 = GUN_YELLOW, BackgroundTransparency = 1,
                            TextStrokeTransparency = 0.3, Size = UDim2.fromScale(1, 1), Parent = bb
                        })
                        GunESPObjects[obj] = bb
                    end
                end
            end
            if obj:IsA("Model") or obj:IsA("Folder") then scan(obj) end
        end
    end
    scan(workspace)
    for obj, bb in pairs(GunESPObjects) do
        if not seen[obj] then bb:Destroy(); GunESPObjects[obj] = nil end
    end
end

-- ============================================================ AIMBOT
local FIRE_INTERVAL = 0.1
local lastShot = 0

local function getMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            if GetPlayerRole(player) == "Murderer" then return player end
        end
    end
    return nil
end

local function isRemote(obj)
    return obj and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction"))
end

local function findGunRemote(gun)
    if not gun then return nil end
    local cached = RemoteCache[gun]
    if cached and cached.Parent then return cached end
    local remote = gun:FindFirstChild("Shoot") or gun:FindFirstChild("Fire")
    if not isRemote(remote) then
        remote = gun:FindFirstChildOfClass("RemoteEvent") or gun:FindFirstChildOfClass("RemoteFunction")
    end
    if not remote then
        for _, child in ipairs(gun:GetDescendants()) do
            if isRemote(child) then remote = child; break end
        end
    end
    RemoteCache[gun] = remote
    return remote
end

-- Fire the gun's shoot remote at a position. Tries (pos, part) then (pos) since
-- MM2 gun versions differ. RemoteFunctions are invoked off-thread so a yield
-- never stalls the render loop.
local function fireRemote(remote, pos, part)
    if remote:IsA("RemoteFunction") then
        task.spawn(function()
            if not pcall(function() remote:InvokeServer(pos, part) end) then
                pcall(function() remote:InvokeServer(pos) end)
            end
        end)
    else
        if not pcall(function() remote:FireServer(pos, part) end) then
            pcall(function() remote:FireServer(pos) end)
        end
    end
end

local function findGun()
    local char = LocalPlayer.Character
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if isGunTool(child) then return child end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if isGunTool(child) then return child end
        end
    end
    return nil
end

local function equipGun(gun)
    gun = gun or findGun()
    if not gun then return nil end
    local char = LocalPlayer.Character
    if not char then return nil end
    if gun.Parent == char then return gun end -- already in hand
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:EquipTool(gun) end) end
    return gun
end

local function aimPart(char)
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end

local function executeAimbot()
    if not S.Aimbot.Enabled then return end
    local gun = findGun()
    if not gun then return end
    local murderer = getMurderer()
    if not murderer or not murderer.Character then return end
    local part = aimPart(murderer.Character)
    if not part then return end

    if not S.Aimbot.OffScreen then
        local _, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then return end
    end

    gun = equipGun(gun)
    if not gun then return end
    local remote = findGunRemote(gun)
    if not remote then return end
    fireRemote(remote, part.Position, part)
end

-- ============================================================ AUTO COLLECT
local autoCollectThrottle = 0
local function doAutoCollect()
    local now = tick()
    if now - autoCollectThrottle < 0.3 then return end
    autoCollectThrottle = now
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if HasGun(char) then return end -- already armed

    local nearestPart, nearestDist = nil, math.huge
    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if isGunDrop(obj) then
                local part = gunPart(obj)
                if part then
                    local d = (part.Position - hrp.Position).Magnitude
                    if d < nearestDist then nearestDist, nearestPart = d, part end
                end
            end
            if obj:IsA("Model") or obj:IsA("Folder") then scan(obj) end
        end
    end
    scan(workspace)

    if nearestPart and nearestDist > 5 then
        hrp.CFrame = CFrame.new(nearestPart.Position + Vector3.new(0, 3, 0))
    end
end

-- ============================================================ MOVEMENT / NOCLIP
function ApplyMovementSettings(char)
    char = char or LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed = S.Movement.SpeedEnabled and S.Movement.SpeedValue or 16
    hum.JumpPower = S.Movement.JumpEnabled and S.Movement.JumpValue or 50
end

local NoclipConn
function EnableNoclip()
    if NoclipConn then NoclipConn:Disconnect() end
    NoclipConn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
            end
        end
    end)
    track(NoclipConn)
end
function DisableNoclip()
    if NoclipConn then NoclipConn:Disconnect(); NoclipConn = nil end
end

-- Restore noclip if it was left enabled in a previous run (setting persists).
if S.MM2.Noclip then EnableNoclip() end

track(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.4)
    ApplyMovementSettings(char)
end))
if LocalPlayer.Character then ApplyMovementSettings() end

-- ============================================================ KEYBINDS
track(UserInputService.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if UIState.capturing then return end -- a keybind picker is grabbing this press
    -- Toggle menu (ignore while typing in a textbox)
    if input.KeyCode == Enum.KeyCode.X and not processed then
        setOpen(not Window.Visible)
    end
    if not processed then
        local nk = Enum.KeyCode[S.MM2.NoclipKey]
        if nk and input.KeyCode == nk then
            S.MM2.Noclip = not S.MM2.Noclip
            if S.MM2.Noclip then EnableNoclip() else DisableNoclip() end
        end
        -- Aim key pressed: equip the gun (if needed) and shoot the murderer NOW.
        -- Holding the key keeps firing via the render loop below.
        local ak = Enum.KeyCode[S.Aimbot.AimbotKey]
        if ak and input.KeyCode == ak and S.Aimbot.Enabled then
            lastShot = tick()
            executeAimbot()
        end
    end
end))

-- ============================================================ MAIN LOOP
local lastCacheClear = 0
track(RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera or Camera

    local now = tick()
    if now - lastCacheClear > 1.5 then
        RoleCache = {}
        lastCacheClear = now
    end

    if S.Movement.SpeedEnabled or S.Movement.JumpEnabled then
        ApplyMovementSettings()
    end

    updateESP()

    if S.MM2.GunESP then updateGunESP()
    elseif next(GunESPObjects) then updateGunESP() end -- one pass to clean up

    if S.MM2.AutoCollect then doAutoCollect() end

    -- Aimbot: the aim key fires one shot per press (handled in InputBegan).
    -- Auto Shoot keeps firing on its own while a murderer is in play.
    if S.Aimbot.Enabled and S.Aimbot.AutoShoot and now - lastShot > FIRE_INTERVAL then
        lastShot = now
        executeAimbot()
    end
end))

-- ============================================================ PLAYER TRACKING
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        watchPlayer(player)
        createESP(player)
    end
end
track(Players.PlayerAdded:Connect(function(player)
    watchPlayer(player)
    createESP(player)
end))
track(Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
    RoleCache[player] = nil
end))

-- ============================================================ CLEANUP HOOK
env.KittyHubCleanup = function()
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() EspGui:Destroy() end)
end

print("Kitty Hub (MM2) loaded — native UI build.")
print(string.format("[X] menu  |  [%s] noclip  |  tap [%s] to aim+shoot", S.MM2.NoclipKey, S.Aimbot.AimbotKey))
