-- MM2 Aimbot & ESP — Kitty Hub (v7: native Roblox UI, Xeno-compatible)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local env = (pcall(getgenv) and getgenv()) or _G

-- Drawing is still used for in-world ESP/gun text. Xeno renders Drawing TEXT
-- fine; only filled shapes/thick lines are unsupported, which is exactly why
-- the MENU is now built from native Roblox GUI instead of the Drawing API.
local hasDrawing = pcall(function() local d = Drawing.new("Text"); if d and d.Remove then d:Remove() end end)

env.CatSettings = env.CatSettings or {
    ESP = { Enabled = false, Names = false, Roles = false, Chams = false, Distance = false,
            MaxDistance = 1000, Boxes = false, Tracers = false },
    Aimbot = { Enabled = true, AutoShoot = false, AimbotKey = "C", Prediction = false,
               LeadTime = 0.15, AimPart = "Head", OffScreen = true, AutoUnequip = false, Debug = false },
    MM2 = { GunESP = false, Noclip = false, NoclipKey = "N", AutoCollect = false },
    Movement = { SpeedEnabled = false, SpeedValue = 16, JumpEnabled = false, JumpValue = 50 }
}

local S = env.CatSettings
-- Backfill defaults for users whose CatSettings was cached by an older run
S.ESP = S.ESP or {}; S.Aimbot = S.Aimbot or {}; S.MM2 = S.MM2 or {}; S.Movement = S.Movement or {}
if S.Aimbot.Enabled == nil then S.Aimbot.Enabled = true end
if S.Aimbot.OffScreen == nil then S.Aimbot.OffScreen = true end
if S.Aimbot.AimbotKey == nil then S.Aimbot.AimbotKey = "C" end
if S.Aimbot.AimPart == nil then S.Aimbot.AimPart = "Head" end
if S.Aimbot.LeadTime == nil then S.Aimbot.LeadTime = 0.15 end
if S.Aimbot.Debug == nil then S.Aimbot.Debug = false end
if S.MM2.NoclipKey == nil then S.MM2.NoclipKey = "N" end
if S.ESP.MaxDistance == nil then S.ESP.MaxDistance = 1000 end
if S.Movement.SpeedValue == nil then S.Movement.SpeedValue = 16 end
if S.Movement.JumpValue == nil then S.Movement.JumpValue = 50 end

local tableFind = table.find or function(t, v)
    for i, x in pairs(t) do if x == v then return i end end
end

----------------------------------------------------------------------
-- Role detection
----------------------------------------------------------------------
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
    local char = player.Character
    if char then
        char.ChildAdded:Connect(function() RoleCache[player] = nil end)
    end
end

local function OnPlayerAdded(player)
    player.CharacterAdded:Connect(function() OnCharacterAdded(player) end)
    local bp = player:FindFirstChild("Backpack")
    if bp then
        bp.ChildAdded:Connect(function() RoleCache[player] = nil end)
    end
    player.ChildAdded:Connect(function(child)
        if child.Name == "Backpack" then
            child.ChildAdded:Connect(function() RoleCache[player] = nil end)
        end
    end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then OnPlayerAdded(player) end
end

----------------------------------------------------------------------
-- Aimbot
----------------------------------------------------------------------
local setAimStatus = function() end -- assigned once the UI exists

local lastShot = 0
local FIRE_INTERVAL = 0.1
local aimbotActive = false
local aimbotKeyHeld = false
local aimbotKeyCode = nil

local function GetMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            if GetPlayerRole(player) == "Murderer" then return player end
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char and char:FindFirstChild("Knife") then
                RoleCache[player] = "Murderer"; return player
            end
            local bp = player:FindFirstChild("Backpack")
            if bp and bp:FindFirstChild("Knife") then
                RoleCache[player] = "Murderer"; return player
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
            if child:IsA("RemoteEvent") then remote = child; break end
        end
    end
    if remote and not remote:IsA("RemoteEvent") then remote = nil end
    RemoteCache[gun] = remote
    return remote
end

local function InvalidateRemoteCache(gun) RemoteCache[gun] = nil end

local function GetAimPart(character)
    if not character then return nil end
    local part = character:FindFirstChild(S.Aimbot.AimPart)
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
    if gun.Parent == char then return gun end -- already in hand, don't re-equip
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:EquipTool(gun) end) end
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
    local ok = pcall(function() remote:FireServer(targetPos, part) end)
    if not ok then
        pcall(function() remote:FireServer(targetPos) end)
    end
    return true
end

local function ExecuteAimbot()
    if not S.Aimbot.Enabled then aimbotActive = false; return end
    local gun = FindGun()
    if not gun then
        aimbotActive = false
        setAimStatus("no gun in your inventory", Color3.fromRGB(255, 120, 120))
        return
    end
    local murderer = GetMurderer()
    if not murderer or not murderer.Character then
        aimbotActive = false
        setAimStatus("no murderer found yet", Color3.fromRGB(255, 185, 90))
        return
    end
    if not S.Aimbot.OffScreen then
        local part = GetAimPart(murderer.Character)
        if part then
            local _, onScreen = Camera:WorldToViewportPoint(part.Position)
            if not onScreen then
                aimbotActive = false
                setAimStatus("murderer off-screen (enable Off-Screen Aim)", Color3.fromRGB(255, 185, 90))
                return
            end
        end
    end
    aimbotActive = true
    local fired = ShootMurderer(murderer, gun)
    if fired then
        setAimStatus("fired at " .. murderer.Name, Color3.fromRGB(120, 230, 150))
    else
        setAimStatus("found gun + murderer, but no fire remote on the gun", Color3.fromRGB(255, 120, 120))
    end
    if fired and S.Aimbot.AutoUnequip then UnequipGun() end
end

local function StopAimbot() aimbotActive = false end

----------------------------------------------------------------------
-- Movement / Noclip
----------------------------------------------------------------------
local function ApplyMovementSettings(char)
    char = char or LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    hum.WalkSpeed = S.Movement.SpeedEnabled and S.Movement.SpeedValue or 16
    hum.JumpPower = S.Movement.JumpEnabled and S.Movement.JumpValue or 50
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    ApplyMovementSettings(char)
end)
if LocalPlayer.Character then ApplyMovementSettings() end

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
    S.MM2.Noclip = not S.MM2.Noclip
    if S.MM2.Noclip then EnableNoclip() else DisableNoclip() end
end

----------------------------------------------------------------------
-- Auto Collect (teleport to dropped gun)
----------------------------------------------------------------------
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

local AutoCollectThrottle = 0
local function DoAutoCollect()
    local now = tick()
    if now - AutoCollectThrottle < 0.3 then return end
    AutoCollectThrottle = now
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local nearestGun, nearestPart, nearestDist = nil, nil, math.huge
    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if IsGunDrop(obj) then
                local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if handle then
                    local dist = (handle.Position - hrp.Position).Magnitude
                    if dist < nearestDist then
                        nearestDist = dist; nearestGun = obj; nearestPart = handle
                    end
                end
            end
            if obj:IsA("Model") or obj:IsA("Folder") then scan(obj) end
        end
    end
    scan(workspace)

    if HasSheriffGun(char) and nearestDist <= 3 then return end
    if nearestGun and nearestPart then
        local targetPos = nearestPart.Position + Vector3.new(0, 3, 0)
        if nearestDist > 5 then hrp.CFrame = CFrame.new(targetPos) end
        if nearestDist <= 20 then
            local gun = FindGun()
            if gun then
                local hum = char:FindFirstChild("Humanoid")
                if hum then pcall(function() hum:EquipTool(gun) end) end
            end
        end
    end
end

----------------------------------------------------------------------
-- In-world ESP (Drawing text/lines + Highlight chams)
----------------------------------------------------------------------
local ESPObjects = {}
local ChamsObjects = {}
local _chamsComplete = false

local function CreateESP(player)
    if player == LocalPlayer or not hasDrawing then return end
    local boxLines = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Visible = false; l.Thickness = 2; l.Color = Color3.new(1, 1, 1); l.Transparency = 0
        table.insert(boxLines, l)
    end
    local objs = {
        Box = boxLines,
        Name = Drawing.new("Text"),
        Role = Drawing.new("Text"),
        Tracer = Drawing.new("Line")
    }
    objs.Name.Visible = false; objs.Name.Size = 14; objs.Name.Center = true; objs.Name.Font = 2
    objs.Role.Visible = false; objs.Role.Size = 13; objs.Role.Center = true; objs.Role.Font = 2
    objs.Tracer.Visible = false; objs.Tracer.Thickness = 1.5; objs.Tracer.Transparency = 0.6
    ESPObjects[player] = objs
end

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
            if S.ESP.Chams then CreateChams(player) end
        end)
    end
end)

----------------------------------------------------------------------
-- Gun ESP (yellow in-world label on dropped guns)
----------------------------------------------------------------------
local GunESPObjects = {}
local function UpdateGunESP()
    if not S.MM2.GunESP or not hasDrawing then
        for _, text in pairs(GunESPObjects) do pcall(function() text:Remove() end) end
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
                        text.Color = Color3.fromRGB(255, 215, 0) -- yellow
                        text.Center = true
                        text.Font = 2
                        GunESPObjects[obj] = text
                    end
                end
            end
            if obj:IsA("Model") or obj:IsA("Folder") then scan(obj) end
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

----------------------------------------------------------------------
-- Native UI (ScreenGui — renders correctly on Xeno)
----------------------------------------------------------------------
local COL = {
    Bg = Color3.fromRGB(22, 23, 31), Header = Color3.fromRGB(29, 31, 42), Sidebar = Color3.fromRGB(25, 27, 37),
    Card = Color3.fromRGB(34, 36, 49), CardHover = Color3.fromRGB(45, 48, 66),
    Accent = Color3.fromRGB(124, 152, 255), AccentDim = Color3.fromRGB(66, 84, 160),
    Text = Color3.fromRGB(237, 239, 247), TextDim = Color3.fromRGB(142, 146, 167),
    Stroke = Color3.fromRGB(48, 51, 71), On = Color3.fromRGB(86, 214, 140), OffTrack = Color3.fromRGB(58, 61, 82)
}

local function mk(class, props, children)
    local o = Instance.new(class)
    if props then for k, v in pairs(props) do o[k] = v end end
    if children then for _, c in ipairs(children) do c.Parent = o end end
    return o
end
local function uicorner(r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end
local function uistroke(c, t) return mk("UIStroke", { Color = c or COL.Stroke, Thickness = t or 1 }) end

local guiParent
do
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then
        guiParent = hui
    else
        local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
        guiParent = (ok2 and cg) or LocalPlayer:WaitForChild("PlayerGui")
    end
end
pcall(function()
    local old = guiParent:FindFirstChild("KittyHubUI")
    if old then old:Destroy() end
end)

local Gui = mk("ScreenGui", {
    Name = "KittyHubUI", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999, Parent = guiParent
})

local Window = mk("Frame", {
    Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(560, 420), BackgroundColor3 = COL.Bg, BorderSizePixel = 0, Active = true, Visible = true, Parent = Gui
}, { uicorner(10), uistroke(COL.Stroke, 1) })

local Header = mk("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = COL.Header, BorderSizePixel = 0, Parent = Window }, { uicorner(10) })
mk("Frame", { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = COL.Header, BorderSizePixel = 0, Parent = Header })
mk("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL.Accent, BorderSizePixel = 0, Parent = Header })
mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 160, 1, 0),
    Font = Enum.Font.GothamBold, Text = "Kitty Hub", TextSize = 18, TextColor3 = COL.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header })
mk("TextLabel", { BackgroundColor3 = COL.Accent, Position = UDim2.fromOffset(126, 14), Size = UDim2.fromOffset(42, 18),
    Font = Enum.Font.GothamBold, Text = "MM2", TextSize = 11, TextColor3 = Color3.new(1, 1, 1), Parent = Header }, { uicorner(5) })

local CloseBtn = mk("TextButton", { BackgroundTransparency = 1, Position = UDim2.new(1, -42, 0, 0), Size = UDim2.fromOffset(42, 44),
    Font = Enum.Font.GothamBold, Text = "X", TextSize = 17, TextColor3 = COL.TextDim, AutoButtonColor = false, Parent = Header })
CloseBtn.MouseEnter:Connect(function() CloseBtn.TextColor3 = Color3.fromRGB(255, 95, 95) end)
CloseBtn.MouseLeave:Connect(function() CloseBtn.TextColor3 = COL.TextDim end)
CloseBtn.MouseButton1Click:Connect(function() Window.Visible = false end)

local Sidebar = mk("Frame", { Name = "Sidebar", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(0, 138, 1, -44), BackgroundColor3 = COL.Sidebar, BorderSizePixel = 0, Parent = Window })
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = Sidebar })
mk("UIPadding", { PaddingTop = UDim.new(0, 10), Parent = Sidebar })

local Content = mk("Frame", { Name = "Content", Position = UDim2.fromOffset(138, 44), Size = UDim2.new(1, -138, 1, -44), BackgroundTransparency = 1, Parent = Window })

local pages, tabButtons = {}, {}
local activeTabName = nil
local function selectTab(name)
    activeTabName = name
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, btn in pairs(tabButtons) do
        local active = (n == name)
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = active and 0 or 1 }):Play()
        btn.TextColor3 = active and Color3.new(1, 1, 1) or COL.TextDim
    end
end

for i, name in ipairs({"ESP", "Aimbot", "MM2", "Movement"}) do
    local btn = mk("TextButton", { Name = name, Size = UDim2.new(1, -14, 0, 34), BackgroundColor3 = COL.Accent, BackgroundTransparency = 1,
        BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamMedium, Text = name, TextSize = 14, TextColor3 = COL.TextDim, LayoutOrder = i, Parent = Sidebar }, { uicorner(7) })
    tabButtons[name] = btn
    local page = mk("ScrollingFrame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = COL.Accent, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = Content })
    mk("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
    mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), Parent = page })
    pages[name] = page
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    btn.MouseEnter:Connect(function() if activeTabName ~= name then TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.82 }):Play() end end)
    btn.MouseLeave:Connect(function() if activeTabName ~= name then TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play() end end)
end

local function hoverify(frame)
    frame.MouseEnter:Connect(function() TweenService:Create(frame, TweenInfo.new(0.12), { BackgroundColor3 = COL.CardHover }):Play() end)
    frame.MouseLeave:Connect(function() TweenService:Create(frame, TweenInfo.new(0.12), { BackgroundColor3 = COL.Card }):Play() end)
end

local function Toggle(tab, label, ref, key, callback)
    local row = mk("TextButton", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = COL.Card, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = pages[tab] }, { uicorner(8) })
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 1, 0),
        Font = Enum.Font.GothamMedium, Text = label, TextSize = 14, TextColor3 = COL.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
    local track = mk("Frame", { Position = UDim2.new(1, -58, 0.5, -11), Size = UDim2.fromOffset(44, 22), BackgroundColor3 = COL.OffTrack, BorderSizePixel = 0, Parent = row }, { uicorner(11) })
    local knob = mk("Frame", { Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track }, { uicorner(8) })
    hoverify(row)
    local function refresh(v, anim)
        local ti = TweenInfo.new(anim and 0.15 or 0, Enum.EasingStyle.Quad)
        TweenService:Create(track, ti, { BackgroundColor3 = v and COL.On or COL.OffTrack }):Play()
        TweenService:Create(knob, ti, { Position = v and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3) }):Play()
    end
    refresh(ref[key] and true or false, false)
    row.MouseButton1Click:Connect(function()
        ref[key] = not ref[key]
        refresh(ref[key] and true or false, true)
        if callback then callback(ref[key]) end
    end)
end

local function Slider(tab, label, ref, key, minV, maxV, callback)
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = COL.Card, BorderSizePixel = 0, Parent = pages[tab] }, { uicorner(8) })
    hoverify(row)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -70, 0, 18),
        Font = Enum.Font.GothamMedium, Text = label, TextSize = 14, TextColor3 = COL.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
    local valLbl = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(1, -54, 0, 8), Size = UDim2.fromOffset(40, 18),
        Font = Enum.Font.GothamBold, Text = "", TextSize = 14, TextColor3 = COL.Accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
    local track = mk("Frame", { Position = UDim2.new(0, 14, 0, 36), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = COL.OffTrack, BorderSizePixel = 0, Active = true, Parent = row }, { uicorner(3) })
    local fill = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COL.Accent, BorderSizePixel = 0, Parent = track }, { uicorner(3) })
    local knob = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track }, { uicorner(7) })
    local function apply(a)
        a = math.clamp(a, 0, 1)
        local val = math.floor(minV + (maxV - minV) * a + 0.5)
        ref[key] = val
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        valLbl.Text = tostring(val)
        if callback then callback(val) end
    end
    apply(((tonumber(ref[key]) or minV) - minV) / math.max(maxV - minV, 1))
    local dragging = false
    local function fromInput(input)
        apply((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true; fromInput(input) end
    end)
    track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then fromInput(input) end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function Dropdown(tab, label, ref, key, options, callback)
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = COL.Card, BorderSizePixel = 0, Parent = pages[tab] }, { uicorner(8) })
    hoverify(row)
    mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0),
        Font = Enum.Font.GothamMedium, Text = label, TextSize = 14, TextColor3 = COL.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
    local btn = mk("TextButton", { Position = UDim2.new(1, -96, 0.5, -13), Size = UDim2.fromOffset(84, 26), BackgroundColor3 = COL.AccentDim,
        BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = tostring(ref[key]), TextSize = 13, TextColor3 = COL.Text, Parent = row }, { uicorner(6) })
    local idx = 1
    for i, o in ipairs(options) do if o == ref[key] then idx = i; break end end
    btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = COL.Accent }):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = COL.AccentDim }):Play() end)
    btn.MouseButton1Click:Connect(function()
        idx = (idx % #options) + 1
        ref[key] = options[idx]
        btn.Text = tostring(ref[key])
        if callback then callback(ref[key]) end
    end)
end

-- ESP tab
Toggle("ESP", "Enabled", S.ESP, "Enabled")
Toggle("ESP", "Names", S.ESP, "Names")
Toggle("ESP", "Roles", S.ESP, "Roles")
Toggle("ESP", "Chams", S.ESP, "Chams")
Toggle("ESP", "Distance", S.ESP, "Distance")
Toggle("ESP", "Gun ESP (yellow)", S.MM2, "GunESP")

-- Aimbot tab
Toggle("Aimbot", "Enabled", S.Aimbot, "Enabled")
Toggle("Aimbot", "Auto Shoot", S.Aimbot, "AutoShoot")
Toggle("Aimbot", "Prediction", S.Aimbot, "Prediction")
Toggle("Aimbot", "Off-Screen Aim", S.Aimbot, "OffScreen")
Toggle("Aimbot", "Auto Unequip", S.Aimbot, "AutoUnequip")
Toggle("Aimbot", "Debug (show status)", S.Aimbot, "Debug")
Dropdown("Aimbot", "Aimbot Key", S.Aimbot, "AimbotKey", {"C", "G", "V", "B", "X", "Z", "F", "T", "Q", "E", "R", "Y"})

-- MM2 tab
Toggle("MM2", "Noclip", S.MM2, "Noclip", function(v) if v then EnableNoclip() else DisableNoclip() end end)
Toggle("MM2", "Auto Collect", S.MM2, "AutoCollect")
Dropdown("MM2", "Noclip Key", S.MM2, "NoclipKey", {"N", "C", "G", "V", "B", "X", "Z", "F", "T", "Q", "E", "R", "Y"})

-- Movement tab
Toggle("Movement", "Speed Hack", S.Movement, "SpeedEnabled", function() ApplyMovementSettings() end)
Slider("Movement", "Speed", S.Movement, "SpeedValue", 16, 100, function() ApplyMovementSettings() end)
Toggle("Movement", "Jump Hack", S.Movement, "JumpEnabled", function() ApplyMovementSettings() end)
Slider("Movement", "Jump Power", S.Movement, "JumpValue", 50, 200, function() ApplyMovementSettings() end)

selectTab("ESP")

-- Floating launcher button
local Launcher = mk("TextButton", { Name = "Launcher", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18),
    Size = UDim2.fromOffset(50, 50), BackgroundColor3 = COL.Accent, BorderSizePixel = 0, AutoButtonColor = false,
    Font = Enum.Font.GothamBold, Text = "K", TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Parent = Gui }, { uicorner(25), uistroke(Color3.new(1, 1, 1), 1) })
Launcher.MouseButton1Click:Connect(function() Window.Visible = not Window.Visible end)

-- Aimbot status toast (only shows when Aimbot > Debug is on)
local AimStatus = mk("TextLabel", { Name = "AimStatus", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -76),
    Size = UDim2.fromOffset(380, 28), BackgroundColor3 = Color3.fromRGB(20, 21, 28), BackgroundTransparency = 0.1, BorderSizePixel = 0,
    Font = Enum.Font.GothamMedium, Text = "", TextSize = 14, TextColor3 = COL.Text, Visible = false, Parent = Gui }, { uicorner(8), uistroke(COL.Stroke, 1) })
local aimStatusToken = 0
setAimStatus = function(msg, color)
    if not S.Aimbot.Debug then AimStatus.Visible = false; return end
    AimStatus.Text = "Aimbot: " .. msg
    AimStatus.TextColor3 = color or COL.Text
    AimStatus.Visible = true
    aimStatusToken = aimStatusToken + 1
    local my = aimStatusToken
    task.delay(1.4, function() if my == aimStatusToken then AimStatus.Visible = false end end)
end

-- Draggable window (via header)
do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = Window.Position
        end
    end)
    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            Window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

----------------------------------------------------------------------
-- Keybinds
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.X then
        Window.Visible = not Window.Visible
    end
    local nk = Enum.KeyCode[S.MM2.NoclipKey or "N"]
    if nk and input.KeyCode == nk then ToggleNoclip() end
    local keyCode = Enum.KeyCode[S.Aimbot.AimbotKey]
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

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
local lastCacheClear = 0
RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera or Camera

    local now = tick()
    if now - lastCacheClear > 2 then
        RoleCache = {}
        lastCacheClear = now
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

                if S.ESP.MaxDistance and dist > S.ESP.MaxDistance then onScreen = false end

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
                    if player.Character then CreateChams(player) end
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
                if hl.Adornee ~= player.Character then hl.Adornee = player.Character end
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
        for _, text in pairs(GunESPObjects) do text.Visible = false end
    end

    if S.MM2.AutoCollect then DoAutoCollect() end

    local aimbotKeyEnum = Enum.KeyCode[S.Aimbot.AimbotKey]
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
end)

----------------------------------------------------------------------
-- Player tracking
----------------------------------------------------------------------
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        CreateESP(player)
        player.CharacterAdded:Connect(function() OnCharacterAdded(player) end)
        if player.Character and S.ESP.Chams then CreateChams(player) end
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then CreateESP(player) end
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

print("Kitty Hub v7 (MM2) Loaded! Native UI.")
print("[X] = toggle menu | [" .. (S.MM2.NoclipKey or "N") .. "] = Noclip | [" .. S.Aimbot.AimbotKey .. "] = Auto Aim")
