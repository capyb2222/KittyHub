-- MM2 Aimbot & ESP v3
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local env = (pcall(getgenv) and getgenv()) or _G
local tableFind = table.find or function(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
end
local hasDrawing = pcall(function() return Drawing.new("Text") end)

if hasDrawing then
    local dbg = Drawing.new("Text")
    dbg.Text = "Kitty Hub MM2 loaded — Press X"
    dbg.Size = 18
    dbg.Position = Vector2.new(10, 10)
    dbg.Color = Color3.new(0, 1, 0)
    dbg.Center = false
    dbg.Visible = true
    task.delay(5, function() if dbg and dbg.Remove then dbg:Remove() end end)
end

env.CatSettings = env.CatSettings or {
    ESP = {
        Enabled = false, Boxes = false, Names = false, Roles = false,
        Chams = false, Tracers = false, Distance = false, MaxDistance = 1000
    },
    Aimbot = {
        AutoShoot = false, AimbotKey = "C", Prediction = false,
        LeadTime = 0.15, AimPart = "Head", OffScreen = false,
        FOVCircle = false, FOVRadius = 200, FOVColor = "#C864FF"
    },
    MM2 = {
        GunESP = false, Noclip = false, NoclipKey = "N", AutoCollect = false
    },
    Movement = {
        SpeedEnabled = false, SpeedValue = 16,
        JumpEnabled = false, JumpValue = 50
    },
    Visuals = {
        RainbowMode = false, RainbowSpeed = 1
    },
    Crosshair = {
        Enabled = false, Style = "Cross", Size = 10, Thickness = 2
    },
    Misc = {
        SpectatorList = false
    }
}

local S = env.CatSettings

local RoleCache = {}
local RemoteCache = {}

local RoleColors = {
    Murderer = Color3.fromRGB(255, 50, 50),
    Sheriff = Color3.fromRGB(50, 120, 255),
    Innocent = Color3.fromRGB(120, 255, 120)
}

local GunToolNames = {"Gun", "Revolver", "Pistol", "Shotgun", "Rifle"}
local function HasSheriffGun(container)
    for _, name in ipairs(GunToolNames) do
        if container:FindFirstChild(name) then return true end
    end
    return false
end

local function GetPlayerRole(player)
    local cached = RoleCache[player]
    if cached then return cached end
    local char = player.Character
    if char then
        if char:FindFirstChild("Knife") then RoleCache[player] = "Murderer"; return "Murderer" end
        if HasSheriffGun(char) then RoleCache[player] = "Sheriff"; return "Sheriff" end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then RoleCache[player] = "Murderer"; return "Murderer" end
        if HasSheriffGun(bp) then RoleCache[player] = "Sheriff"; return "Sheriff" end
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

-- Drawing-based GUI
local UI = {
    Bg = Color3.fromRGB(25, 25, 35),
    Surface = Color3.fromRGB(35, 35, 45),
    Accent = Color3.fromRGB(200, 100, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(150, 150, 150),
    Border = Color3.fromRGB(70, 65, 85)
}

local W = {
    x = 50, y = 50, w = 620, h = 420,
    show = false,
    tab = "ESP",
    tabs = {"ESP", "Aimbot", "MM2", "Movement", "Visuals", "Misc"},
    scroll = {},
    dragging = false,
    dragStart = Vector2.new(0, 0),
    dragWinPos = Vector2.new(0, 0)
}

for _, name in ipairs(W.tabs) do
    W.scroll[name] = 0
end

local allDrawings = {}
local function NewRect(color, filled, transparency)
    local s = Drawing.new("Square")
    s.Visible = false
    s.Filled = filled ~= false
    s.Thickness = 1
    s.Color = color or Color3.new(1, 1, 1)
    s.Transparency = transparency or 0
    table.insert(allDrawings, s)
    return s
end

local function NewText(color, size, center)
    local t = Drawing.new("Text")
    t.Visible = false
    t.Font = 2
    t.Size = size or 13
    t.Center = center or false
    t.Color = color or Color3.new(1, 1, 1)
    table.insert(allDrawings, t)
    return t
end

local winBg = NewRect(UI.Bg, true, 0)
local sidebarBg = NewRect(UI.Surface, true, 0)
local titleTxt = NewText(UI.Accent, 18, false)
titleTxt.Text = "Kitty Hub"
local subTxt = NewText(UI.TextDim, 12, false)
subTxt.Text = "v3"
local closeTxt = NewText(UI.Text, 16, false)
closeTxt.Text = "X"
local accentLine = NewRect(UI.Accent, true, 0)
accentLine.Thickness = 0

local toggleBg = NewRect(UI.Accent, true, 0)
local toggleTxt = NewText(UI.Text, 14, true)
toggleTxt.Text = "Kitty"

local tabBtns = {}
for i, name in ipairs(W.tabs) do
    local bg = NewRect(UI.Surface, true, 0.85)
    local txt = NewText(UI.Text, 13, false)
    txt.Text = name
    table.insert(tabBtns, {bg = bg, txt = txt, name = name, idx = i})
end

local controls = {}
local controlsByTab = {}
local contentY = {}

for _, name in ipairs(W.tabs) do
    controlsByTab[name] = {}
    contentY[name] = 5
end

local function addControl(tabName, ctrl)
    table.insert(controls, ctrl)
    table.insert(controlsByTab[tabName], #controls)
    ctrl.contentY = contentY[tabName]
    contentY[tabName] = contentY[tabName] + ctrl.h + 6
end

local function Toggle(tabName, label, ref, key, callback)
    local bg = NewRect(Color3.fromRGB(32, 30, 38), true, 0)
    local lbl = NewText(UI.Text, 13, false)
    lbl.Text = label
    local track = NewRect(Color3.fromRGB(60, 60, 70), true, 0)
    local knob = NewRect(Color3.fromRGB(150, 150, 150), true, 0)

    local ctrl = {
        type = "toggle", h = 38, ref = ref, key = key, callback = callback,
        parts = {bg, lbl, track, knob},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            bg.Visible = true
            bg.Position = Vector2.new(wx + 4, cy)
            bg.Size = Vector2.new(432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 11)
            local tx = wx + 380
            track.Visible = true
            track.Position = Vector2.new(tx + 5, cy + 9)
            track.Size = Vector2.new(40, 20)
            knob.Visible = true
            knob.Size = Vector2.new(16, 16)
            if ref[key] then
                track.Color = UI.Accent
                knob.Color = Color3.new(1, 1, 1)
                knob.Position = Vector2.new(tx + 5 + 22, cy + 11)
            else
                track.Color = Color3.fromRGB(60, 60, 70)
                knob.Color = Color3.fromRGB(150, 150, 150)
                knob.Position = Vector2.new(tx + 5 + 2, cy + 11)
            end
        end,
        hitTest = function(self, mx, my, wx, wy)
            local cy = wy + self.contentY
            return mx >= wx + 4 and mx <= wx + 436 and my >= cy and my <= cy + self.h
        end,
        click = function(self)
            ref[key] = not ref[key]
            if self.callback then self.callback(ref[key]) end
        end
    }
    addControl(tabName, ctrl)
    return ctrl
end

local function Slider(tabName, label, ref, key, minV, maxV, callback)
    minV = minV or 0
    maxV = maxV or 100
    local bg = NewRect(Color3.fromRGB(32, 30, 38), true, 0)
    local lbl = NewText(UI.Text, 13, false)
    lbl.Text = label
    local valTxt = NewText(UI.Accent, 13, false)
    local track = NewRect(Color3.fromRGB(55, 55, 65), true, 0)
    local fill = NewRect(UI.Accent, true, 0)

    local ctrl = {
        type = "slider", h = 45, minV = minV, maxV = maxV,
        ref = ref, key = key, callback = callback,
        parts = {bg, lbl, valTxt, track, fill},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            bg.Visible = true
            bg.Position = Vector2.new(wx + 4, cy)
            bg.Size = Vector2.new(432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 6)
            valTxt.Visible = true
            valTxt.Text = tostring(math.floor(ref[key]))
            valTxt.Position = Vector2.new(wx + 404, cy + 6)
            local pct = math.max(0, math.min((ref[key] - minV) / (maxV - minV), 1))
            track.Visible = true
            track.Position = Vector2.new(wx + 16, cy + 34)
            track.Size = Vector2.new(408, 4)
            fill.Visible = true
            fill.Position = Vector2.new(wx + 16, cy + 34)
            fill.Size = Vector2.new(408 * pct, 4)
            fill.Color = UI.Accent
        end,
        hitTest = function(self, mx, my, wx, wy)
            local cy = wy + self.contentY
            return mx >= wx + 16 and mx <= wx + 424 and my >= cy + 30 and my <= cy + 42
        end,
        beginDrag = function(self, mx, my, wx, wy)
            local pct = math.max(0, math.min((mx - (wx + 16)) / 408, 1))
            local val = minV + (maxV - minV) * pct
            ref[key] = math.max(minV, math.min(math.floor(val + 0.5), maxV))
            if self.callback then self.callback(ref[key]) end
        end,
        drag = function(self, mx, my, wx, wy)
            local pct = math.max(0, math.min((mx - (wx + 16)) / 408, 1))
            local val = minV + (maxV - minV) * pct
            ref[key] = math.max(minV, math.min(math.floor(val + 0.5), maxV))
            if self.callback then self.callback(ref[key]) end
        end
    }
    addControl(tabName, ctrl)
    return ctrl
end

local function Cycle(tabName, label, ref, key, options)
    local bg = NewRect(Color3.fromRGB(32, 30, 38), true, 0)
    local lbl = NewText(UI.Text, 13, false)
    lbl.Text = label
    local btnBg = NewRect(UI.Accent, true, 0)
    local btnTxt = NewText(UI.Text, 12, false)

    local idx = 1
    for i, opt in ipairs(options) do
        if opt == ref[key] then idx = i; break end
    end

    local ctrl = {
        type = "cycle", h = 38, options = options, idx = idx, ref = ref, key = key,
        parts = {bg, lbl, btnBg, btnTxt},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            bg.Visible = true
            bg.Position = Vector2.new(wx + 4, cy)
            bg.Size = Vector2.new(432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 11)
            btnBg.Visible = true
            btnBg.Position = Vector2.new(wx + 356, cy + 6)
            btnBg.Size = Vector2.new(76, 26)
            btnBg.Color = UI.Accent
            btnTxt.Visible = true
            btnTxt.Text = ref[key]
            btnTxt.Position = Vector2.new(wx + 394, cy + 11)
            btnTxt.Center = true
        end,
        hitTest = function(self, mx, my, wx, wy)
            local cy = wy + self.contentY
            return mx >= wx + 356 and mx <= wx + 432 and my >= cy + 6 and my <= cy + 32
        end,
        click = function(self)
            self.idx = (self.idx % #self.options) + 1
            ref[key] = self.options[self.idx]
        end
    }
    addControl(tabName, ctrl)
    return ctrl
end

Toggle("ESP", "Enabled", S.ESP, "Enabled")
Toggle("ESP", "Boxes", S.ESP, "Boxes")
Toggle("ESP", "Names", S.ESP, "Names")
Toggle("ESP", "Roles", S.ESP, "Roles")
Toggle("ESP", "Chams", S.ESP, "Chams")
Toggle("ESP", "Tracers", S.ESP, "Tracers")
Toggle("ESP", "Distance", S.ESP, "Distance")

Toggle("Aimbot", "Auto Shoot", S.Aimbot, "AutoShoot")
Toggle("Aimbot", "Prediction", S.Aimbot, "Prediction")
Toggle("Aimbot", "FOV Circle", S.Aimbot, "FOVCircle")
Toggle("Aimbot", "Off-Screen Aim", S.Aimbot, "OffScreen")
Slider("Aimbot", "FOV Radius", S.Aimbot, "FOVRadius", 50, 400)

Toggle("MM2", "Gun ESP", S.MM2, "GunESP")
Toggle("MM2", "Noclip", S.MM2, "Noclip", function(v)
    if v then EnableNoclip() else DisableNoclip() end
end)
Toggle("MM2", "Auto Collect", S.MM2, "AutoCollect")

Toggle("Movement", "Speed Hack", S.Movement, "SpeedEnabled", function(v)
    ApplyMovementSettings()
end)
Slider("Movement", "Speed Value", S.Movement, "SpeedValue", 16, 100, function(v)
    ApplyMovementSettings()
end)
Toggle("Movement", "Jump Hack", S.Movement, "JumpEnabled", function(v)
    ApplyMovementSettings()
end)
Slider("Movement", "Jump Value", S.Movement, "JumpValue", 50, 200, function(v)
    ApplyMovementSettings()
end)

Toggle("Visuals", "Rainbow Mode", S.Visuals, "RainbowMode")
Slider("Visuals", "Rainbow Speed", S.Visuals, "RainbowSpeed", 0.5, 5)
Toggle("Visuals", "Crosshair", S.Crosshair, "Enabled")
Cycle("Visuals", "Crosshair Style", S.Crosshair, "Style", {"Dot", "Cross", "Circle"})
Slider("Visuals", "Crosshair Size", S.Crosshair, "Size", 5, 30)
Slider("Visuals", "Crosshair Thickness", S.Crosshair, "Thickness", 1, 5)

Toggle("Misc", "Spectator List", S.Misc, "SpectatorList")

local lastTab = ""
local toggleBtnY = 0
local function CenterWindow()
    local cam = workspace.CurrentCamera
    if cam and cam.ViewportSize and cam.ViewportSize.X > 0 then
        W.x = math.floor((cam.ViewportSize.X - W.w) / 2)
        W.y = math.floor((cam.ViewportSize.Y - W.h) / 2)
        return true
    end
    return false
end
task.spawn(function()
    repeat task.wait() until CenterWindow()
end)

local function RenderGUI()
    local cam = workspace.CurrentCamera
    local vs = cam and cam.ViewportSize
    if vs then
        toggleBtnY = vs.Y - 100
    end
    if not W.show then
        toggleBg.Visible = true
        toggleBg.Position = Vector2.new(20, toggleBtnY - 25)
        toggleBg.Size = Vector2.new(50, 50)
        toggleTxt.Visible = true
        toggleTxt.Position = Vector2.new(45, toggleBtnY)
        if W.show ~= nil then
            for _, d in ipairs(allDrawings) do
                if d ~= toggleBg and d ~= toggleTxt then
                    d.Visible = false
                end
            end
        end
        lastTab = ""
        return
    end
    local wx, wy = W.x, W.y
    winBg.Visible = true
    winBg.Position = Vector2.new(wx, wy)
    winBg.Size = Vector2.new(W.w, W.h)
    sidebarBg.Visible = true
    sidebarBg.Position = Vector2.new(wx, wy + 40)
    sidebarBg.Size = Vector2.new(170, W.h - 40)
    titleTxt.Visible = true
    titleTxt.Position = Vector2.new(wx + 15, wy + 11)
    subTxt.Visible = true
    subTxt.Position = Vector2.new(wx + 140, wy + 13)
    closeTxt.Visible = true
    closeTxt.Position = Vector2.new(wx + W.w - 25, wy + 11)
    accentLine.Visible = true
    accentLine.Position = Vector2.new(wx, wy + 48)
    accentLine.Size = Vector2.new(3, W.h - 60)
    accentLine.Color = UI.Accent
    for _, btn in ipairs(tabBtns) do
        local by = wy + 40 + (btn.idx - 1) * 40 + 8
        local isActive = btn.name == W.tab
        btn.bg.Visible = true
        btn.bg.Position = Vector2.new(wx + 5, by)
        btn.bg.Size = Vector2.new(160, 36)
        btn.bg.Color = isActive and UI.Accent or UI.Surface
        btn.bg.Transparency = isActive and 0.2 or 0.85
        btn.txt.Visible = true
        btn.txt.Position = Vector2.new(wx + 18, by + 10)
        btn.txt.Color = isActive and UI.Text or UI.TextDim
    end
    local scroll = W.scroll[W.tab] or 0
    local cx, cwy = wx + 175, wy + 45 + scroll
    if W.tab ~= lastTab then
        for _, d in ipairs(allDrawings) do
            d.Visible = false
        end
        for _, idx in ipairs(controlsByTab[lastTab]) do
            for _, part in ipairs(controls[idx].parts) do
                part.Visible = false
            end
        end
        lastTab = W.tab
    end
    for _, idx in ipairs(controlsByTab[W.tab]) do
        controls[idx].draw(controls[idx], cx, cwy)
    end
end

local activeSlider = nil

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseWheel and W.show then
        W.scroll[W.tab] = (W.scroll[W.tab] or 0) + input.Position.Y * 30
        local cList = controlsByTab[W.tab]
        if #cList > 0 then
            local last = controls[cList[#cList]]
            local total = last.contentY + last.h + 10
            local maxS = math.max(0, total - 370)
            W.scroll[W.tab] = math.max(-maxS, math.min(W.scroll[W.tab], 0))
        else
            W.scroll[W.tab] = 0
        end
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local mx, my = UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y
    if not W.show then
        local cam = workspace.CurrentCamera
        local tglY = cam and cam.ViewportSize and (cam.ViewportSize.Y - 100) or toggleBtnY
        if mx >= 20 and mx <= 70 and my >= tglY - 25 and my <= tglY + 25 then
            W.show = true
        end
        return
    end
    if mx >= W.x + W.w - 28 and mx <= W.x + W.w - 8 and my >= W.y + 8 and my <= W.y + 30 then
        W.show = false
        return
    end
    for _, btn in ipairs(tabBtns) do
        local by = W.y + 40 + (btn.idx - 1) * 40 + 8
        if mx >= W.x + 5 and mx <= W.x + 165 and my >= by and my <= by + 36 then
            W.tab = btn.name
            return
        end
    end
    if my >= W.y and my <= W.y + 40 then
        W.dragging = true
        W.dragStart = Vector2.new(mx, my)
        W.dragWinPos = Vector2.new(W.x, W.y)
        return
    end
    local scroll = W.scroll[W.tab] or 0
    local cwx = W.x + 175
    local cwy = W.y + 45 + scroll
    for _, idx in ipairs(controlsByTab[W.tab]) do
        local ctrl = controls[idx]
        if ctrl.hitTest(ctrl, mx, my, cwx, cwy) then
            if ctrl.type == "slider" then
                ctrl.beginDrag(ctrl, mx, my, cwx, cwy)
                activeSlider = ctrl
            else
                ctrl.click(ctrl)
            end
            return
        end
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local mx, my = UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y
    if W.dragging then
        W.x = W.dragWinPos.X + (mx - W.dragStart.X)
        W.y = W.dragWinPos.Y + (my - W.dragStart.Y)
        return
    end
    if activeSlider then
        local scroll = W.scroll[W.tab] or 0
        activeSlider.drag(activeSlider, mx, my, W.x + 175, W.y + 45 + scroll)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        W.dragging = false
        activeSlider = nil
    end
end)

-- Spectator List (Drawing-based)
local specLabels = {}
local specBg = NewRect(Color3.fromRGB(25, 25, 35), true, 0)
local specTitle = NewText(UI.Accent, 11, false)
specTitle.Text = "Spectators"

local function UpdateSpectatorList()
    local cam = workspace.CurrentCamera
    if not S.Misc.SpectatorList or not cam or not cam.ViewportSize or cam.ViewportSize.X == 0 then
        specBg.Visible = false
        specTitle.Visible = false
        for _, lbl in pairs(specLabels) do
            lbl.Visible = false
        end
        return
    end
    local vs = cam.ViewportSize
    local bx = vs.X - 190
    local by = vs.Y / 2
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local specs = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.CameraSubject == hum then
            table.insert(specs, player.Name)
        end
    end
    for name, lbl in pairs(specLabels) do
        if not tableFind(specs, name) then
            lbl.Visible = false
            specLabels[name] = nil
        end
    end
    local count = #specs
    local height = math.max(24, 24 + count * 18)
    specBg.Visible = true
    specBg.Position = Vector2.new(bx, by)
    specBg.Size = Vector2.new(180, height)
    specTitle.Visible = true
    specTitle.Position = Vector2.new(bx + 5, by + 2)
    for i, name in ipairs(specs) do
        if not specLabels[name] then
            local lbl = Drawing.new("Text")
            lbl.Visible = false
            lbl.Font = 2
            lbl.Size = 11
            lbl.Center = false
            lbl.Color = UI.Text
            specLabels[name] = lbl
        end
        specLabels[name].Visible = true
        specLabels[name].Text = name
        specLabels[name].Position = Vector2.new(bx + 5, by + 24 + (i - 1) * 18)
    end
end

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
    hl.Parent = game:GetService("CoreGui")
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

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function()
            if S.ESP.Chams then
                CreateChams(player)
            end
        end)
    end
end)

-- Gun ESP
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
            CrosshairDrawings[1].From = Vector2.new(pos.X - size, pos.Y)
            CrosshairDrawings[1].To = Vector2.new(pos.X + size, pos.Y)
            CrosshairDrawings[1].Color = color
            CrosshairDrawings[1].Thickness = thick
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
        W.show = not W.show
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
    RenderGUI()

    if S.Visuals.RainbowMode then
        RainbowHue = (tick() * S.Visuals.RainbowSpeed * 0.15) % 1
        UI.Accent = Color3.fromHSV(RainbowHue, 0.9, 1)
        subTxt.Color = UI.Accent
    else
        UI.Accent = Color3.fromRGB(200, 100, 255)
        subTxt.Color = UI.TextDim
    end

    if S.ESP.Enabled then
        for player, objs in pairs(ESPObjects) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                local role = GetPlayerRole(player)
                local color = RoleColors[role]
                local dist = (Camera.CFrame.Position - hrp.Position).Magnitude

                if onScreen then
                    if S.ESP.Boxes then
                        objs.Box.Visible = true
                        objs.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35)
                        objs.Box.Size = Vector2.new(50, 70)
                        objs.Box.Color = color
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
                        objs.Name.Color = color
                    else
                        objs.Name.Visible = false
                    end

                    if S.ESP.Roles then
                        objs.Role.Visible = true
                        objs.Role.Position = Vector2.new(pos.X, pos.Y + 35)
                        objs.Role.Text = role
                        objs.Role.Color = color
                    else
                        objs.Role.Visible = false
                    end

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

    if S.MM2.AutoCollect then
        DoAutoCollect()
    end

    if S.Aimbot.AutoShoot then
        local now = tick()
        if now - lastShot > 0.35 then
            lastShot = now
            ExecuteAimbot()
        end
    else
        StopAimbot()
    end

    UpdateFOVCircle()

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

local lastCrosshairStyle = S.Crosshair.Style
RunService.Heartbeat:Connect(function()
    if S.Crosshair.Style ~= lastCrosshairStyle then
        lastCrosshairStyle = S.Crosshair.Style
        RebuildCrosshair()
    end
end)

print("Kitty Hub v3 (MM2) Loaded!")
print("[X] = GUI | [N] = Noclip | [" .. S.Aimbot.AimbotKey .. "] = Auto Aim")
print("Features: ESP | Tracers | AutoShoot | Prediction | Rainbow | Crosshair | SpectatorList | AutoCollect")
