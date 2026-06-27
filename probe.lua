-- Kitty Hub — Drawing RENDER test.
-- Tells us which primitives actually DISPLAY (not just create) on this executor.
local items = {}
local function label(t, x, y, color, size)
    local d = Drawing.new("Text")
    d.Text = t
    d.Size = size or 20
    d.Position = Vector2.new(x, y)
    d.Color = color or Color3.new(1, 1, 1)
    d.Font = 3
    d.Center = false
    d.Visible = true
    table.insert(items, d)
    return d
end

label("KITTY HUB DRAW TEST  —  tell me which shapes you can SEE:", 60, 60, Color3.fromRGB(255, 255, 0), 22)

local y = 110

label("1) THIN LINE", 60, y, Color3.new(1, 1, 1))
pcall(function()
    local l = Drawing.new("Line")
    l.From = Vector2.new(280, y + 12); l.To = Vector2.new(520, y + 12)
    l.Thickness = 2; l.Color = Color3.fromRGB(255, 255, 255); l.Visible = true
    table.insert(items, l)
end)

y = y + 50
label("2) THICK LINE (30px)", 60, y, Color3.new(1, 1, 1))
pcall(function()
    local l = Drawing.new("Line")
    l.From = Vector2.new(280, y + 14); l.To = Vector2.new(520, y + 14)
    l.Thickness = 30; l.Color = Color3.fromRGB(120, 200, 255); l.Visible = true
    table.insert(items, l)
end)

y = y + 64
label("3) SQUARE (filled)", 60, y, Color3.new(1, 1, 1))
pcall(function()
    local s = Drawing.new("Square")
    s.Size = Vector2.new(70, 44); s.Position = Vector2.new(280, y - 4)
    s.Filled = true; s.Color = Color3.fromRGB(255, 120, 120); s.Visible = true
    table.insert(items, s)
end)

y = y + 64
label("4) TRIANGLE (filled)", 60, y, Color3.new(1, 1, 1))
pcall(function()
    local t = Drawing.new("Triangle")
    t.PointA = Vector2.new(280, y + 40); t.PointB = Vector2.new(350, y + 40); t.PointC = Vector2.new(315, y - 4)
    t.Filled = true; t.Color = Color3.fromRGB(120, 255, 140); t.Visible = true
    table.insert(items, t)
end)

y = y + 64
label("5) CIRCLE (filled)", 60, y, Color3.new(1, 1, 1))
pcall(function()
    local c = Drawing.new("Circle")
    c.Position = Vector2.new(312, y + 18); c.Radius = 24; c.Filled = true
    c.NumSides = 32; c.Color = Color3.fromRGB(180, 160, 255); c.Visible = true
    table.insert(items, c)
end)

label("(auto-clears in 30s)", 60, y + 60, Color3.fromRGB(160, 160, 160), 16)
task.delay(30, function()
    for _, d in ipairs(items) do pcall(function() d:Remove() end) end
end)
print("Kitty Hub draw test displayed — report which of 1-5 are visible.")
