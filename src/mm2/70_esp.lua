-- ============================================================================
--  ESP — player boxes/names/tracers/chams plus coin, gun-drop and trap markers
-- ============================================================================

do
    local UI      = KH.UI
    local C       = UI.C
    local make    = UI.make
    local U       = KH.U
    local Game    = KH.Game
    local S       = KH.S
    local Players = KH.Services.Players
    local LocalPlayer = KH.LocalPlayer

    local Layer = UI.World

    -- ------------------------------------------------------ player objects
    local objects = {} -- player -> drawing set
    local chams   = {} -- player -> Highlight

    local function corner(parent)
        return make("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            Parent = parent,
        })
    end

    local function build(player)
        if player == LocalPlayer or objects[player] then return end

        local box = make("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Parent = Layer,
        })
        local boxStroke = make("UIStroke", {
            Thickness = 1.4,
            Color = Color3.new(1, 1, 1),
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Enabled = false,
            Parent = box,
        })

        -- Eight segments make the four L-shaped corners of a bracket box.
        local corners = {}
        for i = 1, 8 do corners[i] = corner(box) end

        local name = make("TextLabel", {
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            BackgroundTransparency = 1,
            TextStrokeTransparency = 0.35,
            RichText = true,
            AnchorPoint = Vector2.new(0.5, 1),
            Size = UDim2.fromOffset(260, 16),
            Visible = false,
            Parent = Layer,
        })
        local role = make("TextLabel", {
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            BackgroundTransparency = 1,
            TextStrokeTransparency = 0.35,
            RichText = true,
            AnchorPoint = Vector2.new(0.5, 0),
            Size = UDim2.fromOffset(260, 15),
            Visible = false,
            Parent = Layer,
        })
        local tracer = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(0, 1),
            Visible = false,
            Parent = Layer,
        })
        local healthBg = make("Frame", {
            BackgroundColor3 = Color3.fromRGB(15, 15, 20),
            BorderSizePixel = 0,
            Visible = false,
            Parent = Layer,
        })
        local healthFill = make("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            BackgroundColor3 = C.Good,
            BorderSizePixel = 0,
            Parent = healthBg,
        })
        local arrow = make("TextLabel", {
            Text = "▲",
            Font = Enum.Font.GothamBold,
            TextSize = 20,
            BackgroundTransparency = 1,
            TextStrokeTransparency = 0.4,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(28, 28),
            Visible = false,
            Parent = Layer,
        })

        objects[player] = {
            box = box, boxStroke = boxStroke, corners = corners,
            name = name, role = role, tracer = tracer,
            healthBg = healthBg, healthFill = healthFill, arrow = arrow,
        }
    end

    local function destroy(player)
        local set = objects[player]
        if set then
            for _, key in ipairs({"box", "name", "role", "tracer", "healthBg", "arrow"}) do
                pcall(function() set[key]:Destroy() end)
            end
            objects[player] = nil
        end
        if chams[player] then
            pcall(function() chams[player]:Destroy() end)
            chams[player] = nil
        end
    end

    local function hide(set)
        set.box.Visible = false
        set.name.Visible = false
        set.role.Visible = false
        set.tracer.Visible = false
        set.healthBg.Visible = false
        set.arrow.Visible = false
    end

    -- ------------------------------------------------------------ box paint
    local function paintCorners(set, width, height, color, show)
        local segs = set.corners
        if not show then
            for i = 1, 8 do segs[i].Visible = false end
            return
        end
        -- Arm length scales with the box but stays sane at extreme distances.
        local armX = math.clamp(width * 0.28, 3, 14)
        local armY = math.clamp(height * 0.22, 3, 18)
        local t = 1.6

        local layout = {
            {UDim2.fromOffset(0, 0),               UDim2.fromOffset(armX, t)},
            {UDim2.fromOffset(0, 0),               UDim2.fromOffset(t, armY)},
            {UDim2.fromOffset(width - armX, 0),    UDim2.fromOffset(armX, t)},
            {UDim2.fromOffset(width - t, 0),       UDim2.fromOffset(t, armY)},
            {UDim2.fromOffset(0, height - t),      UDim2.fromOffset(armX, t)},
            {UDim2.fromOffset(0, height - armY),   UDim2.fromOffset(t, armY)},
            {UDim2.fromOffset(width - armX, height - t), UDim2.fromOffset(armX, t)},
            {UDim2.fromOffset(width - t, height - armY), UDim2.fromOffset(t, armY)},
        }
        for i = 1, 8 do
            local seg = segs[i]
            seg.Visible = true
            seg.Position = layout[i][1]
            seg.Size = layout[i][2]
            seg.BackgroundColor3 = color
        end
    end

    -- ----------------------------------------------------------- chams pool
    local function ensureCham(player)
        if chams[player] then return chams[player] end
        local highlight = make("Highlight", {
            FillTransparency = S.ESP.ChamsFill,
            OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
            Enabled = false,
            Parent = Layer,
        })
        chams[player] = highlight
        return highlight
    end

    -- =============================================================== UPDATE
    local function updatePlayers()
        local espOn = S.ESP.Enabled
        if not espOn then
            for _, set in pairs(objects) do hide(set) end
            for _, highlight in pairs(chams) do highlight.Enabled = false end
            return
        end

        local cam = KH.camera()
        local viewport = cam.ViewportSize
        local centre = Vector2.new(viewport.X / 2, viewport.Y / 2)
        local myRoot = U.myRoot()

        for player, set in pairs(objects) do
            local char = U.charOf(player)
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local alive = root ~= nil and Game.isAlive(player)

            if not alive then
                hide(set)
                if chams[player] then chams[player].Enabled = false end
            else
                local color, role = Game.colorOf(player)
                local hideInnocent = S.ESP.OnlyRoles and (role == "Innocent")
                local distance = myRoot and (myRoot.Position - root.Position).Magnitude
                    or (cam.CFrame.Position - root.Position).Magnitude
                local inRange = distance <= S.ESP.MaxDistance

                if hideInnocent or not inRange then
                    hide(set)
                    if chams[player] then chams[player].Enabled = false end
                else
                    local head = char:FindFirstChild("Head")
                    local topWorld = (head and head.Position or root.Position) + Vector3.new(0, 0.75, 0)
                    local botWorld = root.Position - Vector3.new(0, 3.2, 0)
                    local topPos, onScreen, depth = U.toScreen(topWorld)
                    local botPos = U.toScreen(botWorld)

                    if onScreen then
                        set.arrow.Visible = false

                        local height = math.abs(topPos.Y - botPos.Y)
                        local width = height * 0.52
                        local cx = (topPos.X + botPos.X) / 2
                        local left = cx - width / 2

                        -- Box
                        if S.ESP.Boxes then
                            set.box.Visible = true
                            set.box.Position = UDim2.fromOffset(left, topPos.Y)
                            set.box.Size = UDim2.fromOffset(width, height)
                            local isCorner = S.ESP.BoxStyle == "Corner"
                            set.boxStroke.Enabled = not isCorner
                            set.boxStroke.Color = color
                            paintCorners(set, width, height, color, isCorner)
                        else
                            set.box.Visible = false
                        end

                        -- Name (+ optional distance)
                        if S.ESP.Names then
                            set.name.Visible = true
                            set.name.TextSize = S.ESP.TextSize
                            set.name.TextColor3 = color
                            set.name.Text = S.ESP.Distance
                                and string.format("%s  <font color=\"#%s\">%dm</font>",
                                    player.DisplayName, C.TextDim:ToHex(), math.floor(distance))
                                or player.DisplayName
                            set.name.Position = UDim2.fromOffset(cx, topPos.Y - 3)
                        else
                            set.name.Visible = false
                        end

                        -- Role
                        if S.ESP.Roles then
                            set.role.Visible = true
                            set.role.TextSize = math.max(S.ESP.TextSize - 1, 8)
                            set.role.TextColor3 = color
                            set.role.Text = role:upper()
                            set.role.Position = UDim2.fromOffset(cx, botPos.Y + 3)
                        else
                            set.role.Visible = false
                        end

                        -- Health bar, pinned to the left edge of the box
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if S.ESP.Health and hum and hum.MaxHealth > 0 then
                            local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                            set.healthBg.Visible = true
                            set.healthBg.Position = UDim2.fromOffset(left - 6, topPos.Y)
                            set.healthBg.Size = UDim2.fromOffset(3, height)
                            set.healthFill.Size = UDim2.fromScale(1, ratio)
                            set.healthFill.BackgroundColor3 =
                                Color3.fromRGB(255, 80, 80):Lerp(C.Good, ratio)
                        else
                            set.healthBg.Visible = false
                        end

                        -- Tracer
                        if S.ESP.Tracers then
                            local origin = (S.ESP.TracerOrigin == "Center") and centre
                                or Vector2.new(viewport.X / 2, viewport.Y)
                            local target = Vector2.new(cx, botPos.Y)
                            local delta = target - origin
                            set.tracer.Visible = true
                            set.tracer.BackgroundColor3 = color
                            set.tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
                            set.tracer.Position = UDim2.fromOffset(
                                (origin.X + target.X) / 2, (origin.Y + target.Y) / 2)
                            set.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                        else
                            set.tracer.Visible = false
                        end
                    else
                        -- Off-screen: everything hides except the edge arrow.
                        set.box.Visible = false
                        set.name.Visible = false
                        set.role.Visible = false
                        set.tracer.Visible = false
                        set.healthBg.Visible = false

                        if S.ESP.OffScreen then
                            -- Behind the camera the projection mirrors, so flip
                            -- it back before working out a bearing.
                            local point = topPos
                            if depth < 0 then
                                point = Vector2.new(viewport.X - point.X, viewport.Y - point.Y)
                            end
                            local direction = (point - centre)
                            if direction.Magnitude < 1 then direction = Vector2.new(0, -1) end
                            direction = direction.Unit

                            local radius = math.min(viewport.X, viewport.Y) * 0.34
                            local at = centre + direction * radius
                            set.arrow.Visible = true
                            set.arrow.TextColor3 = color
                            set.arrow.Position = UDim2.fromOffset(at.X, at.Y)
                            set.arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
                        else
                            set.arrow.Visible = false
                        end
                    end

                    -- Chams
                    if S.ESP.Chams then
                        local highlight = ensureCham(player)
                        highlight.Enabled = true
                        highlight.FillTransparency = S.ESP.ChamsFill
                        if highlight.Adornee ~= char then highlight.Adornee = char end
                        highlight.FillColor = color
                        highlight.OutlineColor = color
                    elseif chams[player] then
                        chams[player].Enabled = false
                    end
                end
            end
        end
    end

    -- ====================================================== WORLD MARKERS
    -- Anchored in 3D, so BillboardGuis carry them — no per-frame projection
    -- on our side — and they rebuild on a timer rather than every frame.
    local markers = {} -- instance -> BillboardGui

    local function marker(part, text, color, size, maxDistance)
        local billboard = make("BillboardGui", {
            Adornee = part,
            Size = UDim2.fromOffset(size or 70, 20),
            StudsOffset = Vector3.new(0, 1.8, 0),
            AlwaysOnTop = true,
            MaxDistance = maxDistance or 500,
            Parent = Layer,
        })
        make("TextLabel", {
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = color,
            BackgroundTransparency = 1,
            TextStrokeTransparency = 0.35,
            Size = UDim2.fromScale(1, 1),
            Parent = billboard,
        })
        return billboard
    end

    local COIN_COLOR = Color3.fromRGB(255, 214, 64)
    local GUN_COLOR  = Color3.fromRGB(255, 236, 64)
    local TRAP_COLOR = Color3.fromRGB(255, 122, 26)

    local gunHighlight

    local function updateWorld()
        local seen = {}

        -- Coins
        if S.ESP.CoinESP then
            for _, coin in ipairs(Game.coins()) do
                local part = coin.part
                seen[part] = true
                if not markers[part] then
                    markers[part] = marker(part, "◆", COIN_COLOR, 26, 320)
                end
            end
        end

        -- Dropped gun
        local drop = Game.GunDrop
        if S.ESP.GunESP and drop and drop.Parent then
            seen[drop] = true
            if not markers[drop] then
                markers[drop] = marker(drop, "GUN", GUN_COLOR, 70, 2000)
            end
            if not gunHighlight or not gunHighlight.Parent then
                gunHighlight = make("Highlight", {
                    FillColor = GUN_COLOR, FillTransparency = 0.45,
                    OutlineColor = GUN_COLOR, OutlineTransparency = 0,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                    Parent = Layer,
                })
            end
            gunHighlight.Adornee = drop
            gunHighlight.Enabled = true
        elseif gunHighlight then
            gunHighlight.Enabled = false
        end

        -- Traps
        if S.ESP.TrapESP then
            for trap in pairs(Game.Traps) do
                if trap.Parent then
                    seen[trap] = true
                    if not markers[trap] then
                        -- Traps are invisible in game; make ours actually show.
                        pcall(function() trap.Transparency = 0.4 end)
                        markers[trap] = marker(trap, "TRAP", TRAP_COLOR, 70, 900)
                    end
                end
            end
        end

        for instance, billboard in pairs(markers) do
            if not seen[instance] or not instance.Parent then
                pcall(function() billboard:Destroy() end)
                markers[instance] = nil
            end
        end
    end

    -- ------------------------------------------------------------ lifecycle
    for _, player in ipairs(Players:GetPlayers()) do build(player) end
    KH.track(Players.PlayerAdded:Connect(build))
    KH.track(Players.PlayerRemoving:Connect(destroy))

    KH.onFrame("esp", function() updatePlayers() end, 20)

    -- 8 Hz is plenty: coins spawn in batches and the gun drops once a round.
    KH.loop(0.125, function()
        if S.ESP.Enabled and (S.ESP.CoinESP or S.ESP.GunESP or S.ESP.TrapESP) then
            updateWorld()
        elseif next(markers) then
            for instance, billboard in pairs(markers) do
                pcall(function() billboard:Destroy() end)
                markers[instance] = nil
            end
            if gunHighlight then gunHighlight.Enabled = false end
        end
    end)
end
