-- ============================================================================
--  POLICE — arrest one, arrest everyone, arrest whoever comes close
--
--  An arrest is the game's own client deciding a cuffed officer is on top of a
--  criminal, so this does not fake a remote: it puts you there, taps the touch
--  interest to be sure the contact registers, and waits for the team to flip.
--  That is why it is one target at a time rather than truly all at once.
-- ============================================================================

local Police = {}
KH.Police = Police

do
    local UI          = KH.UI
    local U           = KH.U
    local S           = KH.S
    local X           = KH.X
    local Game        = KH.Game
    local Travel      = KH.Travel
    local VirtualUser = KH.Services.VirtualUser

    Police.Busy       = false
    Police.Abort      = false
    Police.Status     = "Idle"
    Police.LastResult = "nothing yet"
    Police.Arrests    = 0

    -- ------------------------------------------------------------ handcuffs
    -- The item system is the only reliable way to read what is in hand, and it
    -- is not there on every executor. Without it, pressing the hotbar key is
    -- still the right move — we just cannot confirm it landed.
    function Police.equipped()
        if not Game.itemSystemReady() then return "unknown" end
        return Game.equippedName() or "nothing"
    end

    local SLOT_KEYS = {
        Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
        Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
        Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
    }

    local function pressSlot(slot)
        local key = SLOT_KEYS[slot] or SLOT_KEYS[1]

        local sent = pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, key, false, game)
            task.wait(0.03)
            vim:SendKeyEvent(false, key, false, game)
        end)
        if sent then return true end

        return (pcall(function()
            VirtualUser:SetKeyDown(tostring(slot))
            task.wait(0.03)
            VirtualUser:SetKeyUp(tostring(slot))
        end))
    end

    -- Rate limited: without the item system there is no way to tell a press
    -- worked, and the aura would otherwise hammer the hotbar key forever.
    local lastEquip = 0

    function Police.equipCuffs()
        if Game.holdingHandcuffs() then return true end
        if not S.Police.AutoEquip then return false end
        if os.clock() - lastEquip < 2 then return false end
        lastEquip = os.clock()

        local slot = math.clamp(math.floor(S.Police.CuffSlot), 1, 9)
        pressSlot(slot)
        task.wait(0.15)
        if Game.holdingHandcuffs() then return true end

        -- No way to check the result, so the configured slot is all we have.
        if not Game.itemSystemReady() then return true end

        -- We can see what landed, so walk the rest of the bar rather than
        -- trusting a slot number, and remember the one that worked.
        for other = 1, 9 do
            if other ~= slot then
                pressSlot(other)
                task.wait(0.12)
                if Game.holdingHandcuffs() then
                    S.Police.CuffSlot = other
                    return true
                end
            end
        end
        return false
    end

    -- ---------------------------------------------------------------- touch
    local function tap(a, b)
        if not X.firetouch then return end
        pcall(firetouchinterest, a, b, 0)
        pcall(firetouchinterest, a, b, 1)
    end

    local function caught(player)
        return Game.isCuffed(player) or Game.teamName(player) ~= "Criminal"
    end

    -- --------------------------------------------------------------- arrest
    function Police.arrest(player)
        if not player then return false end
        if not U.rootOf(player) then return false end

        if S.Police.ArrestMode == "Glide" then
            Travel.toPlayer(player, {direct = true, speed = 260, timeout = 8})
        end

        local offset = math.max(S.Police.Offset, 0)
        local deadline = os.clock() + math.max(S.Police.Dwell, 0.1)
        local nextTap = 0

        while KH.Alive and not Police.Abort and os.clock() < deadline do
            local me, them = U.myRoot(), U.rootOf(player)
            if not me or not them then break end
            if caught(player) then return true end

            me.CFrame = them.CFrame * CFrame.new(0, 0, offset)
            me.AssemblyLinearVelocity = Vector3.zero
            me.AssemblyAngularVelocity = Vector3.zero

            if os.clock() >= nextTap then
                nextTap = os.clock() + 0.1
                tap(me, them)
            end
            task.wait()
        end
        return caught(player)
    end

    -- --------------------------------------------------------------- sweeps
    function Police.arrestAll()
        if Police.Busy then return end
        if not Game.isPolice() then
            UI.notify({
                title = "Arrest All",
                text = "You have to be on the Police team.",
                kind = "warn",
            })
            return
        end

        Police.Busy, Police.Abort = true, false
        local root = U.myRoot()
        local home = root and root.CFrame

        pcall(function()
            Police.equipCuffs()

            -- When the item system is up this is knowable, and "you were not
            -- holding handcuffs" is worth saying instead of fifteen misses.
            if S.Police.AutoEquip and Game.itemSystemReady() and not Game.holdingHandcuffs() then
                Police.LastResult = "no handcuffs — holding " .. Police.equipped()
                UI.notify({
                    title = "Arrest All",
                    text = "Not holding handcuffs (" .. Police.equipped()
                        .. "), so nothing would stick. Turn Equip Handcuffs off to sweep anyway.",
                    kind = "bad",
                    duration = 9,
                })
                return
            end

            local targets = Game.criminals()
            if #targets == 0 then
                Police.LastResult = "no criminals in the server"
                UI.notify({title = "Arrest All", text = "Nobody to arrest.", kind = "warn"})
                return
            end

            local got, gone, driving, stuck = 0, 0, 0, 0
            for index, player in ipairs(targets) do
                if not KH.Alive or Police.Abort then break end
                Police.Status = ("Arresting %d/%d"):format(index, #targets)

                if not U.rootOf(player) then
                    gone = gone + 1
                elseif S.Police.SkipVehicles and Game.inVehicle(player) then
                    driving = driving + 1
                elseif Police.arrest(player) then
                    got = got + 1
                    Police.Arrests = Police.Arrests + 1
                else
                    stuck = stuck + 1
                end
                task.wait(math.max(S.Police.Spacing, 0))
            end

            -- Naming the failure is the whole point: "missed" on its own never
            -- said whether it was the cuffs, the range, or the game refusing.
            local why = {}
            if stuck > 0 then why[#why + 1] = ("%d did not stick"):format(stuck) end
            if driving > 0 then why[#why + 1] = ("%d in vehicles"):format(driving) end
            if gone > 0 then why[#why + 1] = ("%d had no character"):format(gone) end

            Police.LastResult = ("%d arrested"):format(got)
            if #why > 0 then
                Police.LastResult = Police.LastResult .. " — " .. table.concat(why, ", ")
            end
            UI.notify({
                title = "Arrest All",
                text = Police.LastResult,
                kind = got > 0 and "good" or "warn",
            })
        end)

        if S.Police.ReturnAfter and home then
            local me = U.myRoot()
            if me then
                me.CFrame = home
                me.AssemblyLinearVelocity = Vector3.zero
            end
        end

        Police.Busy = false
        Police.Status = "Idle"
    end

    function Police.stop()
        Police.Abort = true
        Travel.stop()
    end

    -- Keeps sweeping. Deliberately separate from the aura: this one moves you.
    KH.loop(2, function()
        if not S.Police.AutoArrest or Police.Busy then return end
        if KH.Rob.Busy then return end
        if not Game.isPolice() then return end
        if #Game.criminals() == 0 then return end
        Police.arrestAll()
    end)

    -- ----------------------------------------------------------------- aura
    -- Stays put and cuffs whoever wanders into range, which is the quiet
    -- version — no teleporting, so nothing on screen looks wrong.
    KH.loop(0.1, function()
        if not S.Police.Aura or Police.Busy then return end
        if not Game.isPolice() then return end

        local me = U.myRoot()
        if not me then return end

        local range = math.max(S.Police.AuraRange, 1)
        local equipped = false
        for _, player in ipairs(Game.criminals()) do
            local them = U.rootOf(player)
            if them and (them.Position - me.Position).Magnitude <= range then
                if not equipped then
                    equipped = true
                    Police.equipCuffs()
                end
                tap(me, them)
            end
        end
    end)
end
