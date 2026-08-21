-- ============================================================================
--  SAFETY — murderer proximity warning, auto-dodge, round/role announcements
--
--  The half of an MM2 script that actually keeps you alive as an innocent,
--  which most feature lists skip entirely.
-- ============================================================================

do
    local UI   = KH.UI
    local C    = UI.C
    local make = UI.make
    local U    = KH.U
    local Game = KH.Game
    local S    = KH.S

    local Safety = {}
    KH.Safety = Safety
    Safety.MurdererDistance = math.huge

    -- ------------------------------------------------------------ vignette
    -- Four edge bars, each fading inward, make a red pulse around the screen
    -- border. No image assets, and it never obscures the middle of the view.
    local vignette = make("Frame", {
        Name = "Alert",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = UI.Overlay,
    })

    local bars = {}
    local EDGES = {
        {size = UDim2.new(1, 0, 0, 90), pos = UDim2.fromScale(0, 0),    rot = 90},
        {size = UDim2.new(1, 0, 0, 90), pos = UDim2.new(0, 0, 1, -90),  rot = 270},
        {size = UDim2.new(0, 120, 1, 0), pos = UDim2.fromScale(0, 0),   rot = 0},
        {size = UDim2.new(0, 120, 1, 0), pos = UDim2.new(1, -120, 0, 0), rot = 180},
    }
    for _, edge in ipairs(EDGES) do
        local bar = make("Frame", {
            Size = edge.size,
            Position = edge.pos,
            BackgroundColor3 = Color3.fromRGB(255, 40, 40),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = vignette,
        })
        make("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Rotation = edge.rot,
            Parent = bar,
        })
        bars[#bars + 1] = bar
    end

    local function setAlertLevel(intensity)
        local visible = intensity > 0.01
        vignette.Visible = visible
        if not visible then return end
        for _, bar in ipairs(bars) do
            bar.BackgroundTransparency = 1 - (0.55 * intensity)
        end
    end

    -- ==================================================== PROXIMITY WARNING
    local ALERT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
    local lastBeep, lastNotify, lastDodge = 0, 0, 0
    local wasClose = false

    KH.onFrame("proximity", function()
        local murderer = Game.murdererPlayer()
        local myRoot = U.myRoot()

        if not murderer or not myRoot or murderer == KH.LocalPlayer then
            Safety.MurdererDistance = math.huge
            setAlertLevel(0)
            wasClose = false
            return
        end

        local part = U.rootOf(murderer)
        if not part then
            Safety.MurdererDistance = math.huge
            setAlertLevel(0)
            return
        end

        local distance = (myRoot.Position - part.Position).Magnitude
        Safety.MurdererDistance = distance

        -- --------------------------------------------------------- warning
        if S.Safety.ProximityAlert then
            local threshold = S.Safety.AlertDistance
            if distance <= threshold then
                -- Intensity ramps as they close in, so the screen tells you how
                -- much trouble you are in without reading a number.
                local intensity = 1 - (distance / threshold)
                setAlertLevel(S.Safety.AlertFlash and intensity or 0)

                local now = os.clock()
                if not wasClose and now - lastNotify > 4 then
                    lastNotify = now
                    UI.notify({
                        title = "Murderer Nearby",
                        text = ("%s is %dm away."):format(murderer.DisplayName, math.floor(distance)),
                        kind = "bad",
                        duration = 3,
                    })
                end
                -- Beep faster the closer they get.
                if S.Safety.AlertSound then
                    local interval = 0.18 + (distance / threshold) * 0.9
                    if now - lastBeep > interval then
                        lastBeep = now
                        U.playSound(ALERT_SOUND, 0.35)
                    end
                end
                wasClose = true
            else
                setAlertLevel(0)
                wasClose = false
            end
        else
            setAlertLevel(0)
        end

        -- ------------------------------------------------------ auto dodge
        -- Only bails when we are not the one hunting: as murderer or an armed
        -- sheriff, launching yourself into the air is worse than useless.
        if S.Safety.AutoDodge
            and distance <= S.Safety.DodgeDistance
            and os.clock() - lastDodge > 1.5
            and not Game.amMurderer()
            and not Game.gunTool() then
            local root = U.myRoot()
            if root then
                lastDodge = os.clock()
                -- Straight up, away from the knife, keeping our facing intact.
                root.CFrame = root.CFrame + Vector3.new(0, S.Safety.DodgeHeight, 0)
                UI.notify({title = "Dodged", text = "Bailed out of knife range.", kind = "warn", duration = 2})
            end
        end
    end, 40)

    -- ================================================ ROLE ANNOUNCEMENTS
    Game.on("RoleChange", function(murderer, sheriff)
        if not S.Safety.RoleNotify then return end
        if not murderer and not sheriff then return end

        local me = KH.LocalPlayer.Name
        if murderer == me then
            UI.notify({title = "You are the MURDERER", text = "Knife tools are on the Knife tab.", kind = "bad", duration = 6})
        elseif sheriff == me then
            UI.notify({title = "You are the SHERIFF", text = "Aimbot is armed — check the Aimbot tab.", kind = "good", duration = 6})
        end

        local lines = {}
        if murderer then lines[#lines + 1] = "Murderer: " .. murderer end
        if sheriff then lines[#lines + 1] = "Sheriff: " .. sheriff end
        if #lines > 0 then
            UI.notify({
                title = "Roles Revealed",
                text = table.concat(lines, "\n"),
                kind = "warn",
                duration = 7,
            })
        end
    end)

    Game.on("RoundStart", function()
        if S.Safety.RoleNotify then
            UI.notify({title = "Round Started", text = "Waiting for roles…", duration = 3})
        end
    end)

    Game.on("TrapPlaced", function()
        if S.ESP.TrapESP then
            UI.notify({title = "Trap Placed", text = "The murderer set a trap.", kind = "warn", duration = 4})
        end
    end)
end
