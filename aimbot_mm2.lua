-- MM2 Aimbot & ESP
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Settings
getgenv().CatSettings = {
    ESP = {
        Enabled = true,
        Boxes = true,
        Names = true,
        Roles = true,
        Chams = true,
        MaxDistance = 1000
    },
    Aimbot = {
        AutoShoot = true,
        AimbotKey = "C"
    },
    MM2 = {
        GunESP = true,
        Noclip = false,
        NoclipKey = "N"
    }
}

-- Role Detection
local RoleCache = {}

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

-- GUI Setup
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MM2Hub"
ScreenGui.Parent = game:GetService("CoreGui")
ScreenGui.ResetOnSpawn = false

local UI = {
    Background = Color3.fromRGB(20, 20, 28),
    Surface = Color3.fromRGB(30, 30, 40),
    Accent = Color3.fromRGB(200, 100, 255),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(150, 150, 150)
}

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 350)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -175)
MainFrame.BackgroundColor3 = UI.Background
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Text = "KAT MM2 Hub"
Title.TextColor3 = UI.Accent
Title.TextSize = 20
Title.Font = Enum.Font.GothamBold
Title.BackgroundTransparency = 1

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0.02, 0, 0.5, -25)
ToggleBtn.BackgroundColor3 = UI.Accent
ToggleBtn.Text = "KAT"
ToggleBtn.TextSize = 18
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextColor3 = UI.Text
ToggleBtn.Parent = ScreenGui

Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)

ToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

local CloseBtn = Instance.new("TextButton", MainFrame)
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -35, 0, 5)
CloseBtn.BackgroundColor3 = UI.Surface
CloseBtn.Text = "X"
CloseBtn.TextColor3 = UI.Text
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14

Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Toggle helper
local function CreateToggle(name, yPos, settingRef, settingName, callback)
    local frame = Instance.new("Frame", MainFrame)
    frame.Size = UDim2.new(1, -20, 0, 35)
    frame.Position = UDim2.new(0, 10, 0, 50 + yPos)
    frame.BackgroundColor3 = UI.Surface
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = name
    label.TextColor3 = UI.Text
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left

    local indicator = Instance.new("Frame", frame)
    indicator.Size = UDim2.new(0, 12, 0, 12)
    indicator.Position = UDim2.new(1, -25, 0.5, -6)
    indicator.BackgroundColor3 = settingRef[settingName] and UI.Accent or UI.TextDim
    indicator.BorderSizePixel = 0
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            settingRef[settingName] = not settingRef[settingName]
            indicator.BackgroundColor3 = settingRef[settingName] and UI.Accent or UI.TextDim
            if callback then callback(settingRef[settingName]) end
        end
    end)
end

CreateToggle("ESP Enabled", 0, CatSettings.ESP, "Enabled")
CreateToggle("Box ESP", 40, CatSettings.ESP, "Boxes")
CreateToggle("Name ESP", 80, CatSettings.ESP, "Names")
CreateToggle("Chams", 120, CatSettings.ESP, "Chams")
CreateToggle("Gun ESP", 160, CatSettings.MM2, "GunESP")
CreateToggle("Auto Shoot", 200, CatSettings.Aimbot, "AutoShoot")
CreateToggle("Noclip (N)", 240, CatSettings.MM2, "Noclip", function(v)
    if v then EnableNoclip() else DisableNoclip() end
end)

-- ESP System
local ESPObjects = {}
local ChamsObjects = {}

local function CreateESP(player)
    if player == LocalPlayer then return end
    local objs = {
        Box = Drawing.new("Square"),
        Name = Drawing.new("Text"),
        Role = Drawing.new("Text")
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
    if not CatSettings.MM2.GunESP then return end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "GunDrop" and obj:FindFirstChild("Handle") then
            local text = Drawing.new("Text")
            text.Text = "[GUN]"
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

local function GetMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and GetPlayerRole(player) == "Murderer" then
            return player
        end
    end
    return nil
end

local function EquipGun()
    local char = LocalPlayer.Character
    if not char then return false end
    local gun = char:FindFirstChild("Gun")
    if gun then return true end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        gun = bp:FindFirstChild("Gun")
        if gun then
            local hum = char:FindFirstChild("Humanoid")
            if hum then hum:EquipTool(gun); return true end
        end
    end
    return false
end

local function ShootAtMurderer()
    local murderer = GetMurderer()
    if not murderer or not murderer.Character then return false end
    local target = murderer.Character:FindFirstChild("Head") or murderer.Character:FindFirstChild("HumanoidRootPart")
    if not target then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local gun = char:FindFirstChild("Gun")
    if not gun then return false end
    pcall(function()
        if gun:FindFirstChild("Shoot") then
            gun.Shoot:FireServer(target.Position, target)
        elseif gun:FindFirstChild("Fire") then
            gun.Fire:FireServer(target.Position, target)
        else
            local remote = gun:FindFirstChildOfClass("RemoteEvent")
            if remote then remote:FireServer(target.Position, target) end
        end
    end)
    return true
end

local function AutoAim()
    if not EquipGun() then return end
    ShootAtMurderer()
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
    if CatSettings.MM2.Noclip then
        CatSettings.MM2.Noclip = false
        DisableNoclip()
    else
        CatSettings.MM2.Noclip = true
        EnableNoclip()
    end
end

-- Keybinds
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.X then
        MainFrame.Visible = not MainFrame.Visible
    elseif input.KeyCode == Enum.KeyCode.N then
        ToggleNoclip()
    end
    local key = CatSettings.Aimbot.AimbotKey
    local keyCode = Enum.KeyCode[key]
    if keyCode and input.KeyCode == keyCode then
        AutoAim()
    end
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    -- ESP
    if CatSettings.ESP.Enabled then
        for player, objs in pairs(ESPObjects) do
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                local role = GetPlayerRole(player)
                local color = RoleColors[role]

                if onScreen then
                    if CatSettings.ESP.Boxes then
                        objs.Box.Visible = true
                        objs.Box.Position = Vector2.new(pos.X - 25, pos.Y - 35)
                        objs.Box.Size = Vector2.new(50, 70)
                        objs.Box.Color = color
                    else
                        objs.Box.Visible = false
                    end
                    if CatSettings.ESP.Names then
                        objs.Name.Visible = true
                        objs.Name.Position = Vector2.new(pos.X, pos.Y - 45)
                        objs.Name.Text = player.Name
                        objs.Name.Color = color
                    else
                        objs.Name.Visible = false
                    end
                    if CatSettings.ESP.Roles then
                        objs.Role.Visible = true
                        objs.Role.Position = Vector2.new(pos.X, pos.Y + 35)
                        objs.Role.Text = role
                        objs.Role.Color = color
                    else
                        objs.Role.Visible = false
                    end
                else
                    objs.Box.Visible = false
                    objs.Name.Visible = false
                    objs.Role.Visible = false
                end
            else
                objs.Box.Visible = false
                objs.Name.Visible = false
                objs.Role.Visible = false
            end
        end
    else
        for _, objs in pairs(ESPObjects) do
            objs.Box.Visible = false
            objs.Name.Visible = false
            objs.Role.Visible = false
        end
    end

    -- Chams
    if CatSettings.ESP.Chams then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and not ChamsObjects[player] then
                CreateChams(player)
            end
        end
    end
    for player, hl in pairs(ChamsObjects) do
        if player and player.Character then
            if CatSettings.ESP.Chams then
                hl.Enabled = true
                hl.Adornee = player.Character
                hl.FillColor = RoleColors[GetPlayerRole(player)]
            else
                hl.Enabled = false
            end
        end
    end

    -- Gun ESP
    if CatSettings.MM2.GunESP then
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

    -- Auto Shoot
    if CatSettings.Aimbot.AutoShoot then
        local now = tick()
        if now - lastShot > 0.5 then
            lastShot = now
            AutoAim()
        end
    end
end)

-- Player tracking
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then CreateESP(player) end
end
Players.PlayerAdded:Connect(function(player) CreateESP(player) end)
Players.PlayerRemoving:Connect(function(player)
    if ESPObjects[player] then
        for _, objs in pairs(ESPObjects[player]) do objs:Remove() end
        ESPObjects[player] = nil
    end
    if ChamsObjects[player] then
        ChamsObjects[player]:Destroy()
        ChamsObjects[player] = nil
    end
    RoleCache[player] = nil
end)

print("MM2 Hub Loaded!")
print("Press X = GUI")
print("Press N = Noclip")
print("Press " .. CatSettings.Aimbot.AimbotKey .. " = Auto Aim")
