-- ============================================================================
--  COMBAT — aimbot, silent aim, knife. MM2's gun is server-authoritative: the
--  shot is a RemoteFunction carrying a world position, so aiming means sending
--  good coordinates, not pointing a camera.
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

    -- char, part, distance when the player can be shot right now. No line of
    -- sight or range test on purpose: the server resolves the position, so
    -- walls and distance do not stop the shot.
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

    function Combat.pickTarget(mode)
        mode = mode or S.Aim.Target

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
        -- Press is one shot per key press, fired from the key handler. Never
        -- engaged, so the render loop leaves it alone.
        if mode == "Press" then return false end
        return U.keyHeld(S.Aim.Key)
    end

    function Combat.setToggle(on)
        toggleArmed = on
        if on then
            UI.notify({title = "Aimbot", text = "Locked on — auto-firing.", kind = "good", duration = 2})
        end
    end
    function Combat.toggleArmedState() return toggleArmed end

    -- Disarm at the end of a round: otherwise the lock grabs the camera again
    -- the moment the next murderer is known, before you have touched the key.
    Game.on("RoundEnd", function()
        if toggleArmed then
            toggleArmed = false
            UI.refreshKeybinds()
        end
    end)

    -- One cooldown for every shot the script sends: MM2 drops shots that land
    -- too close together, and the one it drops could be either feature's.
    function Combat.fireAt(position, force)
        local now = os.clock()
        if not force and now - lastShot < S.Aim.FireRate then return false, "cooldown" end
        lastShot = now
        return Game.shoot(position)
    end

    -- ========================================================== MOUSE AIM
    -- For the executors where the remote shot above never lands. Builds no shot
    -- at all: turns the camera onto the target, drives the real cursor onto
    -- them and clicks, so MM2's own gun fires it. Needs no hook, only synthetic
    -- mouse input. The cost is subtlety — the camera visibly snaps.
    local Mouse = {Firing = false, Turning = false}
    Combat.Mouse = Mouse

    do
        local GuiService = game:GetService("GuiService")
        local Players = KH.Services.Players
        local UIS = KH.Services.UserInputService

        -- Plain globals; one the executor lacks reads back nil.
        local moveRel = type(mousemoverel) == "function" and mousemoverel or nil
        local moveAbs = type(mousemoveabs) == "function" and mousemoveabs or nil
        local press   = type(mouse1press) == "function" and mouse1press or nil
        local release = type(mouse1release) == "function" and mouse1release or nil
        local click   = type(mouse1click) == "function" and mouse1click or nil

        -- The engine's own input injector, open to the elevated context an
        -- executor runs as. Touched now so a stripped service fails here
        -- rather than mid-shot.
        local VIM = (function()
            local ok, service = pcall(function() return game:GetService("VirtualInputManager") end)
            if not ok or typeof(service) ~= "Instance" then return nil end
            local fine = pcall(function() return service.SendMouseButtonEvent end)
            return fine and service or nil
        end)()

        Mouse.CanMove = (moveRel ~= nil) or (moveAbs ~= nil) or (VIM ~= nil)

        -- What a viewport pixel is worth to the cursor, and how long a frame of
        -- the walk really takes. Both are measured rather than assumed, and both
        -- are reported in the menu — a wrong one shows up there first.
        local gain, samples = 1, 0
        local stepTime = 1 / 60

        function Mouse.support()
            if not Mouse.CanMove then return "none — this executor cannot move the cursor" end
            local mover = moveRel and "mousemoverel"
                or moveAbs and "mousemoveabs"
                or "VirtualInputManager"
            local clicker = (press and release) and "mouse1press"
                or click and "mouse1click"
                or VIM and "VirtualInputManager"
                or "Tool:Activate"
            return ("%s + %s · gain %.2f · %d ms"):format(mover, clicker, gain, stepTime * 1000)
        end

        local mouseObj
        local function project(pos)
            local point, onScreen = KH.camera():WorldToViewportPoint(pos)
            -- Behind the camera the X/Y come back mirrored: chasing them walks
            -- the cursor the wrong way, so depth has to agree.
            return Vector2.new(point.X, point.Y), onScreen and point.Z > 0
        end

        -- Where the cursor is, in the same space the target is projected into.
        --
        -- mouse.X/Y are plain screen coordinates and never lag, but they and
        -- WorldToViewportPoint disagree about the topbar on some clients, and a
        -- constant offset between the two is a constant aim error. Projecting
        -- the world point under the cursor lands in the right space but lags a
        -- frame behind the camera, because that point is computed before the
        -- lock turns the view. So take the difference between the two on the
        -- frames where the camera is still — the frames where both readings are
        -- good — and carry it. Right space, no lag, nothing assumed.
        local offset = Vector2.zero
        local function cursor()
            mouseObj = mouseObj or LocalPlayer:GetMouse()
            local raw = Vector2.new(mouseObj.X, mouseObj.Y)
            if not Mouse.Turning then
                local ok, hit = pcall(function() return mouseObj.Hit.Position end)
                if ok and typeof(hit) == "Vector3" then
                    local point, onScreen = project(hit)
                    if onScreen then offset = point - raw end
                end
            end
            return raw + offset, mouseObj
        end

        -- A relative move is in OS pixels and the projection is in viewport
        -- pixels, and on a scaled display those are not the same unit — so watch
        -- what the last move actually achieved and correct the next one.
        local function learn(want, got)
            if not moveRel then return end
            if want.Magnitude < 8 or got.Magnitude < 2 then return end
            -- A real display scale lives near 1. Anything wilder is a dropped
            -- frame or a cursor that hit the edge of the window, and folding
            -- that into the gain is how the aim runs away.
            local ratio = want.Magnitude / got.Magnitude
            if ratio < 0.4 or ratio > 2.5 then return end
            -- Take the first couple of samples whole, since the first press of
            -- a session has nothing better to go on, then ease: one noisy frame
            -- swinging the next move is the cursor wandering instead of walking.
            samples = samples + 1
            gain = U.clamp(gain * (1 + (ratio - 1) * (samples <= 2 and 1 or 0.25)), 0.5, 2)
        end

        local function recalibrate()
            gain, samples = 1, 0
        end

        -- The cursor's reported position only stops responding once it has left
        -- the Roblox window, and it can only leave through an edge.
        local function atBorder(point)
            local view = KH.camera().ViewportSize
            return point.X <= 8 or point.Y <= 8
                or point.X >= view.X - 8 or point.Y >= view.Y - 8
        end

        -- Drag the cursor back inside the window. Once it is out there — put
        -- there by an earlier bad move, or by the player in windowed mode —
        -- mouse.X/Y stick to the border, so every reading is the same pixel and
        -- the walk cannot tell where it is or how far it moved. A big move
        -- inwards is the only way back. Gain is deliberately not applied: in
        -- this state it is the value least worth trusting.
        local function sweepHome(here)
            if not moveRel then return false end   -- absolute movers cannot lose it
            local view = KH.camera().ViewportSize
            local push = Vector2.new(view.X * 0.5, view.Y * 0.5) - here
            if push.Magnitude < 1 then return false end
            local far = push.Unit * (view.Magnitude * 0.75)
            return (pcall(moveRel, math.floor(far.X + 0.5), math.floor(far.Y + 0.5)))
        end

        -- The cursor has to stay somewhere Roblox can still see it. Outside the
        -- window mouse.X/Y stop moving, so every further move reads as achieving
        -- nothing at all.
        local function clampToView(point)
            local view = KH.camera().ViewportSize
            return Vector2.new(
                U.clamp(point.X, 6, math.max(view.X - 6, 6)),
                U.clamp(point.Y, 6, math.max(view.Y - 6, 6)))
        end

        local function moveTo(here, point)
            if moveRel then
                local delta = (point - here) * gain
                return (pcall(moveRel, math.floor(delta.X + 0.5), math.floor(delta.Y + 0.5)))
            end
            local inset = GuiService:GetGuiInset()
            local x, y = point.X + inset.X, point.Y + inset.Y
            if moveAbs then
                return (pcall(moveAbs, math.floor(x + 0.5), math.floor(y + 0.5)))
            end
            if VIM then
                return (pcall(function() VIM:SendMouseMoveEvent(x, y, game) end))
            end
            return false
        end

        -- Down, then up: MM2 shoots on the press, but a button left held means
        -- the next press never arrives.
        local function shootHere()
            if press and release then
                if pcall(press) then
                    -- MM2 shoots on the press, so the release only has to
                    -- happen; waiting here would just delay the next shot.
                    KH.detach(function()
                        task.wait(0.04)
                        pcall(release)
                    end)
                    return true
                end
                pcall(release)
            end
            if click and pcall(click) then return true end
            if VIM then
                local point = cursor()
                local inset = GuiService:GetGuiInset()
                local x, y = point.X + inset.X, point.Y + inset.Y
                local ok = pcall(function()
                    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                    task.wait(0.04)
                    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
                end)
                if ok then return true end
            end
            -- Last resort. MM2 reads the cursor either way, so this still lands
            -- where we pointed — unless the gun listens for the raw button.
            local gun, equipped = Game.gunTool()
            if gun and equipped then
                return (pcall(function() gun:Activate() end))
            end
            return false
        end

        local TOLERANCE = 4     -- pixel floor for "close enough"
        local NEAR_STUDS = 4.5  -- how far off them a landed ray may stop
        -- A ceiling on the loop, not the real limit — the clock below is that.
        -- Forty steps is under a third of a second at 144 fps, which quietly
        -- undid the budget for anyone running a high refresh rate.
        local MAX_STEPS = 90

        -- Every lead below is counted in frames of the walk, so a 30 fps client
        -- leads twice as far as a 144 fps one.
        local function noteStep(dt)
            if dt > 0 and dt < 0.2 then stepTime = stepTime + (dt - stepTime) * 0.2 end
        end

        -- Where the target will be in `lead` seconds. Nothing here has a
        -- projectile to lead, but the cursor lags a frame behind the move that
        -- put it there, the click lags a frame behind that, and the server
        -- resolves the shot a ping later still — a running target crosses most
        -- of their own body in that. Straight-line is enough: over a couple of
        -- frames gravity moves a jumping target a fraction of a stud.
        local function livePoint(part, lead)
            if not lead or lead <= 0 then return part.Position end
            local ok, velocity = pcall(function() return part.AssemblyLinearVelocity end)
            if not ok or typeof(velocity) ~= "Vector3" then return part.Position end
            return part.Position + velocity * lead
        end
        Mouse.livePoint = livePoint

        -- Where the camera should be pointing for the shot to land. The lock
        -- reads this too, so the turn and the shot never disagree about where
        -- the target is going to be.
        Mouse.Lead = 0
        function Mouse.aimPoint(part)
            return livePoint(part, Mouse.Lead)
        end

        -- Where the target sits on screen right now, for the camera lock.
        function Mouse.screenOf(part)
            return project(livePoint(part))
        end

        -- How big they look from here, in pixels. The cursor has to end up on
        -- their body, not on a point: four pixels is nothing to a target
        -- crossing twenty a frame, and the walk would never call itself close
        -- enough.
        --
        -- Measured to the top of their head, not to the top of the part being
        -- aimed at. HumanoidRootPart is a two-stud brick at the middle of a
        -- six-stud body, so reading its half-height gave a figure about a third
        -- of the truth — and every tolerance below is a fraction of this one.
        -- Too small, and the walk keeps correcting a cursor already on them
        -- while the lead is capped somewhere inside their own hitbox: exactly
        -- the case of a target who will not hold still.
        local function bodyRadius(char, part, point)
            local ok, edge = pcall(function()
                local head = char and char:FindFirstChild("Head")
                local top = head and (head.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
                    or (part.Position + Vector3.new(0, part.Size.Y * 0.5, 0))
                return project(top)
            end)
            if not ok then return TOLERANCE end
            return U.clamp((edge - point).Magnitude, TOLERANCE, 150)
        end

        -- A press projects before the camera lock has had a frame to run, so a
        -- target who is off screen this instant may simply not have been turned
        -- to yet. Give the lock time to bring them in, and no more than that:
        -- the walk below is happy to chase a view that is still moving.
        local function waitVisible(part)
            local speed = U.clamp(S.Aim.MouseSpeed or 1, 0.1, 1)
            local deadline = os.clock() + U.clamp(0.2 / speed, 0.2, 0.7)
            repeat
                local _, onScreen = project(part.Position)
                if onScreen then return true end
                if not S.Aim.CameraSnap then return false end
                task.wait()
            until os.clock() >= deadline
            return false
        end

        -- First person and shift lock pin the cursor to the middle of the
        -- screen, so there is no cursor to walk: the crosshair *is* the camera
        -- and aiming is turning. This is the more exact of the two paths — no
        -- display scale to learn, no readback to wait for, one rotation — but it
        -- is only available when the lock is allowed to take the camera.
        local function pointCamera(char, part)
            if not S.Aim.CameraSnap then
                return false, "cursor is locked — switch on Turn Camera to aim in first person"
            end

            Mouse.Lead = stepTime + (S.Aim.PingComp and U.clamp(U.ping() / 3000, 0, 0.06) or 0)
            Mouse.Precise = true

            local budget = os.clock() + 0.3
            local reached, why = false, "could not turn onto them"

            while true do
                if not (char.Parent and part.Parent) then
                    why = "target gone"
                    break
                end

                -- The lock does the turning, on its own bind after Roblox's
                -- camera module. Writing the camera from here as well would put
                -- two authors on it in the same frame.
                task.wait()

                local point, onScreen = project(Mouse.aimPoint(part))
                if onScreen then
                    local view = KH.camera().ViewportSize
                    local centre = Vector2.new(view.X / 2, view.Y / 2)
                    local hit = select(2, cursor()).Target
                    local onBody = hit and hit:IsDescendantOf(char)

                    -- The cursor sits dead centre, so the distance from the
                    -- centre to them is the whole aiming error.
                    if onBody or (point - centre).Magnitude <= bodyRadius(char, part, point) * 0.75 then
                        local blocker = not onBody and hit and hit:FindFirstAncestorOfClass("Model")
                        local owner = blocker and Players:GetPlayerFromCharacter(blocker)
                        if owner and owner ~= LocalPlayer then
                            why = "holding fire — " .. owner.DisplayName .. " is in the line"
                        else
                            reached, why = true, hit and ("through " .. hit.Name) or "on target"
                        end
                        break
                    end
                end

                if os.clock() > budget then break end
            end

            Mouse.Precise = false
            Mouse.Lead = 0
            return reached, why
        end

        -- Puts the cursor on the target and says whether it got there.
        --
        -- Nobody else can see your cursor — the camera turn is the only part of
        -- this anyone else witnesses — so there is nothing to be gained by
        -- easing it across the screen. It goes the whole way in one move, then
        -- spends the frames after that correcting for what the move actually
        -- achieved. That is both the fastest way there and the most exact.
        local function pointAt(char, part)
            -- No cursor to place: turn instead.
            if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
                return pointCamera(char, part)
            end
            if not Mouse.CanMove then return false, "no mouse control" end
            if not waitVisible(part) then return false, "off screen" end

            -- A target standing still is reached in two or three frames and
            -- never sees this. It is the one jumping and strafing that needs
            -- the frames, and a fifth of a second was not enough of them to
            -- catch someone mid-jump: the walk ran out of budget on the way up
            -- and reported that it could not reach them.
            local budget = os.clock() + 0.45
            -- The click lands a frame after the cursor does, and MM2 casts its
            -- own ray then rather than now.
            local pingLead = S.Aim.PingComp and U.clamp(U.ping() / 3000, 0, 0.06) or 0
            local lastFrom, lastWant, stuck = nil, nil, 0
            local tick = os.clock()
            local grazed = false

            for _ = 1, MAX_STEPS do
                if not (char.Parent and part.Parent) then return false, "target gone" end

                local mark = os.clock()
                if lastWant then noteStep(mark - tick) end
                tick = mark

                local here, m = cursor()

                -- The last move has not shown up yet. Issuing another on top of
                -- it is how the cursor overshoots and has to come back — wait
                -- for it to land instead. Against an edge it means something
                -- else: the cursor is outside the window, where its reported
                -- position stops changing at all, and only a sweep inwards gets
                -- it back.
                if lastWant and lastWant.Magnitude >= 4 and (here - lastFrom).Magnitude < 1 then
                    if atBorder(here) then
                        stuck = stuck + 1
                        if stuck >= 2 then
                            stuck = 0
                            recalibrate()
                            lastFrom, lastWant = nil, nil
                            if not sweepHome(here) then return false, "cursor is off the window" end
                        end
                    end
                    task.wait()
                else
                    stuck = 0

                    local now, onScreen = project(part.Position)
                    if not onScreen then return false, "off screen" end

                    if lastWant then learn(lastWant, here - lastFrom) end

                    -- Two questions, and for anyone moving they have different
                    -- answers. Where must the ray land? Where they will be when
                    -- the click is processed, a frame from now. Where must the
                    -- cursor be sent? Where they will be once *this* move has
                    -- landed, a frame later again. Never past their body edge
                    -- either way: MM2 shoots wherever the cursor's ray stops, so
                    -- a lead that overshoots them sends the wall behind instead.
                    local radius = bodyRadius(char, part, now)
                    local function ahead(seconds)
                        local point, ok = project(livePoint(part, seconds))
                        if not ok then return now end
                        local drift = point - now
                        local cap = radius * 0.8
                        if drift.Magnitude > cap then drift = drift.Unit * cap end
                        return now + drift
                    end

                    local hitPoint = ahead(stepTime + pingLead)
                    local sendTo   = ahead(stepTime * 2 + pingLead)
                    -- Against where the shot has to land, not where the next
                    -- move is going: the cursor is already a frame ahead, and
                    -- measuring it against the frame after that left a running
                    -- target permanently one step out of reach.
                    local gap = (hitPoint - here).Magnitude
                    local spent = os.clock() >= budget

                    -- The ray hitting them proves where they were a frame ago,
                    -- which is the whole answer for someone standing still and
                    -- worth nothing against someone crossing.
                    local hit = m.Target
                    local onBody = hit and hit:IsDescendantOf(char)
                    local settled = (hitPoint - now).Magnitude <= radius * 0.3
                    local close = gap <= math.max(TOLERANCE, radius * 0.7)
                        or (spent and gap <= radius)

                    -- Pixels lie. A cursor within a body width of their centre
                    -- can still be a ray that slips past them into the scenery
                    -- twenty studs behind, and MM2 sends wherever the ray
                    -- stops, so that is what has to be near them -- in studs.
                    local lands = onBody and settled
                    if not lands and close then
                        local reach, at = pcall(function() return m.Hit.Position end)
                        lands = reach
                            and (at - livePoint(part, stepTime)).Magnitude <= NEAR_STUDS
                        if not lands then grazed = true end
                    end

                    if lands then
                        -- MM2 shoots where the cursor's ray stops. A wall costs
                        -- a wasted shot, but another player standing in the line
                        -- costs the round: a sheriff who shoots an innocent dies
                        -- for it. Hold fire and let the next press try again.
                        local blocker = not onBody and hit and hit:FindFirstAncestorOfClass("Model")
                        local owner = blocker and Players:GetPlayerFromCharacter(blocker)
                        if owner and owner ~= LocalPlayer then
                            return false, "holding fire — " .. owner.DisplayName .. " is in the line"
                        end
                        return true, hit and ("through " .. hit.Name) or "on target"
                    end
                    if spent then break end

                    -- The whole way, every time. What the move does not achieve
                    -- is measured next frame and taken off the one after.
                    local dest = clampToView(sendTo)
                    lastFrom, lastWant = here, dest - here
                    if not moveTo(here, dest) then
                        return false, "no mouse control"
                    end
                    task.wait()
                end
            end
            -- On them by the pixels every time and never by the ray: they are
            -- behind something, and the shot would go into whatever that is.
            if grazed then return false, "the shot would land behind them" end

            -- Never got there: the scale it is moving by is the thing most
            -- likely wrong, so the next press starts from a clean one.
            recalibrate()
            return false, "could not reach"
        end

        local busy = false
        local activePart

        -- The part the in-flight sequence is aiming at, or nil between shots.
        function Mouse.active() return activePart end

        -- One at a time: the walk yields across frames, and the render loop
        -- would otherwise have a dozen of them fighting over the cursor.
        function Mouse.fire(player, char, part, force)
            if busy then return false, "aiming" end
            -- A locked cursor is aimed by turning, which needs no mouse mover
            -- at all — only something to click with.
            if UIS.MouseBehavior == Enum.MouseBehavior.Default and not Mouse.CanMove then
                return false, "no mouse control"
            end

            local now = os.clock()
            if not force and now - lastShot < S.Aim.FireRate then return false, "cooldown" end
            lastShot = now
            busy = true
            activePart = part

            local function sequence()
                local dry = S.Aim.DryRun

                -- Draw the gun and walk at the same time rather than one after
                -- the other: EquipTool takes a frame or two, and so does the
                -- walk, so waiting for the first before starting the second
                -- doubled the time from the key press to the shot.
                local gun, equipped = Game.gunTool()
                if gun and not equipped and not dry then Game.equip(gun) end

                local reached, why = pointAt(char, part)
                if not reached then
                    Combat.LastResult = (dry and "aim test — " or "mouse aim — ") .. why
                    -- No shot went out; do not charge the next one a cooldown.
                    lastShot = 0
                    -- A press that quietly does nothing looks like a dead key.
                    if force then
                        UI.notify({title = dry and "Aim Test" or "Aimbot", text = why, kind = "warn", duration = 2})
                    end
                    return
                end

                -- Aim test: say where the cursor actually ended up. The point
                -- under it is the one MM2 would have sent, so its distance to
                -- them is the whole truth about whether the shot would land.
                if dry then
                    local _, m = cursor()
                    local ok, at = pcall(function() return m.Hit.Position end)
                    local speed = 0
                    pcall(function() speed = part.AssemblyLinearVelocity.Magnitude end)
                    local text = ok
                        and ("%.1f studs off %s, who was doing %.0f studs/s (%s)"):format(
                            (at - part.Position).Magnitude, player.DisplayName, speed, why)
                        or "could not read where the cursor landed"
                    Combat.LastResult = "aim test — " .. text
                    if force then
                        UI.notify({title = "Aim Test", text = text, duration = 4})
                    end
                    return
                end

                -- The click still needs the gun actually out.
                local began = os.clock()
                while not select(2, Game.gunTool()) and os.clock() - began < 0.25 do
                    task.wait()
                end

                Mouse.Firing = true
                local sent = shootHere()
                Combat.LastResult = sent
                    and ("mouse shot at " .. player.DisplayName .. " — " .. why)
                    or "cursor on target but the click went nowhere"
                if force and not sent then
                    UI.notify({title = "Aimbot", text = "the click went nowhere", kind = "bad", duration = 2})
                end
            end

            KH.detach(function()
                -- Both flags have to clear even if the walk throws. A stuck
                -- busy refuses every later shot, and a stuck Firing makes the
                -- silent-aim handler ignore every real click.
                local ok, err = pcall(sequence)
                Mouse.Firing = false
                Mouse.Precise = false
                Mouse.Lead = 0
                activePart = nil
                busy = false
                if not ok then Combat.LastResult = "mouse aim error: " .. tostring(err) end
            end)
            return true
        end
    end

    -- Fires once at the current best target. Returns true when a shot went out.
    function Combat.fireOnce(force)
        -- A key press that does nothing at all is the most confusing thing this
        -- can do, so say why. Only for a real press: the render loop calls this
        -- every frame and would notify every frame with it.
        local function refuse(reason)
            Combat.LastResult = reason
            if force then
                UI.notify({title = "Aimbot", text = reason, kind = "warn", duration = 2})
            end
            return false, reason
        end

        -- An aim test needs no gun: it is checking where the cursor lands, and
        -- waiting to roll sheriff to find that out is most of a round each try.
        local gun = Game.gunTool()
        if not gun and not S.Aim.DryRun then
            return refuse("no gun — you are not holding one")
        end

        local player, char, part = Combat.pickTarget()
        if not player and S.Aim.DryRun then
            -- Anyone will do when nothing is going to be fired at them.
            player, char, part = Combat.pickTarget("Nearest")
        end
        if not player then
            return refuse(S.Aim.Target == "Murderer"
                and "no target — the murderer is not known yet"
                or "no target")
        end
        Combat.LastTarget = player

        local ok, err
        if S.Aim.Method == "Mouse" then
            -- Mouse.fire reports its own result, several frames from now.
            ok, err = Mouse.fire(player, char, part, force)
        else
            ok, err = Combat.fireAt(Combat.aimPoint(char, part), force)
            if ok then
                Combat.LastResult = "remote shot at " .. player.DisplayName
            elseif err ~= "cooldown" then
                -- A cooldown is the fire rate doing its job, not a failure.
                Combat.LastResult = tostring(err)
            end
        end
        -- A cooldown is the fire rate doing its job, not a failure worth saying
        -- out loud; everything else here means the press went nowhere.
        if not ok then
            if err == "cooldown" then return false, err end
            return refuse(tostring(err))
        end

        if S.Aim.NotifyShot then
            UI.notify({title = "Shot", text = "Fired at " .. player.DisplayName, duration = 1.5})
        end
        return ok, err
    end

    -- Why the aimbot is or is not shooting. A dead key, no gun and a shot the
    -- server drops all look identical, and only the last one means anything.
    function Combat.aimStatus()
        if not S.Aim.Enabled then return "off" end
        if not Combat.isEngaged() then
            local key = tostring(S.Aim.Key)
            if S.Aim.Mode == "Press" then
                -- The last press is the only thing worth reporting here.
                return "ready — press " .. key .. (Combat.LastResult and (" · last: " .. Combat.LastResult) or "")
            end
            if S.Aim.Mode == "Toggle" then return "not armed — press " .. key end
            if S.Aim.Mode == "Hold" then return "waiting for " .. key end
            return "idle"
        end
        return "engaged — " .. (Combat.LastResult or "...")
    end

    -- Bound after Roblox's own camera step rather than onto KH's render job.
    -- The job runs before the camera module, so every lock we wrote there was
    -- overwritten in the same frame — the aim fighting itself, once per frame.
    do
        local RunService = KH.Services.RunService
        local BIND = "KittyHubAimCam"

        -- Start turning at the edge of the view, stop well inside it. The gap
        -- between the two is what stops a target hovering near the border from
        -- switching the lock on and off every frame.
        local TURN_IN, TURN_OUT = 0.10, 0.28

        local turning = false
        local held              -- the rotation we are driving, nil when hands off

        -- How far into the view the target is: 0 at the border, 0.5 dead
        -- centre, negative off screen.
        local function inset(part)
            local point, onScreen = Combat.Mouse.screenOf(part)
            if not onScreen then return -1 end
            local view = KH.camera().ViewportSize
            return math.min(
                math.min(point.X, view.X - point.X) / math.max(view.X, 1),
                math.min(point.Y, view.Y - point.Y) / math.max(view.Y, 1))
        end

        -- What the lock should be aiming at, or nil for hands off. Ordered
        -- cheapest test first: this runs every rendered frame of the session,
        -- and in Press mode it answers nil on the second line nearly always.
        local function lockTarget()
            if S.Aim.Method ~= "Mouse" or not S.Aim.CameraSnap then return nil end

            -- While a shot is in flight, hold that shot's target. Between
            -- shots only the sustained triggers keep the camera, which is what
            -- lets Press lock on, fire, and hand it straight back.
            local part = Combat.Mouse.active()
            if not part then
                if not Combat.isEngaged() then return nil end
                local _, _, picked = Combat.pickTarget()
                part = picked
            end
            -- Last, because it is the only test that walks the character.
            if part and (Game.gunTool() or S.Aim.DryRun) then return part end
            return nil
        end

        local function lockCamera(dt)
            local part = lockTarget()
            -- A shot with a locked cursor is aimed entirely by this: it has to
            -- land exactly on the target rather than ease towards it, and it
            -- cannot stop early for being comfortably inside the view.
            local precise = part ~= nil and Combat.Mouse.Precise
            if precise then
                turning = true
            elseif part then
                -- Turn only when there is something to turn for: a target
                -- already well inside the view needs no camera work at all,
                -- and a view that stays still is both smoother and far less
                -- obvious than one that snaps on every shot.
                local depth = inset(part)
                if depth < TURN_IN then turning = true
                elseif depth > TURN_OUT then turning = false end
            else
                turning = false
            end
            -- The walk needs to know: while this is true its projected cursor
            -- reading is a frame behind the camera and must not be trusted.
            Combat.Mouse.Turning = turning
            if not (turning or held) then return end

            local cam = KH.camera()
            local speed = U.clamp(S.Aim.MouseSpeed or 1, 0.1, 1)
            -- The same share of the gap per second rather than per frame, so
            -- the turn lasts the same at 30 fps as at 144.
            local alpha = speed >= 1 and 1
                or U.clamp(1 - (1 - speed) ^ ((dt or 1 / 60) * 60), 0, 1)

            -- Position belongs to the camera module, which has already written
            -- it this frame; we only ever replace the rotation, carried forward
            -- from wherever the module has just put the camera.
            held = CFrame.new(cam.CFrame.Position) * (held or cam.CFrame).Rotation

            if turning then
                local want = CFrame.new(cam.CFrame.Position, Combat.Mouse.aimPoint(part))
                held = precise and want or held:Lerp(want, alpha)
                cam.CFrame = held
                return
            end

            -- Turned far enough, but the shot is still in the air: hold this
            -- rotation rather than starting to give it back. Drifting towards
            -- the player's angles now would walk the target across the screen
            -- while the cursor is still closing on it, and the two would spend
            -- the rest of the shot chasing each other.
            if Combat.Mouse.active() then
                cam.CFrame = held
                return
            end

            -- Hand it back over a few frames rather than dropping it. The
            -- module still holds the angles the player left it at, so letting
            -- go in one frame snaps the view — easing into its CFrame, which is
            -- what we just read, turns that snap into a turn.
            held = held:Lerp(cam.CFrame, alpha)
            if held.LookVector:Dot(cam.CFrame.LookVector) > 0.9995 then
                held = nil
                return
            end
            cam.CFrame = held
        end

        -- A bind left over from a session that failed to unload would make
        -- this one error out and leave the camera unlocked.
        pcall(function() RunService:UnbindFromRenderStep(BIND) end)
        pcall(function()
            RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
                if KH.Alive then KH.safe("aimcam", lockCamera, dt) end
            end)
        end)
        KH.undo(function() pcall(function() RunService:UnbindFromRenderStep(BIND) end) end)
    end

    KH.onFrame("aimbot", function()
        if not Combat.isEngaged() then return end
        Combat.fireOnce(false)
    end, 30)

    -- MM2 stows your tool on respawn and when a round flips, which would
    -- leave the next round's first shot doing nothing but re-equipping.
    KH.loop(0.5, function()
        if not (S.Aim.Enabled and S.Aim.KeepEquipped) then return end
        local gun, equipped = Game.gunTool()
        if gun and not equipped then Game.equip(gun) end
    end)

    -- =========================================================== SILENT AIM
    -- The shot *you* fire by hand lands on the target instead of under your
    -- cursor. Three routes, best available wins:
    --   hook      rewrite the position argument in flight. Invisible, but needs
    --             a real hookmetamethod or a writable game metatable.
    --   takeover  no hook: switch MM2's gun script off so your click stops
    --             producing a shot of its own, and fire the aimed one from that
    --             same click. One shot, out of a plain property write.
    --   click     neither: an aimed shot beside your real one, two beams.
    do
        local X = KH.X
        local UIS = KH.Services.UserInputService

        -- --------------------------------------------------------- route probe
        -- Takeover needs one thing: switching a client script off. A throwaway
        -- instance settles that without going near the gun.
        local canDisableScripts = (function()
            local ok, disabled = pcall(function()
                local probe = Instance.new("LocalScript")
                probe.Disabled = true
                local value = probe.Disabled
                probe:Destroy()
                return value
            end)
            return ok and disabled == true
        end)()

        local hookReady = false      -- set by the install self-test below
        local suppressed = {}        -- [BaseScript] = true, ones we turned off

        -- Which route is live. The manual settings exist because "installed"
        -- and "works" are not the same claim on these executors.
        local function effectiveMode()
            local want = S.Aim.SilentMode or "Auto"
            if want == "Click" then return "click" end
            -- Takeover switches MM2's gun script off; the mouse aimbot fires
            -- that same script. They cannot both be on, and the aimbot wins.
            local canTakeover = canDisableScripts and S.Aim.Method ~= "Mouse"
            if want == "Takeover" then return canTakeover and "takeover" or "click" end
            if hookReady then return "hook" end
            -- Auto and Hook both prefer the hook, and both fall back the same
            -- way when there isn't one.
            return canTakeover and "takeover" or "click"
        end
        Combat.effectiveMode = effectiveMode

        -- ------------------------------------------------------ route 1: hook
        -- Must never throw — an error here breaks the call it wrapped, leaving
        -- the gun unable to shoot — and must ignore our own calls, or Kill All
        -- would have every shot rewritten onto one target. No reliable unhook
        -- exists, so it stays installed and passes through once KH.Alive drops.
        local oldNamecall            -- the original, set by whichever route installs
        local verifying = true       -- flipped off once the install self-test is done
        local sawCall = false

        local function onNamecall(self, ...)
            if verifying then sawCall = true end
            if not oldNamecall then return end
            if not KH.Alive or not S.Aim.SilentAim then
                return oldNamecall(self, ...)
            end
            -- Forced onto another route: leave the shot exactly as it was sent.
            if not verifying and effectiveMode() ~= "hook" then
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
        end

        -- Two ways in: the convenience wrapper, then the raw metatable for
        -- executors that only expose the primitives.
        local function installHook()
            local cb = onNamecall
            if X.newcclosure then
                -- Some executors reject a plain Lua closure as a metamethod.
                local ok, wrapped = pcall(newcclosure, cb)
                if ok and type(wrapped) == "function" then cb = wrapped end
            end

            if X.hookmetamethod then
                local ok, old = pcall(hookmetamethod, game, "__namecall", cb)
                if ok and type(old) == "function" then
                    oldNamecall = old
                    return "hookmetamethod"
                end
            end

            if X.rawmeta then
                local ok = pcall(function()
                    local mt = getrawmetatable(game)
                    local old = rawget(mt, "__namecall")
                    if type(old) ~= "function" then error("__namecall is not a function") end
                    setreadonly(mt, false)
                    oldNamecall = old
                    mt.__namecall = cb
                    setreadonly(mt, true)
                end)
                if ok then return "getrawmetatable" end
                oldNamecall = nil
            end
        end

        local route = installHook()
        if route then
            -- Reporting success and never firing is the normal failure here,
            -- so prove it runs on a harmless call before trusting it.
            pcall(function() return game:GetService("Players") end)
            verifying = false
            hookReady = sawCall
            Combat.SilentRoute = route
            if not sawCall then
                Combat.SilentReason = "the " .. route .. " hook installed but never fires"
            end
        else
            verifying = false
            Combat.SilentReason = (X.hookmetamethod or X.rawmeta)
                and "this executor's metamethod hook could not be installed"
                or "this executor exposes no metamethod hook"
        end
        Combat.HookAvailable = hookReady

        -- -------------------------------------------------- route 2: takeover
        -- Client-side property writes do not replicate, so the server's view of
        -- the tool is untouched — it just stops hearing from the script that
        -- spoke for your mouse. You lose the local shot sound and muzzle flash;
        -- the beam and the kill are the server's work and look normal.
        local function isClientScript(inst)
            if inst:IsA("LocalScript") then return true end
            if not inst:IsA("Script") then return false end
            -- A re-upload could use a client-context Script instead.
            local ok, ctx = pcall(function() return inst.RunContext end)
            return ok and ctx == Enum.RunContext.Client
        end

        -- Only record scripts *we* turned off, so restoring never switches on
        -- something MM2 disabled for its own reasons.
        local function suppress(gun)
            -- Every round destroys the old Gun, so drop the dead entries or the
            -- table grows for the whole session.
            for inst in pairs(suppressed) do
                if not inst.Parent then suppressed[inst] = nil end
            end

            for _, inst in ipairs(gun:GetDescendants()) do
                local ok, isClient = pcall(isClientScript, inst)
                if ok and isClient and not inst.Disabled then
                    if pcall(function() inst.Disabled = true end) and inst.Disabled then
                        suppressed[inst] = true
                    end
                end
            end
        end

        local function restore()
            if not next(suppressed) then return end
            for inst in pairs(suppressed) do
                pcall(function() inst.Disabled = false end)
            end
            suppressed = {}

            -- Re-enabling restarts the script from the top. One that only
            -- connects from Equipped would sit dead until the gun is next
            -- drawn, so hand it that event rather than guess which it is.
            local gun, equipped = Game.gunTool()
            if gun and equipped then
                KH.detach(function()
                    local char = U.charOf(LocalPlayer)
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hum then return end
                    pcall(function() hum:UnequipTools() end)
                    task.wait(0.1)
                    Game.equip(gun)
                end)
            end
        end
        KH.undo(restore)

        -- On a timer, not once: the Gun is a fresh instance every round, and
        -- the toggle and unload have to hand it back at any moment.
        KH.loop(0.3, function()
            if KH.Alive and S.Aim.SilentAim and effectiveMode() == "takeover" then
                local gun = Game.gunTool()
                if gun then suppress(gun) end
            elseif next(suppressed) then
                restore()
            end
        end)

        -- --------------------------------------------------------- your click
        -- Under takeover this *is* the gun — MM2's script is off, so if this
        -- does not fire, nothing does. Under the hook it stays out of the way.
        local mouse
        local function mousePoint()
            local ok, point = pcall(function()
                mouse = mouse or LocalPlayer:GetMouse()
                return mouse.Hit.Position
            end)
            if ok and typeof(point) == "Vector3" then return point end
            return nil
        end

        KH.track(UIS.InputBegan:Connect(function(input, processed)
            -- Touch counts: no-hook executors are also the phone ones.
            local kind = input.UserInputType
            if kind ~= Enum.UserInputType.MouseButton1
                and kind ~= Enum.UserInputType.Touch then return end
            if processed then return end          -- the input landed on the menu
            if Combat.Mouse.Firing then return end -- our own synthetic click
            if not (KH.Alive and S.Aim.SilentAim) then return end

            local mode = effectiveMode()
            if mode == "hook" then return end     -- the hook already redirected it

            -- Only with the gun genuinely in hand. Drawing it here would yank
            -- a murderer's knife away mid-round.
            local gun, equipped = Game.gunTool()
            if not (gun and equipped) then return end

            local ok, err = Combat.fireOnce(false)
            if not ok and err == "no target" and mode == "takeover" then
                -- Nothing to redirect onto and MM2's script is off, so put the
                -- round where you actually pointed.
                local point = mousePoint()
                if point then Combat.fireAt(point, false) end
            end
        end))

        -- ------------------------------------------------------------- status
        -- Both real routes give one shot on target; only "click" has to apologise.
        Combat.SilentDesc = hookReady
            and "Redirects the shot you fire by hand onto the target. One shot, and nothing on screen moves."
            or (canDisableScripts
                and "No working hook on this executor, so Kitty Hub switches MM2's gun script off and fires the aimed shot on your click itself. Still one shot; you lose the local shot sound."
                or "No route on this executor — your click fires an aimed shot beside your real one, so two beams go out.")

        function Combat.silentStatus()
            local mode = effectiveMode()
            if mode == "hook" then
                return "hook (" .. tostring(Combat.SilentRoute) .. ")"
            elseif mode == "takeover" then
                return "takeover" .. (next(suppressed) and " — gun script off" or " — waiting for gun")
            end
            -- Only say *why* when it was forced on us.
            if S.Aim.SilentMode == "Click" then return "click aim, two shots — your choice" end
            if canDisableScripts and S.Aim.Method == "Mouse" then
                return "click aim, two shots — takeover is off while Fire Method is Mouse"
            end
            return "click aim, two shots — " .. (Combat.SilentReason or "no route")
        end
    end

    -- ============================================================= KILL ALL
    -- Sequential, not a burst: MM2 rate-limits the shot remote.
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
    -- `sheriffFirst` is the bound-key path asking for the gun holder whatever
    -- the Target Filter toggles say: pressing the throw key is a deliberate
    -- call, and the one target worth spending the knife on is the one who can
    -- shoot back.
    local function knifeTargets(sheriffFirst)
        local out = {}
        local myRoot = U.myRoot()
        if not myRoot then return out end

        local skipSheriff = S.Knife.SkipSheriff and not sheriffFirst

        for _, player in ipairs(U.otherPlayers()) do
            if Game.isAlive(player) then
                local role = Game.roleOf(player)
                local isSheriff = (role == "Sheriff" or role == "Hero")
                -- Prioritising the sheriff is the sort's job, below. Filtering
                -- here as well left an empty list whenever no sheriff was alive.
                if not (skipSheriff and isSheriff) then
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
        local preferSheriff = sheriffFirst or S.Knife.TargetSheriff
        table.sort(out, function(a, b)
            if preferSheriff and a.sheriff ~= b.sheriff then return a.sheriff end
            return a.distance < b.distance
        end)
        return out
    end
    Combat.knifeTargets = knifeTargets

    -- A thrown knife is gone until it comes back, so it is only worth throwing
    -- at a range the throw can actually cover.
    local function inThrowRange(target)
        return target ~= nil and target.distance <= (S.Knife.ThrowRange or 70)
    end

    -- Asked once now, for the throw that goes straight out, and again at the
    -- release when the animation holds the knife back. Same aim either way.
    local function throwAt(target)
        local function point()
            return U.predict(target.char, S.Aim.Prediction + 1, S.Aim.PingComp)
                or target.part.Position
        end
        return Game.throwKnife(point(), point)
    end

    function Combat.throwAtNearest()
        if not Game.knifeTool() then return false end
        local target = knifeTargets()[1]
        if not inThrowRange(target) then return false end
        return throwAt(target)
    end

    -- The sheriff when the throw can reach them, otherwise the closest target
    -- it can: the list already runs sheriff-then-distance, so the first entry
    -- in range is the right one. Refusing outright because the only sheriff is
    -- across the map would make the key feel dead with someone stood in front
    -- of you.
    local function pickThrowTarget()
        for _, target in ipairs(knifeTargets(true)) do
            if inThrowRange(target) then return target end
        end
        return nil
    end

    -- ------------------------------------------------------ bound-key throw
    -- One press, one throw — no loop, no repeat, no cooldown beyond the draw
    -- it may have to wait for. The flag only covers that draw: while the knife
    -- is already out the whole thing runs inline on the pressing frame, which
    -- is as fast as a throw can be sent.
    local drawing = false

    function Combat.throwOnce(announce)
        local function refuse(text, kind)
            if announce then
                UI.notify({title = "Knife", text = text, kind = kind or "warn"})
            end
            return false
        end

        -- A second press during the draw would put two knives in the air off
        -- one keystroke.
        if drawing then return false end

        local knife, equipped = Game.knifeTool()
        if not knife then return refuse("You have no knife.", "bad") end

        local target = pickThrowTarget()
        if not target then return refuse("Nobody alive within throwing range.") end

        -- Already drawn: send it now rather than a frame later.
        if equipped then return throwAt(target) end

        -- Not drawn. EquipTool is not instant and the server drops a throw from
        -- a knife it does not yet think we hold, so wait for the tool to land
        -- in the character first. It stays out afterwards — nothing here stows
        -- it again, and the next press skips this branch entirely.
        drawing = true
        KH.detach(function()
            -- pcall, or one error leaves the flag stuck on forever.
            pcall(function()
                if not Game.equip(knife) then return end

                local char = U.charOf(LocalPlayer)
                local began = os.clock()
                while knife.Parent ~= char and os.clock() - began < 0.35 do
                    task.wait()
                    char = U.charOf(LocalPlayer)
                end
                if knife.Parent ~= char then return end

                -- Re-pick: the wait is short, but a target can die or walk out
                -- of range inside it and a stale point throws the knife away.
                local fresh = pickThrowTarget()
                if fresh then throwAt(fresh) end
            end)
            drawing = false
        end)
        return true
    end

    -- Auto throw, Always mode only — in Press mode the bound key is the
    -- trigger and a timer running underneath it would throw knives the user
    -- never asked for.
    KH.loop(0.1, function()
        if not (S.Knife.AutoThrow and S.Knife.ThrowMode == "Always") then return end
        if not Game.knifeTool() then return end
        Combat.throwAtNearest()
        task.wait(math.max(S.Knife.ThrowDelay, 0.2))
    end)

    -- Load the throw animation before it is first needed. Its length is what
    -- the release is measured from, and that reads zero until Roblox has the
    -- asset — which would leave the first throw of every round the one that
    -- goes out on frame one.
    KH.loop(1, function()
        if not S.Knife.ThrowAnim then return end
        local knife = Game.knifeTool()
        if knife then Game.primeThrowAnimation(knife) end
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

    -- Blink to the target, swing, blink back. The return hop is what keeps it
    -- from reading as a teleport to everyone else.
    local tpStabRunning = false
    function Combat.tpStab()
        if tpStabRunning then return end
        if not Game.knifeTool() then
            UI.notify({title = "Knife", text = "You are not holding a knife.", kind = "bad"})
            return
        end
        local target = knifeTargets()[1]
        if not target then return end
        -- Blinking the length of the map to reach someone is not a stab, it is
        -- a teleport everyone can see.
        if target.distance > (S.Knife.TpRange or 150) then return end

        tpStabRunning = true
        KH.detach(function()
            local root = U.myRoot()
            if root then
                local origin = root.CFrame
                -- Already within swinging distance: no reason to blink at all.
                if target.distance > 6 then
                    root.CFrame = target.part.CFrame * CFrame.new(0, 0, 2.5)
                    task.wait(0.08)
                end
                Game.stab()
                task.wait(0.12)
                -- Same body only. Dying mid-blink would otherwise drag the
                -- fresh spawn back to where the old one was standing.
                if U.myRoot() == root then root.CFrame = origin end
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
