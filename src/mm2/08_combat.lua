-- ============================================================================
--  COMBAT — sheriff aimbot, silent aim, and murderer knife tooling
--
--  MM2's gun does not raycast on the client: the shot is a RemoteFunction that
--  carries a world position and the server decides what it hit. "Aiming" here
--  therefore means sending good coordinates, which is why prediction and ping
--  compensation matter far more than where the camera points.
-- ============================================================================

do
    local UI          = KH.UI
    local U           = KH.U
    local Game        = KH.Game
    local S           = KH.S
    local LocalPlayer = KH.LocalPlayer

    local Combat = {}
    KH.Combat = Combat

    -- ===================================================== TARGET SELECTION
    local function shootableParts(player)
        local char = U.charOf(player)
        if not char then return nil end
        local part = S.Aim.AimAtHead and char:FindFirstChild("Head") or U.torsoOf(char)
        return char, part
    end

    -- Returns char, part, distance when the player can be shot right now.
    --
    -- The only requirements are that they are alive and have a body part with a
    -- position. There is deliberately no visibility or range test: the shot is
    -- a world position the server resolves, so walls, floors and distance do
    -- not stop it, and refusing to fire through them would only make the
    -- aimbot worse than a human with good aim.
    local function validate(player)
        if not player or player == LocalPlayer then return nil end
        if not Game.isAlive(player) then return nil end

        local char, part = shootableParts(player)
        if not char or not part then return nil end

        local myRoot = U.myRoot()
        local distance = myRoot and (myRoot.Position - part.Position).Magnitude or 0
        return char, part, distance
    end

    -- Angular distance from the crosshair, in pixels, or nil when off-screen.
    local function screenOffset(part)
        local cam = KH.camera()
        local pos, onScreen = U.toScreen(part.Position)
        if not onScreen then return nil end
        local centre = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        return (pos - centre).Magnitude
    end

    function Combat.pickTarget()
        local mode = S.Aim.Target

        if mode == "Murderer" then
            local murderer = Game.murdererPlayer()
            if not murderer then return nil end
            local char, part, distance = validate(murderer)
            if not char then return nil end
            return murderer, char, part, distance
        end

        local bestPlayer, bestChar, bestPart, bestDistance
        local bestScore = math.huge

        for _, player in ipairs(U.otherPlayers()) do
            local char, part, distance = validate(player)
            if char then
                local score
                if mode == "Crosshair" then
                    score = screenOffset(part)
                else -- Nearest
                    score = distance
                end
                if score and score < bestScore then
                    bestScore = score
                    bestPlayer, bestChar, bestPart, bestDistance = player, char, part, distance
                end
            end
        end
        return bestPlayer, bestChar, bestPart, bestDistance
    end

    function Combat.aimPoint(char, part)
        return U.predict(char, S.Aim.Prediction, S.Aim.PingComp, part) or part.Position
    end

    -- ============================================================== AIMBOT
    local lastShot = 0
    local toggleArmed = false
    Combat.LastTarget = nil

    function Combat.isEngaged()
        if not S.Aim.Enabled then return false end
        local mode = S.Aim.Mode
        if mode == "Always" then return true end
        if mode == "Toggle" then return toggleArmed end
        return U.keyHeld(S.Aim.Key)
    end

    function Combat.setToggle(on)
        toggleArmed = on
        if on then
            UI.notify({title = "Aimbot", text = "Locked on — auto-firing.", kind = "good", duration = 2})
        end
    end
    function Combat.toggleArmedState() return toggleArmed end

    -- Fires once at the current best target. Returns true when a shot went out.
    function Combat.fireOnce(force)
        local gun = Game.gunTool()
        if not gun then return false, "no gun" end

        local player, char, part = Combat.pickTarget()
        if not player then return false, "no target" end

        local now = os.clock()
        if not force and now - lastShot < S.Aim.FireRate then return false, "cooldown" end
        lastShot = now
        Combat.LastTarget = player

        local ok, err = Game.shoot(Combat.aimPoint(char, part))
        if ok and S.Aim.NotifyShot then
            UI.notify({title = "Shot", text = "Fired at " .. player.DisplayName, duration = 1.5})
        end
        return ok, err
    end

    KH.onFrame("aimbot", function()
        if not Combat.isEngaged() then return end
        Combat.fireOnce(false)
    end, 30)

    -- Keeps the gun in hand. Firing draws it, but MM2 stows your tool on respawn
    -- and when a round flips, which would otherwise leave the first shot of the
    -- next round doing nothing but re-equipping.
    KH.loop(0.5, function()
        if not (S.Aim.Enabled and S.Aim.KeepEquipped) then return end
        local gun, equipped = Game.gunTool()
        if gun and not equipped then Game.equip(gun) end
    end)

    -- =========================================================== SILENT AIM
    -- Redirects the shots *you* fire by hand, instead of firing for you.
    --
    -- Two things this has to get right. First, it must never throw: an error in
    -- a __namecall hook breaks the underlying call, which would leave the gun
    -- unable to shoot at all. Every decision therefore happens inside a pcall
    -- and any failure falls straight through to the original call. Second, it
    -- must ignore calls the script itself made — otherwise Kill All would have
    -- each of its shots rewritten onto the same target.
    --
    -- Executors offer no reliable unhook, so the hook stays installed for the
    -- session and turns into a pass-through once KH.Alive goes false.
    do
        local X = KH.X
        if X.hookmetamethod then
            local installed = pcall(function()
                local oldNamecall
                oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    if not KH.Alive or not S.Aim.SilentAim then
                        return oldNamecall(self, ...)
                    end
                    if X.checkcaller and checkcaller() then
                        -- Our own Game.shoot() call; already aimed.
                        return oldNamecall(self, ...)
                    end

                    local ok, redirected = pcall(function(...)
                        if getnamecallmethod() ~= "InvokeServer" then return nil end

                        -- Only the gun's own beam remote is of interest.
                        local parent = typeof(self) == "Instance" and self.Parent or nil
                        if not parent or parent.Name ~= "CreateBeam" then return nil end

                        local args = table.pack(...)
                        if typeof(args[2]) ~= "Vector3" then return nil end

                        local player, char, part = Combat.pickTarget()
                        if not (player and char and part) then return nil end

                        args[2] = Combat.aimPoint(char, part)
                        Combat.LastTarget = player
                        return args
                    end, ...)

                    if ok and redirected then
                        return oldNamecall(self, table.unpack(redirected, 1, redirected.n))
                    end
                    return oldNamecall(self, ...)
                end)
            end)
            Combat.SilentAvailable = installed
        else
            Combat.SilentAvailable = false
        end
    end

    -- ============================================================= KILL ALL
    -- Sequential rather than a single burst: MM2 rate-limits the shot remote,
    -- so spraying them in one frame just gets most of them dropped.
    local killAllRunning = false
    function Combat.killAll()
        if killAllRunning then return end
        if not Game.gunTool() then
            UI.notify({title = "Kill All", text = "You are not holding a gun.", kind = "bad"})
            return
        end
        killAllRunning = true
        KH.detach(function()
            local count = 0
            for _, player in ipairs(U.otherPlayers()) do
                if not KH.Alive then break end
                if Game.isAlive(player) then
                    local char, part = shootableParts(player)
                    if char and part then
                        Game.shoot(Combat.aimPoint(char, part))
                        count = count + 1
                        task.wait(0.12)
                    end
                end
            end
            killAllRunning = false
            UI.notify({title = "Kill All", text = ("Fired at %d players."):format(count), kind = "good"})
        end)
    end

    -- =============================================================== KNIFE
    local function knifeTargets()
        local out = {}
        local myRoot = U.myRoot()
        if not myRoot then return out end

        for _, player in ipairs(U.otherPlayers()) do
            if Game.isAlive(player) then
                local role = Game.roleOf(player)
                local isSheriff = (role == "Sheriff" or role == "Hero")
                local allowed = true
                if S.Knife.TargetSheriff and not isSheriff then allowed = false end
                if S.Knife.SkipSheriff and isSheriff then allowed = false end

                if allowed then
                    local char = U.charOf(player)
                    local part = char and U.torsoOf(char)
                    if part then
                        out[#out + 1] = {
                            player = player, char = char, part = part,
                            distance = (myRoot.Position - part.Position).Magnitude,
                            sheriff = isSheriff,
                        }
                    end
                end
            end
        end

        -- Sheriff first when asked for, then by proximity.
        table.sort(out, function(a, b)
            if S.Knife.TargetSheriff and a.sheriff ~= b.sheriff then return a.sheriff end
            return a.distance < b.distance
        end)
        return out
    end
    Combat.knifeTargets = knifeTargets

    function Combat.throwAtNearest()
        if not Game.knifeTool() then return false end
        local targets = knifeTargets()
        local target = targets[1]
        if not target then return false end
        local point = U.predict(target.char, S.Aim.Prediction + 1, S.Aim.PingComp) or target.part.Position
        return Game.throwKnife(point)
    end

    -- Auto throw
    KH.loop(0.1, function()
        if not S.Knife.AutoThrow then return end
        if not Game.knifeTool() then return end
        Combat.throwAtNearest()
        task.wait(math.max(S.Knife.ThrowDelay, 0.2))
    end)

    -- Knife aura: stab anything that wanders into range.
    KH.loop(0.05, function()
        if not S.Knife.Aura then return end
        if not Game.knifeTool() then return end
        local targets = knifeTargets()
        local nearest = targets[1]
        if nearest and nearest.distance <= S.Knife.AuraRadius then
            Game.stab()
            task.wait(math.max(S.Knife.AuraDelay, 0.05))
        end
    end)

    -- Teleport-stab: blink to the target, swing, blink back. The return hop is
    -- what keeps it from looking like a permanent teleport to everyone else.
    local tpStabRunning = false
    function Combat.tpStab()
        if tpStabRunning then return end
        if not Game.knifeTool() then
            UI.notify({title = "Knife", text = "You are not holding a knife.", kind = "bad"})
            return
        end
        local targets = knifeTargets()
        local target = targets[1]
        if not target then return end

        tpStabRunning = true
        KH.detach(function()
            local root = U.myRoot()
            if root then
                local origin = root.CFrame
                root.CFrame = target.part.CFrame * CFrame.new(0, 0, 2.5)
                task.wait(0.08)
                Game.stab()
                task.wait(0.12)
                if U.myRoot() then U.myRoot().CFrame = origin end
            end
            tpStabRunning = false
        end)
    end

    KH.loop(0.1, function()
        if S.Knife.TpStab and Game.knifeTool() then
            Combat.tpStab()
            task.wait(0.35)
        end
    end)
end
