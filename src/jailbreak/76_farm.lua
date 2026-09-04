-- ============================================================================
--  FARM — the bits of grinding that are not a robbery
-- ============================================================================

local Farm = {}
KH.Farm = Farm

do
    local U           = KH.U
    local S           = KH.S
    local Game        = KH.Game
    local Rob         = KH.Rob
    local Police      = KH.Police
    local Travel      = KH.Travel
    local LocalPlayer = KH.LocalPlayer
    local VirtualUser = KH.Services.VirtualUser

    Farm.Collected = 0

    -- --------------------------------------------------------------- items
    -- Dropped pickups live in workspace.Items. Collecting one is standing on
    -- it, or the prompt that appears when you do, so both happen here.
    local function itemsFolder()
        return workspace:FindFirstChild("Items")
    end

    function Farm.nearestItem()
        local folder = itemsFolder()
        local root = U.myRoot()
        if not folder or not root then return nil end

        local best, bestDist
        for _, item in ipairs(folder:GetChildren()) do
            local position = Game.pivotOf(item)
            if position then
                local dist = (position - root.Position).Magnitude
                if dist <= S.Farm.ItemRadius and (not bestDist or dist < bestDist) then
                    best, bestDist = item, dist
                end
            end
        end
        return best
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
            Rob.fireNearby(12)
            task.wait(0.15)
        end
        if not item.Parent then Farm.Collected = Farm.Collected + 1 end
    end)

    -- ---------------------------------------------------------- interaction
    -- Fires any prompt in range without moving: doors, registers, hatches.
    KH.loop(0.2, function()
        if not S.Farm.InteractAura then return end
        Rob.fireNearby(math.max(S.Farm.AuraRange, 1))
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
