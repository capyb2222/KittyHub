-- ============================================================================
--  ROBBERY — auto rob, and the pieces it is built from
--
--  Interiors are not hardcoded. Jailbreak offers everything you can interact
--  with through CircleAction, and the loot itself is parts you stand on, so a
--  job is: fly to the entrance, fire the prompts around you, hop between the
--  loot, and run the bag to a base. That survives a map update; a path of
--  waypoints through a vault does not.
-- ============================================================================

local Rob = {}
KH.Rob = Rob

do
    local UI     = KH.UI
    local U      = KH.U
    local S      = KH.S
    local Game   = KH.Game
    local Travel = KH.Travel

    Rob.Status  = "Idle"
    Rob.Current = nil
    Rob.Busy    = false
    Rob.Abort   = false
    Rob.Runs    = 0

    local function say(text, kind)
        Rob.Status = text
        if S.Rob.Notify then
            UI.notify({title = "Auto Rob", text = text, kind = kind, duration = 4})
        end
    end

    -- ---------------------------------------------------------- interaction
    -- Jailbreak's hold-to-interact timer lives on the spec being held, so
    -- zeroing it every frame completes any prompt the moment it is started.
    KH.onFrame("jb-instant", function()
        if not S.Rob.Instant then return end
        local circle = Game.circleAction()
        local spec = circle and circle.Spec
        if typeof(spec) == "table" then spec.PressedAt = 0 end
    end, 40)

    -- Firing the same prompt every tick would be a packet flood; once every
    -- half second per prompt is enough for anything that yields loot.
    local fired = setmetatable({}, {__mode = "k"})

    function Rob.fireNearby(range)
        local specs = Game.specs()
        if not specs then return 0 end
        local root = U.myRoot()
        if not root then return 0 end

        -- Snapshot first: a callback can add or remove specs, and iterating a
        -- table while it is being rewritten is undefined.
        local list = {}
        for _, spec in pairs(specs) do list[#list + 1] = spec end

        local now, count = os.clock(), 0
        for _, spec in ipairs(list) do
            if Game.specIsSafe(spec) and (fired[spec] or 0) < now then
                local position = Game.specPosition(spec)
                if position and (position - root.Position).Magnitude <= range then
                    fired[spec] = now + 0.5
                    if Game.fireSpec(spec) then count = count + 1 end
                end
            end
        end
        return count
    end

    -- ---------------------------------------------------------------- rules
    local function alive()
        return KH.Alive and not Rob.Abort and U.myRoot() ~= nil
    end

    local function working(entry, deadline)
        if not alive() then return false end
        if os.clock() > deadline then return false end
        if Game.isCuffed(KH.LocalPlayer) then return false end
        -- Closed means the job is over; whatever is in the bag gets banked.
        return Game.isRobbable(entry)
    end

    -- ------------------------------------------------------------- hazards
    -- Bank and museum lasers kill on contact, and the contact is detected on
    -- our side, so a laser that cannot be touched cannot hurt us. Switched
    -- rather than destroyed, because the job ends and the game carries on.
    local muted = {}

    local function looksHazardous(part)
        local node, hops = part, 0
        while node and hops < 4 do
            local name = node.Name:lower()
            if name:find("laser") or name:find("lazer") or name:find("beam") then
                return true
            end
            node, hops = node.Parent, hops + 1
        end
        return false
    end

    local function unmute()
        for part, was in pairs(muted) do
            if part.Parent then pcall(function() part.CanTouch = was end) end
        end
        table.clear(muted)
    end
    KH.undo(unmute)

    local function muteHazards(centre)
        if not S.Rob.Lasers or typeof(centre) ~= "Vector3" then return end

        local params = OverlapParams.new()
        params.MaxParts = 2000
        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(centre, S.Rob.LootRadius, params)
        end)
        if not ok or typeof(parts) ~= "table" then return end

        for _, part in ipairs(parts) do
            if part:IsA("BasePart") and muted[part] == nil and looksHazardous(part) then
                muted[part] = part.CanTouch
                pcall(function() part.CanTouch = false end)
            end
        end
    end

    -- ----------------------------------------------------------------- loot
    -- Stand on each loot part in turn. Money in Jailbreak accrues while you
    -- are on it, so the dwell matters more than the number of stops.
    local function lootSweep(entry, deadline)
        if not Game.centrePoint(entry) then return end

        local parts = Game.lootNear(entry, S.Rob.LootRadius)
        for _, part in ipairs(parts) do
            if not working(entry, deadline) or Game.bagFull() then return end
            if part.Parent then
                Travel.to(part.Position, {direct = true, speed = 150, timeout = 6})
                local until_ = os.clock() + 1.5
                while os.clock() < until_ and working(entry, deadline) do
                    if S.Rob.AutoInteract then Rob.fireNearby(S.Rob.InteractRange) end
                    if Game.bagFull() then return end
                    task.wait(0.15)
                end
            end
        end
    end

    -- -------------------------------------------------------------- deposit
    -- Three failures in a row means the drop-off is not where this thinks it
    -- is, and retrying forever would stop any more robbing from happening.
    local bankFails = 0

    function Rob.deposit()
        if not Game.carrying() then bankFails = 0 return true end
        local base = Game.nearestBase()
        if not base then return false end

        Rob.Status = "Banking at " .. base.name
        Travel.to(base.position)

        local deadline = os.clock() + 30
        while KH.Alive and not Rob.Abort and Game.carrying() and os.clock() < deadline do
            Rob.fireNearby(S.Rob.InteractRange)
            task.wait(0.25)
        end

        if not Game.carrying() then
            bankFails = 0
            return true
        end
        bankFails = bankFails + 1
        if bankFails >= 3 and S.Rob.Deposit then
            bankFails = 0
            S.Rob.Deposit = false
            UI.refreshAll()
            say("Could not bank the bag — turning that off.", "warn")
        end
        return false
    end

    -- Touching a part the way the game's own detection would see it.
    function Rob.touch(part)
        local root = U.myRoot()
        if not root or typeof(part) ~= "Instance" or not KH.X.firetouch then return end
        pcall(firetouchinterest, root, part, 0)
        pcall(firetouchinterest, root, part, 1)
    end

    -- The bank has a real interior with a door and a known way through it, so
    -- it gets walked properly instead of being left to the loot heuristic.
    local function enterBank(entry, deadline)
        local plan = Game.bankPlan()
        if not plan then return end

        Rob.Status = "Entering the bank"
        for _, point in ipairs(Game.BankApproach) do
            if not working(entry, deadline) then return end
            Travel.to(point, {direct = true, speed = 130, timeout = 8})
        end

        if plan.door then Rob.touch(plan.door) end
        Rob.fireNearby(S.Rob.InteractRange)

        for _, point in ipairs(plan.path or {}) do
            if not working(entry, deadline) then return end
            Travel.to(point, {direct = true, speed = 130, timeout = 8})
        end

        if plan.money and plan.money.Parent then
            Travel.to(plan.money.Position, {direct = true, speed = 130, timeout = 8})
        end
    end

    -- ------------------------------------------------------------- one job
    function Rob.runOne(entry)
        if Rob.Busy then return false end
        if not entry then return false end

        Rob.Busy, Rob.Abort, Rob.Current = true, false, entry.name
        -- Held for the whole job, not per hop: vault doors are solid, and with
        -- collisions off there is no floor either, so position has to be held
        -- outright between stops.
        if S.Rob.Noclip then Travel.hold(true) end

        local ok = pcall(function()
            local point = Game.entryPoint(entry)
            if not point then
                say(entry.name .. " could not be located.", "warn")
                return
            end

            Rob.Status = "Flying to " .. entry.name
            if not Travel.to(point) then
                say("Could not reach " .. entry.name .. ".", "warn")
                return
            end

            Rob.Status = "Robbing " .. entry.name
            muteHazards(Game.centrePoint(entry))
            local deadline = os.clock() + math.max(S.Rob.Dwell, 10)
            if entry.key == "BANK" then enterBank(entry, deadline) end

            -- One pass of prompts on arrival opens whatever needs opening,
            -- then alternate sweeping the loot with firing what is in reach.
            local worked = false
            while working(entry, deadline) and not Game.bagFull() do
                worked = true
                if S.Rob.AutoInteract then Rob.fireNearby(S.Rob.InteractRange) end
                if S.Rob.Loot then
                    lootSweep(entry, deadline)
                else
                    task.wait(0.25)
                end
                task.wait(0.2)
            end

            if S.Rob.Deposit then Rob.deposit() end
            if worked then
                Rob.Runs = Rob.Runs + 1
                say(("Finished %s."):format(entry.name), "good")
            else
                say(("%s closed before we got there."):format(entry.name), "warn")
            end
        end)

        if S.Rob.Noclip then Travel.hold(false) end
        unmute()

        Rob.Busy, Rob.Current = false, nil
        Rob.Status = "Idle"
        return ok
    end

    function Rob.stop()
        Rob.Abort = true
        Travel.stop()
        Rob.Status = "Stopping"
    end

    -- --------------------------------------------------------------- choice
    local function allowed(entry)
        if S.Rob.Only == "Quick" then return entry.quick end
        if S.Rob.Only == "Big" then return not entry.quick end
        return true
    end

    function Rob.candidates()
        local out = {}
        for _, entry in ipairs(Game.openRobberies()) do
            if allowed(entry) and Game.entryPoint(entry) then out[#out + 1] = entry end
        end

        if S.Rob.Pick == "Best Payout" then
            table.sort(out, function(a, b) return a.payout > b.payout end)
        elseif S.Rob.Pick == "Nearest" then
            local root = U.myRoot()
            local origin = root and root.Position or Vector3.zero
            local distance = {}
            for _, entry in ipairs(out) do
                local point = Game.entryPoint(entry)
                distance[entry] = point and (point - origin).Magnitude or math.huge
            end
            table.sort(out, function(a, b) return distance[a] < distance[b] end)
        end
        return out
    end

    -- ------------------------------------------------------------ auto loop
    KH.loop(1, function()
        if not S.Rob.Auto or Rob.Busy then return end
        -- Police loads after this one, so it is looked up when the loop runs.
        local police = KH.Police
        if police and police.Busy then return end

        if not Game.isCriminal() then
            Rob.Status = "Waiting — not on the Criminal team"
            return
        end
        if Game.isCuffed(KH.LocalPlayer) then
            Rob.Status = "Waiting — arrested"
            return
        end

        -- Carrying something from a job that was cut short? Bank it first.
        if Game.carrying() and S.Rob.Deposit then
            Rob.Busy = true
            pcall(Rob.deposit)
            Rob.Busy = false
            return
        end

        local next_ = Rob.candidates()[1]
        if not next_ then
            if S.Rob.Restock then
                Rob.Status = "Waiting for a robbery to open"
            else
                S.Rob.Auto = false
                UI.refreshAll()
                say("Nothing left open — stopping.", "warn")
            end
            return
        end

        Rob.runOne(next_)
        task.wait(math.max(S.Rob.Wait, 0))
    end)
end
