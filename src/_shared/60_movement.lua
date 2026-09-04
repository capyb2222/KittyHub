-- ============================================================================
--  MOVEMENT — speed, jump, noclip, fly, spinbot, teleports, waypoints
--
--  Game-agnostic: anything that needs to know what it is teleporting to
--  lives in the game module and builds on Move.tpTo / Move.tpToPlayer.
-- ============================================================================

do
    local UI               = KH.UI
    local U                = KH.U
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
    -- One owner for the character's collisions, refcounted. The toggle is one
    -- holder and a rob routine is another: without that, a job finishing put
    -- the collisions back underneath a noclip the player had switched on by
    -- hand, and the toggle looked broken for the rest of the session.
    --
    -- Weak keys: a respawn leaves the old limbs in here, and nothing should be
    -- keeping a destroyed character alive just to remember it was solid.
    local clipOriginal = setmetatable({}, {__mode = "k"})
    local clipHolders  = 0
    local clipManual   = false
    local clipConn

    -- Descendants every frame, not once: a respawn brings a whole new set of
    -- solid limbs that a one-off pass would never see.
    local function clipStep()
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                if clipOriginal[part] == nil then clipOriginal[part] = true end
                part.CanCollide = false
            end
        end
    end

    local function clipRestore()
        for part, wasCollidable in pairs(clipOriginal) do
            if part.Parent and wasCollidable then
                pcall(function() part.CanCollide = true end)
            end
        end
        table.clear(clipOriginal)
    end

    -- Stepped, not the render loop: this has to be the last write before the
    -- physics step. On the render loop the humanoid controller puts the
    -- collisions back first, and the character bounces off the wall it should
    -- be passing through.
    function Move.pushNoclip()
        clipHolders = clipHolders + 1
        if clipHolders == 1 then
            if not clipConn then
                -- Not KH.track: this is disconnected below and on unload, and
                -- tracking it would add a dead entry on every single toggle.
                clipConn = RunService.Stepped:Connect(clipStep)
            end
            clipStep()   -- this frame, rather than the next one
        end
    end

    function Move.popNoclip()
        clipHolders = math.max(clipHolders - 1, 0)
        if clipHolders == 0 then
            if clipConn then
                clipConn:Disconnect()
                clipConn = nil
            end
            clipRestore()
        end
    end

    function Move.noclipHeld() return clipHolders > 0 end

    -- Seated, it is the vehicle that collides with the world and not the
    -- character, so switching the character's collisions off does nothing at
    -- all. Say that outright instead of leaving a toggle that looks on and
    -- changes nothing.
    function Move.noclipBlocked()
        local hum = U.myHum()
        if hum and hum.SeatPart then
            return "You are in a vehicle — noclip only moves your character."
        end
        return nil
    end

    function Move.setNoclip(on)
        on = on and true or false
        if on ~= clipManual then
            clipManual = on
            if on then Move.pushNoclip() else Move.popNoclip() end
        end
        S.Move.Noclip = on
        if on then
            local why = Move.noclipBlocked()
            if why then UI.notify({title = "Noclip", text = why, kind = "warn"}) end
        end
        UI.refreshKeybinds()
    end

    -- Unload drops every holder, not just the manual one: a job cut short by
    -- an unload would otherwise leave the character permanently intangible.
    KH.undo(function()
        clipManual, clipHolders = false, 0
        S.Move.Noclip = false
        if clipConn then
            clipConn:Disconnect()
            clipConn = nil
        end
        clipRestore()
    end)

    -- ================================================== INFINITE JUMP / BHOP
    KH.track(UserInputService.JumpRequest:Connect(function()
        if not S.Move.InfJump then return end
        local hum = U.myHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end))

    KH.onFrame("bhop", function()
        if not S.Move.Bhop then return end
        if U.typing() then return end
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

    -- ======================================================== SAFE LANDING
    -- Roblox itself has no fall damage; Jailbreak adds its own and reads it
    -- off how fast you arrive. Flying is therefore safe right up until the
    -- moment it stops, which is why "fly works but going down kills you".
    -- Everything below exists to make sure the character never reaches the
    -- floor faster than a walk off a kerb.
    local groundParams = RaycastParams.new()
    groundParams.FilterType = Enum.RaycastFilterType.Exclude
    -- Only real floors count. Without this the probe stops on glass canopies
    -- and decorative volumes, and the descent brakes for scenery it would have
    -- passed straight through.
    pcall(function() groundParams.RespectCanCollide = true end)
    pcall(function() groundParams.IgnoreWater = true end)

    -- Studs to whatever is under the character, or nil for nothing in reach.
    -- The character is excluded so noclip does not read its own legs as floor.
    local function groundDrop(root, reach)
        groundParams.FilterDescendantsInstances = {LocalPlayer.Character}
        local hit = workspace:Raycast(root.Position, Vector3.new(0, -(reach or 600), 0), groundParams)
        return hit and (root.Position.Y - hit.Position.Y) or nil
    end

    -- The fastest descent that still lands softly from here: a ramp, so a long
    -- drop stays quick at the top and only bleeds off near the ground. Capped,
    -- because the ramp alone asks for two thousand studs a second from the top
    -- of a skyscraper, and that is a speed check of its own.
    local function descentSpeed(drop)
        return math.min(math.max(drop - 4, 0) * 2.2 + 8, 200)
    end

    -- ================================================================= FLY
    local flyVelocity, flyGyro
    local flying  = false
    local landing = false        -- flying the character down after fly was cut
    local landingUntil = 0

    local function stopFly()
        flying, landing = false, false
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

    -- Letting go three hundred studs up is not a landing, it is a death, so
    -- switching fly off in mid-air keeps the flight parts and flies the
    -- character down instead. PlatformStand stays on the whole way, so a game
    -- reading fall damage off the humanoid freefall state never sees one.
    local function beginLanding()
        local root = U.myRoot()
        if not root or not flyVelocity or not flyVelocity.Parent then return false end
        local drop = groundDrop(root, 900)
        if not drop or drop <= 6 then return false end
        landing = true
        landingUntil = os.clock() + 15
        return true
    end

    local function stepLanding()
        local root = U.myRoot()
        if not root or not flyVelocity or not flyVelocity.Parent then
            stopFly()
            return
        end

        local drop = groundDrop(root, 900)
        -- Nothing underneath at all means the void, and hanging there forever
        -- helps nobody; the timeout hands the character back either way.
        if not drop or drop <= 4 or os.clock() > landingUntil then
            stopFly()
            root.AssemblyLinearVelocity = Vector3.zero
            return
        end
        flyVelocity.Velocity = Vector3.new(0, -descentSpeed(drop), 0)
    end

    function Move.landing() return landing end

    function Move.setFly(on)
        S.Move.Fly = on
        if on then
            landing = false
            -- Already holding the flight parts? Resume rather than rebuild:
            -- this is the path taken when fly is switched back on mid-landing.
            if not (flying and flyVelocity and flyVelocity.Parent) then
                if not startFly() then
                    S.Move.Fly = false
                    UI.notify({title = "Fly", text = "No character to attach to.", kind = "bad"})
                end
            end
        elseif not (S.Move.SafeLand and beginLanding()) then
            stopFly()
        end
        UI.refreshKeybinds()
    end
    KH.undo(function() stopFly() end)

    KH.onFrame("fly", function()
        if landing then
            stepLanding()
            return
        end
        if not S.Move.Fly then
            if flying then stopFly() end
            return
        end
        if not flying or not flyVelocity or not flyVelocity.Parent then
            if not startFly() then return end
        end

        local cam = KH.camera()
        local direction = Vector3.zero
        -- Hold still while typing rather than reading the chat as flight input.
        if U.typing() then
            flyVelocity.Velocity = Vector3.zero
            flyGyro.CFrame = cam.CFrame
            return
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction = direction - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction = direction + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then direction = direction - Vector3.new(0, 1, 0) end

        if direction.Magnitude > 0 then direction = direction.Unit end
        local velocity = direction * S.Move.FlySpeed

        -- Diving into the floor at flight speed is the other way flight kills
        -- you: the fall damage does not care that a BodyVelocity put you there.
        if S.Move.SafeLand and velocity.Y < 0 then
            local root = U.myRoot()
            local drop = root and groundDrop(root, 600)
            if drop then
                local allowed = descentSpeed(drop)
                if -velocity.Y > allowed then
                    velocity = Vector3.new(velocity.X, -allowed, velocity.Z)
                end
            end
        end

        flyVelocity.Velocity = velocity
        flyGyro.CFrame = cam.CFrame
    end, 61)

    -- Falls that did not start as flight: walking off a roof, a jump gone
    -- wrong, a teleport that dropped short. Once this latches on it stays on
    -- until the character is back on the ground, because releasing at a speed
    -- threshold only lets gravity build the speed straight back up.
    local braking = false

    KH.onFrame("safe-land", function()
        if not S.Move.SafeLand or flying or landing or Move.noclipHeld() then
            braking = false
            return
        end
        local root, hum = U.myRoot(), U.myHum()
        if not root or not hum then
            braking = false
            return
        end

        local velocity = root.AssemblyLinearVelocity
        if not braking then
            -- About twelve studs of fall. Below that nothing hurts, and
            -- clamping it would make every ordinary jump feel like a landing.
            if velocity.Y > -70 then return end
            braking = true
        end
        if velocity.Y >= 0 or hum.FloorMaterial ~= Enum.Material.Air then
            braking = false
            return
        end

        local drop = groundDrop(root, 700)
        if not drop then return end
        local allowed = descentSpeed(drop)
        if -velocity.Y > allowed then
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, -allowed, velocity.Z)
        end
    end, 59)

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

    -- ============================================================ WAYPOINTS
    -- Their own file, not the settings profile: the reconciler drops keys it
    -- does not recognise, and waypoint names are never in the schema.
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
