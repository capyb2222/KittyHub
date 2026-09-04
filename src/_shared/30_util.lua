-- ============================================================================
--  UTIL — small helpers shared by every feature module
-- ============================================================================

local U = {}
KH.U = U

do
    local Players = KH.Services.Players
    local Stats   = KH.Services.Stats
    local LocalPlayer = KH.LocalPlayer

    -- ------------------------------------------------------------------ math
    function U.round(n, places)
        local m = 10 ^ (places or 0)
        return math.floor(n * m + 0.5) / m
    end

    function U.lerp(a, b, t) return a + (b - a) * t end

    function U.clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

    -- ------------------------------------------------------------ characters
    function U.charOf(player)
        local char = player and player.Character
        -- A character that has left the DataModel (respawn in flight) still
        -- reads as a valid Instance, so check it is actually parented.
        if char and char.Parent then return char end
        return nil
    end

    function U.rootOf(player)
        local char = U.charOf(player)
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    function U.humOf(player)
        local char = U.charOf(player)
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    function U.isAliveChar(player)
        local hum = U.humOf(player)
        return hum ~= nil and hum.Health > 0
    end

    function U.myRoot() return U.rootOf(LocalPlayer) end
    function U.myHum()  return U.humOf(LocalPlayer) end

    -- R15 names the torso differently from R6. Aim and prediction both want
    -- the mass centre rather than the head.
    function U.torsoOf(char)
        return char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
    end

    function U.distanceTo(position)
        local root = U.myRoot()
        if not root then return math.huge end
        return (root.Position - position).Magnitude
    end

    -- --------------------------------------------------------------- network
    function U.ping()
        local ok, ms = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and typeof(ms) == "number" then return ms end
        return 0
    end

    -- ---------------------------------------------------------------- screen
    -- Screen position, on-screen flag, depth. Depth goes negative behind the
    -- camera, which is what flips off-screen arrows to the right side.
    function U.toScreen(worldPos)
        local cam = KH.camera()
        local v, onScreen = cam:WorldToViewportPoint(worldPos)
        return Vector2.new(v.X, v.Y), onScreen, v.Z
    end

    -- ------------------------------------------------------------ prediction
    -- The server checks the position against where the target is when the
    -- packet lands, so the lead covers their motion and our round trip.
    function U.predict(char, strength, usePing, partOverride)
        local part = partOverride or U.torsoOf(char)
        if not part then return nil end

        local pos = part.Position
        if strength <= 0 then return pos end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local velocity = part.AssemblyLinearVelocity or Vector3.zero
        local moveDir = hum and hum.MoveDirection or Vector3.zero

        -- Y is damped hard: a jumping target's vertical velocity swings far
        -- more than its hitbox does, and over-leading up is the usual miss.
        local flattened = Vector3.new(velocity.X * 0.75, velocity.Y * 0.35, velocity.Z * 0.75)
        local lead = flattened * (strength / 15) + moveDir * strength

        if usePing then
            local pingSec = U.clamp(U.ping() / 1000, 0, 0.5)
            lead = lead + velocity * pingSec
        end
        return pos + lead
    end

    -- ------------------------------------------------------------- teleport
    -- Preserves look direction so a farm teleport does not spin the camera.
    function U.moveTo(position, keepLook)
        local root = U.myRoot()
        if not root then return false end
        if keepLook then
            root.CFrame = CFrame.new(position, position + root.CFrame.LookVector)
        else
            root.CFrame = CFrame.new(position)
        end
        return true
    end

    -- ----------------------------------------------------------------- sound
    -- Asset id or full URI. `rbxasset://sounds/...` ships with the client, so
    -- it always resolves — worth preferring for alerts that must be audible.
    local soundCache = {}
    function U.playSound(assetId, volume)
        local sound = soundCache[assetId]
        if not sound or not sound.Parent then
            sound = Instance.new("Sound")
            sound.SoundId = tostring(assetId):match("^rbx")
                and tostring(assetId)
                or ("rbxassetid://" .. tostring(assetId))
            sound.Parent = KH.camera()
            soundCache[assetId] = sound
            KH.own(sound)
        end
        sound.Volume = volume or 0.5
        pcall(function() sound:Play() end)
    end

    -- ------------------------------------------------------------- keycodes
    function U.keyCode(name)
        if typeof(name) ~= "string" then return nil end
        local ok, key = pcall(function() return Enum.KeyCode[name] end)
        return ok and key or nil
    end

    -- Roblox's chat box and our own text fields are both TextBoxes. A key
    -- held while one of them has focus belongs to whoever is typing, not to a
    -- feature: without this, saying "we" in chat flies you across the map.
    function U.typing()
        local ok, box = pcall(function()
            return KH.Services.UserInputService:GetFocusedTextBox()
        end)
        return ok and box ~= nil
    end

    function U.keyHeld(name)
        if U.typing() then return false end
        local key = U.keyCode(name)
        if not key then return false end
        return KH.Services.UserInputService:IsKeyDown(key)
    end

    -- ------------------------------------------------------------- iteration
    function U.otherPlayers()
        local out = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then out[#out + 1] = player end
        end
        return out
    end
end
