-- ============================================================================
--  MAIN — hotkeys, HUD readouts, and boot
-- ============================================================================

do
    local UI               = KH.UI
    local C                = UI.C
    local U                = KH.U
    local S                = KH.S
    local Game             = KH.Game
    local Rob              = KH.Rob
    local Police           = KH.Police
    local Move             = KH.Move
    local Config           = KH.Config
    local UserInputService = KH.Services.UserInputService

    -- =============================================================== HOTKEYS
    UI.registerKeybind("Menu", function() return S.UI.MenuKey end, function() return UI.IsOpen end)
    UI.registerKeybind("Noclip", function() return S.Move.NoclipKey end, function() return S.Move.Noclip end)
    UI.registerKeybind("Fly", function() return S.Move.FlyKey end, function() return S.Move.Fly end)
    UI.registerKeybind("Arrest All", function() return S.Police.ArrestKey end, function()
        return Police.Busy
    end)
    UI.refreshKeybinds()

    KH.track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if UI.Capturing or processed then return end

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
        -- The sweep takes seconds and yields the whole way; it cannot run on
        -- the input thread.
        if key == U.keyCode(S.Police.ArrestKey) then
            KH.detach(function() Police.arrestAll() end)
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

    local function teamColor()
        local name = Game.myTeamName()
        if name == "Police" then return S.ESP.ColorPolice, name end
        if name == "Criminal" then return S.ESP.ColorCriminal, name end
        if name == "Prisoner" then return S.ESP.ColorPrisoner, name end
        return C.TextDim, "No Team"
    end

    KH.loop(0.25, function()
        local color, team = teamColor()
        local hex, dim = color:ToHex(), C.TextDim:ToHex()

        if S.UI.Watermark then
            local parts = {
                ('<font color="#%s">Kitty Hub</font>'):format(C.Accent:ToHex()),
                ('<font color="#%s">JB</font>'):format(dim),
                ("%d fps"):format(fps),
                ("%d ms"):format(math.floor(U.ping())),
                ('<font color="#%s">%s</font>'):format(hex, team),
            }
            local have, cap = Game.bag()
            if have then parts[#parts + 1] = ("bag %d/%d"):format(have, cap) end
            UI.WatermarkText.Text = table.concat(parts, ('  <font color="#%s">·</font>  '):format(dim))
        end

        UI.RoleLabel.Text = team
        UI.RoleLabel.TextColor3 = color

        local bits = {}
        if Rob.Busy then
            bits[#bits + 1] = Rob.Status
        elseif Police.Busy then
            bits[#bits + 1] = Police.Status
        else
            bits[#bits + 1] = ("%d open"):format(#Game.openRobberies())
            if Game.isPolice() then
                bits[#bits + 1] = ("%d wanted"):format(#Game.criminals())
            end
        end
        UI.StatLabel.Text = table.concat(bits, " · ")

        if UI.IsOpen then
            for _, readout in ipairs(UI.Readouts or {}) do
                KH.safe("readout", readout.refresh)
            end
        end
    end)

    -- ================================================================ BOOT
    if Config.available then
        local ok = Config.load(S.UI.Profile)
        if ok then
            UI.refreshAll()
            UI.applyAccent(S.UI.Accent)
        end
    end

    Move.applyHumanoid()
    if S.Move.Noclip then Move.setNoclip(true) end
    UI.refreshKeybinds()
    UI.setOpen(true)

    -- The sidebar indicator is placed from AbsolutePosition, which is still
    -- zero until the window has been laid out for a frame.
    task.delay(0.35, function()
        if KH.Alive then UI.selectTab(UI.ActiveTab or "Robbery") end
    end)

    if game.PlaceId ~= 606849621 then
        UI.notify({
            title = "Not Jailbreak",
            text = "This build targets Jailbreak. Most features will do nothing here.",
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
    print(("[Kitty Hub] [%s] menu · [%s] noclip · [%s] fly · [%s] arrest all")
        :format(S.UI.MenuKey, S.Move.NoclipKey, S.Move.FlyKey, S.Police.ArrestKey))
end
