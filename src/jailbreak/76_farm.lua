-- ============================================================================
--  FARM — the bits of grinding that are not a robbery
--
--  Two shapes of farm live here. The auto one flies the character to what it
--  wants; the manual one never moves it at all and works whatever the player
--  has driven up to. The manual one exists because a flight is the part the
--  game is most likely to reject, and on an executor that cannot reach the
--  game's own modules it is the only farm that still does anything.
-- ============================================================================

local Farm = {}
KH.Farm = Farm

do
    local UI          = KH.UI
    local U           = KH.U
    local S           = KH.S
    local Game        = KH.Game
    local Rob         = KH.Rob
    local Police      = KH.Police
    local Travel      = KH.Travel
    local LocalPlayer = KH.LocalPlayer
    local VirtualUser = KH.Services.VirtualUser

    Farm.Collected = 0
    Farm.Grabbed   = 0
    Farm.Status    = "Off"

    -- --------------------------------------------------------------- items
    -- Dropped pickups live in workspace.Items. Collecting one is standing on
    -- it, or the prompt that appears when you do, so both happen here.
    local function itemsFolder()
        return workspace:FindFirstChild("Items")
    end

    -- Anything we flew to and failed to collect is parked for a while. Without
    -- this, one pickup we are not allowed to take is always the nearest one and
    -- the farm never looks at anything else again.
    local parked = setmetatable({}, {__mode = "k"})

    function Farm.nearestItem()
        local folder = itemsFolder()
        local root = U.myRoot()
        if not folder or not root then return nil end

        local now = os.clock()
        local best, bestDist
        for _, item in ipairs(folder:GetChildren()) do
            local position = (parked[item] or 0) < now and Game.pivotOf(item) or nil
            if position then
                local dist = (position - root.Position).Magnitude
                if dist <= S.Farm.ItemRadius and (not bestDist or dist < bestDist) then
                    best, bestDist = item, dist
                end
            end
        end
        return best
    end

    -- The parts of nearby pickups, for touching rather than walking onto. A
    -- pickup is usually a model, and it is the parts inside that carry the
    -- TouchInterest the game is listening on.
    function Farm.itemPartsAround(radius)
        local folder = itemsFolder()
        local root = U.myRoot()
        local found = {}
        if not folder or not root then return found end

        for _, item in ipairs(folder:GetChildren()) do
            local position = Game.pivotOf(item)
            if position and (position - root.Position).Magnitude <= radius then
                if item:IsA("BasePart") then
                    found[#found + 1] = item
                else
                    for _, part in ipairs(item:GetDescendants()) do
                        if part:IsA("BasePart") then found[#found + 1] = part end
                    end
                end
            end
        end
        return found
    end

    KH.loop(0.5, function()
        if not S.Farm.Items then return end
        -- Never fight the rob routine or a sweep for the character.
        if Rob.Busy or Police.Busy or Travel.Busy then return end

        local item = Farm.nearestItem()
        if not item then return end

        local position = Game.pivotOf(item)
        if not position then return end

        Travel.to(position, {direct = true, speed = 180, timeout = 8})
        local deadline = os.clock() + 1.5
        while KH.Alive and item.Parent and os.clock() < deadline do
            -- Prompts first where they are reachable, and the touch either
            -- way: on an executor that cannot see the game's modules, landing
            -- on the pickup is the whole of the pickup.
            Rob.fireNearby(12)
            for _, part in ipairs(Farm.itemPartsAround(14)) do Rob.touch(part) end
            task.wait(0.15)
        end

        if item.Parent then
            parked[item] = os.clock() + 60
        else
            Farm.Collected = Farm.Collected + 1
        end
    end)

    -- ---------------------------------------------------------- interaction
    -- Fires any prompt in range without moving: doors, registers, hatches.
    KH.loop(0.2, function()
        if not S.Farm.InteractAura then return end
        Rob.fireNearby(math.max(S.Farm.AuraRange, 1))
    end)

    -- ---------------------------------------------------------- manual farm
    -- No travel, no teleports, no collision changes. The player drives and
    -- parks; this holds the interact key so the game's own hold-to-rob circle
    -- fills, and touches the loot within arm's reach. Every part of it is
    -- something a player does by hand, which is exactly why it survives on
    -- executors where the rest does not.
    local VirtualInput
    pcall(function() VirtualInput = game:GetService("VirtualInputManager") end)

    Farm.InputOK = VirtualInput and "ready" or "no VirtualInputManager"

    local holdingKey, holdUntil = nil, 0

    local function sendKey(down, key)
        if not VirtualInput then return false end
        return (pcall(function() VirtualInput:SendKeyEvent(down, key, false, game) end))
    end

    local function releaseInteract()
        if holdingKey then
            sendKey(false, holdingKey)
            holdingKey = nil
        end
    end

    -- Held down rather than tapped: a key tapped over and over restarts
    -- Jailbreak's hold-to-interact circle from zero every time and never
    -- completes it. Let go and pressed again every few seconds all the same,
    -- because the player's own press of that key ends our virtual one and
    -- nothing tells us it happened.
    local function holdInteract()
        if not VirtualInput then return end
        local key = U.keyCode(S.Farm.InteractKey)
        if not key then
            releaseInteract()
            Farm.InputOK = "no such key"
            return
        end

        if holdingKey == key then
            -- One tick of gap before the next press, so the game sees a real
            -- release rather than two downs in a row.
            if os.clock() >= holdUntil then releaseInteract() end
            return
        end

        releaseInteract()
        if sendKey(true, key) then
            holdingKey, holdUntil = key, os.clock() + 3
            Farm.InputOK = "holding " .. tostring(S.Farm.InteractKey)
        else
            Farm.InputOK = "blocked by the executor"
        end
    end

    -- A key left down after an unload would be stuck down for the rest of the
    -- session, so this has to run whatever else happened.
    KH.undo(releaseInteract)

    function Farm.grabNearby()
        local root = U.myRoot()
        if not root or not KH.X.firetouch then return 0 end

        local radius = math.max(S.Farm.GrabRadius, 1)
        local count = 0
        for _, part in ipairs(Game.lootAround(root.Position, radius)) do
            Rob.touch(part)
            count = count + 1
        end
        for _, part in ipairs(Farm.itemPartsAround(radius)) do
            Rob.touch(part)
            count = count + 1
        end
        return count
    end

    function Farm.setManual(on)
        S.Farm.Manual = on and true or false
        if not S.Farm.Manual then
            releaseInteract()
            Farm.Status = "Off"
        end
        UI.refreshKeybinds()
    end

    KH.loop(0.25, function()
        if not S.Farm.Manual then return end

        -- The auto routines drive the character; letting the manual farm hold
        -- a key down through one of those is how you buy a car mid-robbery.
        if Rob.Busy or Police.Busy or Travel.Busy then
            releaseInteract()
            Farm.Status = "Paused — something else is driving"
            return
        end
        if U.typing() then
            releaseInteract()
            Farm.Status = "Paused — typing"
            return
        end
        if not U.myRoot() then
            releaseInteract()
            Farm.Status = "Waiting for a character"
            return
        end

        if S.Farm.HoldInteract then holdInteract() else releaseInteract() end

        local grabbed = 0
        if S.Farm.GrabLoot then
            grabbed = Farm.grabNearby()
            Farm.Grabbed = Farm.Grabbed + grabbed
        end
        -- Free where the modules are reachable, a no-op where they are not.
        Rob.fireNearby(math.max(S.Farm.GrabRadius, 1))

        local have, cap = Game.bag()
        if have and cap then
            Farm.Status = ("Working — bag %d/%d"):format(have, cap)
        elseif grabbed > 0 then
            Farm.Status = ("Working — %d nearby"):format(grabbed)
        else
            Farm.Status = "Working — nothing in reach"
        end
    end)

    -- -------------------------------------------------------------- anti-afk
    KH.track(LocalPlayer.Idled:Connect(function()
        if not S.Farm.AntiAFK then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end
