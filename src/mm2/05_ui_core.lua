-- ============================================================================
--  UI CORE — window shell, tabs, notifications, watermark, theming
-- ============================================================================

local UI = {}
KH.UI = UI

do
    local TweenService     = KH.Services.TweenService
    local UserInputService = KH.Services.UserInputService
    local Lighting         = KH.Services.Lighting
    local LocalPlayer      = KH.LocalPlayer
    local S                = KH.S

    -- ------------------------------------------------------------- palette
    local C = {
        Bg        = Color3.fromRGB(13, 13, 18),
        Panel     = Color3.fromRGB(20, 20, 28),
        Card      = Color3.fromRGB(25, 25, 34),
        Row       = Color3.fromRGB(31, 31, 42),
        RowHover  = Color3.fromRGB(40, 40, 54),
        Stroke    = Color3.fromRGB(42, 42, 56),
        Text      = Color3.fromRGB(237, 237, 242),
        TextDim   = Color3.fromRGB(138, 138, 160),
        TextFaint = Color3.fromRGB(90, 90, 112),
        Off       = Color3.fromRGB(51, 51, 74),
        Good      = Color3.fromRGB(74, 222, 128),
        Bad       = Color3.fromRGB(248, 113, 113),
        Warn      = Color3.fromRGB(251, 191, 36),
    }
    C.Accent = S.UI.Accent
    UI.C = C

    -- ------------------------------------------------------- instance sugar
    function UI.make(class, props, children)
        local inst = Instance.new(class)
        for k, v in pairs(props or {}) do
            if k ~= "Parent" then inst[k] = v end
        end
        for _, child in ipairs(children or {}) do child.Parent = inst end
        if props and props.Parent then inst.Parent = props.Parent end
        return inst
    end
    local make = UI.make

    function UI.corner(parent, radius)
        return make("UICorner", {CornerRadius = UDim.new(0, radius or 8), Parent = parent})
    end

    function UI.stroke(parent, color, thickness, transparency)
        return make("UIStroke", {
            Color = color or C.Stroke,
            Thickness = thickness or 1,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = parent,
        })
    end

    function UI.pad(parent, all, top, bottom, left, right)
        return make("UIPadding", {
            PaddingTop    = UDim.new(0, top or all or 0),
            PaddingBottom = UDim.new(0, bottom or all or 0),
            PaddingLeft   = UDim.new(0, left or all or 0),
            PaddingRight  = UDim.new(0, right or all or 0),
            Parent = parent,
        })
    end

    function UI.list(parent, padding, align)
        return make("UIListLayout", {
            Padding = UDim.new(0, padding or 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
            Parent = parent,
        })
    end

    function UI.gradient(parent, from, to, rotation)
        return make("UIGradient", {
            Color = ColorSequence.new(from, to),
            Rotation = rotation or 0,
            Parent = parent,
        })
    end

    local QUAD = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    function UI.tween(obj, duration, props, style)
        local info = duration and TweenInfo.new(duration,
            style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out) or QUAD
        local t = TweenService:Create(obj, info, props)
        t:Play()
        return t
    end
    local tween = UI.tween

    -- --------------------------------------------------------- accent theme
    -- Anything painted with the accent registers here so the colour picker in
    -- Settings can repaint the whole menu live.
    local accented = {}
    function UI.accented(obj, property, shade)
        accented[#accented + 1] = {obj = obj, prop = property or "BackgroundColor3", shade = shade}
        return obj
    end

    local function shadeOf(color, shade)
        if not shade then return color end
        local h, s, v = color:ToHSV()
        return Color3.fromHSV(h, math.clamp(s * (shade.s or 1), 0, 1), math.clamp(v * (shade.v or 1), 0, 1))
    end

    function UI.applyAccent(color)
        C.Accent = color
        S.UI.Accent = color
        for i = #accented, 1, -1 do
            local entry = accented[i]
            if entry.obj and entry.obj.Parent then
                local target = shadeOf(color, entry.shade)
                if entry.prop == "Gradient" then
                    entry.obj.Color = ColorSequence.new(shadeOf(color, {v = 1.25, s = 0.75}), target)
                else
                    pcall(function() entry.obj[entry.prop] = target end)
                end
            else
                table.remove(accented, i)
            end
        end
    end

    -- ------------------------------------------------------------- host gui
    local function guiParent()
        if KH.X.gethui then
            local ok, hui = pcall(gethui)
            if ok and hui then return hui end
        end
        local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if ok and coreGui then return coreGui end
        return LocalPlayer:WaitForChild("PlayerGui")
    end

    local function newScreen(name, order)
        local gui = make("ScreenGui", {
            Name = name,
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder = order,
        })
        pcall(function() gui.Parent = guiParent() end)
        return KH.own(gui)
    end

    -- Randomised names so a second copy of the menu never collides with ours.
    local suffix = tostring(math.random(100000, 999999))
    UI.Screen  = newScreen("kh_" .. suffix, 10000)
    UI.World   = newScreen("kw_" .. suffix, 9998)  -- ESP layer, below the menu
    UI.Overlay = newScreen("ko_" .. suffix, 10001) -- notifications, watermark

    -- ---------------------------------------------------------- drop shadow
    -- Standard 9-slice shadow image; if the asset ever fails to resolve it just
    -- renders as nothing rather than erroring.
    function UI.shadow(parent, spread, transparency)
        spread = spread or 22
        return make("ImageLabel", {
            Name = "Shadow",
            BackgroundTransparency = 1,
            Image = "rbxassetid://6014261993",
            ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = transparency or 0.45,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(49, 49, 450, 450),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, spread * 2, 1, spread * 2),
            ZIndex = 0,
            Parent = parent,
        })
    end

    -- ============================================================== WINDOW
    local WIN_W, WIN_H = 660, 452
    local SIDEBAR_W, TOPBAR_H = 152, 46

    local Root = make("Frame", {
        Name = "Root",
        Size = UDim2.fromOffset(WIN_W, WIN_H),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = UI.Screen,
    })
    UI.Root = Root
    UI.shadow(Root, 26, 0.4)

    local Window = make("Frame", {
        Name = "Window",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = C.Bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = Root,
    })
    UI.corner(Window, 12)
    UI.stroke(Window, C.Stroke, 1)
    UI.Window = Window

    -- A soft accent wash across the top edge, so the window reads as themed
    -- rather than as a flat grey box.
    local wash = make("Frame", {
        Size = UDim2.new(1, 0, 0, 150),
        BackgroundColor3 = C.Accent,
        BackgroundTransparency = 0.93,
        BorderSizePixel = 0,
        Parent = Window,
    })
    UI.accented(wash, "BackgroundColor3")
    make("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 90,
        Parent = wash,
    })

    -- ------------------------------------------------------------- top bar
    local TopBar = make("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, TOPBAR_H),
        BackgroundTransparency = 1,
        Parent = Window,
    })

    local titleHolder = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(0, 300, 1, 0),
        Parent = TopBar,
    })

    local title = make("TextLabel", {
        Text = "Kitty Hub",
        Font = Enum.Font.GothamBold,
        TextSize = 19,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 92, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleHolder,
    })
    UI.accented(UI.gradient(title, C.Accent, C.Accent, 25), "Gradient")

    local badge = make("Frame", {
        BackgroundColor3 = C.Accent,
        BackgroundTransparency = 0.82,
        Position = UDim2.fromOffset(96, 13),
        Size = UDim2.fromOffset(46, 20),
        BorderSizePixel = 0,
        Parent = titleHolder,
    })
    UI.corner(badge, 6)
    UI.accented(badge, "BackgroundColor3")
    local badgeText = make("TextLabel", {
        Text = "MM2",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = C.Accent,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = badge,
    })
    UI.accented(badgeText, "TextColor3", {v = 1.35, s = 0.5})

    make("TextLabel", {
        Text = "v" .. KH.Version,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.TextFaint,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(150, 0),
        Size = UDim2.new(0, 60, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleHolder,
    })

    local function topButton(text, offsetX, hoverColor)
        local btn = make("TextButton", {
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            TextColor3 = C.TextDim,
            BackgroundColor3 = C.Row,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, offsetX, 0.5, 0),
            Size = UDim2.fromOffset(28, 28),
            Parent = TopBar,
        })
        UI.corner(btn, 7)
        btn.MouseEnter:Connect(function()
            tween(btn, 0.12, {BackgroundTransparency = 0, TextColor3 = hoverColor or C.Text})
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, 0.12, {BackgroundTransparency = 1, TextColor3 = C.TextDim})
        end)
        return btn
    end

    local closeBtn = topButton("✕", -12, C.Bad)
    local minBtn   = topButton("—", -46)

    -- ------------------------------------------------------------- sidebar
    local Sidebar = make("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_W, 1, -TOPBAR_H),
        Position = UDim2.fromOffset(0, TOPBAR_H),
        BackgroundColor3 = C.Panel,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Parent = Window,
    })
    make("Frame", { -- hairline divider
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = C.Stroke,
        BorderSizePixel = 0,
        Parent = Sidebar,
    })

    local tabHolder = make("Frame", {
        Size = UDim2.new(1, 0, 1, -58),
        BackgroundTransparency = 1,
        Parent = Sidebar,
    })
    UI.list(tabHolder, 3)
    UI.pad(tabHolder, 0, 12, 0, 10, 10)

    -- The indicator glides between tabs instead of hard-cutting.
    local indicator = make("Frame", {
        Size = UDim2.fromOffset(3, 18),
        Position = UDim2.fromOffset(0, 16),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
        Parent = Sidebar,
    })
    UI.corner(indicator, 2)
    UI.accented(indicator, "BackgroundColor3")

    -- Status strip pinned to the bottom of the sidebar.
    local statusBox = make("Frame", {
        Size = UDim2.new(1, -20, 0, 44),
        Position = UDim2.new(0, 10, 1, -52),
        BackgroundColor3 = C.Card,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Parent = Sidebar,
    })
    UI.corner(statusBox, 8)
    local roleLabel = make("TextLabel", {
        Text = "Waiting…",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = C.TextDim,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 5),
        Size = UDim2.new(1, -20, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = statusBox,
    })
    local statLabel = make("TextLabel", {
        Text = "—",
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.TextFaint,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 22),
        Size = UDim2.new(1, -20, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = statusBox,
    })
    UI.RoleLabel, UI.StatLabel = roleLabel, statLabel

    -- ------------------------------------------------------------- content
    local Content = make("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -SIDEBAR_W, 1, -TOPBAR_H),
        Position = UDim2.fromOffset(SIDEBAR_W, TOPBAR_H),
        BackgroundTransparency = 1,
        Parent = Window,
    })

    -- Search box: filters every control by label across the active tab.
    local searchWrap = make("Frame", {
        Size = UDim2.new(1, -28, 0, 30),
        Position = UDim2.fromOffset(14, 8),
        BackgroundColor3 = C.Row,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Parent = Content,
    })
    UI.corner(searchWrap, 8)
    make("TextLabel", {
        Text = "⌕",
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = C.TextFaint,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.fromOffset(16, 30),
        Parent = searchWrap,
    })
    local searchBox = make("TextBox", {
        Text = "",
        PlaceholderText = "Search settings…",
        PlaceholderColor3 = C.TextFaint,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -40, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = searchWrap,
    })

    local Pages = make("Frame", {
        Size = UDim2.new(1, 0, 1, -44),
        Position = UDim2.fromOffset(0, 44),
        BackgroundTransparency = 1,
        Parent = Content,
    })

    -- ============================================================== TABS
    local tabs = {}
    UI.Tabs = tabs
    local activeTab
    local tabOrder = 0

    function UI.selectTab(name)
        local tab = tabs[name]
        if not tab then return end
        activeTab = name
        UI.ActiveTab = name
        for tabName, entry in pairs(tabs) do
            local on = (tabName == name)
            entry.page.Visible = on
            tween(entry.button, 0.14, {BackgroundTransparency = on and 0.86 or 1})
            tween(entry.label, 0.14, {TextColor3 = on and C.Text or C.TextDim})
        end
        indicator.Visible = true
        tween(indicator, 0.2, {
            Position = UDim2.fromOffset(0, tab.button.AbsolutePosition.Y
                - Sidebar.AbsolutePosition.Y + tab.button.AbsoluteSize.Y / 2),
        }, Enum.EasingStyle.Back)
    end

    function UI.addTab(name)
        tabOrder = tabOrder + 1
        local button = make("TextButton", {
            Name = name,
            Text = "",
            AutoButtonColor = false,
            BackgroundColor3 = C.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 34),
            LayoutOrder = tabOrder,
            Parent = tabHolder,
        })
        UI.corner(button, 7)
        UI.accented(button, "BackgroundColor3")

        local textLabel = make("TextLabel", {
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(15, 0),
            Size = UDim2.new(1, -21, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = button,
        })

        local page = make("ScrollingFrame", {
            Name = name,
            Visible = false,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.Accent,
            ScrollBarImageTransparency = 0.3,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = Pages,
        })
        UI.accented(page, "ScrollBarImageColor3")
        UI.list(page, 10)
        UI.pad(page, 0, 2, 16, 14, 14)

        local tab = {name = name, button = button, page = page, label = textLabel, sections = {}}
        tabs[name] = tab

        button.MouseEnter:Connect(function()
            if activeTab ~= name then tween(button, 0.1, {BackgroundTransparency = 0.94}) end
        end)
        button.MouseLeave:Connect(function()
            if activeTab ~= name then tween(button, 0.1, {BackgroundTransparency = 1}) end
        end)
        button.MouseButton1Click:Connect(function() UI.selectTab(name) end)
        return tab
    end

    -- ---------------------------------------------------------- sections
    -- Every control lives inside a card. Cards auto-size to their contents so
    -- nothing has to declare a pixel height.
    function UI.section(tab, titleText)
        tab.order = (tab.order or 0) + 1
        local card = make("Frame", {
            BackgroundColor3 = C.Card,
            BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = tab.order,
            Parent = tab.page,
        })
        UI.corner(card, 10)
        UI.stroke(card, C.Stroke, 1, 0.35)

        make("TextLabel", {
            Text = titleText:upper(),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(14, 11),
            Size = UDim2.new(1, -28, 0, 14),
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })

        local body = make("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 30),
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = card,
        })
        UI.list(body, 4)
        UI.pad(body, 0, 0, 10, 10, 10)

        local section = {card = card, body = body, rows = {}, tab = tab, order = 0}
        table.insert(tab.sections, section)
        return section
    end

    -- Controls call this so each row lands below the previous one. Without an
    -- explicit LayoutOrder every row ties at 0 and the order is undefined.
    function UI.nextOrder(section)
        section.order = (section.order or 0) + 1
        return section.order
    end

    -- ------------------------------------------------------------- search
    -- Rows register their searchable text; sections with no visible row hide
    -- themselves so the results do not leave empty cards floating around.
    function UI.registerSearch(section, frame, text)
        table.insert(section.rows, {frame = frame, text = text:lower()})
    end

    local function applySearch(query)
        query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
        for _, tab in pairs(tabs) do
            for _, section in ipairs(tab.sections) do
                local anyVisible = false
                for _, row in ipairs(section.rows) do
                    local visible = (query == "") or row.text:find(query, 1, true) ~= nil
                    row.frame.Visible = visible
                    anyVisible = anyVisible or visible
                end
                section.card.Visible = anyVisible or #section.rows == 0
            end
        end
    end
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        applySearch(searchBox.Text)
    end)

    -- ==================================================== OPEN / CLOSE / DRAG
    local blur = make("BlurEffect", {Name = "kh_blur", Size = 0, Enabled = false, Parent = Lighting})
    KH.own(blur)

    local isOpen = false
    UI.IsOpen = false

    function UI.setOpen(open, instant)
        if open == isOpen then return end
        isOpen = open
        UI.IsOpen = open

        if open then
            Root.Visible = true
            UI.OpenButton.Visible = false
            blur.Enabled = true
            if instant then
                Root.Size = UDim2.fromOffset(WIN_W, WIN_H)
                blur.Size = 12
            else
                Root.Size = UDim2.fromOffset(WIN_W * 0.94, WIN_H * 0.94)
                tween(Root, 0.22, {Size = UDim2.fromOffset(WIN_W, WIN_H)}, Enum.EasingStyle.Back)
                tween(blur, 0.22, {Size = 12})
            end
        else
            tween(Root, 0.16, {Size = UDim2.fromOffset(WIN_W * 0.94, WIN_H * 0.94)})
            tween(blur, 0.16, {Size = 0})
            task.delay(0.17, function()
                if not isOpen then
                    Root.Visible = false
                    blur.Enabled = false
                    if UI.OpenButton then UI.OpenButton.Visible = true end
                end
            end)
        end
    end

    function UI.toggleOpen() UI.setOpen(not isOpen) end

    closeBtn.MouseButton1Click:Connect(function() UI.setOpen(false) end)
    minBtn.MouseButton1Click:Connect(function() UI.setOpen(false) end)

    -- Floating re-open button.
    local openBtn = make("TextButton", {
        Name = "Open",
        Text = "  Kitty Hub",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = C.Text,
        BackgroundColor3 = C.Accent,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(116, 38),
        Position = UDim2.new(0, 20, 1, -62),
        Parent = UI.Screen,
    })
    UI.corner(openBtn, 10)
    UI.accented(openBtn, "BackgroundColor3")
    UI.shadow(openBtn, 14, 0.55)
    UI.OpenButton = openBtn
    openBtn.MouseButton1Click:Connect(function() UI.setOpen(true) end)
    openBtn.MouseEnter:Connect(function() tween(openBtn, 0.12, {Size = UDim2.fromOffset(122, 40)}) end)
    openBtn.MouseLeave:Connect(function() tween(openBtn, 0.12, {Size = UDim2.fromOffset(116, 38)}) end)

    -- Dragging, from the top bar only.
    do
        local dragging, dragStart, startPos
        KH.track(TopBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, Root.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end))
        KH.track(UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                Root.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end))
    end

    -- =========================================================== NOTIFICATIONS
    local notifyHolder = make("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(280, 400),
        BackgroundTransparency = 1,
        Parent = UI.Overlay,
    })
    make("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Parent = notifyHolder,
    })

    local KIND_COLOR = {info = nil, good = C.Good, bad = C.Bad, warn = C.Warn}
    local notifySeq = 0

    -- A card inside a layout-managed slot: the list stacks the slot, the card
    -- slides within it. A list layout overwrites its children's Position.
    function UI.notify(opts)
        if not S.UI.Notifications then return end
        opts = opts or {}
        local duration = opts.duration or 3.5
        local accent = KIND_COLOR[opts.kind or "info"] or C.Accent

        notifySeq = notifySeq + 1
        local slot = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = notifySeq,
            Parent = notifyHolder,
        })

        local card = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.fromOffset(320, 0),
            BackgroundColor3 = C.Card,
            BorderSizePixel = 0,
            Parent = slot,
        })
        UI.corner(card, 9)
        UI.stroke(card, C.Stroke, 1, 0.2)
        UI.shadow(card, 12, 0.6)
        UI.pad(card, 0, 10, 12, 0, 0)

        make("Frame", {
            Size = UDim2.new(0, 3, 1, -20),
            Position = UDim2.fromOffset(0, 10),
            BackgroundColor3 = accent,
            BorderSizePixel = 0,
            Parent = card,
        })

        make("TextLabel", {
            Text = opts.title or "Kitty Hub",
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = C.Text,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -26, 0, 16),
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })

        local text = opts.text or ""
        if text ~= "" then
            make("TextLabel", {
                Text = text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = C.TextDim,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(14, 18),
                Size = UDim2.new(1, -26, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = card,
            })
        end

        tween(card, 0.26, {Position = UDim2.fromOffset(0, 0)}, Enum.EasingStyle.Quint)

        task.delay(duration, function()
            if not slot.Parent then return end
            tween(card, 0.2, {Position = UDim2.fromOffset(340, 0)})
            task.delay(0.22, function() pcall(function() slot:Destroy() end) end)
        end)
        return card
    end

    -- ============================================================= WATERMARK
    local watermark = make("Frame", {
        Name = "Watermark",
        Position = UDim2.fromOffset(20, 18),
        Size = UDim2.fromOffset(340, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = C.Bg,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Visible = S.UI.Watermark,
        Parent = UI.Overlay,
    })
    UI.corner(watermark, 8)
    UI.stroke(watermark, C.Stroke, 1, 0.3)
    local watermarkBar = make("Frame", {
        Size = UDim2.new(0, 3, 1, -10),
        Position = UDim2.fromOffset(6, 5),
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
        Parent = watermark,
    })
    UI.corner(watermarkBar, 2)
    UI.accented(watermarkBar, "BackgroundColor3")
    local watermarkText = make("TextLabel", {
        Text = "Kitty Hub",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = C.Text,
        BackgroundTransparency = 1,
        RichText = true,
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = watermark,
    })
    UI.Watermark, UI.WatermarkText = watermark, watermarkText

    -- ========================================================== KEYBIND LIST
    local keybindPanel = make("Frame", {
        Name = "Keybinds",
        Position = UDim2.fromOffset(20, 58),
        Size = UDim2.fromOffset(168, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.Bg,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Visible = S.UI.KeybindList,
        Parent = UI.Overlay,
    })
    UI.corner(keybindPanel, 8)
    UI.stroke(keybindPanel, C.Stroke, 1, 0.3)
    make("TextLabel", {
        Text = "KEYBINDS",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = C.TextFaint,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 0, 12),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = keybindPanel,
    })
    local keybindList = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 24),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = keybindPanel,
    })
    UI.list(keybindList, 2, Enum.HorizontalAlignment.Left)
    UI.pad(keybindList, 0, 0, 9, 10, 10)
    UI.KeybindPanel, UI.KeybindList = keybindPanel, keybindList

    -- Entries are re-rendered whenever a bind changes, so the panel always
    -- shows the current key rather than whatever it was at load.
    local keybindEntries = {}
    function UI.registerKeybind(label, getKey, isActive)
        keybindEntries[#keybindEntries + 1] = {label = label, get = getKey, active = isActive}
    end

    function UI.refreshKeybinds()
        for _, child in ipairs(keybindList:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        for _, entry in ipairs(keybindEntries) do
            local on = entry.active and entry.active() or false
            make("TextLabel", {
                Text = string.format('<font color="#%s">[%s]</font>  %s',
                    (on and C.Good or C.TextFaint):ToHex(), entry.get(), entry.label),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                RichText = true,
                TextColor3 = C.TextDim,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 14),
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = keybindList,
            })
        end
    end

    -- Some controls (keybind pickers, text boxes) need to swallow global
    -- hotkeys while they are focused.
    UI.Capturing = false
end
