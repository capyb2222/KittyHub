-- ============================================================================
--  PROBE — the diagnostics tab. Everything the mouse aim rests on but cannot
--  see for itself: whether the cursor answers a synthetic move, what a pixel is
--  worth to it, how fast a target really crosses the screen, and where the last
--  few shots actually landed.
-- ============================================================================

do
    local UI     = KH.UI
    local U      = KH.U
    local Combat = KH.Combat
    local UIS    = KH.Services.UserInputService
    local LocalPlayer = KH.LocalPlayer

    local Probe = {}
    KH.Probe = Probe

    Probe.Cursor = "not run yet"
    local live = {}       -- the target's numbers, while the tab is open
    local history = {}    -- the last few aim results, newest first
    local lines = {}      -- the labels those are printed into
    local lastResult

    -- --------------------------------------------------------- cursor test
    -- Ask for a move of a known size and watch what mouse.X/Y makes of it. Two
    -- answers matter: whether it answers at all, which is what the whole aim
    -- loop is built on, and by how much, which is the display scale it has to
    -- learn rather than assume.
    local testing = false
    function Probe.testCursor()
        if testing then return end
        if type(mousemoverel) ~= "function" then
            Probe.Cursor = "no mousemoverel on this executor"
            return
        end
        testing = true
        Probe.Cursor = "running…"

        KH.detach(function()
            pcall(function()
                local mouse = LocalPlayer:GetMouse()
                local home = Vector2.new(mouse.X, mouse.Y)
                local lag, scale, lost = {}, {}, 0

                -- Start from the middle of the screen. A move that runs into
                -- the edge of the window is clamped, and a clamped sample looks
                -- exactly like a wildly wrong display scale.
                local view = KH.camera().ViewportSize
                pcall(mousemoverel,
                    math.floor(view.X / 2 - mouse.X + 0.5),
                    math.floor(view.Y / 2 - mouse.Y + 0.5))
                task.wait()
                task.wait()

                local moves = {
                    Vector2.new(120, 0), Vector2.new(-120, 0),
                    Vector2.new(0, 90), Vector2.new(0, -90),
                }
                for _, delta in ipairs(moves) do
                    local from = Vector2.new(mouse.X, mouse.Y)
                    pcall(mousemoverel, delta.X, delta.Y)

                    local landed, waited = nil, 0
                    for frame = 1, 10 do
                        task.wait()
                        waited = frame
                        if (Vector2.new(mouse.X, mouse.Y) - from).Magnitude >= 1 then
                            task.wait()   -- one more, in case it arrives in pieces
                            landed = Vector2.new(mouse.X, mouse.Y)
                            break
                        end
                    end

                    if landed then
                        lag[#lag + 1] = waited
                        scale[#scale + 1] = delta.Magnitude
                            / math.max((landed - from).Magnitude, 0.001)
                    else
                        lost = lost + 1
                    end
                end

                -- Put it back roughly where it was found.
                pcall(mousemoverel,
                    math.floor(home.X - mouse.X + 0.5),
                    math.floor(home.Y - mouse.Y + 0.5))

                if lost >= 3 then
                    Probe.Cursor = "never moved — mouse aim cannot work on this setup"
                elseif #scale == 0 then
                    Probe.Cursor = "no usable samples"
                else
                    local frames = 0
                    for i = 1, #lag do frames = frames + lag[i] end

                    -- Median, and every sample printed beside it. One clamped
                    -- or half-landed move used to drag the mean into nonsense
                    -- and make a healthy setup look broken.
                    local sorted, each = {}, {}
                    for i = 1, #scale do
                        sorted[i] = scale[i]
                        each[i] = ("%.2f"):format(scale[i])
                    end
                    table.sort(sorted)

                    Probe.Cursor = ("%d frame lag · scale %.2f (%s)%s"):format(
                        math.floor(frames / #lag + 0.5),
                        sorted[math.ceil(#sorted / 2)],
                        table.concat(each, " "),
                        lost > 0 and (" · " .. lost .. " lost") or "")
                end
            end)
            testing = false
        end)
    end

    -- ----------------------------------------------------------------- tab
    local tab = UI.addTab("Probe")

    local env = UI.section(tab, "This Executor")
    UI.label(env, "What the mouse aim has to work with. If something here is wrong, no amount of tuning on the Aimbot tab will land a shot.")
    UI.readout(env, {text = "Mouse Control", get = function() return Combat.Mouse.support() end})
    UI.readout(env, {
        text = "Mouse Behaviour",
        get = function()
            local mode = tostring(UIS.MouseBehavior):gsub("Enum%.MouseBehavior%.", "")
            if mode == "Default" then return mode end
            return mode .. " — cursor is locked"
        end,
    })
    UI.button(env, {text = "Run Cursor Test", callback = function() Probe.testCursor() end})
    UI.readout(env, {text = "Cursor Test", get = function() return Probe.Cursor end})

    local target = UI.section(tab, "Target Right Now")
    UI.label(target, "Live while this tab is open. The last line is the one that matters: a shot takes roughly 30 ms from the key press to the server, so anything near that is a target the aim has to lead rather than follow.")
    UI.readout(target, {text = "Target", get = function() return live.name or "none" end})
    UI.readout(target, {
        text = "Distance",
        get = function() return live.distance and ("%.0f studs"):format(live.distance) or "—" end,
    })
    UI.readout(target, {
        text = "Speed",
        get = function() return live.speed and ("%.0f studs/s"):format(live.speed) or "—" end,
    })
    UI.readout(target, {
        text = "On Screen",
        get = function()
            if not live.name then return "—" end
            return live.onScreen and "yes" or "no"
        end,
    })
    UI.readout(target, {
        text = "Body Width",
        get = function() return live.radius and ("%.0f px"):format(live.radius * 2) or "—" end,
    })
    UI.readout(target, {
        text = "Screen Speed",
        get = function() return live.pxPerSec and ("%.0f px/s"):format(live.pxPerSec) or "—" end,
    })
    UI.readout(target, {
        text = "Crosses Own Width",
        get = function() return live.crossMs and ("%.0f ms"):format(live.crossMs) or "—" end,
    })

    local results = UI.section(tab, "Last Aim Results")
    UI.label(results, "Switch on Aim Test on the Aimbot tab, then press your aim key at someone who is moving. Under a stud means the cursor was on them; twenty means the ray went past them into the scenery.")
    for i = 1, 6 do
        lines[i] = UI.label(results, "—")
    end

    -- -------------------------------------------------------- the report
    -- One button, one paste. Reading numbers off a screen and retyping them is
    -- how the important digit gets lost.
    local function report()
        local out = {
            "kitty hub probe · v" .. tostring(KH.Version),
            "executor: " .. tostring(KH.X.name),
            "mouse control: " .. tostring(Combat.Mouse.support()),
            "mouse behaviour: " .. tostring(UIS.MouseBehavior),
            "cursor test: " .. tostring(Probe.Cursor),
        }
        if live.name then
            out[#out + 1] = ("target: %s · %.0f studs · %.0f studs/s · body %.0f px · %.0f px/s · own width in %s")
                :format(live.name, live.distance or 0, live.speed or 0,
                    (live.radius or 0) * 2, live.pxPerSec or 0,
                    live.crossMs and ("%.0f ms"):format(live.crossMs) or "n/a")
        else
            out[#out + 1] = "target: none in view"
        end
        out[#out + 1] = "aim results:"
        for i = 1, #history do out[#out + 1] = "  " .. tostring(history[i]) end
        if #history == 0 then out[#out + 1] = "  (none yet)" end
        return table.concat(out, "\n")
    end

    local share = UI.section(tab, "Report")
    UI.label(share, "Copies everything on this tab as text. Open the tab, take a few shots at someone moving with Aim Test on, then copy.")
    UI.button(share, {
        text = "Copy Report",
        callback = function()
            local ok, text = pcall(report)
            if not ok then
                UI.notify({title = "Probe", text = "Could not build the report.", kind = "bad", duration = 3})
                return
            end
            if KH.X.setclipboard and pcall(setclipboard, text) then
                UI.notify({title = "Probe", text = "Copied. Paste it wherever you need it.", kind = "good", duration = 3})
            else
                print(text)
                UI.notify({
                    title = "Probe",
                    text = "No clipboard here — printed to the console (F9) instead.",
                    kind = "warn",
                    duration = 5,
                })
            end
        end,
    })

    -- ------------------------------------------------------- aim history
    -- Polled rather than pushed: the aim already writes its own outcome, and
    -- nothing here has to reach into it to find out.
    KH.loop(0.2, function()
        local result = Combat.LastResult
        if not result or result == lastResult then return end
        lastResult = result
        table.insert(history, 1, result)
        for i = #history, 7, -1 do history[i] = nil end
        for i = 1, #lines do lines[i].Text = history[i] or "—" end
    end)

    -- ------------------------------------------------------- live target
    local lastPoint, lastAt
    KH.loop(0.1, function()
        if not (UI.IsOpen and UI.ActiveTab == "Probe") then
            lastPoint = nil
            return
        end

        local player, _, part = Combat.pickTarget()
        if not player then player, _, part = Combat.pickTarget("Nearest") end
        if not part then
            live, lastPoint = {}, nil
            return
        end

        local cam = KH.camera()
        local point, onScreen = cam:WorldToViewportPoint(part.Position)
        local here = Vector2.new(point.X, point.Y)
        local now = os.clock()

        local pxPerSec = 0
        if lastPoint and now > lastAt then
            pxPerSec = (here - lastPoint).Magnitude / (now - lastAt)
        end
        lastPoint, lastAt = here, now

        local edge = cam:WorldToViewportPoint(part.Position + Vector3.new(0, part.Size.Y * 0.5, 0))
        local radius = (Vector2.new(edge.X, edge.Y) - here).Magnitude

        local speed = 0
        pcall(function() speed = part.AssemblyLinearVelocity.Magnitude end)

        live = {
            name = player.DisplayName,
            onScreen = onScreen,
            distance = U.distanceTo(part.Position),
            speed = speed,
            pxPerSec = pxPerSec,
            radius = radius,
            crossMs = pxPerSec > 1 and (radius * 2 / pxPerSec) * 1000 or nil,
        }
    end)
end
