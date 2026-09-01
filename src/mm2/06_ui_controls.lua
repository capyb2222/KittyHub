-- ============================================================================
--  UI CONTROLS — toggle, slider, dropdown, keybind, button, input, colour
-- ============================================================================

do
    local UI               = KH.UI
    local C                = UI.C
    local make             = UI.make
    local tween            = UI.tween
    local UserInputService = KH.Services.UserInputService
    local Config           = KH.Config

    local ROW_H, ROW_DESC_H = 36, 50

    -- Every control that can redraw itself registers here, so loading a config
    -- profile can repaint the entire menu in one pass.
    UI.Controls = {}
    local function register(control)
        if control and control.refresh then UI.Controls[#UI.Controls + 1] = control end
        return control
    end

    function UI.refreshAll()
        for _, control in ipairs(UI.Controls) do
            KH.safe("refresh", control.refresh)
        end
        for _, readout in ipairs(UI.Readouts or {}) do
            KH.safe("readout", readout.refresh)
        end
        UI.refreshKeybinds()
    end

    -- Every control writes through here so autosave and any dependent UI stay
    -- in step with the settings table.
    local function commit(opts, value)
        if opts.set then KH.safe("control:" .. tostring(opts.text), opts.set, value) end
        Config.touch()
    end

    -- ---------------------------------------------------------------- row
    local function baseRow(section, opts, height)
        local hasDesc = opts.desc ~= nil
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, height or (hasDesc and ROW_DESC_H or ROW_H)),
            BackgroundColor3 = C.Row,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = UI.nextOrder(section),
            Parent = section.body,
        })
        UI.corner(row, 7)

        row.MouseEnter:Connect(function() tween(row, 0.1, {BackgroundTransparency = 0.55}) end)
        row.MouseLeave:Connect(function() tween(row, 0.1, {BackgroundTransparency = 1}) end)

        local label = make("TextLabel", {
            Text = opts.text or "",
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = C.Text,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, hasDesc and 8 or 0),
            Size = UDim2.new(1, -110, 0, hasDesc and 15 or height or ROW_H),
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })

        if hasDesc then
            make("TextLabel", {
                Text = opts.desc,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextColor3 = C.TextFaint,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 25),
                Size = UDim2.new(1, -110, 0, 14),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
        end

        UI.registerSearch(section, row, (opts.text or "") .. " " .. (opts.desc or ""))
        return row, label
    end

    -- =============================================================== TOGGLE
    function UI.toggle(section, opts)
        local row = baseRow(section, opts)

        local track = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(40, 21),
            BackgroundColor3 = C.Off,
            BorderSizePixel = 0,
            Parent = row,
        })
        UI.corner(track, 11)
        local fill = make("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = C.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = track,
        })
        UI.corner(fill, 11)
        UI.accented(fill, "BackgroundColor3")

        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.fromOffset(15, 15),
            BackgroundColor3 = Color3.fromRGB(235, 235, 242),
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = track,
        })
        UI.corner(knob, 8)

        local control = {}
        function control.refresh(animate)
            local on = opts.get and opts.get() or false
            local pos = on and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
            local transparency = on and 0 or 1
            if animate then
                tween(knob, 0.15, {Position = pos}, Enum.EasingStyle.Back)
                tween(fill, 0.15, {BackgroundTransparency = transparency})
            else
                knob.Position = pos
                fill.BackgroundTransparency = transparency
            end
        end
        control.refresh(false)

        local hit = make("TextButton", {
            Text = "", BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), Parent = row,
        })
        hit.MouseButton1Click:Connect(function()
            local value = not (opts.get and opts.get())
            commit(opts, value)
            control.refresh(true)
            UI.refreshKeybinds()
        end)

        control.row = row
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- =============================================================== SLIDER
    function UI.slider(section, opts)
        local height = opts.desc and 60 or 48
        local row = baseRow(section, opts, height)
        local minV, maxV = opts.min or 0, opts.max or 100
        local step = opts.step or 1
        local decimals = (step < 1) and 2 or 0

        local value = make("TextLabel", {
            Text = "0",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = C.Accent,
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 8),
            Size = UDim2.fromOffset(70, 15),
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        })
        UI.accented(value, "TextColor3", {v = 1.3, s = 0.6})

        local track = make("Frame", {
            Position = UDim2.new(0, 12, 0, height - 16),
            Size = UDim2.new(1, -24, 0, 5),
            BackgroundColor3 = C.Off,
            BorderSizePixel = 0,
            Parent = row,
        })
        UI.corner(track, 3)
        local fill = make("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = C.Accent,
            BorderSizePixel = 0,
            Parent = track,
        })
        UI.corner(fill, 3)
        UI.accented(UI.gradient(fill, C.Accent, C.Accent, 0), "Gradient")

        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(1, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = Color3.fromRGB(245, 245, 250),
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = fill,
        })
        UI.corner(knob, 6)

        local function format(n)
            local text = (decimals > 0) and string.format("%." .. decimals .. "f", n) or tostring(math.floor(n))
            return text .. (opts.suffix or "")
        end

        local control = {}
        local function paint(n)
            local scale = (maxV > minV) and ((n - minV) / (maxV - minV)) or 0
            fill.Size = UDim2.fromScale(math.clamp(scale, 0, 1), 1)
            value.Text = format(n)
        end

        function control.refresh()
            paint(opts.get and opts.get() or minV)
        end
        control.refresh()

        local function setFromX(x)
            local scale = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
            local raw = minV + (maxV - minV) * scale
            local snapped = math.clamp(math.floor(raw / step + 0.5) * step, minV, maxV)
            paint(snapped)
            commit(opts, snapped)
        end

        -- The hit area is taller than the 5px track so the slider is actually
        -- grabbable, and covers the row's lower half.
        local hit = make("TextButton", {
            Text = "", BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, height - 26),
            Size = UDim2.new(1, 0, 0, 26),
            Parent = row,
        })

        local dragging = false
        hit.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                tween(knob, 0.1, {Size = UDim2.fromOffset(15, 15)})
                setFromX(input.Position.X)
            end
        end)
        KH.track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                setFromX(input.Position.X)
            end
        end))
        KH.track(UserInputService.InputEnded:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                tween(knob, 0.1, {Size = UDim2.fromOffset(12, 12)})
            end
        end))

        control.row = row
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- ============================================================= DROPDOWN
    -- Expands inline instead of floating a popup: the page auto-sizes, so
    -- pushing rows down avoids every z-order problem a popup would bring.
    function UI.dropdown(section, opts)
        local row = baseRow(section, opts)
        local options = opts.options or {}

        local button = make("TextButton", {
            Text = "",
            AutoButtonColor = false,
            BackgroundColor3 = C.Card,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(112, 26),
            Parent = row,
        })
        UI.corner(button, 6)
        UI.stroke(button, C.Stroke, 1, 0.3)

        local current = make("TextLabel", {
            Text = "—",
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = C.Text,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(9, 0),
            Size = UDim2.new(1, -26, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = button,
        })
        local chevron = make("TextLabel", {
            Text = "▾",
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0),
            Size = UDim2.fromOffset(12, 26),
            Parent = button,
        })

        -- The expanded list is a sibling row inside the same section body, so
        -- the list layout handles all the spacing for us.
        local panel = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = C.Bg,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = false,
            LayoutOrder = UI.nextOrder(section),
            Parent = section.body,
        })
        UI.corner(panel, 7)
        UI.stroke(panel, C.Stroke, 1, 0.4)
        local panelList = make("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Parent = panel,
        })
        UI.list(panelList, 2)
        UI.pad(panelList, 5)

        local expanded = false
        local entryHeight = 26

        local control = {}

        function control.refresh()
            current.Text = tostring(opts.get and opts.get() or "—")
            for _, child in ipairs(panelList:GetChildren()) do
                if child:IsA("TextButton") then
                    local selected = child.Name == current.Text
                    child.BackgroundTransparency = selected and 0.85 or 1
                    child.TextColor3 = selected and C.Text or C.TextDim
                end
            end
        end

        local function setExpanded(open)
            expanded = open
            local target = open and (#options * (entryHeight + 2) + 10) or 0
            panel.Visible = true
            tween(chevron, 0.15, {Rotation = open and 180 or 0})
            tween(panel, 0.16, {Size = UDim2.new(1, 0, 0, target)})
            if not open then
                task.delay(0.17, function()
                    if not expanded then panel.Visible = false end
                end)
            end
        end

        local function buildEntry(option)
            local entry = make("TextButton", {
                Name = tostring(option),
                Text = tostring(option),
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = C.TextDim,
                BackgroundColor3 = C.Accent,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, entryHeight),
                Parent = panelList,
            })
            UI.corner(entry, 5)
            UI.accented(entry, "BackgroundColor3")
            entry.MouseButton1Click:Connect(function()
                commit(opts, option)
                control.refresh()
                setExpanded(false)
            end)
        end

        for _, option in ipairs(options) do buildEntry(option) end

        -- Lists that are discovered at runtime (saved waypoints, config
        -- profiles) rebuild themselves through this.
        function control.setOptions(newOptions)
            options = newOptions or {}
            for _, child in ipairs(panelList:GetChildren()) do
                if child:IsA("TextButton") then child:Destroy() end
            end
            for _, option in ipairs(options) do buildEntry(option) end
            if expanded then
                panel.Size = UDim2.new(1, 0, 0, #options * (entryHeight + 2) + 10)
            end
            control.refresh()
        end

        button.MouseButton1Click:Connect(function() setExpanded(not expanded) end)
        control.refresh()

        UI.registerSearch(section, panel, (opts.text or ""))

        control.row = row
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- ============================================================== KEYBIND
    function UI.keybind(section, opts)
        local row = baseRow(section, opts)

        local button = make("TextButton", {
            Text = "—",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = C.Text,
            BackgroundColor3 = C.Card,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(78, 26),
            Parent = row,
        })
        UI.corner(button, 6)
        UI.stroke(button, C.Stroke, 1, 0.3)

        local control = {}
        function control.refresh()
            button.Text = tostring(opts.get and opts.get() or "None")
            button.TextColor3 = C.Text
        end
        control.refresh()

        local listening = false
        button.MouseButton1Click:Connect(function()
            listening = true
            UI.Capturing = true
            button.Text = "press…"
            button.TextColor3 = C.Accent
        end)

        KH.track(UserInputService.InputBegan:Connect(function(input)
            if not listening then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            listening = false
            UI.Capturing = false
            -- Escape clears the binding rather than binding Escape itself.
            if input.KeyCode == Enum.KeyCode.Escape then
                commit(opts, "None")
            else
                commit(opts, input.KeyCode.Name)
            end
            control.refresh()
            UI.refreshKeybinds()
        end))

        control.row = row
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- =============================================================== BUTTON
    function UI.button(section, opts)
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, opts.desc and 46 or 32),
            BackgroundTransparency = 1,
            LayoutOrder = UI.nextOrder(section),
            Parent = section.body,
        })

        local button = make("TextButton", {
            Text = opts.text or "Button",
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = opts.kind == "danger" and C.Bad or C.Text,
            BackgroundColor3 = opts.kind == "primary" and C.Accent or C.Row,
            BackgroundTransparency = opts.kind == "primary" and 0 or 0.35,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            Parent = row,
        })
        UI.corner(button, 7)
        if opts.kind == "primary" then UI.accented(button, "BackgroundColor3") end
        UI.stroke(button, opts.kind == "danger" and C.Bad or C.Stroke, 1, 0.45)

        if opts.desc then
            make("TextLabel", {
                Text = opts.desc,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextColor3 = C.TextFaint,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(2, 31),
                Size = UDim2.new(1, -4, 0, 14),
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
        end

        local baseTransparency = button.BackgroundTransparency
        button.MouseEnter:Connect(function()
            tween(button, 0.1, {BackgroundTransparency = math.max(baseTransparency - 0.25, 0)})
        end)
        button.MouseLeave:Connect(function()
            tween(button, 0.1, {BackgroundTransparency = baseTransparency})
        end)
        button.MouseButton1Click:Connect(function()
            -- A click that opens a teleport or a server hop can yield; never
            -- let it block the input thread.
            KH.detach(function()
                if opts.callback then opts.callback() end
            end)
        end)

        UI.registerSearch(section, row, (opts.text or "") .. " " .. (opts.desc or ""))
        return {row = row, button = button}
    end

    -- ================================================================ INPUT
    function UI.input(section, opts)
        local row = baseRow(section, opts)

        local box = make("TextBox", {
            Text = tostring(opts.get and opts.get() or ""),
            PlaceholderText = opts.placeholder or "",
            PlaceholderColor3 = C.TextFaint,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = C.Text,
            BackgroundColor3 = C.Card,
            ClearTextOnFocus = false,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(opts.width or 130, 26),
            Parent = row,
        })
        UI.corner(box, 6)
        UI.stroke(box, C.Stroke, 1, 0.3)
        UI.pad(box, 0, 0, 0, 8, 8)

        -- Hotkeys must not fire while the user is typing into the field.
        box.Focused:Connect(function() UI.Capturing = true end)
        box.FocusLost:Connect(function(enter)
            UI.Capturing = false
            if enter or opts.commitOnBlur ~= false then
                commit(opts, box.Text)
                if opts.clearOnSubmit then box.Text = "" end
            end
        end)

        local control = {box = box, row = row}
        function control.refresh()
            if opts.get then box.Text = tostring(opts.get()) end
        end
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- ========================================================= COLOUR PICKER
    -- Three gradient strips rather than a 2D swatch image, so it needs no
    -- uploaded assets and renders identically on every executor.
    function UI.colorpicker(section, opts)
        local row = baseRow(section, opts)

        local swatch = make("TextButton", {
            Text = "",
            AutoButtonColor = false,
            BackgroundColor3 = opts.get and opts.get() or C.Accent,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(42, 22),
            Parent = row,
        })
        UI.corner(swatch, 6)
        UI.stroke(swatch, C.Stroke, 1, 0.2)

        local panel = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundColor3 = C.Bg,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = false,
            LayoutOrder = UI.nextOrder(section),
            Parent = section.body,
        })
        UI.corner(panel, 7)
        UI.stroke(panel, C.Stroke, 1, 0.4)

        local h, s, v = (opts.get and opts.get() or C.Accent):ToHSV()

        local function currentColor() return Color3.fromHSV(h, s, v) end

        local strips = {}
        local function strip(name, y, buildGradient)
            local holder = make("Frame", {
                Position = UDim2.fromOffset(10, y),
                Size = UDim2.new(1, -20, 0, 14),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Parent = panel,
            })
            UI.corner(holder, 4)
            local gradient = make("UIGradient", {Parent = holder})
            buildGradient(gradient)

            local marker = make("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(4, 20),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                ZIndex = 3,
                Parent = holder,
            })
            UI.corner(marker, 2)
            UI.stroke(marker, Color3.new(0, 0, 0), 1, 0.5)

            strips[name] = {holder = holder, gradient = gradient, marker = marker}
            return strips[name]
        end

        strip("hue", 10, function(gradient)
            local keys = {}
            for i = 0, 6 do
                keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))
            end
            gradient.Color = ColorSequence.new(keys)
        end)
        strip("sat", 32, function(gradient)
            gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(h, 1, 1))
        end)
        strip("val", 54, function(gradient)
            gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
        end)

        local preview = make("Frame", {
            Position = UDim2.fromOffset(10, 76),
            Size = UDim2.new(1, -20, 0, 18),
            BackgroundColor3 = currentColor(),
            BorderSizePixel = 0,
            Parent = panel,
        })
        UI.corner(preview, 4)

        local function repaint(pushValue)
            local color = currentColor()
            swatch.BackgroundColor3 = color
            preview.BackgroundColor3 = color
            strips.sat.gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(h, 1, 1))
            strips.val.gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
            strips.hue.marker.Position = UDim2.fromScale(h, 0.5)
            strips.sat.marker.Position = UDim2.fromScale(s, 0.5)
            strips.val.marker.Position = UDim2.fromScale(v, 0.5)
            if pushValue then commit(opts, color) end
        end
        repaint(false)

        local dragTarget = nil
        local function stripScale(entry, x)
            return math.clamp((x - entry.holder.AbsolutePosition.X)
                / math.max(entry.holder.AbsoluteSize.X, 1), 0, 1)
        end

        for name, entry in pairs(strips) do
            entry.holder.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragTarget = name
                    local scale = stripScale(entry, input.Position.X)
                    if name == "hue" then h = scale elseif name == "sat" then s = scale else v = scale end
                    repaint(true)
                end
            end)
        end
        KH.track(UserInputService.InputChanged:Connect(function(input)
            if not dragTarget then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local entry = strips[dragTarget]
            local scale = stripScale(entry, input.Position.X)
            if dragTarget == "hue" then h = scale elseif dragTarget == "sat" then s = scale else v = scale end
            repaint(true)
        end))
        KH.track(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragTarget = nil
            end
        end))

        local expanded = false
        swatch.MouseButton1Click:Connect(function()
            expanded = not expanded
            panel.Visible = true
            tween(panel, 0.16, {Size = UDim2.new(1, 0, 0, expanded and 104 or 0)})
            if not expanded then
                task.delay(0.17, function()
                    if not expanded then panel.Visible = false end
                end)
            end
        end)

        UI.registerSearch(section, panel, opts.text or "")

        local control = {row = row}
        function control.refresh()
            local color = opts.get and opts.get() or C.Accent
            h, s, v = color:ToHSV()
            repaint(false)
        end
        if opts.flag then UI[opts.flag] = control end
        return register(control)
    end

    -- ================================================================ LABEL
    function UI.label(section, text)
        local label = make("TextLabel", {
            Text = text,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextColor3 = C.TextFaint,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -8, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = UI.nextOrder(section),
            Parent = section.body,
        })
        UI.registerSearch(section, label, text)
        return label
    end

    -- ============================================================ READOUT
    -- A live value display: same shape as a row, but the right-hand side is
    -- driven by a getter polled from the main loop.
    function UI.readout(section, opts)
        local row = baseRow(section, opts)
        local value = make("TextLabel", {
            Text = "—",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            RichText = true,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(180, 20),
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        })
        local control = {row = row, label = value}
        function control.refresh()
            if opts.get then
                local ok, text = pcall(opts.get)
                value.Text = ok and tostring(text) or "—"
            end
        end
        control.refresh()
        UI.Readouts = UI.Readouts or {}
        table.insert(UI.Readouts, control)
        return control
    end
end
