`-- MM2 Aimbot & ESP v3
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local env = (pcall(getgenv) and getgenv()) or _G
local tableFind = table.find or function(t, v)
    for i, x in pairs(t) do if x == v then return i end end
end
local hasDrawing = pcall(function() local d = Drawing.new("Text"); d:Remove() end)

if not hasDrawing then
    warn("Kitty Hub: Drawing API not supported. Aborting.")
    return
end

local dbg = Drawing.new("Text")
dbg.Text = "Kitty Hub MM2 loaded — Press X"
dbg.Size = 18
dbg.Position = Vector2.new(10, 10)
dbg.Font = 3
dbg.Color = Color3.new(0, 1, 0)
dbg.Center = false
dbg.Visible = true
task.delay(5, function() if dbg and dbg.Remove then dbg:Remove() end end)

env.CatSettings = env.CatSettings or {
    ESP = {
        Enabled = false, Boxes = false, Names = false, Roles = false,
        Chams = false, Tracers = false, Distance = false, MaxDistance = 1000
    },
    Aimbot = {
        Enabled = true, AutoShoot = false, AimbotKey = "C", Prediction = false,
        LeadTime = 0.15, AimPart = "Head", OffScreen = true, AutoUnequip = false,
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

-- Backfill new Aimbot keys for users whose CatSettings was cached by an older run
if S.Aimbot.Enabled == nil then S.Aimbot.Enabled = true end
if S.Aimbot.OffScreen == nil then S.Aimbot.OffScreen = true end
if S.Aimbot.AutoUnequip == nil then S.Aimbot.AutoUnequip = false end

local function ParseFOVColor()
    local hex = S.Aimbot.FOVColor and S.Aimbot.FOVColor:gsub("#", "")
    if hex and #hex == 6 then
        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        if r and g and b then
            return Color3.fromRGB(r, g, b)
        end
    end
    return nil
end

local RoleCache = {}
local RemoteCache = {}

local RoleColors = {
    Murderer = Color3.fromRGB(255, 50, 50),
    Sheriff = Color3.fromRGB(65, 130, 255),
    Innocent = Color3.fromRGB(120, 255, 120)
}

local GunToolNames = {"Gun", "Revolver", "Pistol", "Shotgun", "Rifle"}
local function HasSheriffGun(container)
    for _, name in ipairs(GunToolNames) do
        if container:FindFirstChild(name) then return true end
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") and (child:FindFirstChild("Shoot") or child:FindFirstChild("Fire") or child:FindFirstChildOfClass("RemoteEvent")) then
            return true
        end
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
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") and (child:FindFirstChild("Shoot") or child:FindFirstChild("Fire") or child:FindFirstChildOfClass("RemoteEvent")) then
                RoleCache[player] = "Sheriff"; return "Sheriff"
            end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then RoleCache[player] = "Murderer"; return "Murderer" end
        if HasSheriffGun(bp) then RoleCache[player] = "Sheriff"; return "Sheriff" end
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") and (child:FindFirstChild("Shoot") or child:FindFirstChild("Fire") or child:FindFirstChildOfClass("RemoteEvent")) then
                RoleCache[player] = "Sheriff"; return "Sheriff"
            end
        end
    end
    RoleCache[player] = "Innocent"
    return "Innocent"
end

local function OnCharacterAdded(player)
    RoleCache[player] = nil
    local function onToolAdded()
        RoleCache[player] = nil
    end
    local char = player.Character
    if char then
        char.ChildAdded:Connect(onToolAdded)
    end
end

local function OnPlayerAdded(player)
    player.CharacterAdded:Connect(function() OnCharacterAdded(player) end)
    local bp = player:FindFirstChild("Backpack")
    if bp then
        bp.ChildAdded:Connect(function()
            RoleCache[player] = nil
        end)
    end
    player.ChildAdded:Connect(function(child)
        if child.Name == "Backpack" then
            child.ChildAdded:Connect(function()
                RoleCache[player] = nil
            end)
        end
    end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        OnPlayerAdded(player)
    end
end

-- Drawing-based GUI
local UI = {
    Bg = Color3.fromRGB(25, 25, 35),
    Surface = Color3.fromRGB(35, 35, 50),
    Accent = Color3.fromRGB(200, 100, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(140, 140, 150),
    Border = Color3.fromRGB(80, 78, 95)
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

local function NewFill(color, transparency)
    local t1 = Drawing.new("Triangle")
    t1.Visible = false
    t1.Filled = true
    t1.Thickness = 1
    t1.Color = color or Color3.new(1, 1, 1)
    t1.Transparency = transparency or 0
    local t2 = Drawing.new("Triangle")
    t2.Visible = false
    t2.Filled = true
    t2.Thickness = 1
    t2.Color = color or Color3.new(1, 1, 1)
    t2.Transparency = transparency or 0
    table.insert(allDrawings, t1)
    table.insert(allDrawings, t2)
    local fill = {
        _t1 = t1, _t2 = t2,
        _color = color or Color3.new(1, 1, 1),
        _transparency = transparency or 0,
        _visible = true
    }
    function fill:set(x, y, w, h)
        self._t1.Visible = self._visible
        self._t1.Color = self._color
        self._t1.Transparency = self._transparency
        self._t1.PointA = Vector2.new(x, y)
        self._t1.PointB = Vector2.new(x + w, y)
        self._t1.PointC = Vector2.new(x, y + h)
        self._t2.Visible = self._visible
        self._t2.Color = self._color
        self._t2.Transparency = self._transparency
        self._t2.PointA = Vector2.new(x + w, y)
        self._t2.PointB = Vector2.new(x, y + h)
        self._t2.PointC = Vector2.new(x + w, y + h)
    end
    return setmetatable(fill, {
        __index = function(t, k)
            if k == "Visible" then return t._visible end
            if k == "Color" then return t._color end
            if k == "Transparency" then return t._transparency end
            return rawget(t, k)
        end,
        __newindex = function(t, k, v)
            if k == "Visible" then
                t._visible = v
                t._t1.Visible = v; t._t2.Visible = v
            elseif k == "Color" then
                t._color = v
                t._t1.Color = v; t._t2.Color = v
            elseif k == "Transparency" then
                t._transparency = v
                t._t1.Transparency = v; t._t2.Transparency = v
            end
            rawset(t, k, v)
        end
    })
end

-- Line-quad outline (replaces Square for compatibility)
local function NewOutline(color, transparency)
    local lines = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Visible = false
        l.Thickness = 2
        l.Color = color or Color3.new(1, 1, 1)
        l.Transparency = transparency or 0
        table.insert(allDrawings, l)
        table.insert(lines, l)
    end
    local outline = { _lines = lines, _visible = true, _color = color or Color3.new(1, 1, 1) }
    function outline:setPosSize(x, y, w, h)
        for _, l in ipairs(self._lines) do l.Visible = self._visible end
        self._lines[1].From = Vector2.new(x, y); self._lines[1].To = Vector2.new(x + w, y)
        self._lines[2].From = Vector2.new(x + w, y); self._lines[2].To = Vector2.new(x + w, y + h)
        self._lines[3].From = Vector2.new(x + w, y + h); self._lines[3].To = Vector2.new(x, y + h)
        self._lines[4].From = Vector2.new(x, y + h); self._lines[4].To = Vector2.new(x, y)
    end
    return setmetatable(outline, {
        __index = function(t, k)
            if k == "Visible" then return t._visible end
            if k == "Color" then return t._color end
            return rawget(t, k)
        end,
        __newindex = function(t, k, v)
            if k == "Visible" then
                t._visible = v
                for _, l in ipairs(t._lines) do l.Visible = v end
            elseif k == "Color" then
                t._color = v
                for _, l in ipairs(t._lines) do l.Color = v end
            end
            rawset(t, k, v)
        end
    })
end

local function NewText(color, size, center)
    local t = Drawing.new("Text")
    t.Visible = false
    t.Font = 3
    t.Size = size or 14
    t.Center = center or false
    t.Color = color or Color3.new(1, 1, 1)
    table.insert(allDrawings, t)
    return t
end

local winBg = NewFill(UI.Bg, 0)
local sidebarBg = NewFill(UI.Surface, 0)
local titleTxt = NewText(UI.Accent, 22, false)
titleTxt.Text = "Kitty Hub"
local subTxt = NewText(UI.TextDim, 15, false)
subTxt.Text = "v3"
local closeTxt = NewText(UI.Text, 18, false)
closeTxt.Text = "X"
local accentLine = Drawing.new("Line")
accentLine.Visible = false
accentLine.Thickness = 3
accentLine.Color = UI.Accent
accentLine.Transparency = 0
table.insert(allDrawings, accentLine)

local winBorder = NewOutline(UI.Border, 0)

local toggleBg = NewFill(UI.Accent, 0)
local toggleTxt = NewText(UI.Text, 22, true)
toggleTxt.Text = "Kitty"

local tabBtns = {}
for i, name in ipairs(W.tabs) do
    local bg = NewFill(UI.Surface, 0.85)
    local txt = NewText(UI.Text, 15, false)
    txt.Text = name
    table.insert(tabBtns, {bg = bg, txt = txt, name = name, idx = i})
end

local controls = {}
local controlsByTab = {}
local contentY = {}

for _, name in ipairs(W.tabs) do
    controlsByTab[name] = {}
    contentY[name] = 12
end

local function addControl(tabName, ctrl)
    table.insert(controls, ctrl)
    table.insert(controlsByTab[tabName], #controls)
    ctrl.contentY = contentY[tabName]
    contentY[tabName] = contentY[tabName] + ctrl.h + 9
end

local function Toggle(tabName, label, ref, key, callback)
    local bg = NewFill(Color3.fromRGB(25, 23, 30), 0)
    local lbl = NewText(UI.Text, 15, false)
    lbl.Text = label
    local track = NewFill(Color3.fromRGB(40, 40, 50), 0)
    local knob = NewFill(Color3.fromRGB(80, 80, 90), 0)
    local stateTxt = NewText(UI.TextDim, 12, true)

    local ctrl = {
        type = "toggle", h = 42, ref = ref, key = key, callback = callback,
        parts = {bg, lbl, track, knob, stateTxt},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            bg:set(wx + 4, cy, 432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 13)
            local tx = wx + 370
            track:set(tx + 5, cy + 11, 40, 20)
            knob.Visible = true
            stateTxt.Visible = true
            stateTxt.Position = Vector2.new(tx - 14, cy + 14)
            if ref[key] then
                track.Color = Color3.fromRGB(80, 255, 100)
                knob.Color = Color3.new(1, 1, 1)
                knob:set(tx + 5 + 22, cy + 13, 16, 16)
                stateTxt.Text = "ON"
                stateTxt.Color = Color3.fromRGB(80, 255, 100)
            else
                track.Color = Color3.fromRGB(40, 40, 50)
                knob.Color = Color3.fromRGB(80, 80, 90)
                knob:set(tx + 5 + 2, cy + 13, 16, 16)
                stateTxt.Text = "OFF"
                stateTxt.Color = Color3.fromRGB(80, 80, 90)
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
    local bg = NewFill(Color3.fromRGB(25, 23, 30), 0)
    local lbl = NewText(UI.Text, 15, false)
    lbl.Text = label
    local valTxt = NewText(UI.Accent, 15, false)
    local track = NewFill(Color3.fromRGB(40, 40, 50), 0)
    local fill = NewFill(UI.Accent, 0)

    local ctrl = {
        type = "slider", h = 48, minV = minV, maxV = maxV,
        ref = ref, key = key, callback = callback,
        parts = {bg, lbl, valTxt, track, fill},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            bg:set(wx + 4, cy, 432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 7)
            valTxt.Visible = true
            valTxt.Text = tostring(math.floor(ref[key]))
            valTxt.Position = Vector2.new(wx + 400, cy + 7)
            local pct = math.max(0, math.min((ref[key] - minV) / (maxV - minV), 1))
            track:set(wx + 16, cy + 36, 408, 4)
            fill.Visible = pct > 0
            if pct > 0 then fill:set(wx + 16, cy + 36, 408 * pct, 4) end
            fill.Color = UI.Accent
        end,
        hitTest = function(self, mx, my, wx, wy)
            local cy = wy + self.contentY
            return mx >= wx + 16 and mx <= wx + 424 and my >= cy + 32 and my <= cy + 44
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
    local bg = NewFill(Color3.fromRGB(25, 23, 30), 0)
    local lbl = NewText(UI.Text, 15, false)
    lbl.Text = label
    local btnBg = NewFill(UI.Accent, 0)
    local btnTxt = NewText(UI.Text, 14, false)

    local idx = 1
    for i, opt in ipairs(options) do
        if opt == ref[key] then idx = i; break end
    end

    local ctrl = {
        type = "cycle", h = 42, options = options, idx = idx, ref = ref, key = key,
        parts = {bg, lbl, btnBg, btnTxt},
        draw = function(self, wx, wy)
            local cy = wy + self.contentY
            for i, opt in ipairs(self.options) do
                if opt == ref[key] then self.idx = i; break end
            end
            bg:set(wx + 4, cy, 432, self.h)
            lbl.Visible = true
            lbl.Position = Vector2.new(wx + 16, cy + 13)
            btnBg:set(wx + 356, cy + 8, 76, 26)
            btnBg.Color = UI.Accent
            btnTxt.Visible = true
            btnTxt.Text = ref[key]
            btnTxt.Position = Vector2.new(wx + 394, cy + 12)
            btnTxt.Center = true
        end,
        hitTest = function(self, mx, my, wx, wy)
            local cy = wy + self.contentY
            return mx >= wx + 356 and mx <= wx + 432 and my >= cy + 8 and my <= cy + 34
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

Toggle("Aimbot", "Enabled", S.Aimbot, "Enabled")
Toggle("Aimbot", "Auto Shoot", S.Aimbot, "AutoShoot")
Toggle("Aimbot", "Prediction", S.Aimbot, "Prediction")
Toggle("Aimbot", "FOV Circle", S.Aimbot, "FOVCircle")
Toggle("Aimbot", "Off-Screen Aim", S.Aimbot, "OffScreen")
Toggle("Aimbot", "Auto Unequip", S.Aimbot, "AutoUnequip")
Slider("Aimbot", "FOV Radius", S.Aimbot, "FOVRadius", 50, 400)
Cycle("Aimbot", "Aimbot Key", S.Aimbot, "AimbotKey", {"C", "G", "V", "B", "X", "Z", "F", "T", "Q", "E", "R", "Y"})

Toggle("MM2", "Gun ESP", S.MM2, "GunESP")
Toggle("MM2", "Noclip", S.MM2, "Noclip", function(v)
    if v then EnableNoclip() else DisableNoclip() end
end)
Toggle("MM2", "Auto Collect", S.MM2, "AutoCollect")
Cycle("MM2", "Noclip Key", S.MM2, "NoclipKey", {"N", "C", "G", "V", "B", "X", "Z", "F", "T", "Q", "E", "R", "Y"})

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

local lastTab = W.tab
local toggleBtnY = 0
local tglRect = {x = 20, y = 0, w = 72, h = 72}
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
        tglRect.y = toggleBtnY - math.floor(tglRect.h / 2)
    end
    if not W.show then
        for _, d in ipairs(allDrawings) do
            d.Visible = false
        end
        toggleBg.Visible = true
        toggleBg:set(tglRect.x, tglRect.y, tglRect.w, tglRect.h)
        toggleTxt.Visible = true
        toggleTxt.Color = UI.Text
        toggleTxt.Position = Vector2.new(tglRect.x + math.floor(tglRect.w / 2), tglRect.y + math.floor(tglRect.h / 2))
        lastTab = W.tab
        return
    end
    local wx, wy = W.x, W.y
    toggleBg.Visible = false
    toggleTxt.Visible = false
    winBg:set(wx, wy, W.w, W.h)
    winBorder:setPosSize(wx, wy, W.w, W.h)
    sidebarBg:set(wx, wy + 40, 170, W.h - 40)
    titleTxt.Visible = true
    titleTxt.Color = UI.Accent
    titleTxt.Position = Vector2.new(wx + 15, wy + 11)
    subTxt.Visible = true
    subTxt.Position = Vector2.new(wx + 135, wy + 12)
    closeTxt.Visible = true
    closeTxt.Position = Vector2.new(wx + W.w - 25, wy + 11)
    accentLine.Visible = true
    accentLine.From = Vector2.new(wx + 1.5, wy + 48)
    accentLine.To = Vector2.new(wx + 1.5, wy + 48 + (W.h - 60))
    accentLine.Thickness = 3
    accentLine.Color = UI.Accent
    for _, btn in ipairs(tabBtns) do
        local by = wy + 40 + (btn.idx - 1) * 40 + 8
        local isActive = btn.name == W.tab
        btn.bg:set(wx + 5, by, 160, 36)
        btn.bg.Color = isActive and UI.Accent or UI.Surface
        btn.bg.Transparency = isActive and 0.2 or 0.85
        btn.txt.Visible = true
        btn.txt.Position = Vector2.new(wx + 18, by + 10)
        btn.txt.Color = isActive and UI.Text or UI.TextDim
    end
    local scroll = W.scroll[W.tab] or 0
    local cx, cwy = wx + 175, wy + 45 + scroll
    if W.tab ~= lastTab then
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
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local mousePos = UserInputService:GetMouseLocation()
    local mx, my = mousePos.X, mousePos.Y
    if not W.show then
        if mx >= tglRect.x and mx <= tglRect.x + tglRect.w and my >= tglRect.y and my <= tglRect.y + tglRect.h then
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
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local mousePos = UserInputService:GetMouseLocation()
    local mx, my = mousePos.X, mousePos.Y
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
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        W.dragging = false
        activeSlider = nil
    end
end)

-- Spectator List (Drawing-based)
local specLabels = {}
local specT1 = Drawing.new("Triangle")
specT1.Visible = false; specT1.Filled = true; specT1.Thickness = 1
specT1.Color = Color3.fromRGB(25, 25, 35); specT1.Transparency = 0
local specT2 = Drawing.new("Triangle")
specT2.Visible = false; specT2.Filled = true; specT2.Thickness = 1
specT2.Color = Color3.fromRGB(25, 25, 35); specT2.Transparency = 0
local specTitle = Drawing.new("Text")
specTitle.Visible = false
specTitle.Font = 3
specTitle.Size = 11
specTitle.Center = false
specTitle.Color = UI.Accent
specTitle.Text = "Spectators"

local function UpdateSpectatorList()
    local cam = workspace.CurrentCamera
    if not S.Misc.SpectatorList or not cam or not cam.ViewportSize or cam.ViewportSize.X == 0 then
        specT1.Visible = false; specT2.Visible = false
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
    if hum then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.CameraSubject == hum then
                table.insert(specs, player.Name)
            end
        end
    end
    for name, lbl in pairs(specLabels) do
        if not tableFind(specs, name) then
            lbl:Remove()
            specLabels[name] = nil
        end
    end
    local count = #specs
    local height = math.max(24, 24 + count * 18)
    specT1.Visible = true; specT2.Visible = true
    specT1.PointA = Vector2.new(bx, by)
    specT1.PointB = Vector2.new(bx + 180, by)
    specT1.PointC = Vector2.new(bx, by + height)
    specT2.PointA = Vector2.new(bx + 180, by)
    specT2.PointB = Vector2.new(bx, by + height)
    specT2.PointC = Vector2.new(bx + 180, by + height)
    specTitle.Visible = true
    specTitle.Position = Vector2.new(bx + 5, by + 2)
    for i, name in ipairs(specs) do
        if not specLabels[name] then
            local lbl = Drawing.new("Text")
            lbl.Visible = false
            lbl.Font = 3
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
local _chamsComplete = false

local function CreateESP(player)
    if player == LocalPlayer then return end
    local boxLines = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Visible = false
        l.Thickness = 2
        l.Color = Color3.new(1, 1, 1)
        l.Transparency = 0
        table.insert(boxLines, l)
    end
    local objs = {
        Box = boxLines,
        Name = Drawing.new("Text"),
        Role = Drawing.new("Text"),
        Tracer = Drawing.new("Line")
    }
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
local GunDropNames = {"GunDrop", "Gun_Drop", "Gun_Giver", "Giver"}
local function IsGunDrop(obj)
    for _, name in ipairs(GunDropNames) do
        if obj.Name == name then return true end
    end
    if obj:IsA("Tool") then
        if obj:FindFirstChild("Handle") then return true end
        if obj:FindFirstChild("Gun") or obj:FindFirstChild("Shoot") or obj:FindFirstChild("Fire") then return true end
    end
    if obj:IsA("Part") or obj:IsA("MeshPart") then
        if obj.Name:lower():find("gun") then return true end
    end
    return false
end

local GunESPObjects = {}

local function UpdateGunESP()
    if not S.MM2.GunESP then
        for _, text in pairs(GunESPObjects) do
            pcall(function() text:Remove() end)
        end
        GunESPObjects = {}
        return
    end
    local seen = {}
    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if IsGunDrop(obj) then
                local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart") or obj
                local part = handle:IsA("BasePart") and handle or nil
                if part then
                    seen[obj] = part
                    if not GunESPObjects[obj] then
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
            if obj:IsA("Model") or obj:IsA("Folder") then
                scan(obj)
            end
        end
    end
    scan(workspace)
    for obj, text in pairs(GunESPObjects) do
        if not seen[obj] then
            pcall(function() text:Remove() end)
            GunESPObjects[obj] = nil
        end
    end
end

-- Aimbot
local lastShot = 0
local FIRE_INTERVAL = 0.1 -- seconds between shots while the key is held / auto-shooting
local aimbotActive = false
local aimbotKeyHeld = false
local aimbotKeyCode = nil
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
    local color = S.Visuals.RainbowMode and UI.Accent or ParseFOVColor() or Color3.fromRGB(200, 100, 255)
    FOVCircle.Color = aimbotActive and Color3.fromRGB(100, 200, 255) or color
    FOVCircle.Visible = true
end

local function GetMurderer()
    -- Prefer role detection (cached) so we never miss a re-skinned knife
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            if GetPlayerRole(player) == "Murderer" then
                return player
            end
        end
    end
    -- Fallback: direct knife scan in character / backpack
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char and char:FindFirstChild("Knife") then
                RoleCache[player] = "Murderer"
                return player
            end
            local bp = player:FindFirstChild("Backpack")
            if bp and bp:FindFirstChild("Knife") then
                RoleCache[player] = "Murderer"
                return player
            end
        end
    end
    return nil
end

local function FindGunRemote(gun)
    if not gun then return nil end
    local cached = RemoteCache[gun]
    if cached then return cached end
    local remote = gun:FindFirstChild("Shoot") or gun:FindFirstChild("Fire")
    if not (remote and remote:IsA("RemoteEvent")) then
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
    if remote and not remote:IsA("RemoteEvent") then
        remote = nil
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

    local function isGunTool(tool)
        if not tool:IsA("Tool") then return false end
        if tool:FindFirstChild("Shoot") or tool:FindFirstChild("Fire") then return true end
        if tool:FindFirstChildOfClass("RemoteEvent") then return true end
        if tool:FindFirstChild("Handle") then
            for _, name in ipairs(GunToolNames) do
                if tool.Name == name then return true end
            end
        end
        return false
    end

    for _, name in ipairs(GunToolNames) do
        local g = char:FindFirstChild(name)
        if g and isGunTool(g) then return g end
    end
    for _, child in ipairs(char:GetChildren()) do
        if isGunTool(child) then return child end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, name in ipairs(GunToolNames) do
            local g = bp:FindFirstChild(name)
            if g and isGunTool(g) then return g end
        end
        for _, child in ipairs(bp:GetChildren()) do
            if isGunTool(child) then return child end
        end
    end
    return nil
end

local function EquipGun(gun)
    gun = gun or FindGun()
    if not gun then return nil end
    local char = LocalPlayer.Character
    if not char then return nil end
    -- Already in hand? Don't re-equip — avoids flicker and keeps it smooth.
    if gun.Parent == char then return gun end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        -- EquipTool reparents the tool into the character; its child remote
        -- comes along, so we can fire immediately without yielding a frame.
        pcall(function() hum:EquipTool(gun) end)
    end
    return gun
end

local function UnequipGun()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:UnequipTools() end) end
end

local function ShootMurderer(murderer, gun)
    if not murderer or not murderer.Character then return false end
    local part = GetAimPart(murderer.Character)
    if not part then return false end
    gun = EquipGun(gun)
    if not gun then return false end
    local targetPos = PredictPosition(part)
    local remote = FindGunRemote(gun)
    if not remote then
        -- Gun tool had no remote we recognise; sweep other equipped tools.
        local char = LocalPlayer.Character
        if char then
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") then
                    InvalidateRemoteCache(child)
                    remote = FindGunRemote(child)
                    if remote then break end
                end
            end
        end
    end
    if not remote then return false end
    -- Different MM2 gun versions expect different arguments; try both.
    local ok = pcall(function() remote:FireServer(targetPos, part) end)
    if not ok then
        pcall(function() remote:FireServer(targetPos) end)
    end
    return true
end

local function ExecuteAimbot()
    if not S.Aimbot.Enabled then aimbotActive = false; return end

    -- 1. No gun? Stop here and reset — you can't shoot without one.
    local gun = FindGun()
    if not gun then
        aimbotActive = false
        return
    end

    -- 2. Find the murderer.
    local murderer = GetMurderer()
    if not murderer or not murderer.Character then
        aimbotActive = false
        return
    end

    -- 3. Off-screen aim shoots wherever the murderer is. When it's off, only
    --    fire while they're actually on screen.
    if not S.Aimbot.OffScreen then
        local part = GetAimPart(murderer.Character)
        if part then
            local _, onScreen = Camera:WorldToViewportPoint(part.Position)
            if not onScreen then aimbotActive = false; return end
        end
    end

    -- 4. Equip (if needed) and shoot.
    aimbotActive = true
    local fired = ShootMurderer(murderer, gun)

    -- 5. Bonus: unequip after shooting, only if the user asked for it. When
    --    off we never touch the equip state, so an already-equipped gun stays.
    if fired and S.Aimbot.AutoUnequip then
        UnequipGun()
    end
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
    local nearestPart = nil
    local nearestDist = math.huge

    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if IsGunDrop(obj) then
                local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if handle then
                    local dist = (handle.Position - hrp.Position).Magnitude
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestGun = obj
                        nearestPart = handle
                    end
                end
            end
            if obj:IsA("Model") or obj:IsA("Folder") then
                scan(obj)
            end
        end
    end
    scan(workspace)

    if HasSheriffGun(char) and nearestDist <= 3 then return end

    if nearestGun and nearestPart then
        local targetPos = nearestPart.Position + Vector3.new(0, 3, 0)
        if nearestDist > 5 then
            hrp.CFrame = CFrame.new(targetPos)
        end
        if nearestDist <= 20 then
            local gun = FindGun()
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
local function ApplyMovementSettings(char)
    char = char or LocalPlayer.Character
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
    ApplyMovementSettings(char)
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
    if input.KeyCode == Enum.KeyCode.X then
        W.show = not W.show
    end
    local noclipKey = S.MM2.NoclipKey or "N"
    local nk = Enum.KeyCode[noclipKey]
    if nk and input.KeyCode == nk then
        ToggleNoclip()
    end
    local key = S.Aimbot.AimbotKey
    local keyCode = Enum.KeyCode[key]
    if keyCode and input.KeyCode == keyCode and S.Aimbot.Enabled then
        aimbotKeyCode = keyCode
        aimbotKeyHeld = true
        lastShot = tick()
        ExecuteAimbot()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if aimbotKeyCode and input.KeyCode == aimbotKeyCode then
        aimbotKeyHeld = false
    end
end)

local lastCrosshairStyle = S.Crosshair.Style
local lastCacheClear = 0

-- Main Loop
RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera or Camera
    RenderGUI()

    local now = tick()
    if now - lastCacheClear > 2 then
        RoleCache = {}
        lastCacheClear = now
    end

    if S.Visuals.RainbowMode then
        RainbowHue = (now * S.Visuals.RainbowSpeed * 0.15) % 1
        UI.Accent = Color3.fromHSV(RainbowHue, 0.9, 1)
        subTxt.Color = UI.Accent
    else
        UI.Accent = Color3.fromRGB(200, 100, 255)
        subTxt.Color = UI.TextDim
    end

    if S.Movement.SpeedEnabled or S.Movement.JumpEnabled then
        ApplyMovementSettings()
    end

    if S.ESP.Enabled then
        for player, objs in pairs(ESPObjects) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                local role = GetPlayerRole(player)
                local color = RoleColors[role]
                local dist = (Camera.CFrame.Position - hrp.Position).Magnitude

                if S.ESP.MaxDistance and dist > S.ESP.MaxDistance then
                    onScreen = false
                end

                if onScreen then
                    if S.ESP.Boxes then
                        local bx = pos.X - 25; local by = pos.Y - 35
                        objs.Box[1].Visible = true; objs.Box[1].Color = color
                        objs.Box[1].From = Vector2.new(bx, by); objs.Box[1].To = Vector2.new(bx + 50, by)
                        objs.Box[2].Visible = true; objs.Box[2].Color = color
                        objs.Box[2].From = Vector2.new(bx + 50, by); objs.Box[2].To = Vector2.new(bx + 50, by + 70)
                        objs.Box[3].Visible = true; objs.Box[3].Color = color
                        objs.Box[3].From = Vector2.new(bx + 50, by + 70); objs.Box[3].To = Vector2.new(bx, by + 70)
                        objs.Box[4].Visible = true; objs.Box[4].Color = color
                        objs.Box[4].From = Vector2.new(bx, by + 70); objs.Box[4].To = Vector2.new(bx, by)
                    else
                        for _, l in ipairs(objs.Box) do l.Visible = false end
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
                    for _, l in ipairs(objs.Box) do l.Visible = false end
                    objs.Name.Visible = false
                    objs.Role.Visible = false
                    objs.Tracer.Visible = false
                end
            else
                for _, l in ipairs(objs.Box) do l.Visible = false end
                objs.Name.Visible = false
                objs.Role.Visible = false
                objs.Tracer.Visible = false
            end
        end
    else
        for _, objs in pairs(ESPObjects) do
            for _, l in ipairs(objs.Box) do l.Visible = false end
            objs.Name.Visible = false
            objs.Role.Visible = false
            objs.Tracer.Visible = false
        end
    end

    if S.ESP.Chams then
        if not _chamsComplete then
            local anyMissing = false
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and not ChamsObjects[player] then
                    anyMissing = true
                    local char = player.Character
                    if char then
                        CreateChams(player)
                    end
                end
            end
            if not anyMissing then _chamsComplete = true end
        end
    else
        _chamsComplete = false
    end
    for player, hl in pairs(ChamsObjects) do
        if player and player.Character then
            if S.ESP.Chams then
                hl.Enabled = true
                if hl.Adornee ~= player.Character then
                    hl.Adornee = player.Character
                end
                hl.FillColor = RoleColors[GetPlayerRole(player)]
            else
                hl.Enabled = false
            end
        end
    end

    if S.MM2.GunESP then
        UpdateGunESP()
        for obj, text in pairs(GunESPObjects) do
            local handle = obj and (obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart"))
            if handle then
                local pos, onScreen = Camera:WorldToViewportPoint(handle.Position)
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

    local aimbotKeyName = S.Aimbot.AimbotKey
    local aimbotKeyEnum = Enum.KeyCode[aimbotKeyName]
    if S.Aimbot.Enabled and aimbotKeyEnum and UserInputService:IsKeyDown(aimbotKeyEnum) then
        aimbotKeyCode = aimbotKeyEnum
        aimbotKeyHeld = true
    end
    if S.Aimbot.Enabled and (S.Aimbot.AutoShoot or aimbotKeyHeld) then
        local shotNow = tick()
        if shotNow - lastShot > FIRE_INTERVAL then
            lastShot = shotNow
            ExecuteAimbot()
        end
    else
        StopAimbot()
    end

    UpdateFOVCircle()

    if S.Crosshair.Enabled then
        if #CrosshairDrawings == 0 or lastCrosshairStyle ~= S.Crosshair.Style then
            lastCrosshairStyle = S.Crosshair.Style
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
        player.CharacterAdded:Connect(function() OnCharacterAdded(player) end)
        if player.Character and S.ESP.Chams then
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

print("Kitty Hub v3 (MM2) Loaded!")
print("[X] = GUI | [" .. (S.MM2.NoclipKey or "N") .. "] = Noclip | [" .. S.Aimbot.AimbotKey .. "] = Auto Aim")
print("Features: ESP | Tracers | AutoShoot | Prediction | Rainbow | Crosshair | SpectatorList | AutoCollect")
