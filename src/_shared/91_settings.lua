-- ============================================================================
--  SETTINGS — the tab every build has: interface, profiles, session
--
--  Added after the game module's own tabs so it is always last, and it picks up
--  whatever extra rows that module left in KH.SessionInfo.
-- ============================================================================

do
    local UI     = KH.UI
    local S      = KH.S
    local Config = KH.Config

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

    local tab = UI.addTab("Settings")

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
    for _, row in ipairs(KH.SessionInfo or {}) do
        UI.readout(session, row)
    end
    UI.readout(session, {
        text = "Teleport Queue",
        get = function() return KH.X.queueteleport and "supported" or "not supported" end,
    })

    -- Only the games this build is not already in.
    local elsewhere = {}
    for _, entry in ipairs(KH.Games) do
        if entry.place ~= game.PlaceId then elsewhere[#elsewhere + 1] = entry end
    end
    if #elsewhere > 0 then
        local going = {name = elsewhere[1].name}
        local names = {}
        for _, entry in ipairs(elsewhere) do names[#names + 1] = entry.name end

        UI.dropdown(session, {
            text = "Switch Game",
            options = names,
            get = function() return going.name end,
            set = function(v) going.name = v end,
        })
        UI.button(session, {
            text = "Go There",
            desc = "Queues the hub before teleporting, so it loads itself on arrival — for when your executor will not attach to that game.",
            callback = function()
                for _, entry in ipairs(elsewhere) do
                    if entry.name == going.name then KH.goToGame(entry.place) end
                end
            end,
        })
    end

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

    UI.selectTab(KH.FirstTab or (next(UI.Tabs)))
end
