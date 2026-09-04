-- ============================================================================
--  MENU — every tab, section and control
-- ============================================================================

do
    local UI     = KH.UI
    local S      = KH.S
    local Game   = KH.Game
    local Rob    = KH.Rob
    local Police = KH.Police
    local Farm   = KH.Farm
    local Travel = KH.Travel
    local Move   = KH.Move

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

    local function robberyNames()
        local names = {}
        for _, entry in ipairs(Game.Robberies) do
            if not entry.skip then names[#names + 1] = entry.name end
        end
        return names
    end

    local function robberyNamed(name)
        for _, entry in ipairs(Game.Robberies) do
            if entry.name == name then return entry end
        end
        return nil
    end

    -- ========================================================= ROBBERY TAB
    do
        local tab = UI.addTab("Robbery")

        local auto = UI.section(tab, "Auto Rob")
        UI.label(auto, "Flies to whatever is open, fires the prompts it finds, stands on the loot until the bag is full, then runs it to the nearest criminal base. Nothing here needs you to be near the robbery first.")
        UI.toggle(auto, opt("Rob", "Auto", {
            text = "Auto Rob",
            desc = "Keep taking jobs for as long as this is on.",
            onSet = function(on) if not on then Rob.stop() end end,
        }))
        UI.dropdown(auto, opt("Rob", "Pick", {
            text = "Choose By",
            desc = "Best Payout goes for the biggest score that is open. Nearest is faster per run.",
            options = {"Best Payout", "Nearest", "In Order"},
        }))
        UI.dropdown(auto, opt("Rob", "Only", {
            text = "Job Size",
            desc = "Quick is the gas station and donut store — small, but they reopen fast.",
            options = {"Any", "Quick", "Big"},
        }))
        UI.toggle(auto, opt("Rob", "Deposit", {
            text = "Bank The Bag",
            desc = "Run a full bag to a criminal base before taking the next job.",
        }))
        UI.toggle(auto, opt("Rob", "Restock", {
            text = "Wait For The Next One",
            desc = "Off, Auto Rob switches itself off once nothing is open instead of idling.",
        }))
        UI.slider(auto, opt("Rob", "Wait", {
            text = "Gap Between Jobs", min = 0, max = 20, step = 1, suffix = "s",
        }))
        UI.slider(auto, opt("Rob", "Dwell", {
            text = "Give Up After",
            desc = "How long one job may take before it is abandoned.",
            min = 20, max = 180, step = 5, suffix = "s",
        }))
        UI.readout(auto, {text = "Status", get = function() return Rob.Status end})
        UI.readout(auto, {
            text = "Bag",
            get = function()
                local have, cap = Game.bag()
                if not have then return "empty" end
                return ("%d / %d"):format(have, cap)
            end,
        })
        UI.readout(auto, {text = "Jobs Done", get = function() return Rob.Runs end})
        UI.readout(auto, {
            text = "Noclip",
            get = function()
                local clipped, parked = Travel.held()
                if not clipped then return "off" end
                return parked and "held, parked" or "held"
            end,
        })
        UI.readout(auto, {
            text = "Server Gap",
            get = function()
                local gap = Game.serverGap()
                if not gap then return "unknown" end
                return ("%d studs"):format(math.floor(gap))
            end,
        })

        local manual = UI.section(tab, "Run One")
        local chosen = {name = "Rising City Bank"}
        UI.dropdown(manual, {
            text = "Robbery",
            options = robberyNames(),
            get = function() return chosen.name end,
            set = function(v) chosen.name = v end,
        })
        UI.button(manual, {
            text = "Rob This One",
            kind = "primary",
            callback = function() Rob.runOne(robberyNamed(chosen.name)) end,
        })
        UI.button(manual, {
            text = "Rob The Best Open One",
            callback = function()
                local pick = Rob.candidates()[1]
                if pick then
                    Rob.runOne(pick)
                else
                    UI.notify({title = "Auto Rob", text = "Nothing is open.", kind = "warn"})
                end
            end,
        })
        UI.button(manual, {
            text = "Bank What I Am Carrying",
            callback = function() Rob.deposit() end,
        })
        UI.button(manual, {
            text = "Stop",
            kind = "danger",
            desc = "Abandon the current job and stay where you are.",
            callback = function() Rob.stop() end,
        })

        local safety = UI.section(tab, "Staying Alive")
        UI.toggle(safety, opt("Rob", "Noclip", {
            text = "Hold Position And Noclip",
            desc = "For the whole robbery, not just the flight: collisions off, gravity off, humanoid parked. Without it you bounce off the vault door, and with collisions off but gravity on you fall through the floor.",
        }))
        UI.toggle(safety, opt("Rob", "Lasers", {
            text = "Disable Lasers",
            desc = "Stops laser parts at the robbery registering a touch. Not god mode — it only covers the hazard that does the killing.",
        }))

        local how = UI.section(tab, "How It Works")
        UI.toggle(how, opt("Rob", "Instant", {
            text = "Instant Interactions",
            desc = "Jailbreak's hold-to-use circle completes the moment it starts — vault doors, registers, keypads, everything.",
        }))
        UI.toggle(how, opt("Rob", "AutoInteract", {
            text = "Fire Nearby Prompts",
            desc = "Trigger anything interactable in range while looting. Prompts that spend money or put you in a seat are never fired.",
        }))
        UI.slider(how, opt("Rob", "InteractRange", {
            text = "Prompt Range", min = 10, max = 120, step = 5, suffix = " studs",
        }))
        UI.toggle(how, opt("Rob", "Loot", {
            text = "Hop Between Loot",
            desc = "Stand on each money pile, gem case and crate in turn instead of waiting in one spot.",
        }))
        UI.slider(how, opt("Rob", "LootRadius", {
            text = "Loot Search Radius", min = 60, max = 500, step = 10, suffix = " studs",
        }))
        UI.toggle(how, opt("Rob", "Notify", {text = "Announce Each Job"}))

        local board = UI.section(tab, "Robbery States")
        for _, entry in ipairs(Game.Robberies) do
            if not entry.skip then
                UI.readout(board, {
                    text = entry.name,
                    get = function() return Game.statusText(entry) end,
                })
            end
        end
    end

    -- ========================================================== POLICE TAB
    do
        local tab = UI.addTab("Police")

        local arrest = UI.section(tab, "Arrest")
        UI.label(arrest, "An arrest is the game deciding a cuffed officer is touching a criminal, so this goes to each one in turn rather than cuffing the whole server in a single frame. Equip handcuffs first, or let it press the hotbar key for you.")
        UI.button(arrest, {
            text = "Arrest Everyone",
            kind = "primary",
            desc = "Sweep every criminal in the server, then come back.",
            callback = function() Police.arrestAll() end,
        })
        UI.button(arrest, {
            text = "Stop Sweeping",
            kind = "danger",
            callback = function() Police.stop() end,
        })
        UI.keybind(arrest, opt("Police", "ArrestKey", {text = "Arrest All Key"}))
        UI.readout(arrest, {text = "Status", get = function() return Police.Status end})
        UI.readout(arrest, {text = "Last Sweep", get = function() return Police.LastResult end})
        UI.readout(arrest, {
            text = "Criminals",
            get = function() return #Game.criminals() end,
        })

        local tuning = UI.section(tab, "Tuning")
        UI.dropdown(tuning, opt("Police", "ArrestMode", {
            text = "Approach",
            desc = "Instant snaps onto each target. Glide flies there first, which looks far less obvious but takes longer.",
            options = {"Instant", "Glide"},
        }))
        UI.slider(tuning, opt("Police", "Dwell", {
            text = "Time Per Target",
            desc = "How long to stay on someone before moving on. Lower is faster and misses more.",
            min = 0.1, max = 3, step = 0.05, suffix = "s",
        }))
        UI.slider(tuning, opt("Police", "Spacing", {
            text = "Gap Between Targets", min = 0, max = 1, step = 0.05, suffix = "s",
        }))
        UI.slider(tuning, opt("Police", "Offset", {
            text = "Stand-Off Distance", min = 0, max = 8, step = 0.5, suffix = " studs",
        }))
        UI.toggle(tuning, opt("Police", "ReturnAfter", {
            text = "Return Afterwards",
            desc = "Go back to where you started once the sweep ends.",
        }))
        UI.toggle(tuning, opt("Police", "SkipVehicles", {
            text = "Skip People In Cars",
            desc = "You cannot arrest a driver, so this saves the wasted stop.",
        }))

        local aura = UI.section(tab, "Arrest Aura")
        UI.label(aura, "Stays where you are and cuffs anyone who walks into range. Nothing teleports, so this is the version that does not look like anything.")
        UI.toggle(aura, opt("Police", "Aura", {text = "Arrest Aura"}))
        UI.slider(aura, opt("Police", "AuraRange", {
            text = "Aura Range", min = 5, max = 60, step = 1, suffix = " studs",
        }))
        UI.toggle(aura, opt("Police", "AutoArrest", {
            text = "Keep Sweeping",
            desc = "Re-run Arrest Everyone whenever new criminals appear.",
        }))

        local gear = UI.section(tab, "Handcuffs")
        UI.toggle(gear, opt("Police", "AutoEquip", {
            text = "Equip Handcuffs",
            desc = "Press the hotbar key before arresting. Turn it off if you would rather hold them yourself.",
        }))
        UI.slider(gear, opt("Police", "CuffSlot", {
            text = "Handcuff Hotbar Slot", min = 1, max = 9, step = 1,
        }))
        UI.readout(gear, {text = "In Hand", get = function() return Police.equipped() end})
    end

    -- ============================================================ FARM TAB
    do
        local tab = UI.addTab("Farm")

        local pickups = UI.section(tab, "Pickups")
        UI.toggle(pickups, opt("Farm", "Items", {
            text = "Collect Dropped Items",
            desc = "Fly to anything lying in the world and pick it up. Pauses while a robbery is running.",
        }))
        UI.slider(pickups, opt("Farm", "ItemRadius", {
            text = "Search Radius", min = 50, max = 1000, step = 25, suffix = " studs",
        }))
        UI.readout(pickups, {text = "Picked Up", get = function() return Farm.Collected end})

        local aura = UI.section(tab, "Interact Aura")
        UI.toggle(aura, opt("Farm", "InteractAura", {
            text = "Interact Aura",
            desc = "Fire every prompt in range, all the time — doors, hatches, registers. Independent of Auto Rob.",
        }))
        UI.slider(aura, opt("Farm", "AuraRange", {
            text = "Aura Range", min = 5, max = 80, step = 1, suffix = " studs",
        }))

        local session = UI.section(tab, "Session")
        UI.toggle(session, opt("Farm", "AntiAFK", {
            text = "Anti AFK",
            desc = "Answer the idle check so a long farm is not kicked.",
        }))
    end

    -- ========================================================== TRAVEL TAB
    do
        local tab = UI.addTab("Travel")

        local how = UI.section(tab, "How To Move")
        UI.label(how, "Jailbreak rejects a character that covers a long distance in one frame, so a crossing is flown at altitude instead of snapped. Instant is faster and far more likely to be caught.")
        UI.dropdown(how, opt("Travel", "Mode", {
            text = "Mode", options = {"Glide", "Instant"},
        }))
        UI.slider(how, opt("Travel", "Speed", {
            text = "Glide Speed",
            desc = "Studs per second. Higher gets there sooner and is more conspicuous.",
            min = 40, max = 400, step = 10,
        }))
        UI.slider(how, opt("Travel", "Height", {
            text = "Cruise Height", min = 120, max = 500, step = 10, suffix = " studs",
        }))
        UI.slider(how, opt("Travel", "Timeout", {
            text = "Give Up After", min = 10, max = 90, step = 5, suffix = "s",
        }))
        UI.button(how, {
            text = "Stop Travelling",
            kind = "danger",
            callback = function() Travel.stop() end,
        })

        local places = UI.section(tab, "Places")
        local place = {name = Game.Places[1].name}
        UI.dropdown(places, {
            text = "Destination",
            options = Game.placeNames(),
            get = function() return place.name end,
            set = function(v) place.name = v end,
        })
        UI.button(places, {
            text = "Go",
            kind = "primary",
            callback = function()
                local target = Game.placeByName(place.name)
                if target then Travel.to(target.position) end
            end,
        })
        UI.button(places, {
            text = "Nearest Criminal Base",
            callback = function()
                local base = Game.nearestBase()
                if base then Travel.to(base.position) end
            end,
        })

        local waypoints = UI.section(tab, "Waypoints")
        local waypointName = {value = ""}
        local waypointList
        local function refreshWaypoints()
            local names = Move.waypointNames()
            if #names == 0 then names = {"none saved"} end
            if waypointList then waypointList.setOptions(names) end
        end
        UI.input(waypoints, {
            text = "Name",
            placeholder = "hideout",
            get = function() return waypointName.value end,
            set = function(v) waypointName.value = v end,
        })
        UI.button(waypoints, {
            text = "Save Here",
            callback = function()
                if Move.saveWaypoint(waypointName.value) then refreshWaypoints() end
            end,
        })
        waypointList = UI.dropdown(waypoints, {
            text = "Saved",
            options = {"none saved"},
            get = function() return waypointName.value end,
            set = function(v) waypointName.value = v end,
        })
        UI.button(waypoints, {
            text = "Go To Waypoint",
            callback = function() Move.gotoWaypoint(waypointName.value) end,
        })
        UI.button(waypoints, {
            text = "Delete Waypoint",
            kind = "danger",
            callback = function()
                Move.deleteWaypoint(waypointName.value)
                refreshWaypoints()
            end,
        })
        refreshWaypoints()
    end

    -- ============================================================= ESP TAB
    do
        local tab = UI.addTab("ESP")

        local players = UI.section(tab, "Players")
        UI.toggle(players, opt("ESP", "Enabled", {text = "ESP Enabled"}))
        UI.toggle(players, opt("ESP", "Highlight", {
            text = "Highlight",
            desc = "Fill and outline the whole character, visible through walls.",
        }))
        UI.toggle(players, opt("ESP", "Names", {text = "Names"}))
        UI.toggle(players, opt("ESP", "Distance", {text = "Distance"}))
        UI.toggle(players, opt("ESP", "Team", {
            text = "Colour By Team",
            desc = "Off, everything uses the accent colour instead.",
        }))
        UI.toggle(players, opt("ESP", "OnlyEnemies", {
            text = "Enemies Only",
            desc = "Hide anyone on your own team.",
        }))
        UI.slider(players, opt("ESP", "MaxDistance", {
            text = "Max Distance", min = 250, max = 6000, step = 250, suffix = " studs",
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("ESP", "Robberies", {
            text = "Robbery Markers",
            desc = "Name and state floating over every robbery that is open.",
        }))

        local colours = UI.section(tab, "Colours")
        UI.colorpicker(colours, opt("ESP", "ColorCriminal", {text = "Criminal"}))
        UI.colorpicker(colours, opt("ESP", "ColorPolice", {text = "Police"}))
        UI.colorpicker(colours, opt("ESP", "ColorPrisoner", {text = "Prisoner"}))
    end

    -- ======================================================== MOVEMENT TAB
    do
        local tab = UI.addTab("Movement")

        local speed = UI.section(tab, "Speed & Jump")
        UI.toggle(speed, opt("Move", "SpeedEnabled", {
            text = "Walk Speed",
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Speed", {
            text = "Speed", min = 16, max = 200, step = 1,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.dropdown(speed, opt("Move", "SpeedMode", {
            text = "Speed Method",
            desc = "Humanoid sets WalkSpeed. CFrame drives the character directly, which ignores any clamp the server puts on it.",
            options = {"Humanoid", "CFrame"},
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "JumpEnabled", {
            text = "Jump Power",
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Jump", {
            text = "Jump", min = 50, max = 300, step = 5,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "InfJump", {text = "Infinite Jump"}))
        UI.toggle(speed, opt("Move", "Bhop", {text = "Bunny Hop"}))

        local clip = UI.section(tab, "Noclip & Fly")
        UI.toggle(clip, opt("Move", "Noclip", {
            text = "Noclip",
            onSet = function(on) Move.setNoclip(on) end,
        }))
        UI.keybind(clip, opt("Move", "NoclipKey", {text = "Noclip Key"}))
        UI.toggle(clip, opt("Move", "Fly", {
            text = "Fly",
            desc = "WASD to move, space up, shift down.",
            onSet = function(on) Move.setFly(on) end,
        }))
        UI.keybind(clip, opt("Move", "FlyKey", {text = "Fly Key"}))
        UI.slider(clip, opt("Move", "FlySpeed", {
            text = "Fly Speed", min = 20, max = 400, step = 5,
        }))
        UI.toggle(clip, opt("Move", "Spinbot", {text = "Spinbot"}))
    end

    -- ========================================================= VISUALS TAB
    do
        local tab = UI.addTab("Visuals")

        local lighting = UI.section(tab, "Lighting")
        UI.toggle(lighting, opt("Visual", "Fullbright", {text = "Fullbright"}))
        UI.slider(lighting, opt("Visual", "Brightness", {
            text = "Brightness", min = 1, max = 5, step = 0.1,
        }))
        UI.toggle(lighting, opt("Visual", "NoFog", {text = "No Fog"}))

        local camera = UI.section(tab, "Camera")
        UI.toggle(camera, opt("Visual", "FovEnabled", {text = "Custom FOV"}))
        UI.slider(camera, opt("Visual", "Fov", {
            text = "Field Of View", min = 40, max = 120, step = 1,
        }))

        local world = UI.section(tab, "Performance")
        UI.toggle(world, opt("Visual", "LowDetail", {
            text = "Low Detail",
            desc = "Strip shadows and effects. Worth it on a map this size.",
        }))
    end

    KH.SessionInfo = {
        {text = "Team", get = function() return Game.myTeamName() or "none" end},
        {
            text = "Thread Identity",
            get = function()
                local id = Game.identity()
                if id == nil then return Game.CanSetIdentity and "settable" or "no control" end
                return tostring(id) .. (Game.CanSetIdentity and "" or " (fixed)")
            end,
        },
        {
            text = "Memory Scan",
            get = function() return Game.CanScan and "available" or "unavailable" end,
        },
        {
            text = "Game Modules",
            get = function()
                local have = {}
                for name, value in pairs(Game.M) do
                    if value ~= nil then have[#have + 1] = name end
                end
                table.sort(have)
                if #have > 0 then return table.concat(have, ", ") end
                return Game.Resolved and "none found" or "looking…"
            end,
        },
    }

    KH.FirstTab = "Robbery"
end
