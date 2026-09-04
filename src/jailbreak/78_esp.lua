-- ============================================================================
--  ESP — who is on which team, and which robberies are open
--
--  Highlights and billboards rather than drawn boxes: the engine keeps them on
--  the target by itself, so there is no per-frame projection to get wrong, and
--  they behave the same on every executor.
-- ============================================================================

local ESP = {}
KH.ESP = ESP

do
    local UI          = KH.UI
    local U           = KH.U
    local S           = KH.S
    local Game        = KH.Game
    local Players     = KH.Services.Players
    local LocalPlayer = KH.LocalPlayer
    local make        = UI.make

    -- Billboards do not render inside a ScreenGui, so they get a plain folder
    -- next to it in the same host.
    local holder = make("Folder", {Name = "kh_jb_esp", Parent = UI.World.Parent})
    KH.own(holder)
    local markerHolder = make("Folder", {Name = "kh_jb_marks", Parent = workspace})
    KH.own(markerHolder)

    local tags = {}     -- player -> {highlight, billboard, label}
    local marks = {}    -- robbery entry -> {part, billboard, label}

    local function teamColor(player)
        if not S.ESP.Team then return S.UI.Accent end
        local name = Game.teamName(player)
        if name == "Police" then return S.ESP.ColorPolice end
        if name == "Criminal" then return S.ESP.ColorCriminal end
        return S.ESP.ColorPrisoner
    end

    -- ------------------------------------------------------------- players
    local function dropTag(player)
        local entry = tags[player]
        if not entry then return end
        tags[player] = nil
        pcall(function() entry.highlight:Destroy() end)
        pcall(function() entry.billboard:Destroy() end)
    end

    local function tagFor(player)
        local entry = tags[player]
        if entry and entry.highlight.Parent and entry.billboard.Parent then return entry end
        dropTag(player)

        local highlight = make("Highlight", {
            Name = "kh_hl",
            FillTransparency = 0.65,
            OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
            Parent = holder,
        })
        local billboard = make("BillboardGui", {
            Name = "kh_bb",
            AlwaysOnTop = true,
            Size = UDim2.fromOffset(210, 34),
            StudsOffset = Vector3.new(0, 3.2, 0),
            MaxDistance = 5000,
            Parent = holder,
        })
        local label = make("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            RichText = true,
            TextStrokeTransparency = 0.4,
            Parent = billboard,
        })

        entry = {highlight = highlight, billboard = billboard, label = label}
        tags[player] = entry
        return entry
    end

    local function wanted(player)
        if player == LocalPlayer then return false end
        if not U.isAliveChar(player) then return false end
        if S.ESP.OnlyEnemies and Game.teamName(player) == Game.myTeamName() then return false end

        local root, mine = U.rootOf(player), U.myRoot()
        if not root then return false end
        if mine and (root.Position - mine.Position).Magnitude > S.ESP.MaxDistance then
            return false
        end
        return true
    end

    local function refreshPlayers()
        for _, player in ipairs(Players:GetPlayers()) do
            if not wanted(player) then
                dropTag(player)
            else
                local char = U.charOf(player)
                local root = U.rootOf(player)
                local entry = tagFor(player)
                local color = teamColor(player)

                entry.highlight.Enabled = S.ESP.Highlight
                entry.highlight.Adornee = char
                entry.highlight.FillColor = color
                entry.highlight.OutlineColor = color

                local show = S.ESP.Names or S.ESP.Distance
                entry.billboard.Enabled = show
                entry.billboard.Adornee = char and (char:FindFirstChild("Head") or root) or nil

                if show then
                    local bits = {}
                    if S.ESP.Names then bits[#bits + 1] = player.DisplayName end
                    -- No character of our own means no distance to show, and
                    -- formatting the infinity that stands in for it would throw.
                    local away = U.distanceTo(root.Position)
                    if S.ESP.Distance and away < 1e6 then
                        bits[#bits + 1] = ("%dm"):format(math.floor(away))
                    end
                    entry.label.Text = table.concat(bits, "  ")
                    entry.label.TextColor3 = color
                end
            end
        end

        -- Players who left never come back through the loop above.
        for player in pairs(tags) do
            if player.Parent ~= Players then dropTag(player) end
        end
    end

    -- ------------------------------------------------------------ robberies
    local function dropMark(entry)
        local mark = marks[entry]
        if not mark then return end
        marks[entry] = nil
        pcall(function() mark.part:Destroy() end)
    end

    local function markFor(entry)
        local mark = marks[entry]
        if mark and mark.part.Parent then return mark end
        dropMark(entry)

        local part = make("Part", {
            Name = "kh_mark",
            Anchored = true,
            CanCollide = false,
            CanQuery = false,
            CanTouch = false,
            Transparency = 1,
            Size = Vector3.new(1, 1, 1),
            Parent = markerHolder,
        })
        local billboard = make("BillboardGui", {
            AlwaysOnTop = true,
            Size = UDim2.fromOffset(220, 32),
            MaxDistance = 4000,
            Parent = part,
        })
        local label = make("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextStrokeTransparency = 0.4,
            Parent = billboard,
        })

        mark = {part = part, billboard = billboard, label = label}
        marks[entry] = mark
        return mark
    end

    local function refreshRobberies()
        for _, entry in ipairs(Game.Robberies) do
            local open = not entry.skip and S.ESP.Robberies and Game.isRobbable(entry)
            local point = open and Game.centrePoint(entry) or nil

            if not point then
                dropMark(entry)
            else
                local mark = markFor(entry)
                mark.part.Position = point + Vector3.new(0, 8, 0)
                mark.label.Text = ("%s  ·  %s"):format(entry.name, Game.statusText(entry))
                mark.label.TextColor3 = Game.status(entry) == Game.Status.Started
                    and Color3.fromRGB(255, 196, 64)
                    or Color3.fromRGB(112, 232, 128)
            end
        end
    end

    local function clearAll()
        for player in pairs(tags) do dropTag(player) end
        for entry in pairs(marks) do dropMark(entry) end
    end
    KH.undo(clearAll)

    KH.loop(0.25, function()
        if not S.ESP.Enabled then
            if next(tags) or next(marks) then clearAll() end
            return
        end
        refreshPlayers()
        refreshRobberies()
    end)
end
