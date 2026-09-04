-- ============================================================================
--  TRAVEL — getting across the map without tripping the movement check
--
--  Jailbreak rejects a character that jumps a long way in one frame, so a
--  crossing is flown: climb, cruise at a height nothing reaches, drop in. The
--  speed is a setting because what the server tolerates changes with updates.
-- ============================================================================

local Travel = {}
KH.Travel = Travel

do
    local U           = KH.U
    local S           = KH.S
    local LocalPlayer = KH.LocalPlayer

    local BASE_GRAVITY = workspace.Gravity
    local held = {}      -- parts we switched off, and only those
    local depth = 0
    local cancel = false

    Travel.Busy = false

    local function holdCollisions()
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                held[part] = true
                part.CanCollide = false
            end
        end
    end

    local function releaseCollisions()
        for part in pairs(held) do
            if part.Parent then pcall(function() part.CanCollide = true end) end
        end
        table.clear(held)
    end

    -- Noclip is refcounted and separate from the flight, so a rob routine can
    -- hold it for a whole job. Vault doors and laser housings are solid, and a
    -- character that has to squeeze past them never gets in.
    local clipDepth = 0

    function Travel.noclip(on)
        if on then
            clipDepth = clipDepth + 1
            if clipDepth == 1 then holdCollisions() end
        else
            clipDepth = math.max(clipDepth - 1, 0)
            if clipDepth == 0 then releaseCollisions() end
        end
    end

    -- Re-applied every frame while the lease is held: a respawn brings back a
    -- whole new set of solid limbs, and holding it once would not cover them.
    KH.onFrame("jb-noclip", function()
        if clipDepth <= 0 then return end
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.CanCollide then
                held[part] = true
                part.CanCollide = false
            end
        end
    end, 45)

    local function beginFlight()
        depth = depth + 1
        if depth == 1 then workspace.Gravity = 0 end
        Travel.noclip(true)
    end

    local function endFlight()
        depth = math.max(depth - 1, 0)
        if depth == 0 then workspace.Gravity = BASE_GRAVITY end
        Travel.noclip(false)
    end

    -- Gravity is world state; leaving it at zero would break the game for the
    -- rest of the session, so unload puts it back whatever else happened.
    KH.undo(function()
        depth, clipDepth = 0, 0
        workspace.Gravity = BASE_GRAVITY
        releaseCollisions()
    end)

    function Travel.stop() cancel = true end

    local function stopped()
        return not KH.Alive or cancel
    end

    -- One leg of the flight. Returns false if we ran out of time, lost the
    -- character, or were cancelled — never partially and silently.
    local function leg(goal, speed, arrive, deadline)
        while not stopped() do
            local root = U.myRoot()
            if not root then return false end

            local delta = goal - root.Position
            local distance = delta.Magnitude
            if distance <= arrive then return true end
            if os.clock() > deadline then return false end

            -- Clamped: a frame spike would otherwise become one huge jump,
            -- which is exactly what the movement check looks for.
            local dt = math.min(task.wait(), 0.1)
            local hop = math.min(speed * dt, distance)
            local position = root.Position + delta.Unit * hop

            local facing = Vector3.new(delta.X, 0, delta.Z)
            if facing.Magnitude > 0.05 then
                root.CFrame = CFrame.lookAt(position, position + facing.Unit)
            else
                root.CFrame = CFrame.new(position)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        return false
    end

    local function fly(target, opts)
        local root = U.myRoot()
        if not root then return false end

        local speed = math.max(opts.speed or S.Travel.Speed, 20)
        local deadline = os.clock() + math.max(opts.timeout or S.Travel.Timeout, 3)
        local landing = target + Vector3.new(0, 3, 0)

        if opts.direct then
            return leg(landing, speed, 2, deadline)
        end

        local start = root.Position
        local height = math.max(opts.height or S.Travel.Height, target.Y + 60, start.Y + 20)
        return leg(Vector3.new(start.X, height, start.Z), speed, 4, deadline)
            and leg(Vector3.new(target.X, height, target.Z), speed, 4, deadline)
            and leg(landing, speed, 2.5, deadline)
    end

    -- Never hand the character back in mid-air. Restoring gravity three hundred
    -- studs up is not a failed teleport, it is a death, and a flight that timed
    -- out is exactly when that happens.
    local function settle()
        local root = U.myRoot()
        if not root then return end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character}
        local hit = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), params)
        if not hit then return end

        local drop = root.Position.Y - hit.Position.Y
        if drop <= 10 then return end

        -- Landing has to happen even when the flight was cancelled, or Stop
        -- would be the most reliable way to kill yourself.
        local cancelled = cancel
        cancel = false
        leg(Vector3.new(root.Position.X, hit.Position.Y + 4, root.Position.Z),
            math.max(drop, 120), 3, os.clock() + 10)
        cancel = cancelled
    end

    -- destination may be a Vector3 or a CFrame. opts: mode, speed, height,
    -- timeout, direct.
    function Travel.to(destination, opts)
        opts = opts or {}
        if Travel.Busy then return false end

        local target = typeof(destination) == "CFrame" and destination.Position or destination
        if typeof(target) ~= "Vector3" then return false end
        if not U.myRoot() then return false end

        local mode = opts.mode or S.Travel.Mode
        Travel.Busy, cancel = true, false

        local ok
        if mode == "Instant" then
            ok = U.moveTo(target + Vector3.new(0, 3, 0), true)
            task.wait(0.1)
        else
            beginFlight()
            -- pcall so a mid-flight error can never leave gravity at zero.
            local safe, result = pcall(fly, target, opts)
            pcall(settle)
            endFlight()
            ok = safe and result or false
        end

        local root = U.myRoot()
        if root then root.AssemblyLinearVelocity = Vector3.zero end

        Travel.Busy = false
        return ok == true
    end

    function Travel.toPlayer(player, opts)
        local part = player and U.rootOf(player)
        if not part then return false end
        return Travel.to(part.Position, opts)
    end
end
