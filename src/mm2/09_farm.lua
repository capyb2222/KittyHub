-- ============================================================================
--  FARM — coin collection, the coin magnet, gun-drop grabbing, anti-AFK
-- ============================================================================

do
    local UI          = KH.UI
    local U           = KH.U
    local Game        = KH.Game
    local S           = KH.S
    local X           = KH.X
    local VirtualUser = KH.Services.VirtualUser
    local LocalPlayer = KH.LocalPlayer

    local Farm = {}
    KH.Farm = Farm
    Farm.Collected = 0

    -- Coins that were touched but whose model has not despawned yet. Without
    -- this the farm re-targets the same coin forever.
    local claimed = {}
    Game.on("RoundStart", function() claimed = {} end)
    Game.on("RoundEnd", function() claimed = {} end)

    -- ------------------------------------------------------------- collect
    local function touch(part)
        if not X.firetouch then return false end
        local root = U.myRoot()
        if not root or not part or not part.Parent then return false end
        local ok = pcall(function()
            firetouchinterest(root, part, 0)
            firetouchinterest(root, part, 1)
        end)
        return ok
    end
    Farm.touch = touch

    local function markCollected(coin)
        if claimed[coin.model] then return end
        claimed[coin.model] = os.clock()
        Farm.Collected = Farm.Collected + 1
    end

    -- Stale claims are released after a few seconds so a coin we failed to pick
    -- up does not get ignored for the rest of the round.
    KH.loop(2, function()
        local now = os.clock()
        for model, at in pairs(claimed) do
            if not model.Parent or now - at > 6 then claimed[model] = nil end
        end
    end)

    -- ============================================================ COIN FARM
    local function moveTeleport(coin)
        U.moveTo(coin.part.Position + Vector3.new(0, 2.5, 0), true)
        task.wait(math.max(S.Farm.CoinDelay, 0))
    end

    -- Interpolated hop: still a teleport, but spread over several frames so it
    -- reads as fast movement rather than a snap.
    local function moveSmooth(coin)
        local root = U.myRoot()
        if not root then return end
        local startPos = root.Position
        local endPos = coin.part.Position + Vector3.new(0, 2.5, 0)
        local distance = (endPos - startPos).Magnitude
        local duration = distance / math.max(S.Farm.CoinSpeed, 1)
        local began = os.clock()

        while S.Farm.CoinFarm and KH.Alive do
            local elapsed = os.clock() - began
            if elapsed >= duration then break end
            if not coin.part.Parent then break end
            local current = U.myRoot()
            if not current then break end
            current.CFrame = CFrame.new(startPos:Lerp(endPos, elapsed / duration))
            task.wait()
        end
    end

    local function moveWalk(coin)
        local hum = U.myHum()
        if not hum then return end
        hum:MoveTo(coin.part.Position)
        local began = os.clock()
        while S.Farm.CoinFarm and KH.Alive and os.clock() - began < 6 do
            local root = U.myRoot()
            if not root or not coin.part.Parent then break end
            if (root.Position - coin.part.Position).Magnitude < 4 then break end
            task.wait(0.15)
        end
    end

    KH.loop(0.05, function()
        if not S.Farm.CoinFarm then return end
        if not U.myRoot() then return end

        local coin = Game.nearestCoin(claimed)
        if not coin then
            task.wait(1)
            return
        end

        local mode = S.Farm.CoinMode
        if mode == "Smooth" then moveSmooth(coin)
        elseif mode == "Walk" then moveWalk(coin)
        else moveTeleport(coin) end

        touch(coin.part)
        markCollected(coin)
    end)

    -- =========================================================== COIN MAGNET
    -- Fires touch events on every coin inside the radius without moving. Much
    -- less conspicuous than teleporting, and it stacks with normal play.
    KH.loop(0.2, function()
        if not S.Farm.Magnet then return end
        local root = U.myRoot()
        if not root then return end

        local radius = S.Farm.MagnetRadius
        for _, coin in ipairs(Game.coins()) do
            if (coin.part.Position - root.Position).Magnitude <= radius then
                if touch(coin.part) then markCollected(coin) end
            end
        end
    end)

    -- ========================================================= GUN GRABBING
    local grabbing = false

    function Farm.grabGun(announce)
        local drop = Game.GunDrop
        if not drop or not drop.Parent then
            if announce then
                UI.notify({title = "Gun Drop", text = "No dropped gun right now.", kind = "warn"})
            end
            return false
        end
        if grabbing then return false end
        if Game.gunTool() then return false end -- already armed

        grabbing = true
        KH.detach(function()
            local root = U.myRoot()
            if root then
                local origin = root.CFrame
                root.CFrame = CFrame.new(drop.Position + Vector3.new(0, 2.5, 0))

                -- Wait for the pickup to actually register before hopping back.
                local began = os.clock()
                repeat
                    task.wait(0.08)
                until Game.gunTool() or not drop.Parent or os.clock() - began > 2.5

                if S.Farm.GrabReturn then
                    local current = U.myRoot()
                    if current then current.CFrame = origin end
                end

                if Game.gunTool() then
                    UI.notify({title = "Gun Drop", text = "Picked up the dropped gun.", kind = "good"})
                end
            end
            grabbing = false
        end)
        return true
    end

    Game.on("GunDropped", function()
        UI.notify({title = "Gun Dropped", text = "The sheriff went down — gun is on the floor.", kind = "warn", duration = 5})
        if S.Farm.AutoGrabGun then
            task.wait(0.6) -- let the part settle where it lands
            Farm.grabGun(false)
        end
    end)

    Game.on("GunTaken", function()
        local hero = Game.Hero and Game.Hero or nil
        UI.notify({
            title = "Gun Taken",
            text = hero and (hero .. " picked up the gun.") or "Someone picked up the gun.",
            duration = 4,
        })
    end)

    -- ============================================================= ANTI-AFK
    KH.track(LocalPlayer.Idled:Connect(function()
        if not S.Farm.AntiAFK then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end
