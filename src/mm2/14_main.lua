-- ============================================================================
--  MAIN — hotkeys, the single render loop, HUD readouts, and unload
-- ============================================================================

do
    local UI               = KH.UI
    local C                = UI.C
    local U                = KH.U
    local S                = KH.S
    local Game             = KH.Game
    local Combat           = KH.Combat
    local Move             = KH.Move
    local Safety           = KH.Safety
    local Config           = KH.Config
    local RunService       = KH.Services.RunService
    local UserInputService = KH.Services.UserInputService
    local TeleportService  = KH.Services.TeleportService
    local HttpService      = KH.Services.HttpService
    local LocalPlayer      = KH.LocalPlayer

    -- =============================================================== HOTKEYS
    UI.registerKeybind("Menu", function() return S.UI.MenuKey end, function() return UI.IsOpen end)
    -- Press mode is never "engaged", so light the chip while its shot is in
    -- flight instead — otherwise the key would look dead every time it works.
    UI.registerKeybind("Aimbot", function() return S.Aim.Key end, function()
        return Combat.isEngaged() or Combat.Mouse.active() ~= nil
    end)
    UI.registerKeybind("Noclip", function() return S.Move.NoclipKey end, function() return S.Move.Noclip end)
    UI.registerKeybind("Fly", function() return S.Move.FlyKey end, function() return S.Move.Fly end)
    -- No lit state: the throw is a single action, over before the panel would
    -- be redrawn, so the chip just carries the key.
    UI.registerKeybind("Throw Knife", function() return S.Knife.ThrowKey end)
    UI.refreshKeybinds()

    KH.track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        -- A keybind picker or a focused text box owns this press.
        if UI.Capturing then return end
        if processed then return end

        local key = input.KeyCode

        if key == U.keyCode(S.UI.MenuKey) then
            UI.toggleOpen()
            return
        end
        if key == U.keyCode(S.Move.NoclipKey) then
            Move.setNoclip(not S.Move.Noclip)
            UI.refreshAll()
            return
        end
        if key == U.keyCode(S.Move.FlyKey) then
            Move.setFly(not S.Move.Fly)
            UI.refreshAll()
            return
        end
        -- One throw per press. InputBegan does not auto-repeat, so holding the
        -- key throws once and then nothing until it is released and pressed
        -- again — which is the whole point of it not being the auto-throw loop.
        if key == U.keyCode(S.Knife.ThrowKey) then
            Combat.throwOnce(true)
            return
        end
        -- In Toggle mode the aim key arms the aimbot rather than firing once.
        if key == U.keyCode(S.Aim.Key) and S.Aim.Enabled then
            if S.Aim.Mode == "Toggle" then
                Combat.setToggle(not Combat.toggleArmedState())
                UI.refreshKeybinds()
            elseif S.Aim.Mode == "Press" or S.Aim.Mode == "Hold" then
                -- Both shoot on the press. Hold then keeps going from the
                -- render loop while the key is down; Press is done here.
                Combat.fireOnce(true)
            end
        end
    end))

    -- ============================================================ RENDER LOOP
    -- One connection drives every per-frame job. Each is pcall-wrapped, so a
    -- feature that breaks cannot take the rest of the menu down with it.
    KH.track(RunService.RenderStepped:Connect(function(delta)
        if not KH.Alive then return end
        KH.camera()
        local jobs = KH.Frame
        for i = 1, #jobs do
            local job = jobs[i]
            KH.safe(job.name, job.fn, delta)
        end
    end))

    -- ================================================================= HUD
    local frames, fpsAccum, fps = 0, 0, 0

    KH.onFrame("fps", function(delta)
        frames = frames + 1
        fpsAccum = fpsAccum + delta
        if fpsAccum >= 0.5 then
            fps = math.floor(frames / fpsAccum + 0.5)
            frames, fpsAccum = 0, 0
        end
    end, 90)

    local function roleColorHex()
        local role = Game.myRole()
        if role == "Murderer" then return S.ESP.ColorMurderer:ToHex(), role end
        if role == "Sheriff" then return S.ESP.ColorSheriff:ToHex(), role end
        if role == "Hero" then return S.ESP.ColorHero:ToHex(), role end
        return S.ESP.ColorInnocent:ToHex(), role
    end

    local function clockText()
        local seconds = Game.roundTime()
        if not seconds then return nil end
        seconds = math.max(math.floor(seconds), 0)
        return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
    end

    KH.loop(0.25, function()
        local hex, role = roleColorHex()
        local dim = C.TextDim:ToHex()

        -- Watermark
        if S.UI.Watermark then
            local parts = {
                ('<font color="#%s">Kitty Hub</font>'):format(C.Accent:ToHex()),
                ('<font color="#%s">MM2</font>'):format(dim),
                ("%d fps"):format(fps),
                ("%d ms"):format(math.floor(U.ping())),
                ('<font color="#%s">%s</font>'):format(hex, role),
            }
            local clock = clockText()
            if clock then parts[#parts + 1] = clock end
            UI.WatermarkText.Text = table.concat(parts, ('  <font color="#%s">·</font>  '):format(dim))
        end

        -- Sidebar status strip
        UI.RoleLabel.Text = role
        UI.RoleLabel.TextColor3 = Color3.fromHex(hex)

        local bits = {}
        local distance = Safety.MurdererDistance
        if distance and distance ~= math.huge then
            bits[#bits + 1] = ("murderer %dm"):format(math.floor(distance))
        elseif Game.inRound() then
            bits[#bits + 1] = "in round"
        else
            bits[#bits + 1] = "lobby"
        end
        local clock = clockText()
        if clock then bits[#bits + 1] = clock end
        UI.StatLabel.Text = table.concat(bits, " · ")

        -- Live readouts, only while their tab is actually on screen.
        if UI.IsOpen then
            for _, readout in ipairs(UI.Readouts or {}) do
                KH.safe("readout", readout.refresh)
            end
        end
    end)

    -- ============================================================== SESSION
    function KH.rejoin()
        UI.notify({title = "Rejoin", text = "Teleporting…"})
        pcall(function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
    end

    function KH.serverHop()
        KH.detach(function()
            UI.notify({title = "Server Hop", text = "Looking for a server…"})
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100")
                :format(game.PlaceId)

            local ok, body = pcall(function() return game:HttpGet(url) end)
            if not ok then
                UI.notify({title = "Server Hop", text = "Could not reach the server list.", kind = "bad"})
                return
            end

            local decoded, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not decoded or typeof(data) ~= "table" or typeof(data.data) ~= "table" then
                UI.notify({title = "Server Hop", text = "Server list was unreadable.", kind = "bad"})
                return
            end

            local candidates = {}
            for _, server in ipairs(data.data) do
                if typeof(server) == "table"
                    and server.id ~= game.JobId
                    and typeof(server.playing) == "number"
                    and typeof(server.maxPlayers) == "number"
                    and server.playing < server.maxPlayers then
                    candidates[#candidates + 1] = server.id
                end
            end

            if #candidates == 0 then
                UI.notify({title = "Server Hop", text = "No other servers with room.", kind = "warn"})
                return
            end

            local pick = candidates[math.random(1, #candidates)]
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, pick, LocalPlayer)
            end)
        end)
    end

    -- =============================================================== UNLOAD
    function KH.unload()
        if not KH.Alive then return end
        KH.Alive = false

        -- Undo world changes first, while our instances still exist.
        for _, restore in ipairs(KH.Undo) do pcall(restore) end
        for _, conn in ipairs(KH.Conn) do pcall(function() conn:Disconnect() end) end

        local current = coroutine.running()
        for _, thread in ipairs(KH.Thread) do
            if thread ~= current then pcall(task.cancel, thread) end
        end

        for _, inst in ipairs(KH.Inst) do pcall(function() inst:Destroy() end) end

        local env = (type(getgenv) == "function" and getgenv()) or _G
        env.KittyHubCleanup = nil
        env.KittyHub = nil
        print("[Kitty Hub] Unloaded.")
    end

    do
        local env = (type(getgenv) == "function" and getgenv()) or _G
        env.KittyHubCleanup = KH.unload
    end

    -- ================================================================ BOOT
    if Config.available then
        local ok = Config.load(S.UI.Profile)
        if ok then
            UI.refreshAll()
            UI.applyAccent(S.UI.Accent)
        end
    end

    -- Bring the world into line with whatever the loaded profile says.
    Move.applyHumanoid()
    if S.Move.Noclip then Move.setNoclip(true) end
    UI.refreshKeybinds()
    UI.setOpen(true)

    -- The sidebar indicator is placed from AbsolutePosition, which is still
    -- zero until the window has been laid out for a frame.
    task.delay(0.35, function()
        if KH.Alive then UI.selectTab(UI.ActiveTab or "Aimbot") end
    end)

    if game.PlaceId ~= 142823291 then
        UI.notify({
            title = "Not Murder Mystery 2",
            text = "This build targets MM2. Most features will do nothing here.",
            kind = "warn",
            duration = 8,
        })
    end

    UI.notify({
        title = "Kitty Hub v" .. KH.Version,
        text = ("Loaded on %s. Press %s for the menu."):format(KH.X.name, S.UI.MenuKey),
        kind = "good",
        duration = 5,
    })

    print(("[Kitty Hub] v%s loaded — executor: %s"):format(KH.Version, KH.X.name))
    print(("[Kitty Hub] [%s] menu · [%s] aim · [%s] noclip · [%s] fly · [%s] throw knife")
        :format(S.UI.MenuKey, S.Aim.Key, S.Move.NoclipKey, S.Move.FlyKey, S.Knife.ThrowKey))
end
