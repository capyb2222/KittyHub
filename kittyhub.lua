-- Kitty Hub Universal Loader
local host = "http://localhost:8000"

local GAME_MODULES = {
    [142823291] = "mm2"
}

print("Kitty Hub: Detecting game...")

local function LoadModule(name)
    local url = host .. "/" .. name .. ".lua"
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
