-- ============================================================================
--  SPLASH — the load-in screen.
--
--  Cosmetic, and honest about it: the script is a single chunk and has already
--  finished running by the time this draws, so nothing here is waiting on
--  anything. It sits over the menu for a moment and fades off.
--
--  Everything it makes is owned by KH and has a hard timer behind it, so there
--  is no path where it stays on screen — including the blur, which would be the
--  worst thing to leave behind.
-- ============================================================================

do
    local UI       = KH.UI
    local C        = UI.C
    local make     = UI.make
    local Lighting = KH.Services.Lighting

    if UI.Overlay then
        local fades = {}
        local function fading(obj, prop)
            fades[#fades + 1] = {obj = obj, prop = prop or "BackgroundTransparency"}
            return obj
        end

        -- Blurring what is behind it is what makes a transparent cover read as
        -- glass rather than as a screen that failed to draw.
        local blur = make("BlurEffect", {Name = "khSplash", Size = 0, Parent = Lighting})
        KH.own(blur)

        -- Active = false: even in the worst case this can never swallow a click.
        local root = fading(make("Frame", {
            Name = "Splash",
            BackgroundColor3 = C.Bg,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Active = false,
            ZIndex = 500,
            Parent = UI.Overlay,
        }))
        KH.own(root)

        -- Darkest at the edges, thinnest across the middle, so the game stays
        -- readable behind the card instead of being painted out.
        make("UIGradient", {
            Rotation = 90,
            Color = ColorSequence.new(C.Bg, C.Panel),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.12),
                NumberSequenceKeypoint.new(0.5, 0.46),
                NumberSequenceKeypoint.new(1, 0.12),
            }),
            Parent = root,
        })

        local card = fading(make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(330, 224),
            BackgroundColor3 = C.Panel,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            ZIndex = 502,
            Parent = root,
        }))
        UI.corner(card, 16)
        UI.gradient(card, C.Card, C.Panel, 90)
        fading(UI.stroke(card, C.Accent, 1, 0.55), "Transparency")

        local shadow = UI.shadow(card, 30, 0.45)
        shadow.ZIndex = 501
        fading(shadow, "ImageTransparency")

        -- A hairline of accent along the top edge, faded out at both ends.
        local edge = fading(make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.new(1, -70, 0, 1),
            BackgroundColor3 = C.Accent,
            BorderSizePixel = 0,
            ZIndex = 503,
            Parent = card,
        }))
        make("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0.05),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = edge,
        })

        -- The mark carries the name, so there is no title line to draw with it.
        -- Without it, the name has to be set instead.
        local asset = KH.logoAsset()
        if asset then
            fading(make("ImageLabel", {
                Image = asset,
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 24),
                Size = UDim2.fromOffset(96, 96),
                ZIndex = 503,
                Parent = card,
            }), "ImageTransparency")
        else
            fading(make("TextLabel", {
                Text = "KITTY HUB",
                Font = Enum.Font.GothamBold,
                TextSize = 24,
                TextColor3 = C.Text,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, 56),
                Size = UDim2.new(1, 0, 0, 30),
                ZIndex = 503,
                Parent = card,
            }), "TextTransparency")
        end

        fading(make("TextLabel", {
            Text = KH.GameName or "Roblox",
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 128),
            Size = UDim2.new(1, 0, 0, 16),
            ZIndex = 503,
            Parent = card,
        }), "TextTransparency")

        local track = fading(make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 156),
            Size = UDim2.fromOffset(236, 3),
            BackgroundColor3 = C.Row,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 503,
            Parent = card,
        }))
        UI.corner(track, 2)

        local fill = fading(make("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = C.Accent,
            BorderSizePixel = 0,
            ZIndex = 504,
            Parent = track,
        }))
        UI.corner(fill, 2)

        local status = fading(make("TextLabel", {
            Text = "starting up",
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 170),
            Size = UDim2.new(1, 0, 0, 14),
            ZIndex = 503,
            Parent = card,
        }), "TextTransparency")

        fading(make("TextLabel", {
            Text = ("v%s  ·  %s"):format(KH.Version, KH.X.name),
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = C.TextFaint,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 194),
            Size = UDim2.new(1, 0, 0, 14),
            ZIndex = 503,
            Parent = card,
        }), "TextTransparency")

        -- Nothing is loading, so the bar walks a fixed path rather than
        -- pretending to measure one. Each step glides for as long as it is held
        -- so the bar keeps moving the whole way rather than jumping and waiting.
        local STAGE = 0.72
        local stages = {
            {0.15, "checking the executor"},
            {0.33, "building the interface"},
            {0.52, "loading features"},
            {0.7, "arming the aimbot"},
            {0.88, "reading the map"},
            {1, "ready"},
        }

        KH.spawn(function()
            UI.tween(blur, 0.5, {Size = 14})
            for _, stage in ipairs(stages) do
                if not (KH.Alive and root.Parent) then return end
                status.Text = stage[2]
                UI.tween(fill, STAGE, {Size = UDim2.fromScale(stage[1], 1)})
                task.wait(STAGE)
            end

            task.wait(0.15)
            if not (KH.Alive and root.Parent) then return end
            for _, item in ipairs(fades) do
                pcall(function() UI.tween(item.obj, 0.35, {[item.prop] = 1}) end)
            end
            UI.tween(blur, 0.35, {Size = 0})
            task.wait(0.4)
            root:Destroy()
            blur:Destroy()
        end)

        -- Whatever happens above — an error, an unload mid-fade — both come
        -- off. Reading Parent on a destroyed instance is safe.
        task.delay(9, function()
            if root.Parent then root:Destroy() end
            if blur.Parent then blur:Destroy() end
        end)
    end
end
