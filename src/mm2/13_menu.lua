-- ============================================================================
--  MENU — every tab, section and control
-- ============================================================================

do
    local UI     = KH.UI
    local C      = UI.C
    local make   = UI.make
    local U      = KH.U
    local S      = KH.S
    local Game   = KH.Game
    local Combat = KH.Combat
    local Farm   = KH.Farm
    local Move   = KH.Move
    local Safety = KH.Safety
    local Config = KH.Config
    local Players = KH.Services.Players
    local LocalPlayer = KH.LocalPlayer

    -- Binds a control straight to a settings field, with an optional side
    -- effect to run after the value lands.
    local function opt(group, key, extra)
        local t = extra or {}
        local after = t.onSet
        t.onSet = nil
        t.get = function() return S[group][key] end
        t.set = function(value)
            S[group][key] = value
            if after then after(value) end
        end
        return t
    end

    -- ========================================================== AIMBOT TAB
    do
        local tab = UI.addTab("Aimbot", "🎯")

        local targeting = UI.section(tab, "Targeting")
        UI.label(targeting, "Draws your gun, then shoots the murderer wherever they are — through walls, across the map, no mouse movement. MM2's shot is a world position the server resolves, so nothing needs to be on screen.")
        UI.toggle(targeting, opt("Aim", "Enabled", {
            text = "Aimbot Enabled",
            desc = "Master switch for automatic firing.",
        }))
        UI.dropdown(targeting, opt("Aim", "Target", {
            text = "Target",
            desc = "Nearest and Crosshair will shoot innocents too.",
            options = {"Murderer", "Nearest", "Crosshair"},
        }))
        UI.dropdown(targeting, opt("Aim", "Mode", {
            text = "Trigger",
            desc = "Press: one lock-and-shot per key press — it aims, fires once, and gives the camera straight back. Hold: keeps firing while the key is down. Toggle: press once to stay locked on, again to stop. Always: never stops.",
            options = {"Press", "Hold", "Toggle", "Always"},
        }))
        UI.keybind(targeting, opt("Aim", "Key", {text = "Aim Key"}))
        UI.dropdown(targeting, opt("Aim", "Method", {
            text = "Fire Method",
            desc = "Mouse (default) turns the camera onto the target, puts the cursor on them and clicks, so MM2's own gun fires the shot — the one that works without a hook. Remote hands the server the position instead: silent, shoots through walls, and does nothing at all on an executor the game does not accept built shots from.",
            options = {"Remote", "Mouse"},
        }))
        UI.toggle(targeting, opt("Aim", "KeepEquipped", {
            text = "Keep Gun Equipped",
            desc = "Re-draw the gun if a respawn or round change stows it.",
        }))

        local accuracy = UI.section(tab, "Accuracy")
        UI.slider(accuracy, opt("Aim", "Prediction", {
            text = "Prediction",
            desc = "Studs of lead, Remote method only. Mouse aim points at where the target actually is — leading a client raycast just walks it off their body.",
            min = 0, max = 8, step = 0.1,
        }))
        UI.toggle(accuracy, opt("Aim", "PingComp", {
            text = "Ping Compensation",
            desc = "Scale the lead by your measured ping.",
        }))
        UI.toggle(accuracy, opt("Aim", "AimAtHead", {
            text = "Aim At Head",
            desc = "Target the head instead of the torso.",
        }))
        UI.slider(accuracy, opt("Aim", "FireRate", {
            text = "Fire Rate", min = 0.05, max = 1, step = 0.05, suffix = "s",
        }))

        local mouseAim = UI.section(tab, "Mouse Aim")
        UI.label(mouseAim, "Only used when Fire Method is Mouse. Your camera snaps onto the target and the cursor is driven there, so this one is visible — to you and to anyone watching you.")
        UI.toggle(mouseAim, opt("Aim", "CameraSnap", {
            text = "Turn Camera",
            desc = "Turn towards the target when they are near the edge of your view or behind you, so they do not have to be on screen already. Anyone already well inside the view is left to the cursor alone and the camera stays still. Off, the aimbot can only shoot what you can see.",
        }))
        UI.slider(mouseAim, opt("Aim", "MouseSpeed", {
            text = "Aim Speed",
            desc = "Governs the turn and the cursor together. 1 is an instant snap; lower eases both, which looks far smoother for a few frames' delay. 0.4 lands in about a tenth of a second.",
            min = 0.1, max = 1, step = 0.05,
        }))
        UI.readout(mouseAim, {
            text = "Mouse Control",
            get = function() return Combat.Mouse.support() end,
        })

        local extras = UI.section(tab, "Extras")
        UI.toggle(extras, opt("Aim", "SilentAim", {
            text = "Silent Aim",
            desc = Combat.SilentDesc,
        }))
        UI.dropdown(extras, opt("Aim", "SilentMode", {
            text = "Silent Aim Route",
            desc = "Auto picks the best one your executor can do. Takeover needs no hook at all — switch to it by hand if Auto's hook reports success but your shots still miss.",
            options = {"Auto", "Hook", "Takeover", "Click"},
        }))
        UI.readout(extras, {
            text = "Route In Use",
            get = function() return Combat.silentStatus() end,
        })
        UI.toggle(extras, opt("Aim", "NotifyShot", {text = "Notify On Shot"}))
        UI.readout(extras, {
            text = "Aimbot Status",
            get = function() return Combat.aimStatus() end,
        })
        UI.readout(extras, {
            text = "Current Target",
            get = function()
                local target = Combat.LastTarget
                if target and target.Parent then return target.DisplayName end
                return "none"
            end,
        })
        UI.button(extras, {
            text = "Kill All",
            desc = "Fire at every living player in sequence.",
            kind = "danger",
            callback = function() Combat.killAll() end,
        })
    end

    -- =========================================================== KNIFE TAB
    do
        local tab = UI.addTab("Knife", "🔪")
        UI.label(UI.section(tab, "Murderer Only"),
            "These do nothing unless you are holding the knife.")

        local throwing = UI.section(tab, "Throwing")
        UI.toggle(throwing, opt("Knife", "AutoThrow", {
            text = "Auto Throw",
            desc = "Throw at the closest valid target on a timer.",
        }))
        UI.slider(throwing, opt("Knife", "ThrowDelay", {
            text = "Throw Delay", min = 0.2, max = 5, step = 0.1, suffix = "s",
        }))
        UI.slider(throwing, opt("Knife", "ThrowRange", {
            text = "Throw Range",
            desc = "Do not throw at anyone further away than this. The knife is gone until it comes back, so a throw that cannot reach costs you the weapon for nothing.",
            min = 20, max = 200, step = 5, suffix = " studs",
        }))
        UI.button(throwing, {
            text = "Throw Now",
            callback = function()
                if not Combat.throwAtNearest() then
                    UI.notify({title = "Knife", text = "No knife or no target.", kind = "warn"})
                end
            end,
        })

        local melee = UI.section(tab, "Melee")
        UI.toggle(melee, opt("Knife", "Aura", {
            text = "Knife Aura",
            desc = "Stab anyone who walks into range.",
        }))
        UI.slider(melee, opt("Knife", "AuraRadius", {
            text = "Aura Radius", min = 5, max = 40, step = 1, suffix = " studs",
        }))
        UI.slider(melee, opt("Knife", "AuraDelay", {
            text = "Aura Delay", min = 0.05, max = 1, step = 0.05, suffix = "s",
        }))
        UI.toggle(melee, opt("Knife", "TpStab", {
            text = "Teleport Stab",
            desc = "Blink to the target, swing, blink back. Anyone already within swinging distance is stabbed where they stand.",
        }))
        UI.slider(melee, opt("Knife", "TpRange", {
            text = "Teleport Range",
            desc = "How far a blink is worth making. Crossing the map to reach someone is not a stab, it is a teleport everyone sees.",
            min = 20, max = 400, step = 10, suffix = " studs",
        }))

        local targets = UI.section(tab, "Target Filter")
        UI.toggle(targets, opt("Knife", "TargetSheriff", {
            text = "Prioritise Sheriff",
            desc = "Go for whoever is holding the gun first, then everyone else by distance.",
        }))
        UI.toggle(targets, opt("Knife", "SkipSheriff", {
            text = "Never Target Sheriff",
            desc = "Avoid the gun holder entirely.",
        }))
    end

    -- ============================================================= ESP TAB
    do
        local tab = UI.addTab("ESP", "👁")

        local players = UI.section(tab, "Players")
        UI.toggle(players, opt("ESP", "Enabled", {text = "ESP Enabled"}))
        UI.toggle(players, opt("ESP", "Boxes", {text = "Boxes"}))
        UI.dropdown(players, opt("ESP", "BoxStyle", {
            text = "Box Style", options = {"Corner", "Full"},
        }))
        UI.toggle(players, opt("ESP", "Names", {text = "Names"}))
        UI.toggle(players, opt("ESP", "Roles", {text = "Role Labels"}))
        UI.toggle(players, opt("ESP", "Distance", {text = "Show Distance"}))
        UI.toggle(players, opt("ESP", "Health", {text = "Health Bars"}))
        UI.toggle(players, opt("ESP", "Tracers", {text = "Tracers"}))
        UI.dropdown(players, opt("ESP", "TracerOrigin", {
            text = "Tracer Origin", options = {"Bottom", "Center"},
        }))
        UI.toggle(players, opt("ESP", "Chams", {
            text = "Chams", desc = "Fill characters with their role colour.",
        }))
        UI.slider(players, opt("ESP", "ChamsFill", {
            text = "Cham Opacity", min = 0, max = 0.95, step = 0.05,
        }))
        UI.toggle(players, opt("ESP", "OffScreen", {
            text = "Off-Screen Arrows",
            desc = "Edge markers pointing at players behind you.",
        }))
        UI.toggle(players, opt("ESP", "OnlyRoles", {
            text = "Hide Innocents",
            desc = "Only draw the murderer, sheriff and hero.",
        }))
        UI.slider(players, opt("ESP", "MaxDistance", {
            text = "Max Distance", min = 100, max = 5000, step = 50, suffix = " studs",
        }))
        UI.slider(players, opt("ESP", "TextSize", {
            text = "Text Size", min = 8, max = 22, step = 1,
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("ESP", "CoinESP", {text = "Coin ESP"}))
        UI.toggle(world, opt("ESP", "GunESP", {
            text = "Gun Drop ESP", desc = "Highlight the gun when a sheriff dies.",
        }))
        UI.toggle(world, opt("ESP", "TrapESP", {
            text = "Trap ESP", desc = "Reveal the murderer's traps.",
        }))

        local colours = UI.section(tab, "Colours")
        UI.colorpicker(colours, opt("ESP", "ColorMurderer", {text = "Murderer"}))
        UI.colorpicker(colours, opt("ESP", "ColorSheriff", {text = "Sheriff"}))
        UI.colorpicker(colours, opt("ESP", "ColorHero", {text = "Hero"}))
        UI.colorpicker(colours, opt("ESP", "ColorInnocent", {text = "Innocent"}))
    end

    -- ============================================================ FARM TAB
    do
        local tab = UI.addTab("Farm", "💰")

        local coins = UI.section(tab, "Coins")
        UI.toggle(coins, opt("Farm", "CoinFarm", {
            text = "Auto Coin Farm",
            desc = "Travel to every coin on the map and collect it.",
        }))
        UI.dropdown(coins, opt("Farm", "CoinMode", {
            text = "Travel Mode",
            desc = "Teleport is fastest; Walk is the least obvious.",
            options = {"Teleport", "Smooth", "Walk"},
        }))
        UI.slider(coins, opt("Farm", "CoinSpeed", {
            text = "Smooth Speed", min = 20, max = 300, step = 10, suffix = " s/s",
        }))
        UI.slider(coins, opt("Farm", "CoinDelay", {
            text = "Teleport Delay", min = 0, max = 1, step = 0.02, suffix = "s",
        }))
        UI.toggle(coins, opt("Farm", "LobbyFarm", {
            text = "Include Lobby",
            desc = "Also collect the coins in the lobby between rounds.",
        }))

        local magnet = UI.section(tab, "Coin Magnet")
        UI.label(magnet, "Collects nearby coins without moving you. Slower, but it stacks with playing normally.")
        UI.toggle(magnet, opt("Farm", "Magnet", {text = "Coin Magnet"}))
        UI.slider(magnet, opt("Farm", "MagnetRadius", {
            text = "Magnet Radius", min = 5, max = 120, step = 5, suffix = " studs",
        }))

        local gun = UI.section(tab, "Dropped Gun")
        UI.toggle(gun, opt("Farm", "AutoGrabGun", {
            text = "Auto Grab Gun",
            desc = "Rush the gun the moment a sheriff dies.",
        }))
        UI.toggle(gun, opt("Farm", "GrabReturn", {
            text = "Return After Grab",
            desc = "Snap back to where you were standing.",
        }))
        UI.button(gun, {text = "Grab Gun Now", callback = function() Farm.grabGun(true) end})

        local session = UI.section(tab, "Session")
        UI.toggle(session, opt("Farm", "AntiAFK", {
            text = "Anti-AFK", desc = "Block the twenty-minute idle kick.",
        }))
        UI.readout(session, {text = "Coins Collected", get = function() return Farm.Collected end})
        UI.readout(session, {text = "Shots Fired", get = function() return Game.ShotsFired end})
    end

    -- ========================================================== SAFETY TAB
    do
        local tab = UI.addTab("Safety", "🛡")

        local warning = UI.section(tab, "Murderer Warning")
        UI.label(warning, "The half of an MM2 script that keeps you alive when you are just an innocent.")
        UI.toggle(warning, opt("Safety", "ProximityAlert", {
            text = "Proximity Alert",
            desc = "Warn when the murderer closes in.",
        }))
        UI.slider(warning, opt("Safety", "AlertDistance", {
            text = "Alert Distance", min = 10, max = 150, step = 5, suffix = " studs",
        }))
        UI.toggle(warning, opt("Safety", "AlertSound", {
            text = "Alert Beep", desc = "Beeps faster the closer they get.",
        }))
        UI.toggle(warning, opt("Safety", "AlertFlash", {
            text = "Screen Edge Flash",
            desc = "Red vignette that intensifies with proximity.",
        }))
        UI.readout(warning, {
            text = "Murderer Distance",
            get = function()
                local distance = Safety.MurdererDistance
                if distance == math.huge then return "unknown" end
                return ("%dm"):format(math.floor(distance))
            end,
        })

        local dodge = UI.section(tab, "Auto Dodge")
        UI.toggle(dodge, opt("Safety", "AutoDodge", {
            text = "Auto Dodge",
            desc = "Launch upward if the knife gets too close. Off while armed.",
        }))
        UI.slider(dodge, opt("Safety", "DodgeDistance", {
            text = "Trigger Distance", min = 5, max = 40, step = 1, suffix = " studs",
        }))
        UI.slider(dodge, opt("Safety", "DodgeHeight", {
            text = "Dodge Height", min = 10, max = 200, step = 5, suffix = " studs",
        }))

        local announce = UI.section(tab, "Announcements")
        UI.toggle(announce, opt("Safety", "RoleNotify", {
            text = "Role Reveal",
            desc = "Name the murderer and sheriff the moment roles are dealt.",
        }))
    end

    -- ======================================================== MOVEMENT TAB
    do
        local tab = UI.addTab("Movement", "🏃")

        local speed = UI.section(tab, "Speed & Jump")
        UI.toggle(speed, opt("Move", "SpeedEnabled", {
            text = "Speed Hack", onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Speed", {
            text = "Walk Speed", min = 16, max = 250, step = 1,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.dropdown(speed, opt("Move", "SpeedMode", {
            text = "Speed Mode",
            desc = "CFrame ignores server speed clamps but looks less natural.",
            options = {"Humanoid", "CFrame"},
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "JumpEnabled", {
            text = "Jump Hack", onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Jump", {
            text = "Jump Power", min = 50, max = 400, step = 5,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "InfJump", {text = "Infinite Jump"}))
        UI.toggle(speed, opt("Move", "Bhop", {
            text = "Bunny Hop", desc = "Auto-jump while holding space.",
        }))

        local clip = UI.section(tab, "Noclip & Fly")
        UI.toggle(clip, opt("Move", "Noclip", {
            text = "Noclip", onSet = function(v) Move.setNoclip(v) end,
        }))
        UI.keybind(clip, opt("Move", "NoclipKey", {text = "Noclip Key"}))
        UI.toggle(clip, opt("Move", "Fly", {
            text = "Fly",
            desc = "WASD to move, Space up, Left Shift down.",
            onSet = function(v) Move.setFly(v) end,
        }))
        UI.keybind(clip, opt("Move", "FlyKey", {text = "Fly Key"}))
        UI.slider(clip, opt("Move", "FlySpeed", {
            text = "Fly Speed", min = 10, max = 300, step = 5,
        }))
        UI.toggle(clip, opt("Move", "Spinbot", {
            text = "Spinbot", desc = "Constantly rotate your character.",
        }))

        local teleport = UI.section(tab, "Teleport")
        UI.button(teleport, {text = "To Murderer", callback = function() Move.tpMurderer() end})
        UI.button(teleport, {text = "To Sheriff", callback = function() Move.tpSheriff() end})
        UI.button(teleport, {text = "To Dropped Gun", callback = function() Move.tpGunDrop() end})
        UI.button(teleport, {text = "To Nearest Coin", callback = function() Move.tpCoin() end})
        UI.button(teleport, {text = "To Lobby", callback = function() Move.tpLobby() end})
        UI.button(teleport, {text = "To Random Spawn", callback = function() Move.tpRandomSpawn() end})

        local waypoints = UI.section(tab, "Waypoints")
        local pendingName = {value = ""}
        local selected = {value = ""}
        local waypointDropdown

        local function refreshWaypoints()
            local names = Move.waypointNames()
            if #names == 0 then names = {"(none saved)"} end
            if waypointDropdown then waypointDropdown.setOptions(names) end
        end

        UI.input(waypoints, {
            text = "Waypoint Name",
            placeholder = "e.g. roof camp",
            get = function() return pendingName.value end,
            set = function(v) pendingName.value = v end,
        })
        UI.button(waypoints, {
            text = "Save Current Position",
            callback = function()
                if Move.saveWaypoint(pendingName.value) then refreshWaypoints() end
            end,
        })
        waypointDropdown = UI.dropdown(waypoints, {
            text = "Saved Waypoints",
            options = {"(none saved)"},
            get = function() return selected.value ~= "" and selected.value or "(none saved)" end,
            set = function(v) selected.value = v end,
        })
        UI.button(waypoints, {
            text = "Teleport To Waypoint",
            callback = function() Move.gotoWaypoint(selected.value) end,
        })
        UI.button(waypoints, {
            text = "Delete Waypoint",
            kind = "danger",
            callback = function()
                if Move.deleteWaypoint(selected.value) then
                    selected.value = ""
                    refreshWaypoints()
                end
            end,
        })
        refreshWaypoints()
    end

    -- ========================================================= VISUALS TAB
    do
        local tab = UI.addTab("Visuals", "✨")

        local lighting = UI.section(tab, "Lighting")
        UI.toggle(lighting, opt("Visual", "Fullbright", {
            text = "Fullbright", desc = "Flatten the lighting so nowhere is dark.",
        }))
        UI.slider(lighting, opt("Visual", "Brightness", {
            text = "Brightness", min = 0.5, max = 6, step = 0.1,
        }))
        UI.toggle(lighting, opt("Visual", "NoFog", {text = "Remove Fog"}))

        local camera = UI.section(tab, "Camera")
        UI.toggle(camera, opt("Visual", "FovEnabled", {text = "Custom Field Of View"}))
        UI.slider(camera, opt("Visual", "Fov", {
            text = "Field Of View", min = 40, max = 120, step = 1, suffix = "°",
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("Visual", "Xray", {
            text = "X-Ray Walls",
            desc = "Make the map semi-transparent. Players stay solid.",
        }))
        UI.slider(world, opt("Visual", "XrayTransp", {
            text = "Wall Transparency", min = 0.2, max = 0.95, step = 0.05,
        }))
        UI.toggle(world, opt("Visual", "LowDetail", {
            text = "Low Detail Mode",
            desc = "Disable particles, trails and shadows for more frames.",
        }))
    end

    -- ========================================================= PLAYERS TAB
    do
        local tab = UI.addTab("Players", "👥")
        local section = UI.section(tab, "In This Server")
        UI.label(section, "Live roster with roles. Click a name to spectate, or use the arrow to teleport.")

        local listHolder = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = section.body,
        })
        UI.list(listHolder, 4)

        local spectating = nil
        local function setSpectate(player)
            local cam = KH.camera()
            if spectating == player or player == nil then
                spectating = nil
                local hum = U.myHum()
                if hum then cam.CameraSubject = hum end
                UI.notify({title = "Spectate", text = "Back to your own view.", duration = 2})
            else
                local hum = U.humOf(player)
                if not hum then
                    UI.notify({title = "Spectate", text = "No character to watch.", kind = "warn"})
                    return
                end
                spectating = player
                cam.CameraSubject = hum
                UI.notify({title = "Spectate", text = "Watching " .. player.DisplayName .. ".", duration = 2})
            end
        end
        KH.undo(function() setSpectate(nil) end)

        local rows = {}

        local function buildRow(player)
            local row = make("Frame", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = C.Row,
                BackgroundTransparency = 0.55,
                BorderSizePixel = 0,
                Parent = listHolder,
            })
            UI.corner(row, 7)

            local dot = make("Frame", {
                Position = UDim2.fromOffset(10, 13),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = C.TextDim,
                BorderSizePixel = 0,
                Parent = row,
            })
            UI.corner(dot, 4)

            local name = make("TextButton", {
                Text = player.DisplayName,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = C.Text,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Position = UDim2.fromOffset(26, 0),
                Size = UDim2.new(1, -140, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
            name.MouseButton1Click:Connect(function() setSpectate(player) end)

            local info = make("TextLabel", {
                Text = "",
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextColor3 = C.TextDim,
                BackgroundTransparency = 1,
                RichText = true,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -40, 0.5, 0),
                Size = UDim2.fromOffset(120, 20),
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })

            local tp = make("TextButton", {
                Text = "→",
                Font = Enum.Font.GothamBold,
                TextSize = 15,
                TextColor3 = C.TextDim,
                BackgroundColor3 = C.Card,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(26, 22),
                Parent = row,
            })
            UI.corner(tp, 6)
            tp.MouseButton1Click:Connect(function() Move.tpToPlayer(player) end)
            tp.MouseEnter:Connect(function() tp.TextColor3 = C.Text end)
            tp.MouseLeave:Connect(function() tp.TextColor3 = C.TextDim end)

            return {row = row, dot = dot, name = name, info = info, player = player}
        end

        local function refreshList()
            local present = {}
            for _, player in ipairs(Players:GetPlayers()) do
                present[player] = true
                if not rows[player] then rows[player] = buildRow(player) end
            end
            for player, entry in pairs(rows) do
                if not present[player] then
                    pcall(function() entry.row:Destroy() end)
                    rows[player] = nil
                end
            end

            local myRoot = U.myRoot()
            for player, entry in pairs(rows) do
                local color, role = Game.colorOf(player)
                entry.dot.BackgroundColor3 = color

                local bits = {}
                if player == LocalPlayer then
                    bits[#bits + 1] = "you"
                elseif myRoot then
                    local part = U.rootOf(player)
                    if part then
                        bits[#bits + 1] = ("%dm"):format(
                            math.floor((myRoot.Position - part.Position).Magnitude))
                    end
                end
                if not Game.isAlive(player) then bits[#bits + 1] = "dead" end

                entry.info.Text = ('<font color="#%s">%s</font>  %s')
                    :format(color:ToHex(), role, table.concat(bits, " · "))
                entry.name.TextColor3 = (spectating == player) and color or C.Text
            end
        end

        KH.loop(0.6, function()
            if UI.IsOpen and UI.ActiveTab == "Players" then refreshList() end
        end)
        refreshList()
    end

    -- ======================================================== SETTINGS TAB
    do
        local tab = UI.addTab("Settings", "⚙")

        local interface = UI.section(tab, "Interface")
        UI.keybind(interface, opt("UI", "MenuKey", {text = "Menu Key"}))
        UI.colorpicker(interface, opt("UI", "Accent", {
            text = "Accent Colour",
            onSet = function(color) UI.applyAccent(color) end,
        }))
        UI.toggle(interface, opt("UI", "Watermark", {
            text = "Watermark",
            onSet = function(v) UI.Watermark.Visible = v end,
        }))
        UI.toggle(interface, opt("UI", "KeybindList", {
            text = "Keybind List",
            onSet = function(v) UI.KeybindPanel.Visible = v end,
        }))
        UI.toggle(interface, opt("UI", "Notifications", {text = "Notifications"}))

        local configs = UI.section(tab, "Configuration")
        if not Config.available then
            UI.label(configs, "This executor exposes no file API, so settings only persist until you close Roblox.")
        else
            UI.label(configs, "Profiles are stored in the KittyHub/configs folder next to your executor.")
        end
        UI.toggle(configs, opt("UI", "AutoSave", {
            text = "Auto Save",
            desc = "Write the active profile whenever something changes.",
        }))

        local profileName = {value = S.UI.Profile}
        local profileDropdown

        local function refreshProfiles()
            local names = Config.list()
            if #names == 0 then names = {"default"} end
            if profileDropdown then profileDropdown.setOptions(names) end
        end

        UI.input(configs, {
            text = "Profile Name",
            placeholder = "default",
            get = function() return profileName.value end,
            set = function(v) profileName.value = v end,
        })
        UI.button(configs, {
            text = "Save Profile",
            kind = "primary",
            callback = function()
                local ok, err = Config.save(profileName.value)
                if ok then
                    S.UI.Profile = profileName.value
                    refreshProfiles()
                    UI.notify({title = "Config", text = 'Saved "' .. profileName.value .. '".', kind = "good"})
                else
                    UI.notify({title = "Config", text = tostring(err), kind = "bad"})
                end
            end,
        })
        profileDropdown = UI.dropdown(configs, {
            text = "Saved Profiles",
            options = {"default"},
            get = function() return profileName.value end,
            set = function(v) profileName.value = v end,
        })
        UI.button(configs, {
            text = "Load Profile",
            callback = function()
                local ok, err = Config.load(profileName.value)
                if ok then
                    UI.refreshAll()
                    UI.applyAccent(S.UI.Accent)
                    UI.notify({title = "Config", text = 'Loaded "' .. profileName.value .. '".', kind = "good"})
                else
                    UI.notify({title = "Config", text = tostring(err), kind = "bad"})
                end
            end,
        })
        UI.button(configs, {
            text = "Delete Profile",
            kind = "danger",
            callback = function()
                Config.delete(profileName.value)
                refreshProfiles()
                UI.notify({title = "Config", text = "Deleted."})
            end,
        })
        UI.button(configs, {
            text = "Reset To Defaults",
            kind = "danger",
            callback = function()
                Config.reset()
                UI.refreshAll()
                UI.applyAccent(S.UI.Accent)
                UI.notify({title = "Config", text = "Settings reset.", kind = "warn"})
            end,
        })
        refreshProfiles()

        local session = UI.section(tab, "Session")
        UI.readout(session, {text = "Executor", get = function() return KH.X.name end})
        UI.readout(session, {
            text = "Silent Aim Support",
            get = function() return Combat.silentStatus() end,
        })
        UI.readout(session, {
            text = "Mouse Control",
            get = function() return Combat.Mouse.support() end,
        })
        UI.readout(session, {
            text = "Metamethod Hook",
            get = function()
                if Combat.HookAvailable then return tostring(Combat.SilentRoute) end
                return "none — " .. (Combat.SilentReason or "not exposed")
            end,
        })
        UI.button(session, {
            text = "Rejoin Server",
            callback = function() KH.rejoin() end,
        })
        UI.button(session, {
            text = "Server Hop",
            desc = "Find a different public server for this place.",
            callback = function() KH.serverHop() end,
        })
        UI.button(session, {
            text = "Unload Kitty Hub",
            kind = "danger",
            desc = "Remove the menu and undo every change.",
            callback = function() KH.unload() end,
        })
    end

    UI.selectTab("Aimbot")
end
