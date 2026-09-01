-- ============================================================================
--  PRELUDE — services, shared namespace, lifecycle helpers
-- ============================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local Stats             = game:GetService("Stats")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local env = (type(getgenv) == "function" and getgenv()) or _G

-- Re-running the script? Tear the previous instance down first, otherwise we
-- stack a second render loop and a duplicate GUI on top of the old one.
if type(env.KittyHubCleanup) == "function" then
    pcall(env.KittyHubCleanup)
end

-- Every module hangs its exports off KH. One table instead of hundreds of
-- file-level locals: the build concatenates every source into a single chunk,
-- and a chunk's main body is capped at 200 active locals.
local KH = {
    Version = "3.0.0",
    Conn    = {}, -- RBXScriptConnections   -> disconnected on unload
    Inst    = {}, -- Instances we created   -> destroyed on unload
    Thread  = {}, -- task threads           -> cancelled on unload
    Undo    = {}, -- restore closures       -> called on unload (hooks, lighting, ...)
    Frame   = {}, -- ordered per-frame jobs
    Alive   = true,
}
env.KittyHub = KH

-- ---------------------------------------------------------------- lifecycle
function KH.track(conn)
    if conn then KH.Conn[#KH.Conn + 1] = conn end
    return conn
end

function KH.own(inst)
    if inst then KH.Inst[#KH.Inst + 1] = inst end
    return inst
end

function KH.undo(fn)
    if fn then KH.Undo[#KH.Undo + 1] = fn end
end

-- Long-running loops: they check KH.Alive so unload actually stops them.
function KH.spawn(fn)
    local thread = task.spawn(function()
        local ok, err = pcall(fn)
        if not ok and KH.Alive then
            warn("[KittyHub] thread error: " .. tostring(err))
        end
    end)
    KH.Thread[#KH.Thread + 1] = thread
    return thread
end

-- Fire-and-forget: short work that needs no cancellation. Deliberately not
-- tracked — the aimbot spawns one per shot and the table would grow forever.
function KH.detach(fn)
    return task.spawn(function()
        local ok, err = pcall(fn)
        if not ok and KH.Alive then
            warn("[KittyHub] task error: " .. tostring(err))
        end
    end)
end

-- A loop that ends itself on unload. `interval` may be 0 for per-heartbeat.
function KH.loop(interval, fn)
    return KH.spawn(function()
        while KH.Alive do
            local ok, err = pcall(fn)
            if not ok then
                warn("[KittyHub] loop error: " .. tostring(err))
                task.wait(1)
            end
            task.wait(interval)
        end
    end)
end

-- ------------------------------------------------------------- error damping
-- A feature that throws every frame would spam the console into uselessness.
-- Report the first few failures per site, then go quiet.
local errSeen = {}
function KH.safe(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local n = (errSeen[name] or 0) + 1
        errSeen[name] = n
        if n <= 3 then
            warn(("[KittyHub] %s failed (%d): %s"):format(name, n, tostring(err)))
        end
        return false
    end
    return true
end

-- ------------------------------------------------------- per-frame scheduler
-- One RenderStepped connection drives everything, so ordering is explicit and
-- unload is a single disconnect.
function KH.onFrame(name, fn, order)
    KH.Frame[#KH.Frame + 1] = {name = name, fn = fn, order = order or 50}
    table.sort(KH.Frame, function(a, b) return a.order < b.order end)
end

-- ------------------------------------------------------------------ executor
-- Feature-detect once; several modules degrade gracefully without these.
local X = {}
X.getgenv       = type(getgenv) == "function"
X.gethui        = type(gethui) == "function"
X.writefile     = type(writefile) == "function" and type(readfile) == "function"
X.listfiles     = type(listfiles) == "function"
X.makefolder    = type(makefolder) == "function" and type(isfolder) == "function"
X.firetouch     = type(firetouchinterest) == "function"
X.hookmetamethod = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
X.rawmeta       = type(getrawmetatable) == "function" and type(setreadonly) == "function"
X.newcclosure   = type(newcclosure) == "function"
X.checkcaller   = type(checkcaller) == "function"
-- Synthetic input. Every executor names these the same way, and an executor
-- that ships none of them cannot drive the mouse aimbot.
X.mousemove     = type(mousemoverel) == "function" or type(mousemoveabs) == "function"
X.mouseclick    = type(mouse1click) == "function"
    or (type(mouse1press) == "function" and type(mouse1release) == "function")
X.setclipboard  = type(setclipboard) == "function"
X.queueteleport = type(queue_on_teleport) == "function" or type(syn) == "table"
X.identifyexec  = type(identifyexecutor) == "function"
X.name = X.identifyexec and select(1, identifyexecutor()) or "Unknown"
KH.X = X

KH.Services = {
    Players = Players, RunService = RunService, UserInputService = UserInputService,
    TweenService = TweenService, Lighting = Lighting, HttpService = HttpService,
    StarterGui = StarterGui, ReplicatedStorage = ReplicatedStorage,
    TeleportService = TeleportService, Stats = Stats, VirtualUser = VirtualUser,
}
KH.LocalPlayer = LocalPlayer
function KH.camera()
    Camera = workspace.CurrentCamera or Camera
    return Camera
end
