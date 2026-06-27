-- Kitty Hub Universal Loader
local host = "http://localhost:8000"

local GAME_MODULES = {
    [142823291] = "mm2"
}

print("Kitty Hub: Detecting game...")

local function LoadModule(name)
    -- Cache-buster: many executors cache game:HttpGet per-URL for the whole
    -- session, so without a unique query string they'd replay a stale download
    -- and never pick up edits. tick()+random makes every fetch a fresh URL.
    local bust = tostring(tick()) .. "_" .. tostring(math.random(100000, 999999))
    local url = host .. "/" .. name .. ".lua?v=" .. bust
    print("Kitty Hub: Loading " .. name .. ".lua...")
    local success, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if not success then
        warn("Kitty Hub: Failed to load " .. name .. ".lua — " .. tostring(result))
    end
end

local moduleName = GAME_MODULES[game.PlaceId]
if moduleName then
    LoadModule(moduleName)
else
    LoadModule("generic")
end
