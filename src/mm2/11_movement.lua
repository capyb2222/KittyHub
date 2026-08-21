-- ============================================================================
--  MOVEMENT — speed, jump, noclip, fly, spinbot, teleports, waypoints
-- ============================================================================

do
    local UI               = KH.UI
    local U                = KH.U
    local Game             = KH.Game
    local S                = KH.S
    local X                = KH.X
    local UserInputService = KH.Services.UserInputService
    local RunService       = KH.Services.RunService
    local HttpService      = KH.Services.HttpService
    local LocalPlayer      = KH.LocalPlayer

    local Move = {}
    KH.Move = Move

    -- ======================================================== SPEED / JUMP
    -- Re-applied continuously because MM2 resets WalkSpeed on respawn and when
    -- rounds change; a one-shot assignment silently stops working.
    function Move.applyHumanoid()
        local hum = U.myHum()
        if not hum then return end
        if S.Move.SpeedEnabled and S.Move.SpeedMode == "Humanoid" then
            if hum.WalkSpeed ~= S.Move.Speed then hum.WalkSpeed = S.Move.Speed end
        elseif hum.WalkSpeed ~= 16 and not S.Move.SpeedEnabled then
            hum.WalkSpeed = 16
        end

        -- R15 humanoids may be driven by JumpHeight rather than JumpPower;
        -- writing only JumpPower would silently do nothing on those.
        if S.Move.JumpEnabled then
            if hum.UseJumpPower then
                if hum.JumpPower ~= S.Move.Jump then hum.JumpPower = S.Move.Jump end
            else
                local height = S.Move.Jump / 7.5
                if math.abs(hum.JumpHeight - height) > 0.01 then hum.JumpHeight = height end
            end
        else
            if hum.UseJumpPower then
                if hum.JumpPower ~= 50 then hum.JumpPower = 50 end
            elseif math.abs(hum.JumpHeight - 7.2) > 0.01 then
                hum.JumpHeight = 7.2
            end
        end
    end

    -- CFrame mode drives the character directly, which ignores any server-side
    -- WalkSpeed clamp — at the cost of looking less natural.
    KH.onFrame("speed-cframe", function(delta)
        if not (S.Move.SpeedEnabled and S.Move.SpeedMode == "CFrame") then return end
        if S.Move.Fly then return end
        local hum, root = U.myHum(), U.myRoot()
        if not hum or not root then return end
        local direction = hum.MoveDirection
        if direction.Magnitude < 0.05 then return end
        -- delta comes from the shared render loop; never yield in here.
        root.CFrame = root.CFrame + direction * (S.Move.Speed - 16) * (delta or 0)
    end, 60)

    KH.loop(0.4, function() Move.applyHumanoid() end)

    -- ============================================================== NOCLIP
    -- Original collision states are recorded so disabling noclip restores the
    -- character exactly, rather than blanket-setting everything collidable.
    local noclipOriginal = {}
    local noclipConn

    local function noclipStep()
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                if noclipOriginal[part] == nil then noclipOriginal[part] = true end
                part.CanCollide = false
            end
        end
    end

    function Move.setNoclip(on)
        S.Move.Noclip = on
        if on then
            if not noclipConn then
                noclipConn = RunService.Stepped:Connect(noclipStep)
                KH.track(noclipConn)
            end
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
            for part, wasCollidable in pairs(noclipOriginal) do
                if part.Parent and wasCollidable then
                    pcall(function() part.CanCollide = true end)
                end
            end
            noclipOriginal = {}
        end
        UI.refreshKeybinds()
    end
    KH.undo(function() Move.setNoclip(false) end)

    -- ================================================== INFINITE JUMP / BHOP
    KH.track(UserInputService.JumpRequest:Connect(function()
        if not S.Move.InfJump then return end
        local hum = U.myHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end))

    KH.onFrame("bhop", function()
        if not S.Move.Bhop then return end
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
        local hum = U.myHum()
        if not hum then return end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.Landed
            or state == Enum.HumanoidStateType.RunningNoPhysics then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end, 62)

    -- ================================================================= FLY
    local flyVelocity, flyGyro
    local flying = false

    local function stopFly()
        flying = false
        if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
        if flyGyro then flyGyro:Destroy(); flyGyro = nil end
        local hum = U.myHum()
        if hum then hum.PlatformStand = false end
    end

    local function startFly()
        local root, hum = U.myRoot(), U.myHum()
        if not root or not hum then return false end
        stopFly()

        flyVelocity = Instance.new("BodyVelocity")
        flyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyVelocity.Velocity = Vector3.zero
        flyVelocity.Parent = root

        flyGyro = Instance.new("BodyGyro")
        flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyGyro.P = 9e4
        flyGyro.CFrame = root.CFrame
        flyGyro.Parent = root

        hum.PlatformStand = true
        flying = true
        return true
    end

    function Move.setFly(on)
        S.Move.Fly = on
        if on then
            if not startFly() then
                S.Move.Fly = false
                UI.notify({title = "Fly", text = "No character to attach to.", kind = "bad"})
            end
        else
            stopFly()
        end
        UI.refreshKeybinds()
    end
    KH.undo(function() stopFly() end)

    KH.onFrame("fly", function()
        if not S.Move.Fly then
            if flying then stopFly() end
            return
        end
        if not flying or not flyVelocity or not flyVelocity.Parent then
            if not startFly() then return end
        end

        local cam = KH.camera()
        local direction = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction = direction - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction = direction + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then direction = direction - Vector3.new(0, 1, 0) end

        if direction.Magnitude > 0 then direction = direction.Unit end
        flyVelocity.Velocity = direction * S.Move.FlySpeed
        flyGyro.CFrame = cam.CFrame
    end, 61)

    -- ============================================================= SPINBOT
    KH.onFrame("spinbot", function()
        if not S.Move.Spinbot then return end
        local root = U.myRoot()
        if not root then return end
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(28), 0)
    end, 63)

    -- Respawns wipe all of this, so reapply once the new character settles.
    KH.track(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.6)
        Move.applyHumanoid()
        if S.Move.Noclip then Move.setNoclip(true) end
        if S.Move.Fly then Move.setFly(true) end
    end))

    -- =========================================================== TELEPORTS
    local function tpTo(position, label)
        if not U.myRoot() then
            UI.notify({title = "Teleport", text = "No character.", kind = "bad"})
            return false
        end
        U.moveTo(position + Vector3.new(0, 3, 0), true)
        if label then UI.notify({title = "Teleport", text = label, duration = 2}) end
        return true
    end
    Move.tpTo = tpTo

    local function tpToPlayer(player, label)
        if not player then
            UI.notify({title = "Teleport", text = "Nobody to teleport to.", kind = "warn"})
            return false
        end
        local part = U.rootOf(player)
        if not part then
            UI.notify({title = "Teleport", text = player.DisplayName .. " has no character.", kind = "warn"})
            return false
        end
        return tpTo(part.Position, label or ("Moved to " .. player.DisplayName))
    end
    Move.tpToPlayer = tpToPlayer

    function Move.tpMurderer() return tpToPlayer(Game.murdererPlayer(), "Moved to the murderer.") end
    function Move.tpSheriff()  return tpToPlayer(Game.sheriffPlayer(), "Moved to the sheriff.") end

    function Move.tpGunDrop()
        local drop = Game.GunDrop
        if not drop or not drop.Parent then
            UI.notify({title = "Teleport", text = "No dropped gun right now.", kind = "warn"})
            return false
        end
        return tpTo(drop.Position, "Moved to the dropped gun.")
    end

    function Move.tpCoin()
        local coin = Game.nearestCoin()
        if not coin then
            UI.notify({title = "Teleport", text = "No coins found.", kind = "warn"})
            return false
        end
        return tpTo(coin.part.Position, "Moved to the nearest coin.")
    end

    local function anySpawn(container)
        local spawns = container and container:FindFirstChild("Spawns")
        if not spawns then return nil end
        local options = spawns:GetChildren()
        if #options == 0 then return nil end
        local pick = options[math.random(1, #options)]
        return pick:IsA("BasePart") and pick.Position or nil
    end

    function Move.tpLobby()
        local position = anySpawn(Game.lobby())
        if not position then
            UI.notify({title = "Teleport", text = "Could not find the lobby.", kind = "warn"})
            return false
        end
        return tpTo(position, "Moved to the lobby.")
    end

    function Move.tpRandomSpawn()
        local position = anySpawn(Game.map())
        if not position then
            UI.notify({title = "Teleport", text = "No map spawns available.", kind = "warn"})
            return false
        end
        return tpTo(position, "Moved to a random spawn.")
    end

    -- ============================================================ WAYPOINTS
    -- Kept in their own file rather than in the settings profile: the config
    -- reconciler drops keys it does not recognise, and waypoint names are by
    -- definition not in the schema.
    local WAYPOINT_FILE = "KittyHub/waypoints.json"
    Move.Waypoints = {}

    local function loadWaypoints()
        if not (X.writefile and KH.Config.available) then return end
        pcall(function()
            if not isfile(WAYPOINT_FILE) then return end
            local data = HttpService:JSONDecode(readfile(WAYPOINT_FILE))
            if typeof(data) == "table" then Move.Waypoints = data end
        end)
    end

    local function saveWaypoints()
        if not (X.writefile and KH.Config.available) then return end
        pcall(function()
            writefile(WAYPOINT_FILE, HttpService:JSONEncode(Move.Waypoints))
        end)
    end
    loadWaypoints()

    function Move.saveWaypoint(name)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            UI.notify({title = "Waypoint", text = "Give it a name first.", kind = "warn"})
            return false
        end
        local root = U.myRoot()
        if not root then return false end
        local p = root.Position
        Move.Waypoints[name] = {p.X, p.Y, p.Z}
        saveWaypoints()
        UI.notify({title = "Waypoint", text = 'Saved "' .. name .. '".', kind = "good"})
        return true
    end

    function Move.gotoWaypoint(name)
        local entry = Move.Waypoints[name]
        if not entry then
            UI.notify({title = "Waypoint", text = "No waypoint called " .. tostring(name) .. ".", kind = "warn"})
            return false
        end
        return tpTo(Vector3.new(entry[1], entry[2], entry[3]), 'Moved to "' .. name .. '".')
    end

    function Move.deleteWaypoint(name)
        if Move.Waypoints[name] == nil then return false end
        Move.Waypoints[name] = nil
        saveWaypoints()
        UI.notify({title = "Waypoint", text = 'Deleted "' .. name .. '".'})
        return true
    end

    function Move.waypointNames()
        local names = {}
        for name in pairs(Move.Waypoints) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
end
