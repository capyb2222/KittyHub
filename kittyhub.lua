-- ============================================================================
--  Kitty Hub — loader
--
--  Picks the right module for whatever game you are in and runs it. Kept
--  deliberately small: everything it does has to survive a flaky local server,
--  an executor with an aggressive HTTP cache, and being run twice by accident.
-- ============================================================================

local HOSTS = {
    "http://localhost:8000",
    "http://127.0.0.1:8000",
}

local MODULES = {
    [142823291] = "mm2",       -- Murder Mystery 2
    [606849621] = "jailbreak", -- Jailbreak
}
local FALLBACK = "generic"

local env = (type(getgenv) == "function" and getgenv()) or _G

-- ---------------------------------------------------------------- messaging
local function log(message)
    print("[Kitty Hub] " .. message)
end

local function toast(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = text, Duration = 8,
        })
    end)
end

local function fail(message)
    warn("[Kitty Hub] " .. message)
    toast("Kitty Hub failed", message)
end

-- ------------------------------------------------------------------ fetching
-- Many executors cache game:HttpGet per URL for the whole session. Without a
-- unique query string every fetch after the first replays a stale download and
-- your edits never show up.
local function bust()
    return ("?v=%s_%d"):format(tostring(os.clock()), math.random(100000, 999999))
end

local function fetch(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if not ok then return nil, tostring(body) end
    if type(body) ~= "string" or #body == 0 then return nil, "empty response" end
    -- A dev server that 404s usually answers with an HTML error page, which
    -- would otherwise be handed to loadstring and produce a baffling error.
    if body:sub(1, 200):lower():find("<!doctype") or body:sub(1, 200):lower():find("<html") then
        return nil, "server returned HTML (is the file missing?)"
    end
    return body
end

-- --------------------------------------------------------------------- load
local function loadModule(name)
    local errors = {}

    for _, host in ipairs(HOSTS) do
        local url = ("%s/%s.lua%s"):format(host, name, bust())
        local source, err = fetch(url)

        if source then
            local chunk, compileError = loadstring(source, "=" .. name .. ".lua")
            if not chunk then
                fail(("%s.lua failed to compile: %s"):format(name, tostring(compileError)))
                return false
            end

            local ok, runtimeError = pcall(chunk)
            if ok then
                log(("loaded %s.lua from %s (%d bytes)"):format(name, host, #source))
                return true
            end

            fail(("%s.lua errored while running: %s"):format(name, tostring(runtimeError)))
            return false
        end

        errors[#errors + 1] = host .. " — " .. tostring(err)
    end

    fail(("could not fetch %s.lua.\n%s"):format(name, table.concat(errors, "\n")))
    log("Is the dev server running?  python localhost.py")
    return false
end

-- ------------------------------------------------------------------- queue
-- Some executors will not attach to a heavy place. The way in is to attach
-- somewhere they will, run this, and let the queue carry it across the
-- teleport — the executor is already inside the process by then.
local function queueFunction()
    if type(queue_on_teleport) == "function" then return queue_on_teleport end
    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        return syn.queue_on_teleport
    end
    return nil
end

local function quoted(list)
    local parts = {}
    for _, host in ipairs(list) do parts[#parts + 1] = ("%q"):format(host) end
    return table.concat(parts, ", ")
end

-- The queued chunk cannot close over anything here, so it carries its own copy
-- of the host list and re-fetches the loader on the other side.
local function queueAcrossTeleport()
    local queue = queueFunction()
    if not queue then return false end

    local source = ([[
local hosts = {%s}
for _, host in ipairs(hosts) do
    local ok, body = pcall(function()
        return game:HttpGet(host .. "/kittyhub.lua?q=" .. tostring(math.random(100000, 999999)), true)
    end)
    if ok and type(body) == "string" and #body > 0 and not body:lower():find("<html") then
        local chunk = loadstring(body, "=kittyhub.lua")
        if chunk then pcall(chunk) return end
    end
end
]]):format(quoted(HOSTS))

    return (pcall(queue, source))
end
env.KittyHubQueue = queueAcrossTeleport

-- -------------------------------------------------------------------- start
-- Re-running is supported: the module tears its own previous instance down via
-- getgenv().KittyHubCleanup before building a new one.
if type(env.KittyHubCleanup) == "function" then
    log("previous instance detected — it will be unloaded on reload")
end

local moduleName = MODULES[game.PlaceId] or FALLBACK
log(("place %d -> %s.lua"):format(game.PlaceId, moduleName))

if loadModule(moduleName) then
    if queueAcrossTeleport() then
        log("queued for the next teleport — you will not need to attach again")
    else
        log("this executor has no queue_on_teleport; a teleport needs a fresh run")
    end
end
