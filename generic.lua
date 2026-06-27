-- Kitty Hub Generic
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local env = (pcall(getgenv) and getgenv()) or _G
local hasDrawing = pcall(function() return Drawing.new("Text") end)

if hasDrawing then
    local dbg = Drawing.new("Text")
    dbg.Text = "Kitty Hub Generic loaded — Press X"
    dbg.Size = 18
    dbg.Position = Vector2.new(10, 10)
    dbg.Font = 3
    dbg.Color = Color3.new(0, 1, 0)
    dbg.Center = false
    dbg.Visible = true
    task.delay(5, function() if dbg and dbg.Remove then dbg:Remove() end end)
end

env.CatSettings = env.CatSettings or {
    ESP = {
        Enabled = false, Boxes = false, Names = false, Chams = false, Tracers = false, Distance = false
    },
    Movement = {
        SpeedEnabled = false, SpeedValue = 16,
        JumpEnabled = false, JumpValue = 50
    },
    Misc = {
        Noclip = false, NoclipKey = "N", Fly = false, FlyKey = "F"
    }
}

local S = env.CatSettings

-- Drawing-based GUI
local UI = {
    Bg = Color3.fromRGB(12, 12, 16),
    Surface = Color3.fromRGB(20, 20, 25),
    Accent = Color3.fromRGB(200, 100, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(140, 140, 150),
    Border = Color3.fromRGB(50, 48, 60)
}

local W = {
    x = 50, y = 50, w = 620, h = 420,
    show = false,
    tab = "ESP",
    tabs = {"ESP", "Movement", "Misc"},
    scroll = {},
    dragging = false,
    dragStart = Vector2.new(0, 0),
    dragWinPos = Vector2.new(0, 0)
}

for _, name in ipairs(W.tabs) do
    W.scroll[name] = 0
end

local allDrawings = {}

local FILL_STRIP_H = 28

local function NewFill(color, transparency)
    local fill = {
        _color = color or Color3.new(1, 1, 1),
        _transparency = transparency or 0,
        _lines = {},
        _visible = true
    }
    function fill:_line(i)
        while #self._lines < i do
            local l = Drawing.new("Line")
            l.Visible = false
            l.Thickness = 1
            l.Color = self._color
            l.Transparency = self._transparency
            table.insert(allDrawings, l)
            table.insert(self._lines, l)
        end
        return self._lines[i]
    end
    function fill:set(x, y, w, h)
        local count = math.max(1, math.ceil(h / FILL_STRIP_H))
        for i = 1, count do
            local l = self:_line(i)
            local sy = y + (i - 1) * FILL_STRIP_H
            local sh = math.min(h - (i - 1) * FILL_STRIP_H, FILL_STRIP_H)
            l.Visible = self._visible
            l.Color = self._color
            l.Transparency = self._transparency
            l.From = Vector2.new(x, sy + sh / 2)
            l.To = Vector2.new(x + w, sy + sh / 2)
            l.Thickness = sh
        end
        for i = count + 1, #self._lines do
            self._lines[i].Visible = false
        end
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
                for _, l in ipairs(t._lines) do l.Visible = v end
            elseif k == "Color" then
                t._color = v
                for _, l in ipairs(t._lines) do l.Color = v end
            elseif k == "Transparency" then
                t._transparency = v
                for _, l in ipairs(t._lines) do l.Transparency = v end
            end
            rawset(t, k, v)
        end
    })
end

-- Square-based outline (only for borders)
local function NewOutline(color, transparency)
    local s = Drawing.new("Square")
    s.Visible = false
    s.Filled = false
    s.Thickness = 1
    s.Color = color or Color3.new(1, 1, 1)
    s.Transparency = transparency or 0
    table.insert(allDrawings, s)
    return s
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
subTxt.Text = "generic"
local closeTxt = NewText(UI.Text, 18, false)
closeTxt.Text = "X"
local accentLine = Drawing.new("Line")
accentLine.Visible = false
accentLine.Thickness = 3
accentLine.Color = UI.Accent
accentLine.Transparency = 0
table.insert(allDrawings, accentLine)

local winBorder = NewOutline(UI.Border, 0)
winBorder.Thickness = 2

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
    stateTxt.Text = ""

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
            valTxt.Text = tostring(math.floor(ref[key] or 0))
            valTxt.Position = Vector2.new(wx + 400, cy + 7)
            local pct = math.max(0, math.min(((ref[key] or 0) - minV) / (maxV - minV), 1))
            track:set(wx + 16, cy + 36, 408, 4)
            fill.Visible = pct > 0
            fill.Color = UI.Accent
            if pct > 0 then fill:set(wx + 16, cy + 36, 408 * pct, 4) end
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
Toggle("ESP", "Chams", S.ESP, "Chams")
Toggle("ESP", "Tracers", S.ESP, "Tracers")
Toggle("ESP", "Distance", S.ESP, "Distance")

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

Toggle("Misc", "Noclip", S.Misc, "Noclip", function(v)
    if v then EnableNoclip() else DisableNoclip() end
end)
Toggle("Misc", "Fly", S.Misc, "Fly", function(v)
    if v then EnableFly() else DisableFly() end
end)
Cycle("Misc", "Noclip Key", S.Misc, "NoclipKey", {"N", "C", "G", "V", "B", "X", "Z", "F", "T", "Q", "E", "R", "Y"})
Cycle("Misc", "Fly Key", S.Misc, "FlyKey", {"F", "C", "G", "V", "B", "X", "Z", "N", "T", "Q", "E", "R", "Y"})

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
    end
    if not W.show then
        for _, d in ipairs(allDrawings) do
            d.Visible = false
        end
        tglRect.y = toggleBtnY - math.floor(tglRect.h / 2)
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
    winBorder.Visible = true
    winBorder.Position = Vector2.new(wx, wy)
    winBorder.Size = Vector2.new(W.w, W.h)
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
    local mx, my = input.Position.X, input.Position.Y
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
    local mx, my = input.Position.X, input.Position.Y
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

-- ESP System
local ESPObjects = {}
local ChamsObjects = {}
local _chamsComplete = false
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
    hl.Parent = game:GetService("CoreGui")
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

    local existing = hrp:FindFirstChildWhichIsA("BodyVelocity")
    if existing then
        FlyBodyVelocity = existing
    else
        FlyBodyVelocity = Instance.new("BodyVelocity")
        FlyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
        FlyBodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
        FlyBodyVelocity.Parent = hrp
    end

    if FlyConnection then FlyConnection:Disconnect() end
    FlyConnection = RunService.RenderStepped:Connect(function()
        if not FlyBodyVelocity or not FlyBodyVelocity.Parent then
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local existing = hrp:FindFirstChildWhichIsA("BodyVelocity")
                    if existing then
                        FlyBodyVelocity = existing
                    else
                        FlyBodyVelocity = Instance.new("BodyVelocity")
                        FlyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
                        FlyBodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
                        FlyBodyVelocity.Parent = hrp
                    end
                end
            end
            if not FlyBodyVelocity or not FlyBodyVelocity.Parent then return end
        end
        local moveDir = Vector3.new(0, 0, 0)
        local speed = 50
        local look = Camera.CFrame.LookVector
        local right = Camera.CFrame.RightVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        local flatRight = Vector3.new(right.X, 0, right.Z)

        if UserInputService:IsKeyDown(Enum.KeyCode.W) and flatLook.Magnitude > 0 then
            moveDir = moveDir + flatLook.Unit
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) and flatLook.Magnitude > 0 then
            moveDir = moveDir - flatLook.Unit
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) and flatRight.Magnitude > 0 then
            moveDir = moveDir - flatRight.Unit
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) and flatRight.Magnitude > 0 then
            moveDir = moveDir + flatRight.Unit
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
        W.show = not W.show
    end
    local nk = Enum.KeyCode[S.Misc.NoclipKey or "N"]
    local fk = Enum.KeyCode[S.Misc.FlyKey or "F"]
    if nk and input.KeyCode == nk then
        ToggleNoclip()
    end
    if fk and input.KeyCode == fk then
        ToggleFly()
    end
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera or Camera
    RenderGUI()

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

                    if S.ESP.Tracers and Camera and Camera.ViewportSize then
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
            hl.Enabled = S.ESP.Chams
            if hl.Adornee ~= player.Character then
                hl.Adornee = player.Character
            end
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
