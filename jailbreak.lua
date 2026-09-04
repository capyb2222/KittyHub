-- ============================================================================
--
--   ██╗  ██╗██╗████████╗████████╗██╗   ██╗    ██╗  ██╗██╗   ██╗██████╗
--   ██║ ██╔╝██║╚══██╔══╝╚══██╔══╝╚██╗ ██╔╝    ██║  ██║██║   ██║██╔══██╗
--   █████╔╝ ██║   ██║      ██║    ╚████╔╝     ███████║██║   ██║██████╔╝
--   ██╔═██╗ ██║   ██║      ██║     ╚██╔╝      ██╔══██║██║   ██║██╔══██╗
--   ██║  ██╗██║   ██║      ██║      ██║       ██║  ██║╚██████╔╝██████╔╝
--   ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝      ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
--
--   Jailbreak Script
--   build 3.1.0+1230a5b6  ·  2026-09-04 01:19 UTC
--
--   GENERATED FILE — do not edit directly.
--   Sources live in src/jailbreak/ ; rebuild with `python build.py`.
--
-- ============================================================================

-- ─── src/_shared/00_prelude.lua ────────────────────────────────────

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
    Version = "3.1.0",
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
X.queueteleport = type(queue_on_teleport) == "function"
    or (type(syn) == "table" and type(syn.queue_on_teleport) == "function")
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

-- ─── src/jailbreak/10_defaults.lua ─────────────────────────────────

-- ============================================================================
--  DEFAULTS — the Jailbreak settings schema
-- ============================================================================

KH.GameTag  = "JB"
KH.GameName = "Jailbreak"

do
    -- Defaults double as the schema: a saved profile is backfilled from here
    -- and keys that no longer exist are dropped, so upgrades never half-migrate.
    local DEFAULTS = {
        Rob = {
            Auto          = false,
            Pick          = "Best Payout",   -- Best Payout | Nearest | In Order
            Only          = "Any",           -- Any | Quick | Big
            Instant       = true,            -- zero the hold timer on interactions
            AutoInteract  = true,            -- fire loot prompts we are standing in
            InteractRange = 45,
            Loot          = true,            -- hop between loot parts inside
            LootRadius    = 220,             -- how far from the entry to look
            Dwell         = 70,              -- seconds before giving up on one job
            Deposit       = true,            -- run the bag to a base when it is full
            Restock       = true,            -- wait for the next robbery to open
            Wait          = 3,               -- seconds between jobs
            Notify        = true,
        },
        Travel = {
            Mode          = "Glide",         -- Glide | Instant
            Speed         = 140,             -- studs per second while gliding
            Height        = 320,             -- cruise altitude
            Timeout       = 30,
        },
        Police = {
            AutoEquip     = true,
            CuffSlot      = 1,               -- hotbar key the handcuffs sit on
            ArrestMode    = "Instant",       -- Instant | Glide
            Dwell         = 0.6,             -- seconds spent on each target
            Spacing       = 0.05,
            Offset        = 2.5,             -- studs to stand off the target
            ReturnAfter   = true,
            SkipVehicles  = false,
            Aura          = false,
            AuraRange     = 16,
            AutoArrest    = false,           -- keep sweeping the server
            ArrestKey     = "H",
        },
        Farm = {
            Items         = false,           -- collect dropped pickups
            ItemRadius    = 300,
            InteractAura  = false,           -- fire any prompt in range
            AuraRange     = 24,
            AntiAFK       = true,
        },
        ESP = {
            Enabled       = false,
            Highlight     = true,
            Names         = true,
            Distance      = true,
            Team          = true,            -- colour by team
            OnlyEnemies   = false,
            MaxDistance   = 2500,
            Robberies     = true,            -- markers on open robberies
            ColorCriminal = Color3.fromRGB(255, 96, 96),
            ColorPolice   = Color3.fromRGB(96, 160, 255),
            ColorPrisoner = Color3.fromRGB(255, 190, 80),
        },
        Move = {
            SpeedEnabled  = false,
            Speed         = 32,
            SpeedMode     = "Humanoid",      -- Humanoid | CFrame
            JumpEnabled   = false,
            Jump          = 70,
            InfJump       = false,
            Bhop          = false,
            Noclip        = false,
            NoclipKey     = "N",
            Fly           = false,
            FlyKey        = "F",
            FlySpeed      = 90,
            Spinbot       = false,
        },
        Visual = {
            Fullbright    = false,
            Brightness    = 2,
            NoFog         = false,
            FovEnabled    = false,
            Fov           = 90,
            Xray          = false,           -- no control for it: the map is huge
            XrayTransp    = 0.72,
            LowDetail     = false,
        },
        UI = {
            MenuKey       = "X",
            Accent        = Color3.fromRGB(118, 190, 255),
            Watermark     = true,
            KeybindList   = true,
            Notifications = true,
            AutoSave      = true,
            Profile       = "default",
        },
    }
    KH.Defaults = DEFAULTS
end

-- ─── src/_shared/20_config.lua ─────────────────────────────────────

-- ============================================================================
--  CONFIG — deep-merge over the game's defaults, and on-disk profiles
-- ============================================================================

local S -- the settings table every other module reads

do
    local HttpService = KH.Services.HttpService
    local X = KH.X
    local DEFAULTS = KH.Defaults

    -- ------------------------------------------------------------ deep merge
    local function deepCopy(t)
        local out = {}
        for k, v in pairs(t) do
            out[k] = (typeof(v) == "table") and deepCopy(v) or v
        end
        return out
    end

    -- Fill gaps, drop strays, reject values whose type no longer matches — a
    -- toggle that became a slider would crash the control reading it.
    local function reconcile(dst, schema)
        for k, v in pairs(schema) do
            if typeof(v) == "table" then
                if typeof(dst[k]) ~= "table" then dst[k] = {} end
                reconcile(dst[k], v)
            elseif dst[k] == nil or typeof(dst[k]) ~= typeof(v) then
                dst[k] = v
            end
        end
        for k in pairs(dst) do
            if schema[k] == nil then dst[k] = nil end
        end
    end

    S = deepCopy(DEFAULTS)
    KH.S = S

    -- ------------------------------------------------------- (de)serialising
    -- Color3 has no JSON form, so it round-trips through a tagged table.
    local function encode(v)
        if typeof(v) == "Color3" then
            return {__c3 = {
                math.floor(v.R * 255 + 0.5),
                math.floor(v.G * 255 + 0.5),
                math.floor(v.B * 255 + 0.5),
            }}
        elseif typeof(v) == "table" then
            local out = {}
            for k, sub in pairs(v) do out[k] = encode(sub) end
            return out
        end
        return v
    end

    local function decode(v)
        if typeof(v) == "table" then
            if typeof(v.__c3) == "table" then
                return Color3.fromRGB(v.__c3[1] or 0, v.__c3[2] or 0, v.__c3[3] or 0)
            end
            local out = {}
            for k, sub in pairs(v) do out[k] = decode(sub) end
            return out
        end
        return v
    end

    -- ------------------------------------------------------------ disk layer
    local ROOT, DIR = "KittyHub", "KittyHub/configs"

    local Config = {}
    KH.Config = Config

    local function ensureDir()
        if not (X.writefile and X.makefolder) then return false end
        local ok = pcall(function()
            if not isfolder(ROOT) then makefolder(ROOT) end
            if not isfolder(DIR) then makefolder(DIR) end
        end)
        return ok
    end
    Config.available = ensureDir()

    local function pathFor(name)
        local safeName = tostring(name):gsub("[^%w_%-]", "_")
        return DIR .. "/" .. safeName .. ".json"
    end

    function Config.list()
        local names = {}
        if not (Config.available and X.listfiles) then return names end
        pcall(function()
            for _, file in ipairs(listfiles(DIR)) do
                local name = tostring(file):match("([^/\\]+)%.json$")
                if name then names[#names + 1] = name end
            end
        end)
        table.sort(names)
        return names
    end

    function Config.save(name)
        if not Config.available then return false, "executor has no file API" end
        name = name or S.UI.Profile
        local ok, err = pcall(function()
            writefile(pathFor(name), HttpService:JSONEncode(encode(S)))
        end)
        return ok, err
    end

    function Config.load(name)
        if not Config.available then return false, "executor has no file API" end
        name = name or S.UI.Profile
        local path = pathFor(name)
        local ok, data = pcall(function()
            if not isfile(path) then return nil end
            return HttpService:JSONDecode(readfile(path))
        end)
        if not ok or typeof(data) ~= "table" then return false, "no such profile" end

        local loaded = decode(data)
        reconcile(loaded, DEFAULTS)
        -- In place: every control captured a reference to its own sub-table,
        -- so swapping S wholesale would orphan the lot.
        for group, values in pairs(loaded) do
            if typeof(S[group]) == "table" and typeof(values) == "table" then
                for k, v in pairs(values) do S[group][k] = v end
            end
        end
        S.UI.Profile = name
        return true
    end

    function Config.delete(name)
        if not Config.available then return false end
        return pcall(function() delfile(pathFor(name)) end)
    end

    function Config.reset()
        local fresh = deepCopy(DEFAULTS)
        for group, values in pairs(fresh) do
            for k, v in pairs(values) do S[group][k] = v end
        end
    end

    -- Autosave is debounced: sliders fire their callback on every mouse-move,
    -- and writing a file per frame is a good way to stutter the game.
    local pending = false
    function Config.touch()
        if not (S.UI.AutoSave and Config.available) or pending then return end
        pending = true
        KH.detach(function()
            task.wait(1.5)
            pending = false
            Config.save(S.UI.Profile)
        end)
    end
end

-- ─── src/_shared/30_util.lua ───────────────────────────────────────

-- ============================================================================
--  UTIL — small helpers shared by every feature module
-- ============================================================================

local U = {}
KH.U = U

do
    local Players = KH.Services.Players
    local Stats   = KH.Services.Stats
    local LocalPlayer = KH.LocalPlayer

    -- ------------------------------------------------------------------ math
    function U.round(n, places)
        local m = 10 ^ (places or 0)
        return math.floor(n * m + 0.5) / m
    end

    function U.lerp(a, b, t) return a + (b - a) * t end

    function U.clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

    -- ------------------------------------------------------------ characters
    function U.charOf(player)
        local char = player and player.Character
        -- A character that has left the DataModel (respawn in flight) still
        -- reads as a valid Instance, so check it is actually parented.
        if char and char.Parent then return char end
        return nil
    end

    function U.rootOf(player)
        local char = U.charOf(player)
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    function U.humOf(player)
        local char = U.charOf(player)
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    function U.isAliveChar(player)
        local hum = U.humOf(player)
        return hum ~= nil and hum.Health > 0
    end

    function U.myRoot() return U.rootOf(LocalPlayer) end
    function U.myHum()  return U.humOf(LocalPlayer) end

    -- R15 names the torso differently from R6. Aim and prediction both want
    -- the mass centre rather than the head.
    function U.torsoOf(char)
        return char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
    end

    function U.distanceTo(position)
        local root = U.myRoot()
        if not root then return math.huge end
        return (root.Position - position).Magnitude
    end

    -- --------------------------------------------------------------- network
    function U.ping()
        local ok, ms = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and typeof(ms) == "number" then return ms end
        return 0
    end

    -- ---------------------------------------------------------------- screen
    -- Screen position, on-screen flag, depth. Depth goes negative behind the
    -- camera, which is what flips off-screen arrows to the right side.
    function U.toScreen(worldPos)
        local cam = KH.camera()
        local v, onScreen = cam:WorldToViewportPoint(worldPos)
        return Vector2.new(v.X, v.Y), onScreen, v.Z
    end

    -- ------------------------------------------------------------ prediction
    -- The server checks the position against where the target is when the
    -- packet lands, so the lead covers their motion and our round trip.
    function U.predict(char, strength, usePing, partOverride)
        local part = partOverride or U.torsoOf(char)
        if not part then return nil end

        local pos = part.Position
        if strength <= 0 then return pos end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local velocity = part.AssemblyLinearVelocity or Vector3.zero
        local moveDir = hum and hum.MoveDirection or Vector3.zero

        -- Y is damped hard: a jumping target's vertical velocity swings far
        -- more than its hitbox does, and over-leading up is the usual miss.
        local flattened = Vector3.new(velocity.X * 0.75, velocity.Y * 0.35, velocity.Z * 0.75)
        local lead = flattened * (strength / 15) + moveDir * strength

        if usePing then
            local pingSec = U.clamp(U.ping() / 1000, 0, 0.5)
            lead = lead + velocity * pingSec
        end
        return pos + lead
    end

    -- ------------------------------------------------------------- teleport
    -- Preserves look direction so a farm teleport does not spin the camera.
    function U.moveTo(position, keepLook)
        local root = U.myRoot()
        if not root then return false end
        if keepLook then
            root.CFrame = CFrame.new(position, position + root.CFrame.LookVector)
        else
            root.CFrame = CFrame.new(position)
        end
        return true
    end

    -- ----------------------------------------------------------------- sound
    -- Asset id or full URI. `rbxasset://sounds/...` ships with the client, so
    -- it always resolves — worth preferring for alerts that must be audible.
    local soundCache = {}
    function U.playSound(assetId, volume)
        local sound = soundCache[assetId]
        if not sound or not sound.Parent then
            sound = Instance.new("Sound")
            sound.SoundId = tostring(assetId):match("^rbx")
                and tostring(assetId)
                or ("rbxassetid://" .. tostring(assetId))
            sound.Parent = KH.camera()
            soundCache[assetId] = sound
            KH.own(sound)
        end
        sound.Volume = volume or 0.5
        pcall(function() sound:Play() end)
    end

    -- ------------------------------------------------------------- keycodes
    function U.keyCode(name)
        if typeof(name) ~= "string" then return nil end
        local ok, key = pcall(function() return Enum.KeyCode[name] end)
        return ok and key or nil
    end

    -- Roblox's chat box and our own text fields are both TextBoxes. A key
    -- held while one of them has focus belongs to whoever is typing, not to a
    -- feature: without this, saying "we" in chat flies you across the map.
    function U.typing()
        local ok, box = pcall(function()
            return KH.Services.UserInputService:GetFocusedTextBox()
        end)
        return ok and box ~= nil
    end

    function U.keyHeld(name)
        if U.typing() then return false end
        local key = U.keyCode(name)
        if not key then return false end
        return KH.Services.UserInputService:IsKeyDown(key)
    end

    -- ------------------------------------------------------------- iteration
    function U.otherPlayers()
        local out = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then out[#out + 1] = player end
        end
        return out
    end
end

-- ─── src/jailbreak/35_game.lua ─────────────────────────────────────

-- ============================================================================
--  GAME — everything this script knows about Jailbreak itself
--
--  Jailbreak names its networking after a build hash, so nothing here goes near
--  a remote. What it does use are the client modules the game leaves in
--  ReplicatedStorage, the RobberyState values it replicates, and the parts in
--  workspace. All of it is optional: a lookup that fails leaves the feature
--  built on it inert rather than throwing.
-- ============================================================================

local Game = {}
KH.Game = Game

do
    local Players           = KH.Services.Players
    local ReplicatedStorage = KH.Services.ReplicatedStorage
    local LocalPlayer       = KH.LocalPlayer
    local U                 = KH.U
    local CollectionService = game:GetService("CollectionService")

    -- Status codes as replicated in RobberyState. Confirmed against the game's
    -- own constants once they resolve, in case the enum is ever reordered.
    Game.Status = {Opened = 1, Started = 2, Closed = 3}

    -- ------------------------------------------------------------- modules
    -- Resolved once in the background: require() can yield, and no per-frame
    -- job may. Everything else reads the cache and copes with a nil.
    local PATHS = {
        UI         = {{"Module", "UI"}},
        Consts     = {{"Game", "Robbery", "RobberyConsts"}, {"Robbery", "RobberyConsts"}},
        ItemSystem = {{"Game", "ItemSystem", "ItemSystem"}},
    }

    local M = {}
    Game.M = M

    local function descend(root, path)
        local node = root
        for _, name in ipairs(path) do
            node = node:FindFirstChild(name)
            if not node then return nil end
        end
        return node
    end

    local function resolve(name)
        for _, path in ipairs(PATHS[name]) do
            local script = descend(ReplicatedStorage, path)
            if script and script:IsA("ModuleScript") then
                local ok, value = pcall(require, script)
                if ok and value ~= nil then return value end
            end
        end
        return nil
    end

    -- Retried a few times: on a slow join ReplicatedStorage is still filling in.
    KH.spawn(function()
        for attempt = 1, 12 do
            local missing = false
            for name in pairs(PATHS) do
                if M[name] == nil then
                    M[name] = resolve(name)
                    if M[name] == nil then missing = true end
                end
            end
            if not missing then break end
            task.wait(attempt < 4 and 1 or 3)
        end

        local consts = M.Consts
        local map = consts and consts.ENUM_STATUS and consts.ENUM_STATUS._map
        if typeof(map) == "table" then
            Game.Status.Opened  = tonumber(map.OPENED)  or Game.Status.Opened
            Game.Status.Started = tonumber(map.STARTED) or Game.Status.Started
            Game.Status.Closed  = tonumber(map.CLOSED)  or Game.Status.Closed
        end
        Game.Resolved = true
    end)

    function Game.circleAction()
        local ui = M.UI
        return ui and ui.CircleAction or nil
    end

    -- ------------------------------------------------------------- helpers
    function Game.pivotOf(inst)
        if typeof(inst) ~= "Instance" then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            local ok, pivot = pcall(function() return inst:GetPivot().Position end)
            if ok then return pivot end
        end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function firstTagged(tag)
        local ok, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
        if not ok then return nil end
        for _, inst in ipairs(tagged) do
            if inst:IsDescendantOf(workspace) then return inst end
        end
        return nil
    end
    Game.firstTagged = firstTagged

    -- Banks / Jewelrys / Trains are folders holding the live model or models,
    -- so a folder resolves to the nth child rather than to itself.
    local function fromWorkspace(name, index)
        local node = workspace:FindFirstChild(name)
        if not node then return nil end
        index = index or 1
        if node:IsA("BasePart") or node:IsA("Model") then
            if index == 1 then return node end
            return nil
        end
        return node:GetChildren()[index]
    end

    -- ------------------------------------------------------------ robberies
    -- id matches RobberyConsts.ENUM_ROBBERY; entry is an outdoor approach the
    -- travel engine can always reach, and locate finds the live model when the
    -- robbery is one that moves (trains, planes, the truck).
    local ROBBERIES = {
        {id = 1,  key = "BANK",            name = "Rising City Bank", payout = 5000,  quick = false,
         entry = Vector3.new(-12, 20, 782),    locate = function() return fromWorkspace("Banks") end},
        {id = 2,  key = "BANK2",           name = "Crater Bank",      payout = 5000,  quick = false,
         locate = function() return fromWorkspace("Banks", 2) end},
        {id = 3,  key = "JEWELRY",         name = "Jewelry Store",    payout = 3500,  quick = false,
         entry = Vector3.new(126, 20, 1368),   locate = function() return fromWorkspace("Jewelrys") end},
        {id = 4,  key = "MUSEUM",          name = "Museum",           payout = 6000,  quick = false,
         entry = Vector3.new(1142, 104, 1247), locate = function() return fromWorkspace("Museum") end},
        {id = 5,  key = "POWER_PLANT",     name = "Power Plant",      payout = 7000,  quick = false,
         entry = Vector3.new(636, 39, 2357)},
        {id = 6,  key = "TRAIN_PASSENGER", name = "Passenger Train",  payout = 4000,  quick = false,
         locate = function() return fromWorkspace("Trains") end},
        {id = 7,  key = "TRAIN_CARGO",     name = "Cargo Train",      payout = 5000,  quick = false,
         locate = function() return fromWorkspace("Trains") end},
        {id = 8,  key = "CARGO_SHIP",      name = "Cargo Ship",       payout = 6000,  quick = false,
         locate = function() return fromWorkspace("Ships") or firstTagged("CargoShip") end},
        {id = 9,  key = "CARGO_PLANE",     name = "Cargo Plane",      payout = 6000,  quick = false,
         locate = function() return fromWorkspace("Plane") end},
        {id = 10, key = "STORE_GAS",       name = "Gas Station",      payout = 1200,  quick = true,
         entry = Vector3.new(-1526, 19, 699)},
        {id = 11, key = "STORE_DONUT",     name = "Donut Store",      payout = 1200,  quick = true,
         entry = Vector3.new(90, 20, -1511)},
        {id = 12, key = "MONEY_TRUCK",     name = "Money Truck",      payout = 11000, quick = false,
         locate = function() return firstTagged("MoneyTruck") end},
        {id = 13, key = "HOME_VAULT",      name = "Home Vault",       payout = 2000,  quick = true,
         skip = true},
        {id = 14, key = "TOMB",            name = "Tomb",             payout = 8000,  quick = false,
         entry = Vector3.new(465, 21, -464),   locate = function() return firstTagged("TombGem") end},
        {id = 15, key = "CROWN_JEWEL",     name = "Crown Jewel",      payout = 9000,  quick = false,
         locate = function() return firstTagged("CasinoLoot") end},
        {id = 16, key = "MANSION",         name = "Mansion",          payout = 13000, quick = false,
         locate = function() return firstTagged("MansionRobbery") end},
        {id = 17, key = "OIL_RIG",         name = "Oil Rig",          payout = 12000, quick = false,
         locate = function() return firstTagged("OilRig") end},
    }
    Game.Robberies = ROBBERIES

    local byKey = {}
    for _, entry in ipairs(ROBBERIES) do byKey[entry.key] = entry end
    Game.robberyByKey = function(key) return byKey[key] end

    -- The game replicates one IntValue per robbery, named after its id.
    function Game.stateFolder()
        return ReplicatedStorage:FindFirstChild("RobberyState")
    end

    function Game.status(entry)
        local folder = Game.stateFolder()
        local value = folder and folder:FindFirstChild(tostring(entry.id))
        if not value then return nil end
        local ok, raw = pcall(function() return value.Value end)
        return ok and tonumber(raw) or nil
    end

    function Game.statusText(entry)
        local status = Game.status(entry)
        if status == Game.Status.Opened then return "Open" end
        if status == Game.Status.Started then return "Started" end
        if status == Game.Status.Closed then return "Closed" end
        return "—"
    end

    -- Open or already in progress: both are worth walking into.
    function Game.isRobbable(entry)
        local status = Game.status(entry)
        return status == Game.Status.Opened or status == Game.Status.Started
    end

    -- Centre of the area worth looting. The live model wins when there is one,
    -- because trains, planes and the money truck are never twice in the same
    -- place; the fixed coordinate is the fallback for the ones that are.
    function Game.centrePoint(entry)
        if entry.locate then
            local ok, inst = pcall(entry.locate)
            if ok and inst then
                local position = Game.pivotOf(inst)
                if position then return position end
            end
        end
        return entry.entry
    end

    -- Where to fly to. A fixed entry is an outdoor approach that is known to be
    -- reachable, so it beats a model pivot, which is often inside a wall.
    function Game.entryPoint(entry)
        return entry.entry or Game.centrePoint(entry)
    end

    function Game.openRobberies()
        local out = {}
        for _, entry in ipairs(ROBBERIES) do
            if not entry.skip and Game.isRobbable(entry) then out[#out + 1] = entry end
        end
        return out
    end

    -- ------------------------------------------------------------ interaction
    -- CircleAction is Jailbreak's hold-to-interact system. Specs is every
    -- prompt currently offered; Spec is the one being held right now.
    function Game.specs()
        local circle = Game.circleAction()
        local specs = circle and circle.Specs
        return typeof(specs) == "table" and specs or nil
    end

    function Game.fireSpec(spec)
        if typeof(spec) ~= "table" or type(spec.Callback) ~= "function" then return false end
        return (pcall(spec.Callback, spec, true))
    end

    function Game.specPosition(spec)
        local part = typeof(spec) == "table" and spec.Part or nil
        if typeof(part) ~= "Instance" then return nil end
        return Game.pivotOf(part)
    end

    -- Prompts that hand something over. Anything that spends money, moves us
    -- into a seat or swaps gear is left alone — the loot sweep fires blind and
    -- must not be able to buy a car with it.
    local SPEC_BLOCK = {
        "buy", "purchase", "sell", "trade", "rent", "claim", "spawn", "equip",
        "enter", "drive", "ride", "seat", "board", "customi", "upgrade",
        "leave", "exit", "respawn", "reset", "quit",
    }

    function Game.specIsSafe(spec)
        local name = typeof(spec) == "table" and spec.Name
        if typeof(name) ~= "string" then return false end
        local lower = name:lower()
        for _, word in ipairs(SPEC_BLOCK) do
            if lower:find(word, 1, true) then return false end
        end
        return true
    end

    -- -------------------------------------------------------------- the bag
    -- RobberyMoneyGui is only enabled while carrying, and its label reads
    -- "1,200 / 5,000". No gui means nothing is being carried.
    local function bagLabel()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        gui = gui and gui:FindFirstChild("RobberyMoneyGui")
        if not gui then return nil, nil end
        local node = gui
        for _, name in ipairs({"Container", "Bottom", "Progress", "Amount"}) do
            node = node:FindFirstChild(name)
            if not node then return gui, nil end
        end
        return gui, node
    end

    -- An amount, not just an enabled gui: if the label ever stops parsing this
    -- reads as "carrying nothing", which costs a trip to the bank. Trusting
    -- Enabled alone would instead wedge the rob loop on a bag it cannot empty.
    function Game.carrying()
        local have = Game.bag()
        return have ~= nil and have > 0
    end

    function Game.bag()
        local gui, label = bagLabel()
        if not gui or not gui.Enabled or not label then return nil, nil end
        local ok, text = pcall(function() return tostring(label.Text) end)
        if not ok then return nil, nil end
        local have, cap = text:match("([%d,]+)%s*/%s*([%d,]+)")
        if not have then return nil, nil end
        return tonumber((have:gsub(",", ""))), tonumber((cap:gsub(",", "")))
    end

    function Game.bagFull()
        local have, cap = Game.bag()
        return have ~= nil and cap ~= nil and cap > 0 and have >= cap
    end

    -- ---------------------------------------------------------------- teams
    function Game.teamName(player)
        local team = player and player.Team
        return team and team.Name or nil
    end

    function Game.myTeamName() return Game.teamName(LocalPlayer) end
    function Game.isPolice()   return Game.myTeamName() == "Police" end
    function Game.isCriminal() return Game.myTeamName() == "Criminal" end

    function Game.isArrestable(player)
        if player == LocalPlayer then return false end
        if Game.teamName(player) ~= "Criminal" then return false end
        if not U.isAliveChar(player) then return false end
        return not Game.isCuffed(player)
    end

    function Game.isCuffed(player)
        local char = U.charOf(player)
        if not char then return false end
        if char:FindFirstChild("Handcuffs") then return true end
        local ok, flag = pcall(function() return char:GetAttribute("HasHandcuffs") end)
        return ok and flag == true
    end

    function Game.inVehicle(player)
        local char = U.charOf(player)
        if not char then return false end
        local ok, flag = pcall(function() return char:GetAttribute("InVehicle") end)
        return ok and flag == true
    end

    function Game.criminals()
        local out = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if Game.isArrestable(player) then out[#out + 1] = player end
        end
        return out
    end

    -- --------------------------------------------------------------- items
    function Game.equippedName()
        local system = M.ItemSystem
        if not system or type(system.GetLocalEquipped) ~= "function" then return nil end
        local ok, item = pcall(system.GetLocalEquipped, system)
        if not ok or typeof(item) ~= "table" then return nil end
        local named, class = pcall(function() return item.__ClassName end)
        return (named and typeof(class) == "string") and class or nil
    end

    function Game.holdingHandcuffs()
        return Game.equippedName() == "Handcuffs"
    end

    -- -------------------------------------------------------------- places
    -- Somewhere to run a full bag to. Criminal bases only; the closest wins.
    Game.Bases = {
        {name = "City Base",    position = Vector3.new(-250, 20, 1616)},
        {name = "Volcano Base", position = Vector3.new(1816, 48, -1634)},
        {name = "Boat Docks",   position = Vector3.new(-430, 21, 2025)},
    }

    Game.Places = {
        {name = "Prison Yard",        position = Vector3.new(-1220, 18, -1760)},
        {name = "Police HQ",          position = Vector3.new(183, 18, 1084)},
        {name = "City Base",          position = Vector3.new(-250, 20, 1616)},
        {name = "Volcano Base",       position = Vector3.new(1816, 48, -1634)},
        {name = "Military Base",      position = Vector3.new(685, 19, 485)},
        {name = "Secret Agent Base",  position = Vector3.new(1527, 86, 1551)},
        {name = "Boat Docks",         position = Vector3.new(-430, 21, 2025)},
        {name = "Airport",            position = Vector3.new(-1202, 41, 2846)},
        {name = "Fire Station",       position = Vector3.new(-930, 32, 1349)},
        {name = "Gun Store",          position = Vector3.new(391, 18, 533)},
        {name = "Jetpack Mountain",   position = Vector3.new(1384, 168, 2596)},
        {name = "Pirate Hideout",     position = Vector3.new(1955, 14, 2117)},
        {name = "Lighthouse",         position = Vector3.new(-2044, 45, 1722)},
        {name = "Prison Island",      position = Vector3.new(-2917, 24, 2312)},
        {name = "Train Station",      position = Vector3.new(1635, 19, 258)},
        {name = "1M Dealership",      position = Vector3.new(720, 20, -1572)},
        {name = "Dog Shelter",        position = Vector3.new(252, 20, -1620)},
    }

    function Game.nearestBase()
        local root = U.myRoot()
        local origin = root and root.Position or Vector3.zero
        local best, bestDist
        for _, base in ipairs(Game.Bases) do
            local dist = (base.position - origin).Magnitude
            if not bestDist or dist < bestDist then best, bestDist = base, dist end
        end
        return best
    end

    function Game.placeNames()
        local names = {}
        for _, place in ipairs(Game.Places) do names[#names + 1] = place.name end
        return names
    end

    function Game.placeByName(name)
        for _, place in ipairs(Game.Places) do
            if place.name == name then return place end
        end
        return nil
    end

    -- --------------------------------------------------------------- loot
    -- Names Jailbreak gives to the things you stand on or grab to fill a bag.
    local LOOT_WORDS = {
        "money", "cash", "gold", "gem", "jewel", "loot", "uranium", "crate",
        "briefcase", "duffel", "safe", "register", "diamond", "artifact",
    }

    local function looksLikeLoot(part)
        local name = part.Name:lower()
        for _, word in ipairs(LOOT_WORDS) do
            if name:find(word, 1, true) then return true end
        end
        return false
    end

    -- Everything loot-shaped within `radius` of a point, nearest first. Used by
    -- the rob routine to hop across a vault rather than hardcode its layout.
    function Game.lootNear(centre, radius)
        if typeof(centre) ~= "Vector3" then return {} end
        local found = {}
        -- Capped: a radius this big over Jailbreak's map can otherwise return
        -- tens of thousands of parts and stall the thread that asked.
        local params = OverlapParams.new()
        params.MaxParts = 2000
        local ok, parts = pcall(function()
            return workspace:GetPartBoundsInRadius(centre, radius, params)
        end)
        if not ok or typeof(parts) ~= "table" then return found end
        local mine = LocalPlayer.Character
        for _, part in ipairs(parts) do
            if part:IsA("BasePart") and looksLikeLoot(part)
                and not (mine and part:IsDescendantOf(mine)) then
                found[#found + 1] = part
            end
        end
        table.sort(found, function(a, b)
            return (a.Position - centre).Magnitude < (b.Position - centre).Magnitude
        end)
        return found
    end
end

-- ─── src/_shared/40_ui_core.lua ────────────────────────────────────

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
        Text = KH.GameTag or "HUB",
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

-- ─── src/_shared/50_ui_controls.lua ────────────────────────────────

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

-- ─── src/_shared/55_session.lua ────────────────────────────────────

-- ============================================================================
--  SESSION — the one render loop, rejoin, server hop, and unload
-- ============================================================================

do
    local UI              = KH.UI
    local RunService      = KH.Services.RunService
    local TeleportService = KH.Services.TeleportService
    local HttpService     = KH.Services.HttpService
    local LocalPlayer     = KH.LocalPlayer

    -- ============================================================ RENDER LOOP
    -- One connection drives every per-frame job. Each is pcall-wrapped, so a
    -- feature that breaks cannot take the rest of the menu down with it.
    KH.track(RunService.RenderStepped:Connect(function(delta)
        if not KH.Alive then return end
        KH.camera()
        local jobs = KH.Frame
        for i = 1, #jobs do
            local job = jobs[i]
            KH.safe(job.name, job.fn, delta)
        end
    end))


    -- ============================================================== SESSION
    -- The places this hub has a module for. Switching between them from inside
    -- the menu queues the loader first, so an executor that refuses to attach
    -- to the destination still ends up running there — it is already in the
    -- process, and the queue survives the teleport.
    KH.Games = {
        {name = "Murder Mystery 2", place = 142823291},
        {name = "Jailbreak",        place = 606849621},
    }

    function KH.goToGame(placeId)
        if typeof(placeId) ~= "number" or placeId == game.PlaceId then return end
        local env = (type(getgenv) == "function" and getgenv()) or _G
        local queued = type(env.KittyHubQueue) == "function" and env.KittyHubQueue() == true

        UI.notify({
            title = "Switching Game",
            text = queued and "Queued — it will load itself when you land."
                or "This executor cannot queue; run the loadstring again on arrival.",
            kind = queued and "good" or "warn",
            duration = 6,
        })
        task.wait(1)
        pcall(function() TeleportService:Teleport(placeId, LocalPlayer) end)
    end

    function KH.rejoin()
        UI.notify({title = "Rejoin", text = "Teleporting…"})
        pcall(function()
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end)
    end

    function KH.serverHop()
        KH.detach(function()
            UI.notify({title = "Server Hop", text = "Looking for a server…"})
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100")
                :format(game.PlaceId)

            local ok, body = pcall(function() return game:HttpGet(url) end)
            if not ok then
                UI.notify({title = "Server Hop", text = "Could not reach the server list.", kind = "bad"})
                return
            end

            local decoded, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not decoded or typeof(data) ~= "table" or typeof(data.data) ~= "table" then
                UI.notify({title = "Server Hop", text = "Server list was unreadable.", kind = "bad"})
                return
            end

            local candidates = {}
            for _, server in ipairs(data.data) do
                if typeof(server) == "table"
                    and server.id ~= game.JobId
                    and typeof(server.playing) == "number"
                    and typeof(server.maxPlayers) == "number"
                    and server.playing < server.maxPlayers then
                    candidates[#candidates + 1] = server.id
                end
            end

            if #candidates == 0 then
                UI.notify({title = "Server Hop", text = "No other servers with room.", kind = "warn"})
                return
            end

            local pick = candidates[math.random(1, #candidates)]
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, pick, LocalPlayer)
            end)
        end)
    end

    -- =============================================================== UNLOAD
    function KH.unload()
        if not KH.Alive then return end
        KH.Alive = false

        -- Undo world changes first, while our instances still exist.
        for _, restore in ipairs(KH.Undo) do pcall(restore) end
        for _, conn in ipairs(KH.Conn) do pcall(function() conn:Disconnect() end) end

        local current = coroutine.running()
        for _, thread in ipairs(KH.Thread) do
            if thread ~= current then pcall(task.cancel, thread) end
        end

        for _, inst in ipairs(KH.Inst) do pcall(function() inst:Destroy() end) end

        local env = (type(getgenv) == "function" and getgenv()) or _G
        env.KittyHubCleanup = nil
        env.KittyHub = nil
        print("[Kitty Hub] Unloaded.")
    end

    do
        local env = (type(getgenv) == "function" and getgenv()) or _G
        env.KittyHubCleanup = KH.unload
    end

end

-- ─── src/_shared/60_movement.lua ───────────────────────────────────

-- ============================================================================
--  MOVEMENT — speed, jump, noclip, fly, spinbot, teleports, waypoints
--
--  Game-agnostic: anything that needs to know what it is teleporting to
--  lives in the game module and builds on Move.tpTo / Move.tpToPlayer.
-- ============================================================================

do
    local UI               = KH.UI
    local U                = KH.U
    local S                = KH.S
    local X                = KH.X
    local UserInputService = KH.Services.UserInputService
    local RunService       = KH.Services.RunService
    local HttpService      = KH.Services.HttpService
    local LocalPlayer      = KH.LocalPlayer

    local Move = {}
    KH.Move = Move

    -- ======================================================== SPEED / JUMP
    -- Re-applied continuously because MM2 resets WalkSpeed on respawn and when
    -- rounds change; a one-shot assignment silently stops working.
    function Move.applyHumanoid()
        local hum = U.myHum()
        if not hum then return end
        if S.Move.SpeedEnabled and S.Move.SpeedMode == "Humanoid" then
            if hum.WalkSpeed ~= S.Move.Speed then hum.WalkSpeed = S.Move.Speed end
        elseif hum.WalkSpeed ~= 16 and not S.Move.SpeedEnabled then
            hum.WalkSpeed = 16
        end

        -- R15 humanoids may be driven by JumpHeight rather than JumpPower;
        -- writing only JumpPower would silently do nothing on those.
        if S.Move.JumpEnabled then
            if hum.UseJumpPower then
                if hum.JumpPower ~= S.Move.Jump then hum.JumpPower = S.Move.Jump end
            else
                local height = S.Move.Jump / 7.5
                if math.abs(hum.JumpHeight - height) > 0.01 then hum.JumpHeight = height end
            end
        else
            if hum.UseJumpPower then
                if hum.JumpPower ~= 50 then hum.JumpPower = 50 end
            elseif math.abs(hum.JumpHeight - 7.2) > 0.01 then
                hum.JumpHeight = 7.2
            end
        end
    end

    -- CFrame mode drives the character directly, which ignores any server-side
    -- WalkSpeed clamp — at the cost of looking less natural.
    KH.onFrame("speed-cframe", function(delta)
        if not (S.Move.SpeedEnabled and S.Move.SpeedMode == "CFrame") then return end
        if S.Move.Fly then return end
        local hum, root = U.myHum(), U.myRoot()
        if not hum or not root then return end
        local direction = hum.MoveDirection
        if direction.Magnitude < 0.05 then return end
        -- delta comes from the shared render loop; never yield in here.
        root.CFrame = root.CFrame + direction * (S.Move.Speed - 16) * (delta or 0)
    end, 60)

    KH.loop(0.4, function() Move.applyHumanoid() end)

    -- ============================================================== NOCLIP
    -- Original collision states are recorded so disabling noclip restores the
    -- character exactly, rather than blanket-setting everything collidable.
    local noclipOriginal = {}
    local noclipConn

    local function noclipStep()
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                if noclipOriginal[part] == nil then noclipOriginal[part] = true end
                part.CanCollide = false
            end
        end
    end

    function Move.setNoclip(on)
        S.Move.Noclip = on
        if on then
            -- Not KH.track: this is disconnected below and on unload, and
            -- tracking it would add a dead entry on every single toggle.
            if not noclipConn then
                noclipConn = RunService.Stepped:Connect(noclipStep)
            end
        else
            if noclipConn then
                noclipConn:Disconnect()
                noclipConn = nil
            end
            for part, wasCollidable in pairs(noclipOriginal) do
                if part.Parent and wasCollidable then
                    pcall(function() part.CanCollide = true end)
                end
            end
            noclipOriginal = {}
        end
        UI.refreshKeybinds()
    end
    KH.undo(function() Move.setNoclip(false) end)

    -- ================================================== INFINITE JUMP / BHOP
    KH.track(UserInputService.JumpRequest:Connect(function()
        if not S.Move.InfJump then return end
        local hum = U.myHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end))

    KH.onFrame("bhop", function()
        if not S.Move.Bhop then return end
        if U.typing() then return end
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
        local hum = U.myHum()
        if not hum then return end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.Landed
            or state == Enum.HumanoidStateType.RunningNoPhysics then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end, 62)

    -- ================================================================= FLY
    local flyVelocity, flyGyro
    local flying = false

    local function stopFly()
        flying = false
        if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
        if flyGyro then flyGyro:Destroy(); flyGyro = nil end
        local hum = U.myHum()
        if hum then hum.PlatformStand = false end
    end

    local function startFly()
        local root, hum = U.myRoot(), U.myHum()
        if not root or not hum then return false end
        stopFly()

        flyVelocity = Instance.new("BodyVelocity")
        flyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyVelocity.Velocity = Vector3.zero
        flyVelocity.Parent = root

        flyGyro = Instance.new("BodyGyro")
        flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyGyro.P = 9e4
        flyGyro.CFrame = root.CFrame
        flyGyro.Parent = root

        hum.PlatformStand = true
        flying = true
        return true
    end

    function Move.setFly(on)
        S.Move.Fly = on
        if on then
            if not startFly() then
                S.Move.Fly = false
                UI.notify({title = "Fly", text = "No character to attach to.", kind = "bad"})
            end
        else
            stopFly()
        end
        UI.refreshKeybinds()
    end
    KH.undo(function() stopFly() end)

    KH.onFrame("fly", function()
        if not S.Move.Fly then
            if flying then stopFly() end
            return
        end
        if not flying or not flyVelocity or not flyVelocity.Parent then
            if not startFly() then return end
        end

        local cam = KH.camera()
        local direction = Vector3.zero
        -- Hold still while typing rather than reading the chat as flight input.
        if U.typing() then
            flyVelocity.Velocity = Vector3.zero
            flyGyro.CFrame = cam.CFrame
            return
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction = direction - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction = direction + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then direction = direction - Vector3.new(0, 1, 0) end

        if direction.Magnitude > 0 then direction = direction.Unit end
        flyVelocity.Velocity = direction * S.Move.FlySpeed
        flyGyro.CFrame = cam.CFrame
    end, 61)

    -- ============================================================= SPINBOT
    KH.onFrame("spinbot", function()
        if not S.Move.Spinbot then return end
        local root = U.myRoot()
        if not root then return end
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(28), 0)
    end, 63)

    -- Respawns wipe all of this, so reapply once the new character settles.
    KH.track(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.6)
        Move.applyHumanoid()
        if S.Move.Noclip then Move.setNoclip(true) end
        if S.Move.Fly then Move.setFly(true) end
    end))

    -- =========================================================== TELEPORTS
    local function tpTo(position, label)
        if not U.myRoot() then
            UI.notify({title = "Teleport", text = "No character.", kind = "bad"})
            return false
        end
        U.moveTo(position + Vector3.new(0, 3, 0), true)
        if label then UI.notify({title = "Teleport", text = label, duration = 2}) end
        return true
    end
    Move.tpTo = tpTo

    local function tpToPlayer(player, label)
        if not player then
            UI.notify({title = "Teleport", text = "Nobody to teleport to.", kind = "warn"})
            return false
        end
        local part = U.rootOf(player)
        if not part then
            UI.notify({title = "Teleport", text = player.DisplayName .. " has no character.", kind = "warn"})
            return false
        end
        return tpTo(part.Position, label or ("Moved to " .. player.DisplayName))
    end
    Move.tpToPlayer = tpToPlayer

    -- ============================================================ WAYPOINTS
    -- Their own file, not the settings profile: the reconciler drops keys it
    -- does not recognise, and waypoint names are never in the schema.
    local WAYPOINT_FILE = "KittyHub/waypoints.json"
    Move.Waypoints = {}

    local function loadWaypoints()
        if not (X.writefile and KH.Config.available) then return end
        pcall(function()
            if not isfile(WAYPOINT_FILE) then return end
            local data = HttpService:JSONDecode(readfile(WAYPOINT_FILE))
            if typeof(data) == "table" then Move.Waypoints = data end
        end)
    end

    local function saveWaypoints()
        if not (X.writefile and KH.Config.available) then return end
        pcall(function()
            writefile(WAYPOINT_FILE, HttpService:JSONEncode(Move.Waypoints))
        end)
    end
    loadWaypoints()

    function Move.saveWaypoint(name)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            UI.notify({title = "Waypoint", text = "Give it a name first.", kind = "warn"})
            return false
        end
        local root = U.myRoot()
        if not root then return false end
        local p = root.Position
        Move.Waypoints[name] = {p.X, p.Y, p.Z}
        saveWaypoints()
        UI.notify({title = "Waypoint", text = 'Saved "' .. name .. '".', kind = "good"})
        return true
    end

    function Move.gotoWaypoint(name)
        local entry = Move.Waypoints[name]
        if not entry then
            UI.notify({title = "Waypoint", text = "No waypoint called " .. tostring(name) .. ".", kind = "warn"})
            return false
        end
        return tpTo(Vector3.new(entry[1], entry[2], entry[3]), 'Moved to "' .. name .. '".')
    end

    function Move.deleteWaypoint(name)
        if Move.Waypoints[name] == nil then return false end
        Move.Waypoints[name] = nil
        saveWaypoints()
        UI.notify({title = "Waypoint", text = 'Deleted "' .. name .. '".'})
        return true
    end

    function Move.waypointNames()
        local names = {}
        for name in pairs(Move.Waypoints) do names[#names + 1] = name end
        table.sort(names)
        return names
    end
end

-- ─── src/_shared/62_visuals.lua ────────────────────────────────────

-- ============================================================================
--  VISUALS — fullbright, fog, field of view, x-ray walls, detail stripping
--
--  Every effect here records what it changed and restores it on unload, so
--  unloading the script leaves the game looking exactly as it did before.
-- ============================================================================

do
    local S        = KH.S
    local Lighting = KH.Services.Lighting
    local Game     = KH.Game or {}
    local Players  = KH.Services.Players

    local Visual = {}
    KH.Visual = Visual

    -- ========================================================== FULLBRIGHT
    local lightingSaved = nil

    local function saveLighting()
        if lightingSaved then return end
        lightingSaved = {
            Brightness      = Lighting.Brightness,
            ClockTime       = Lighting.ClockTime,
            Ambient         = Lighting.Ambient,
            OutdoorAmbient  = Lighting.OutdoorAmbient,
            GlobalShadows   = Lighting.GlobalShadows,
            FogEnd          = Lighting.FogEnd,
            FogStart        = Lighting.FogStart,
            ExposureCompensation = Lighting.ExposureCompensation,
        }
    end

    local function restoreLighting()
        if not lightingSaved then return end
        for property, value in pairs(lightingSaved) do
            pcall(function() Lighting[property] = value end)
        end
        lightingSaved = nil
    end
    KH.undo(restoreLighting)

    -- Atmosphere density is not a Lighting property, so it needs recording
    -- separately or turning fog off again leaves the map permanently clear.
    local atmosphereSaved = {}

    local function restoreAtmosphere()
        for effect, density in pairs(atmosphereSaved) do
            if effect.Parent then pcall(function() effect.Density = density end) end
        end
        atmosphereSaved = {}
    end
    KH.undo(restoreAtmosphere)

    -- Reapplied on a timer: MM2 drives its own day/night cycle per round and
    -- will happily reset Brightness out from under us.
    KH.loop(0.5, function()
        if S.Visual.Fullbright then
            saveLighting()
            local shade = 128 * math.clamp(S.Visual.Brightness / 2, 0.25, 1.5)
            Lighting.Brightness = S.Visual.Brightness
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(shade, shade, shade)
            Lighting.OutdoorAmbient = Color3.fromRGB(shade, shade, shade)
        elseif lightingSaved and not S.Visual.NoFog and not S.Visual.LowDetail then
            restoreLighting()
        end

        if S.Visual.NoFog then
            saveLighting()
            Lighting.FogEnd = 1e6
            Lighting.FogStart = 1e6
            for _, effect in ipairs(Lighting:GetChildren()) do
                if effect:IsA("Atmosphere") then
                    if atmosphereSaved[effect] == nil then
                        atmosphereSaved[effect] = effect.Density
                    end
                    pcall(function() effect.Density = 0 end)
                end
            end
        elseif next(atmosphereSaved) then
            restoreAtmosphere()
        end
    end)

    -- ================================================================= FOV
    KH.onFrame("fov", function()
        if not S.Visual.FovEnabled then return end
        local cam = KH.camera()
        if math.abs(cam.FieldOfView - S.Visual.Fov) > 0.1 then
            cam.FieldOfView = S.Visual.Fov
        end
    end, 70)
    KH.undo(function()
        pcall(function() KH.camera().FieldOfView = 70 end)
    end)

    -- =============================================================== X-RAY
    -- Only the map. Characters, coins and the dropped gun keep their real
    -- transparency, or x-ray would hide what you turned it on to see.
    local xraySaved = {}
    local xrayOn = false
    local xrayValue = nil   -- the transparency actually painted on

    local function isProtected(part)
        -- Anything belonging to a character.
        local model = part:FindFirstAncestorOfClass("Model")
        while model do
            if Players:GetPlayerFromCharacter(model) then return true end
            model = model:FindFirstAncestorOfClass("Model")
        end
        local name = part.Name
        return name == "GunDrop" or name == "MainCoin" or name == "Trap"
    end

    local function applyXray()
        local map = Game.map and Game.map() or workspace
        if not map then return end
        for _, part in ipairs(map:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.9 and not isProtected(part) then
                if xraySaved[part] == nil then xraySaved[part] = part.Transparency end
                part.Transparency = S.Visual.XrayTransp
            end
        end
        xrayOn = true
        xrayValue = S.Visual.XrayTransp
    end

    local function clearXray()
        for part, transparency in pairs(xraySaved) do
            if part.Parent then
                pcall(function() part.Transparency = transparency end)
            end
        end
        xraySaved = {}
        xrayOn = false
    end
    KH.undo(clearXray)

    -- A new round means a new map model, so re-run rather than tracking parts.
    if Game.on then
        Game.on("RoundStart", function()
            if S.Visual.Xray then
                task.wait(1)
                xraySaved = {}
                applyXray()
            end
        end)
    end

    KH.loop(1, function()
        -- Also when the slider has moved: the walls are already painted, so
        -- nothing else would ever notice a new value.
        if S.Visual.Xray and (not xrayOn or xrayValue ~= S.Visual.XrayTransp) then
            applyXray()
        elseif not S.Visual.Xray and xrayOn then
            clearXray()
        end
    end)

    -- ============================================================ LOW DETAIL
    -- Turns effects off rather than destroying them, so it is fully reversible.
    local detailSaved = {}
    local lowDetailOn = false
    local waterSaved = nil

    local EFFECT_CLASSES = {
        ParticleEmitter = true, Trail = true, Smoke = true,
        Fire = true, Sparkles = true, Beam = true,
    }

    local function applyLowDetail()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if EFFECT_CLASSES[obj.ClassName] and obj.Enabled then
                detailSaved[obj] = true
                obj.Enabled = false
            end
        end
        saveLighting()
        Lighting.GlobalShadows = false
        pcall(function()
            local terrain = workspace.Terrain
            if not waterSaved then
                waterSaved = {
                    size = terrain.WaterWaveSize,
                    reflectance = terrain.WaterReflectance,
                }
            end
            terrain.WaterWaveSize = 0
            terrain.WaterReflectance = 0
        end)
        lowDetailOn = true
    end

    local function clearLowDetail()
        for obj in pairs(detailSaved) do
            if obj.Parent then pcall(function() obj.Enabled = true end) end
        end
        detailSaved = {}
        -- The water was flattened by hand, so it has to be put back by hand.
        if waterSaved then
            pcall(function()
                workspace.Terrain.WaterWaveSize = waterSaved.size
                workspace.Terrain.WaterReflectance = waterSaved.reflectance
            end)
            waterSaved = nil
        end
        lowDetailOn = false
    end
    KH.undo(clearLowDetail)

    KH.loop(2, function()
        if S.Visual.LowDetail and not lowDetailOn then
            applyLowDetail()
        elseif S.Visual.LowDetail and lowDetailOn then
            applyLowDetail() -- catch effects added by the new round
        elseif not S.Visual.LowDetail and lowDetailOn then
            clearLowDetail()
        end
    end)
end

-- ─── src/jailbreak/70_travel.lua ───────────────────────────────────

-- ============================================================================
--  TRAVEL — getting across the map without tripping the movement check
--
--  Jailbreak rejects a character that jumps a long way in one frame, so a
--  crossing is flown: climb, cruise at a height nothing reaches, drop in. The
--  speed is a setting because what the server tolerates changes with updates.
-- ============================================================================

local Travel = {}
KH.Travel = Travel

do
    local U           = KH.U
    local S           = KH.S
    local LocalPlayer = KH.LocalPlayer

    local BASE_GRAVITY = workspace.Gravity
    local held = {}      -- parts we switched off, and only those
    local depth = 0
    local cancel = false

    Travel.Busy = false

    local function holdCollisions()
        local char = U.charOf(LocalPlayer)
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                held[part] = true
                part.CanCollide = false
            end
        end
    end

    local function releaseCollisions()
        for part in pairs(held) do
            if part.Parent then pcall(function() part.CanCollide = true end) end
        end
        table.clear(held)
    end

    local function beginFlight()
        depth = depth + 1
        if depth == 1 then
            workspace.Gravity = 0
            holdCollisions()
        end
    end

    local function endFlight()
        depth = math.max(depth - 1, 0)
        if depth == 0 then
            workspace.Gravity = BASE_GRAVITY
            releaseCollisions()
        end
    end

    -- Gravity is world state; leaving it at zero would break the game for the
    -- rest of the session, so unload puts it back whatever else happened.
    KH.undo(function()
        depth = 0
        workspace.Gravity = BASE_GRAVITY
        releaseCollisions()
    end)

    function Travel.stop() cancel = true end

    local function stopped()
        return not KH.Alive or cancel
    end

    -- One leg of the flight. Returns false if we ran out of time, lost the
    -- character, or were cancelled — never partially and silently.
    local function leg(goal, speed, arrive, deadline)
        while not stopped() do
            local root = U.myRoot()
            if not root then return false end

            local delta = goal - root.Position
            local distance = delta.Magnitude
            if distance <= arrive then return true end
            if os.clock() > deadline then return false end

            -- Clamped: a frame spike would otherwise become one huge jump,
            -- which is exactly what the movement check looks for.
            local dt = math.min(task.wait(), 0.1)
            local hop = math.min(speed * dt, distance)
            local position = root.Position + delta.Unit * hop

            local facing = Vector3.new(delta.X, 0, delta.Z)
            if facing.Magnitude > 0.05 then
                root.CFrame = CFrame.lookAt(position, position + facing.Unit)
            else
                root.CFrame = CFrame.new(position)
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        return false
    end

    local function fly(target, opts)
        local root = U.myRoot()
        if not root then return false end

        local speed = math.max(opts.speed or S.Travel.Speed, 20)
        local deadline = os.clock() + math.max(opts.timeout or S.Travel.Timeout, 3)
        local landing = target + Vector3.new(0, 3, 0)

        if opts.direct then
            return leg(landing, speed, 2, deadline)
        end

        local start = root.Position
        local height = math.max(opts.height or S.Travel.Height, target.Y + 60, start.Y + 20)
        return leg(Vector3.new(start.X, height, start.Z), speed, 4, deadline)
            and leg(Vector3.new(target.X, height, target.Z), speed, 4, deadline)
            and leg(landing, speed, 2.5, deadline)
    end

    -- destination may be a Vector3 or a CFrame. opts: mode, speed, height,
    -- timeout, direct.
    function Travel.to(destination, opts)
        opts = opts or {}
        if Travel.Busy then return false end

        local target = typeof(destination) == "CFrame" and destination.Position or destination
        if typeof(target) ~= "Vector3" then return false end
        if not U.myRoot() then return false end

        local mode = opts.mode or S.Travel.Mode
        Travel.Busy, cancel = true, false

        local ok
        if mode == "Instant" then
            ok = U.moveTo(target + Vector3.new(0, 3, 0), true)
            task.wait(0.1)
        else
            beginFlight()
            -- pcall so a mid-flight error can never leave gravity at zero.
            local safe, result = pcall(fly, target, opts)
            endFlight()
            ok = safe and result or false
        end

        local root = U.myRoot()
        if root then root.AssemblyLinearVelocity = Vector3.zero end

        Travel.Busy = false
        return ok == true
    end

    function Travel.toPlayer(player, opts)
        local part = player and U.rootOf(player)
        if not part then return false end
        return Travel.to(part.Position, opts)
    end
end

-- ─── src/jailbreak/72_robbery.lua ──────────────────────────────────

-- ============================================================================
--  ROBBERY — auto rob, and the pieces it is built from
--
--  Interiors are not hardcoded. Jailbreak offers everything you can interact
--  with through CircleAction, and the loot itself is parts you stand on, so a
--  job is: fly to the entrance, fire the prompts around you, hop between the
--  loot, and run the bag to a base. That survives a map update; a path of
--  waypoints through a vault does not.
-- ============================================================================

local Rob = {}
KH.Rob = Rob

do
    local UI     = KH.UI
    local U      = KH.U
    local S      = KH.S
    local Game   = KH.Game
    local Travel = KH.Travel

    Rob.Status  = "Idle"
    Rob.Current = nil
    Rob.Busy    = false
    Rob.Abort   = false
    Rob.Runs    = 0

    local function say(text, kind)
        Rob.Status = text
        if S.Rob.Notify then
            UI.notify({title = "Auto Rob", text = text, kind = kind, duration = 4})
        end
    end

    -- ---------------------------------------------------------- interaction
    -- Jailbreak's hold-to-interact timer lives on the spec being held, so
    -- zeroing it every frame completes any prompt the moment it is started.
    KH.onFrame("jb-instant", function()
        if not S.Rob.Instant then return end
        local circle = Game.circleAction()
        local spec = circle and circle.Spec
        if typeof(spec) == "table" then spec.PressedAt = 0 end
    end, 40)

    -- Firing the same prompt every tick would be a packet flood; once every
    -- half second per prompt is enough for anything that yields loot.
    local fired = setmetatable({}, {__mode = "k"})

    function Rob.fireNearby(range)
        local specs = Game.specs()
        if not specs then return 0 end
        local root = U.myRoot()
        if not root then return 0 end

        -- Snapshot first: a callback can add or remove specs, and iterating a
        -- table while it is being rewritten is undefined.
        local list = {}
        for _, spec in pairs(specs) do list[#list + 1] = spec end

        local now, count = os.clock(), 0
        for _, spec in ipairs(list) do
            if Game.specIsSafe(spec) and (fired[spec] or 0) < now then
                local position = Game.specPosition(spec)
                if position and (position - root.Position).Magnitude <= range then
                    fired[spec] = now + 0.5
                    if Game.fireSpec(spec) then count = count + 1 end
                end
            end
        end
        return count
    end

    -- ---------------------------------------------------------------- rules
    local function alive()
        return KH.Alive and not Rob.Abort and U.myRoot() ~= nil
    end

    local function working(entry, deadline)
        if not alive() then return false end
        if os.clock() > deadline then return false end
        if Game.isCuffed(KH.LocalPlayer) then return false end
        -- Closed means the job is over; whatever is in the bag gets banked.
        return Game.isRobbable(entry)
    end

    -- ----------------------------------------------------------------- loot
    -- Stand on each loot part in turn. Money in Jailbreak accrues while you
    -- are on it, so the dwell matters more than the number of stops.
    local function lootSweep(entry, deadline)
        local centre = Game.centrePoint(entry)
        if not centre then return end

        local parts = Game.lootNear(centre, S.Rob.LootRadius)
        for _, part in ipairs(parts) do
            if not working(entry, deadline) or Game.bagFull() then return end
            if part.Parent then
                Travel.to(part.Position, {direct = true, speed = 150, timeout = 6})
                local until_ = os.clock() + 1.5
                while os.clock() < until_ and working(entry, deadline) do
                    if S.Rob.AutoInteract then Rob.fireNearby(S.Rob.InteractRange) end
                    if Game.bagFull() then return end
                    task.wait(0.15)
                end
            end
        end
    end

    -- -------------------------------------------------------------- deposit
    -- Three failures in a row means the drop-off is not where this thinks it
    -- is, and retrying forever would stop any more robbing from happening.
    local bankFails = 0

    function Rob.deposit()
        if not Game.carrying() then bankFails = 0 return true end
        local base = Game.nearestBase()
        if not base then return false end

        Rob.Status = "Banking at " .. base.name
        Travel.to(base.position)

        local deadline = os.clock() + 30
        while KH.Alive and not Rob.Abort and Game.carrying() and os.clock() < deadline do
            Rob.fireNearby(S.Rob.InteractRange)
            task.wait(0.25)
        end

        if not Game.carrying() then
            bankFails = 0
            return true
        end
        bankFails = bankFails + 1
        if bankFails >= 3 and S.Rob.Deposit then
            bankFails = 0
            S.Rob.Deposit = false
            UI.refreshAll()
            say("Could not bank the bag — turning that off.", "warn")
        end
        return false
    end

    -- ------------------------------------------------------------- one job
    function Rob.runOne(entry)
        if Rob.Busy then return false end
        if not entry then return false end

        Rob.Busy, Rob.Abort, Rob.Current = true, false, entry.name
        local ok = pcall(function()
            local point = Game.entryPoint(entry)
            if not point then
                say(entry.name .. " could not be located.", "warn")
                return
            end

            Rob.Status = "Flying to " .. entry.name
            if not Travel.to(point) then
                say("Could not reach " .. entry.name .. ".", "warn")
                return
            end

            Rob.Status = "Robbing " .. entry.name
            local deadline = os.clock() + math.max(S.Rob.Dwell, 10)

            -- One pass of prompts on arrival opens whatever needs opening,
            -- then alternate sweeping the loot with firing what is in reach.
            local worked = false
            while working(entry, deadline) and not Game.bagFull() do
                worked = true
                if S.Rob.AutoInteract then Rob.fireNearby(S.Rob.InteractRange) end
                if S.Rob.Loot then
                    lootSweep(entry, deadline)
                else
                    task.wait(0.25)
                end
                task.wait(0.2)
            end

            if S.Rob.Deposit then Rob.deposit() end
            if worked then
                Rob.Runs = Rob.Runs + 1
                say(("Finished %s."):format(entry.name), "good")
            else
                say(("%s closed before we got there."):format(entry.name), "warn")
            end
        end)

        Rob.Busy, Rob.Current = false, nil
        Rob.Status = "Idle"
        return ok
    end

    function Rob.stop()
        Rob.Abort = true
        Travel.stop()
        Rob.Status = "Stopping"
    end

    -- --------------------------------------------------------------- choice
    local function allowed(entry)
        if S.Rob.Only == "Quick" then return entry.quick end
        if S.Rob.Only == "Big" then return not entry.quick end
        return true
    end

    function Rob.candidates()
        local out = {}
        for _, entry in ipairs(Game.openRobberies()) do
            if allowed(entry) and Game.entryPoint(entry) then out[#out + 1] = entry end
        end

        if S.Rob.Pick == "Best Payout" then
            table.sort(out, function(a, b) return a.payout > b.payout end)
        elseif S.Rob.Pick == "Nearest" then
            local root = U.myRoot()
            local origin = root and root.Position or Vector3.zero
            local distance = {}
            for _, entry in ipairs(out) do
                local point = Game.entryPoint(entry)
                distance[entry] = point and (point - origin).Magnitude or math.huge
            end
            table.sort(out, function(a, b) return distance[a] < distance[b] end)
        end
        return out
    end

    -- ------------------------------------------------------------ auto loop
    KH.loop(1, function()
        if not S.Rob.Auto or Rob.Busy then return end
        -- Police loads after this one, so it is looked up when the loop runs.
        local police = KH.Police
        if police and police.Busy then return end

        if not Game.isCriminal() then
            Rob.Status = "Waiting — not on the Criminal team"
            return
        end
        if Game.isCuffed(KH.LocalPlayer) then
            Rob.Status = "Waiting — arrested"
            return
        end

        -- Carrying something from a job that was cut short? Bank it first.
        if Game.carrying() and S.Rob.Deposit then
            Rob.Busy = true
            pcall(Rob.deposit)
            Rob.Busy = false
            return
        end

        local next_ = Rob.candidates()[1]
        if not next_ then
            if S.Rob.Restock then
                Rob.Status = "Waiting for a robbery to open"
            else
                S.Rob.Auto = false
                UI.refreshAll()
                say("Nothing left open — stopping.", "warn")
            end
            return
        end

        Rob.runOne(next_)
        task.wait(math.max(S.Rob.Wait, 0))
    end)
end

-- ─── src/jailbreak/74_police.lua ───────────────────────────────────

-- ============================================================================
--  POLICE — arrest one, arrest everyone, arrest whoever comes close
--
--  An arrest is the game's own client deciding a cuffed officer is on top of a
--  criminal, so this does not fake a remote: it puts you there, taps the touch
--  interest to be sure the contact registers, and waits for the team to flip.
--  That is why it is one target at a time rather than truly all at once.
-- ============================================================================

local Police = {}
KH.Police = Police

do
    local UI          = KH.UI
    local U           = KH.U
    local S           = KH.S
    local X           = KH.X
    local Game        = KH.Game
    local Travel      = KH.Travel
    local VirtualUser = KH.Services.VirtualUser

    Police.Busy       = false
    Police.Abort      = false
    Police.Status     = "Idle"
    Police.LastResult = "nothing yet"
    Police.Arrests    = 0

    -- ------------------------------------------------------------ handcuffs
    -- The item system is the only reliable way to read what is in hand, and it
    -- is not there on every executor. Without it, pressing the hotbar key is
    -- still the right move — we just cannot confirm it landed.
    function Police.equipped()
        local name = Game.equippedName()
        if name == nil then return "unknown" end
        return name
    end

    local SLOT_KEYS = {
        Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
        Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
        Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
    }

    local function pressSlot(slot)
        local key = SLOT_KEYS[slot] or SLOT_KEYS[1]

        local sent = pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, key, false, game)
            task.wait(0.03)
            vim:SendKeyEvent(false, key, false, game)
        end)
        if sent then return true end

        return (pcall(function()
            VirtualUser:SetKeyDown(tostring(slot))
            task.wait(0.03)
            VirtualUser:SetKeyUp(tostring(slot))
        end))
    end

    -- Without the item system there is no way to tell the press worked, so it
    -- is rate limited — otherwise the aura would hammer the hotbar key forever.
    local lastEquip = 0

    function Police.equipCuffs()
        if Game.holdingHandcuffs() then return true end
        if not S.Police.AutoEquip then return Police.equipped() == "unknown" end
        if os.clock() - lastEquip < 2 then return false end

        lastEquip = os.clock()
        pressSlot(math.clamp(math.floor(S.Police.CuffSlot), 1, 9))
        task.wait(0.15)
        -- "unknown" means the item system is unavailable, not that it failed.
        return Game.holdingHandcuffs() or Police.equipped() == "unknown"
    end

    -- ---------------------------------------------------------------- touch
    local function tap(a, b)
        if not X.firetouch then return end
        pcall(firetouchinterest, a, b, 0)
        pcall(firetouchinterest, a, b, 1)
    end

    local function caught(player)
        return Game.isCuffed(player) or Game.teamName(player) ~= "Criminal"
    end

    -- --------------------------------------------------------------- arrest
    function Police.arrest(player)
        if not player then return false end
        if not U.rootOf(player) then return false end

        if S.Police.ArrestMode == "Glide" then
            Travel.toPlayer(player, {direct = true, speed = 260, timeout = 8})
        end

        local offset = math.max(S.Police.Offset, 0)
        local deadline = os.clock() + math.max(S.Police.Dwell, 0.1)
        local nextTap = 0

        while KH.Alive and not Police.Abort and os.clock() < deadline do
            local me, them = U.myRoot(), U.rootOf(player)
            if not me or not them then break end
            if caught(player) then return true end

            me.CFrame = them.CFrame * CFrame.new(0, 0, offset)
            me.AssemblyLinearVelocity = Vector3.zero
            me.AssemblyAngularVelocity = Vector3.zero

            if os.clock() >= nextTap then
                nextTap = os.clock() + 0.1
                tap(me, them)
            end
            task.wait()
        end
        return caught(player)
    end

    -- --------------------------------------------------------------- sweeps
    function Police.arrestAll()
        if Police.Busy then return end
        if not Game.isPolice() then
            UI.notify({
                title = "Arrest All",
                text = "You have to be on the Police team.",
                kind = "warn",
            })
            return
        end

        Police.Busy, Police.Abort = true, false
        local root = U.myRoot()
        local home = root and root.CFrame

        pcall(function()
            Police.equipCuffs()

            local targets = Game.criminals()
            if #targets == 0 then
                Police.LastResult = "no criminals in the server"
                Police.Status = "Idle"
                UI.notify({title = "Arrest All", text = "Nobody to arrest.", kind = "warn"})
                return
            end

            local got, missed = 0, 0
            for index, player in ipairs(targets) do
                if not KH.Alive or Police.Abort then break end
                Police.Status = ("Arresting %d/%d"):format(index, #targets)

                if S.Police.SkipVehicles and Game.inVehicle(player) then
                    missed = missed + 1
                elseif Police.arrest(player) then
                    got = got + 1
                    Police.Arrests = Police.Arrests + 1
                else
                    missed = missed + 1
                end
                task.wait(math.max(S.Police.Spacing, 0))
            end

            Police.LastResult = ("%d arrested, %d missed"):format(got, missed)
            UI.notify({
                title = "Arrest All",
                text = Police.LastResult,
                kind = got > 0 and "good" or "warn",
            })
        end)

        if S.Police.ReturnAfter and home then
            local me = U.myRoot()
            if me then
                me.CFrame = home
                me.AssemblyLinearVelocity = Vector3.zero
            end
        end

        Police.Busy = false
        Police.Status = "Idle"
    end

    function Police.stop()
        Police.Abort = true
        Travel.stop()
    end

    -- Keeps sweeping. Deliberately separate from the aura: this one moves you.
    KH.loop(2, function()
        if not S.Police.AutoArrest or Police.Busy then return end
        if KH.Rob.Busy then return end
        if not Game.isPolice() then return end
        if #Game.criminals() == 0 then return end
        Police.arrestAll()
    end)

    -- ----------------------------------------------------------------- aura
    -- Stays put and cuffs whoever wanders into range, which is the quiet
    -- version — no teleporting, so nothing on screen looks wrong.
    KH.loop(0.1, function()
        if not S.Police.Aura or Police.Busy then return end
        if not Game.isPolice() then return end

        local me = U.myRoot()
        if not me then return end

        local range = math.max(S.Police.AuraRange, 1)
        local equipped = false
        for _, player in ipairs(Game.criminals()) do
            local them = U.rootOf(player)
            if them and (them.Position - me.Position).Magnitude <= range then
                if not equipped then
                    equipped = true
                    Police.equipCuffs()
                end
                tap(me, them)
            end
        end
    end)
end

-- ─── src/jailbreak/76_farm.lua ─────────────────────────────────────

-- ============================================================================
--  FARM — the bits of grinding that are not a robbery
-- ============================================================================

local Farm = {}
KH.Farm = Farm

do
    local U           = KH.U
    local S           = KH.S
    local Game        = KH.Game
    local Rob         = KH.Rob
    local Police      = KH.Police
    local Travel      = KH.Travel
    local LocalPlayer = KH.LocalPlayer
    local VirtualUser = KH.Services.VirtualUser

    Farm.Collected = 0

    -- --------------------------------------------------------------- items
    -- Dropped pickups live in workspace.Items. Collecting one is standing on
    -- it, or the prompt that appears when you do, so both happen here.
    local function itemsFolder()
        return workspace:FindFirstChild("Items")
    end

    -- Anything we flew to and failed to collect is parked for a while. Without
    -- this, one pickup we are not allowed to take is always the nearest one and
    -- the farm never looks at anything else again.
    local parked = setmetatable({}, {__mode = "k"})

    function Farm.nearestItem()
        local folder = itemsFolder()
        local root = U.myRoot()
        if not folder or not root then return nil end

        local now = os.clock()
        local best, bestDist
        for _, item in ipairs(folder:GetChildren()) do
            local position = (parked[item] or 0) < now and Game.pivotOf(item) or nil
            if position then
                local dist = (position - root.Position).Magnitude
                if dist <= S.Farm.ItemRadius and (not bestDist or dist < bestDist) then
                    best, bestDist = item, dist
                end
            end
        end
        return best
    end

    KH.loop(0.5, function()
        if not S.Farm.Items then return end
        -- Never fight the rob routine or a sweep for the character.
        if Rob.Busy or Police.Busy or Travel.Busy then return end

        local item = Farm.nearestItem()
        if not item then return end

        local position = Game.pivotOf(item)
        if not position then return end

        Travel.to(position, {direct = true, speed = 180, timeout = 8})
        local deadline = os.clock() + 1.5
        while KH.Alive and item.Parent and os.clock() < deadline do
            Rob.fireNearby(12)
            task.wait(0.15)
        end

        if item.Parent then
            parked[item] = os.clock() + 60
        else
            Farm.Collected = Farm.Collected + 1
        end
    end)

    -- ---------------------------------------------------------- interaction
    -- Fires any prompt in range without moving: doors, registers, hatches.
    KH.loop(0.2, function()
        if not S.Farm.InteractAura then return end
        Rob.fireNearby(math.max(S.Farm.AuraRange, 1))
    end)

    -- -------------------------------------------------------------- anti-afk
    KH.track(LocalPlayer.Idled:Connect(function()
        if not S.Farm.AntiAFK then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end

-- ─── src/jailbreak/78_esp.lua ──────────────────────────────────────

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

-- ─── src/jailbreak/90_menu.lua ─────────────────────────────────────

-- ============================================================================
--  MENU — every tab, section and control
-- ============================================================================

do
    local UI     = KH.UI
    local S      = KH.S
    local Game   = KH.Game
    local Rob    = KH.Rob
    local Police = KH.Police
    local Farm   = KH.Farm
    local Travel = KH.Travel
    local Move   = KH.Move

    -- Binds a control straight to a settings field, with an optional side
    -- effect to run after the value lands.
    local function opt(group, key, extra)
        local t = extra or {}
        local after = t.onSet
        t.onSet = nil
        t.get = function() return S[group][key] end
        t.set = function(value)
            S[group][key] = value
            if after then after(value) end
        end
        return t
    end

    local function robberyNames()
        local names = {}
        for _, entry in ipairs(Game.Robberies) do
            if not entry.skip then names[#names + 1] = entry.name end
        end
        return names
    end

    local function robberyNamed(name)
        for _, entry in ipairs(Game.Robberies) do
            if entry.name == name then return entry end
        end
        return nil
    end

    -- ========================================================= ROBBERY TAB
    do
        local tab = UI.addTab("Robbery")

        local auto = UI.section(tab, "Auto Rob")
        UI.label(auto, "Flies to whatever is open, fires the prompts it finds, stands on the loot until the bag is full, then runs it to the nearest criminal base. Nothing here needs you to be near the robbery first.")
        UI.toggle(auto, opt("Rob", "Auto", {
            text = "Auto Rob",
            desc = "Keep taking jobs for as long as this is on.",
            onSet = function(on) if not on then Rob.stop() end end,
        }))
        UI.dropdown(auto, opt("Rob", "Pick", {
            text = "Choose By",
            desc = "Best Payout goes for the biggest score that is open. Nearest is faster per run.",
            options = {"Best Payout", "Nearest", "In Order"},
        }))
        UI.dropdown(auto, opt("Rob", "Only", {
            text = "Job Size",
            desc = "Quick is the gas station and donut store — small, but they reopen fast.",
            options = {"Any", "Quick", "Big"},
        }))
        UI.toggle(auto, opt("Rob", "Deposit", {
            text = "Bank The Bag",
            desc = "Run a full bag to a criminal base before taking the next job.",
        }))
        UI.toggle(auto, opt("Rob", "Restock", {
            text = "Wait For The Next One",
            desc = "Off, Auto Rob switches itself off once nothing is open instead of idling.",
        }))
        UI.slider(auto, opt("Rob", "Wait", {
            text = "Gap Between Jobs", min = 0, max = 20, step = 1, suffix = "s",
        }))
        UI.slider(auto, opt("Rob", "Dwell", {
            text = "Give Up After",
            desc = "How long one job may take before it is abandoned.",
            min = 20, max = 180, step = 5, suffix = "s",
        }))
        UI.readout(auto, {text = "Status", get = function() return Rob.Status end})
        UI.readout(auto, {
            text = "Bag",
            get = function()
                local have, cap = Game.bag()
                if not have then return "empty" end
                return ("%d / %d"):format(have, cap)
            end,
        })
        UI.readout(auto, {text = "Jobs Done", get = function() return Rob.Runs end})

        local manual = UI.section(tab, "Run One")
        local chosen = {name = "Rising City Bank"}
        UI.dropdown(manual, {
            text = "Robbery",
            options = robberyNames(),
            get = function() return chosen.name end,
            set = function(v) chosen.name = v end,
        })
        UI.button(manual, {
            text = "Rob This One",
            kind = "primary",
            callback = function() Rob.runOne(robberyNamed(chosen.name)) end,
        })
        UI.button(manual, {
            text = "Rob The Best Open One",
            callback = function()
                local pick = Rob.candidates()[1]
                if pick then
                    Rob.runOne(pick)
                else
                    UI.notify({title = "Auto Rob", text = "Nothing is open.", kind = "warn"})
                end
            end,
        })
        UI.button(manual, {
            text = "Bank What I Am Carrying",
            callback = function() Rob.deposit() end,
        })
        UI.button(manual, {
            text = "Stop",
            kind = "danger",
            desc = "Abandon the current job and stay where you are.",
            callback = function() Rob.stop() end,
        })

        local how = UI.section(tab, "How It Works")
        UI.toggle(how, opt("Rob", "Instant", {
            text = "Instant Interactions",
            desc = "Jailbreak's hold-to-use circle completes the moment it starts — vault doors, registers, keypads, everything.",
        }))
        UI.toggle(how, opt("Rob", "AutoInteract", {
            text = "Fire Nearby Prompts",
            desc = "Trigger anything interactable in range while looting. Prompts that spend money or put you in a seat are never fired.",
        }))
        UI.slider(how, opt("Rob", "InteractRange", {
            text = "Prompt Range", min = 10, max = 120, step = 5, suffix = " studs",
        }))
        UI.toggle(how, opt("Rob", "Loot", {
            text = "Hop Between Loot",
            desc = "Stand on each money pile, gem case and crate in turn instead of waiting in one spot.",
        }))
        UI.slider(how, opt("Rob", "LootRadius", {
            text = "Loot Search Radius", min = 60, max = 500, step = 10, suffix = " studs",
        }))
        UI.toggle(how, opt("Rob", "Notify", {text = "Announce Each Job"}))

        local board = UI.section(tab, "Robbery States")
        for _, entry in ipairs(Game.Robberies) do
            if not entry.skip then
                UI.readout(board, {
                    text = entry.name,
                    get = function() return Game.statusText(entry) end,
                })
            end
        end
    end

    -- ========================================================== POLICE TAB
    do
        local tab = UI.addTab("Police")

        local arrest = UI.section(tab, "Arrest")
        UI.label(arrest, "An arrest is the game deciding a cuffed officer is touching a criminal, so this goes to each one in turn rather than cuffing the whole server in a single frame. Equip handcuffs first, or let it press the hotbar key for you.")
        UI.button(arrest, {
            text = "Arrest Everyone",
            kind = "primary",
            desc = "Sweep every criminal in the server, then come back.",
            callback = function() Police.arrestAll() end,
        })
        UI.button(arrest, {
            text = "Stop Sweeping",
            kind = "danger",
            callback = function() Police.stop() end,
        })
        UI.keybind(arrest, opt("Police", "ArrestKey", {text = "Arrest All Key"}))
        UI.readout(arrest, {text = "Status", get = function() return Police.Status end})
        UI.readout(arrest, {text = "Last Sweep", get = function() return Police.LastResult end})
        UI.readout(arrest, {
            text = "Criminals",
            get = function() return #Game.criminals() end,
        })

        local tuning = UI.section(tab, "Tuning")
        UI.dropdown(tuning, opt("Police", "ArrestMode", {
            text = "Approach",
            desc = "Instant snaps onto each target. Glide flies there first, which looks far less obvious but takes longer.",
            options = {"Instant", "Glide"},
        }))
        UI.slider(tuning, opt("Police", "Dwell", {
            text = "Time Per Target",
            desc = "How long to stay on someone before moving on. Lower is faster and misses more.",
            min = 0.1, max = 3, step = 0.05, suffix = "s",
        }))
        UI.slider(tuning, opt("Police", "Spacing", {
            text = "Gap Between Targets", min = 0, max = 1, step = 0.05, suffix = "s",
        }))
        UI.slider(tuning, opt("Police", "Offset", {
            text = "Stand-Off Distance", min = 0, max = 8, step = 0.5, suffix = " studs",
        }))
        UI.toggle(tuning, opt("Police", "ReturnAfter", {
            text = "Return Afterwards",
            desc = "Go back to where you started once the sweep ends.",
        }))
        UI.toggle(tuning, opt("Police", "SkipVehicles", {
            text = "Skip People In Cars",
            desc = "You cannot arrest a driver, so this saves the wasted stop.",
        }))

        local aura = UI.section(tab, "Arrest Aura")
        UI.label(aura, "Stays where you are and cuffs anyone who walks into range. Nothing teleports, so this is the version that does not look like anything.")
        UI.toggle(aura, opt("Police", "Aura", {text = "Arrest Aura"}))
        UI.slider(aura, opt("Police", "AuraRange", {
            text = "Aura Range", min = 5, max = 60, step = 1, suffix = " studs",
        }))
        UI.toggle(aura, opt("Police", "AutoArrest", {
            text = "Keep Sweeping",
            desc = "Re-run Arrest Everyone whenever new criminals appear.",
        }))

        local gear = UI.section(tab, "Handcuffs")
        UI.toggle(gear, opt("Police", "AutoEquip", {
            text = "Equip Handcuffs",
            desc = "Press the hotbar key before arresting. Turn it off if you would rather hold them yourself.",
        }))
        UI.slider(gear, opt("Police", "CuffSlot", {
            text = "Handcuff Hotbar Slot", min = 1, max = 9, step = 1,
        }))
        UI.readout(gear, {text = "In Hand", get = function() return Police.equipped() end})
    end

    -- ============================================================ FARM TAB
    do
        local tab = UI.addTab("Farm")

        local pickups = UI.section(tab, "Pickups")
        UI.toggle(pickups, opt("Farm", "Items", {
            text = "Collect Dropped Items",
            desc = "Fly to anything lying in the world and pick it up. Pauses while a robbery is running.",
        }))
        UI.slider(pickups, opt("Farm", "ItemRadius", {
            text = "Search Radius", min = 50, max = 1000, step = 25, suffix = " studs",
        }))
        UI.readout(pickups, {text = "Picked Up", get = function() return Farm.Collected end})

        local aura = UI.section(tab, "Interact Aura")
        UI.toggle(aura, opt("Farm", "InteractAura", {
            text = "Interact Aura",
            desc = "Fire every prompt in range, all the time — doors, hatches, registers. Independent of Auto Rob.",
        }))
        UI.slider(aura, opt("Farm", "AuraRange", {
            text = "Aura Range", min = 5, max = 80, step = 1, suffix = " studs",
        }))

        local session = UI.section(tab, "Session")
        UI.toggle(session, opt("Farm", "AntiAFK", {
            text = "Anti AFK",
            desc = "Answer the idle check so a long farm is not kicked.",
        }))
    end

    -- ========================================================== TRAVEL TAB
    do
        local tab = UI.addTab("Travel")

        local how = UI.section(tab, "How To Move")
        UI.label(how, "Jailbreak rejects a character that covers a long distance in one frame, so a crossing is flown at altitude instead of snapped. Instant is faster and far more likely to be caught.")
        UI.dropdown(how, opt("Travel", "Mode", {
            text = "Mode", options = {"Glide", "Instant"},
        }))
        UI.slider(how, opt("Travel", "Speed", {
            text = "Glide Speed",
            desc = "Studs per second. Higher gets there sooner and is more conspicuous.",
            min = 40, max = 400, step = 10,
        }))
        UI.slider(how, opt("Travel", "Height", {
            text = "Cruise Height", min = 120, max = 500, step = 10, suffix = " studs",
        }))
        UI.slider(how, opt("Travel", "Timeout", {
            text = "Give Up After", min = 10, max = 90, step = 5, suffix = "s",
        }))
        UI.button(how, {
            text = "Stop Travelling",
            kind = "danger",
            callback = function() Travel.stop() end,
        })

        local places = UI.section(tab, "Places")
        local place = {name = Game.Places[1].name}
        UI.dropdown(places, {
            text = "Destination",
            options = Game.placeNames(),
            get = function() return place.name end,
            set = function(v) place.name = v end,
        })
        UI.button(places, {
            text = "Go",
            kind = "primary",
            callback = function()
                local target = Game.placeByName(place.name)
                if target then Travel.to(target.position) end
            end,
        })
        UI.button(places, {
            text = "Nearest Criminal Base",
            callback = function()
                local base = Game.nearestBase()
                if base then Travel.to(base.position) end
            end,
        })

        local waypoints = UI.section(tab, "Waypoints")
        local waypointName = {value = ""}
        local waypointList
        local function refreshWaypoints()
            local names = Move.waypointNames()
            if #names == 0 then names = {"none saved"} end
            if waypointList then waypointList.setOptions(names) end
        end
        UI.input(waypoints, {
            text = "Name",
            placeholder = "hideout",
            get = function() return waypointName.value end,
            set = function(v) waypointName.value = v end,
        })
        UI.button(waypoints, {
            text = "Save Here",
            callback = function()
                if Move.saveWaypoint(waypointName.value) then refreshWaypoints() end
            end,
        })
        waypointList = UI.dropdown(waypoints, {
            text = "Saved",
            options = {"none saved"},
            get = function() return waypointName.value end,
            set = function(v) waypointName.value = v end,
        })
        UI.button(waypoints, {
            text = "Go To Waypoint",
            callback = function() Move.gotoWaypoint(waypointName.value) end,
        })
        UI.button(waypoints, {
            text = "Delete Waypoint",
            kind = "danger",
            callback = function()
                Move.deleteWaypoint(waypointName.value)
                refreshWaypoints()
            end,
        })
        refreshWaypoints()
    end

    -- ============================================================= ESP TAB
    do
        local tab = UI.addTab("ESP")

        local players = UI.section(tab, "Players")
        UI.toggle(players, opt("ESP", "Enabled", {text = "ESP Enabled"}))
        UI.toggle(players, opt("ESP", "Highlight", {
            text = "Highlight",
            desc = "Fill and outline the whole character, visible through walls.",
        }))
        UI.toggle(players, opt("ESP", "Names", {text = "Names"}))
        UI.toggle(players, opt("ESP", "Distance", {text = "Distance"}))
        UI.toggle(players, opt("ESP", "Team", {
            text = "Colour By Team",
            desc = "Off, everything uses the accent colour instead.",
        }))
        UI.toggle(players, opt("ESP", "OnlyEnemies", {
            text = "Enemies Only",
            desc = "Hide anyone on your own team.",
        }))
        UI.slider(players, opt("ESP", "MaxDistance", {
            text = "Max Distance", min = 250, max = 6000, step = 250, suffix = " studs",
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("ESP", "Robberies", {
            text = "Robbery Markers",
            desc = "Name and state floating over every robbery that is open.",
        }))

        local colours = UI.section(tab, "Colours")
        UI.colorpicker(colours, opt("ESP", "ColorCriminal", {text = "Criminal"}))
        UI.colorpicker(colours, opt("ESP", "ColorPolice", {text = "Police"}))
        UI.colorpicker(colours, opt("ESP", "ColorPrisoner", {text = "Prisoner"}))
    end

    -- ======================================================== MOVEMENT TAB
    do
        local tab = UI.addTab("Movement")

        local speed = UI.section(tab, "Speed & Jump")
        UI.toggle(speed, opt("Move", "SpeedEnabled", {
            text = "Walk Speed",
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Speed", {
            text = "Speed", min = 16, max = 200, step = 1,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.dropdown(speed, opt("Move", "SpeedMode", {
            text = "Speed Method",
            desc = "Humanoid sets WalkSpeed. CFrame drives the character directly, which ignores any clamp the server puts on it.",
            options = {"Humanoid", "CFrame"},
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "JumpEnabled", {
            text = "Jump Power",
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Jump", {
            text = "Jump", min = 50, max = 300, step = 5,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "InfJump", {text = "Infinite Jump"}))
        UI.toggle(speed, opt("Move", "Bhop", {text = "Bunny Hop"}))

        local clip = UI.section(tab, "Noclip & Fly")
        UI.toggle(clip, opt("Move", "Noclip", {
            text = "Noclip",
            onSet = function(on) Move.setNoclip(on) end,
        }))
        UI.keybind(clip, opt("Move", "NoclipKey", {text = "Noclip Key"}))
        UI.toggle(clip, opt("Move", "Fly", {
            text = "Fly",
            desc = "WASD to move, space up, shift down.",
            onSet = function(on) Move.setFly(on) end,
        }))
        UI.keybind(clip, opt("Move", "FlyKey", {text = "Fly Key"}))
        UI.slider(clip, opt("Move", "FlySpeed", {
            text = "Fly Speed", min = 20, max = 400, step = 5,
        }))
        UI.toggle(clip, opt("Move", "Spinbot", {text = "Spinbot"}))
    end

    -- ========================================================= VISUALS TAB
    do
        local tab = UI.addTab("Visuals")

        local lighting = UI.section(tab, "Lighting")
        UI.toggle(lighting, opt("Visual", "Fullbright", {text = "Fullbright"}))
        UI.slider(lighting, opt("Visual", "Brightness", {
            text = "Brightness", min = 1, max = 5, step = 0.1,
        }))
        UI.toggle(lighting, opt("Visual", "NoFog", {text = "No Fog"}))

        local camera = UI.section(tab, "Camera")
        UI.toggle(camera, opt("Visual", "FovEnabled", {text = "Custom FOV"}))
        UI.slider(camera, opt("Visual", "Fov", {
            text = "Field Of View", min = 40, max = 120, step = 1,
        }))

        local world = UI.section(tab, "Performance")
        UI.toggle(world, opt("Visual", "LowDetail", {
            text = "Low Detail",
            desc = "Strip shadows and effects. Worth it on a map this size.",
        }))
    end

    KH.SessionInfo = {
        {text = "Team", get = function() return Game.myTeamName() or "none" end},
        {
            text = "Game Modules",
            get = function()
                if not Game.Resolved then return "resolving…" end
                local have = {}
                for name, value in pairs(Game.M) do
                    if value ~= nil then have[#have + 1] = name end
                end
                if #have == 0 then return "none found" end
                table.sort(have)
                return table.concat(have, ", ")
            end,
        },
    }

    KH.FirstTab = "Robbery"
end

-- ─── src/_shared/91_settings.lua ───────────────────────────────────

-- ============================================================================
--  SETTINGS — the tab every build has: interface, profiles, session
--
--  Added after the game module's own tabs so it is always last, and it picks up
--  whatever extra rows that module left in KH.SessionInfo.
-- ============================================================================

do
    local UI     = KH.UI
    local S      = KH.S
    local Config = KH.Config

    local function opt(group, key, extra)
        local t = extra or {}
        local after = t.onSet
        t.onSet = nil
        t.get = function() return S[group][key] end
        t.set = function(value)
            S[group][key] = value
            if after then after(value) end
        end
        return t
    end

    local tab = UI.addTab("Settings")

    local interface = UI.section(tab, "Interface")
    UI.keybind(interface, opt("UI", "MenuKey", {text = "Menu Key"}))
    UI.colorpicker(interface, opt("UI", "Accent", {
        text = "Accent Colour",
        onSet = function(color) UI.applyAccent(color) end,
    }))
    UI.toggle(interface, opt("UI", "Watermark", {
        text = "Watermark",
        onSet = function(v) UI.Watermark.Visible = v end,
    }))
    UI.toggle(interface, opt("UI", "KeybindList", {
        text = "Keybind List",
        onSet = function(v) UI.KeybindPanel.Visible = v end,
    }))
    UI.toggle(interface, opt("UI", "Notifications", {text = "Notifications"}))

    local configs = UI.section(tab, "Configuration")
    if not Config.available then
        UI.label(configs, "This executor exposes no file API, so settings only persist until you close Roblox.")
    else
        UI.label(configs, "Profiles are stored in the KittyHub/configs folder next to your executor.")
    end
    UI.toggle(configs, opt("UI", "AutoSave", {
        text = "Auto Save",
        desc = "Write the active profile whenever something changes.",
    }))

    local profileName = {value = S.UI.Profile}
    local profileDropdown

    local function refreshProfiles()
        local names = Config.list()
        if #names == 0 then names = {"default"} end
        if profileDropdown then profileDropdown.setOptions(names) end
    end

    UI.input(configs, {
        text = "Profile Name",
        placeholder = "default",
        get = function() return profileName.value end,
        set = function(v) profileName.value = v end,
    })
    UI.button(configs, {
        text = "Save Profile",
        kind = "primary",
        callback = function()
            local ok, err = Config.save(profileName.value)
            if ok then
                S.UI.Profile = profileName.value
                refreshProfiles()
                UI.notify({title = "Config", text = 'Saved "' .. profileName.value .. '".', kind = "good"})
            else
                UI.notify({title = "Config", text = tostring(err), kind = "bad"})
            end
        end,
    })
    profileDropdown = UI.dropdown(configs, {
        text = "Saved Profiles",
        options = {"default"},
        get = function() return profileName.value end,
        set = function(v) profileName.value = v end,
    })
    UI.button(configs, {
        text = "Load Profile",
        callback = function()
            local ok, err = Config.load(profileName.value)
            if ok then
                UI.refreshAll()
                UI.applyAccent(S.UI.Accent)
                UI.notify({title = "Config", text = 'Loaded "' .. profileName.value .. '".', kind = "good"})
            else
                UI.notify({title = "Config", text = tostring(err), kind = "bad"})
            end
        end,
    })
    UI.button(configs, {
        text = "Delete Profile",
        kind = "danger",
        callback = function()
            Config.delete(profileName.value)
            refreshProfiles()
            UI.notify({title = "Config", text = "Deleted."})
        end,
    })
    UI.button(configs, {
        text = "Reset To Defaults",
        kind = "danger",
        callback = function()
            Config.reset()
            UI.refreshAll()
            UI.applyAccent(S.UI.Accent)
            UI.notify({title = "Config", text = "Settings reset.", kind = "warn"})
        end,
    })
    refreshProfiles()

    local session = UI.section(tab, "Session")
    UI.readout(session, {text = "Executor", get = function() return KH.X.name end})
    for _, row in ipairs(KH.SessionInfo or {}) do
        UI.readout(session, row)
    end
    UI.readout(session, {
        text = "Teleport Queue",
        get = function() return KH.X.queueteleport and "supported" or "not supported" end,
    })

    -- Only the games this build is not already in.
    local elsewhere = {}
    for _, entry in ipairs(KH.Games) do
        if entry.place ~= game.PlaceId then elsewhere[#elsewhere + 1] = entry end
    end
    if #elsewhere > 0 then
        local going = {name = elsewhere[1].name}
        local names = {}
        for _, entry in ipairs(elsewhere) do names[#names + 1] = entry.name end

        UI.dropdown(session, {
            text = "Switch Game",
            options = names,
            get = function() return going.name end,
            set = function(v) going.name = v end,
        })
        UI.button(session, {
            text = "Go There",
            desc = "Queues the hub before teleporting, so it loads itself on arrival — for when your executor will not attach to that game.",
            callback = function()
                for _, entry in ipairs(elsewhere) do
                    if entry.name == going.name then KH.goToGame(entry.place) end
                end
            end,
        })
    end

    UI.button(session, {
        text = "Rejoin Server",
        callback = function() KH.rejoin() end,
    })
    UI.button(session, {
        text = "Server Hop",
        desc = "Find a different public server for this place.",
        callback = function() KH.serverHop() end,
    })
    UI.button(session, {
        text = "Unload Kitty Hub",
        kind = "danger",
        desc = "Remove the menu and undo every change.",
        callback = function() KH.unload() end,
    })

    UI.selectTab(KH.FirstTab or (next(UI.Tabs)))
end

-- ─── src/jailbreak/92_main.lua ─────────────────────────────────────

-- ============================================================================
--  MAIN — hotkeys, HUD readouts, and boot
-- ============================================================================

do
    local UI               = KH.UI
    local C                = UI.C
    local U                = KH.U
    local S                = KH.S
    local Game             = KH.Game
    local Rob              = KH.Rob
    local Police           = KH.Police
    local Move             = KH.Move
    local Config           = KH.Config
    local UserInputService = KH.Services.UserInputService

    -- =============================================================== HOTKEYS
    UI.registerKeybind("Menu", function() return S.UI.MenuKey end, function() return UI.IsOpen end)
    UI.registerKeybind("Noclip", function() return S.Move.NoclipKey end, function() return S.Move.Noclip end)
    UI.registerKeybind("Fly", function() return S.Move.FlyKey end, function() return S.Move.Fly end)
    UI.registerKeybind("Arrest All", function() return S.Police.ArrestKey end, function()
        return Police.Busy
    end)
    UI.refreshKeybinds()

    KH.track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if UI.Capturing or processed then return end

        local key = input.KeyCode

        if key == U.keyCode(S.UI.MenuKey) then
            UI.toggleOpen()
            return
        end
        if key == U.keyCode(S.Move.NoclipKey) then
            Move.setNoclip(not S.Move.Noclip)
            UI.refreshAll()
            return
        end
        if key == U.keyCode(S.Move.FlyKey) then
            Move.setFly(not S.Move.Fly)
            UI.refreshAll()
            return
        end
        -- The sweep takes seconds and yields the whole way; it cannot run on
        -- the input thread.
        if key == U.keyCode(S.Police.ArrestKey) then
            KH.detach(function() Police.arrestAll() end)
        end
    end))

    -- ================================================================= HUD
    local frames, fpsAccum, fps = 0, 0, 0

    KH.onFrame("fps", function(delta)
        frames = frames + 1
        fpsAccum = fpsAccum + delta
        if fpsAccum >= 0.5 then
            fps = math.floor(frames / fpsAccum + 0.5)
            frames, fpsAccum = 0, 0
        end
    end, 90)

    local function teamColor()
        local name = Game.myTeamName()
        if name == "Police" then return S.ESP.ColorPolice, name end
        if name == "Criminal" then return S.ESP.ColorCriminal, name end
        if name == "Prisoner" then return S.ESP.ColorPrisoner, name end
        return C.TextDim, "No Team"
    end

    KH.loop(0.25, function()
        local color, team = teamColor()
        local hex, dim = color:ToHex(), C.TextDim:ToHex()

        if S.UI.Watermark then
            local parts = {
                ('<font color="#%s">Kitty Hub</font>'):format(C.Accent:ToHex()),
                ('<font color="#%s">JB</font>'):format(dim),
                ("%d fps"):format(fps),
                ("%d ms"):format(math.floor(U.ping())),
                ('<font color="#%s">%s</font>'):format(hex, team),
            }
            local have, cap = Game.bag()
            if have then parts[#parts + 1] = ("bag %d/%d"):format(have, cap) end
            UI.WatermarkText.Text = table.concat(parts, ('  <font color="#%s">·</font>  '):format(dim))
        end

        UI.RoleLabel.Text = team
        UI.RoleLabel.TextColor3 = color

        local bits = {}
        if Rob.Busy then
            bits[#bits + 1] = Rob.Status
        elseif Police.Busy then
            bits[#bits + 1] = Police.Status
        else
            bits[#bits + 1] = ("%d open"):format(#Game.openRobberies())
            if Game.isPolice() then
                bits[#bits + 1] = ("%d wanted"):format(#Game.criminals())
            end
        end
        UI.StatLabel.Text = table.concat(bits, " · ")

        if UI.IsOpen then
            for _, readout in ipairs(UI.Readouts or {}) do
                KH.safe("readout", readout.refresh)
            end
        end
    end)

    -- ================================================================ BOOT
    if Config.available then
        local ok = Config.load(S.UI.Profile)
        if ok then
            UI.refreshAll()
            UI.applyAccent(S.UI.Accent)
        end
    end

    Move.applyHumanoid()
    if S.Move.Noclip then Move.setNoclip(true) end
    UI.refreshKeybinds()
    UI.setOpen(true)

    -- The sidebar indicator is placed from AbsolutePosition, which is still
    -- zero until the window has been laid out for a frame.
    task.delay(0.35, function()
        if KH.Alive then UI.selectTab(UI.ActiveTab or "Robbery") end
    end)

    if game.PlaceId ~= 606849621 then
        UI.notify({
            title = "Not Jailbreak",
            text = "This build targets Jailbreak. Most features will do nothing here.",
            kind = "warn",
            duration = 8,
        })
    end

    UI.notify({
        title = "Kitty Hub v" .. KH.Version,
        text = ("Loaded on %s. Press %s for the menu."):format(KH.X.name, S.UI.MenuKey),
        kind = "good",
        duration = 5,
    })

    print(("[Kitty Hub] v%s loaded — executor: %s"):format(KH.Version, KH.X.name))
    print(("[Kitty Hub] [%s] menu · [%s] noclip · [%s] fly · [%s] arrest all")
        :format(S.UI.MenuKey, S.Move.NoclipKey, S.Move.FlyKey, S.Police.ArrestKey))
end

-- ─── src/_shared/96_logo.lua ───────────────────────────────────────

-- ============================================================================
--  LOGO — the Kitty Hub mark, carried in the script rather than fetched.
--
--  Roblox only draws an image it can resolve as an asset, and this one was
--  never uploaded to Roblox. getcustomasset turns a file in the executor's own
--  folder into an asset, so the mark travels here as base64, is written out
--  once on the first run, and is read straight off disk every run after.
--
--  The name carries a version because the file is cached: change the image and
--  the old one has to stop being found, or it is the one that keeps drawing.
--
--  An executor with no file API gets nothing back. Nothing may assume this
--  returns an asset — the splash draws the wordmark as text when it does not.
-- ============================================================================

do
    local FILE = "kittyhub_logo_v2.png"
    local STALE = {"kittyhub_logo.png"}

    local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local VALUE = {}
    for i = 1, #ALPHABET do VALUE[ALPHABET:byte(i)] = i - 1 end

    -- Whitespace and padding read back as nil and are skipped, so the blob
    -- below can be wrapped to a sane width.
    local function decode(text)
        local out, bits, held = {}, 0, 0
        for i = 1, #text do
            local value = VALUE[text:byte(i)]
            if value then
                bits = bits * 64 + value
                held = held + 6
                if held >= 8 then
                    held = held - 8
                    local scale = 2 ^ held
                    out[#out + 1] = string.char(math.floor(bits / scale) % 256)
                    bits = bits % scale
                end
            end
        end
        return table.concat(out)
    end

    local DATA = [[
iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAABpFklEQVR42u29d5xkR3X3/a2qe2/nnp48szub82qTVtIqSxZC
YIOIBptoDDaGFwMPjtjGAWPMYzDG2PjB2YAJNjYmCbCxEEIoh12tNuc8eXqmc7ih6v3j3ukdrbRilVdSH30KpJme7r5VJ/xO
LGGMoU1nJ60NxgAGpBII0fqVmF2+p0U+32RspG7GR+t6bKRmxkbr5Kca5KealEselbJHvR7gugGeqwkCg9bh3kspUEpgOxLH
USQSinTGJpO16exy6O1L0D+YoH8gIQbnJ2T/YFL09MSwbBl9s9bCGFrvK0T43m06O4m2ADyc5jKQUg9jHgHIwowrjh+tmEMH
isHhg2WOHykzfLLGdD5kdNcNCHxjG+gQgm4pRU5K0kKKQSmEFIK0kKL7TLY0gNEmbwwVbYw22oxqTUVrUzCGPFBUSnixmCSd
senuiTNvKMnCJWmWr8iyfFVWLVycFl3dMQPoWYEACILTgiba8tAWgLMx/RkaUwDy5PGq2L1jJnjwgbzZu6vA8aNl8lNNGvUA
YJ5SYolty5WWLVYpJZcJyQIhRB/QjTHZ2fef+1mPeSDiUf5diBKQx5gJrTkZBPqw75n9nqcPBIE5CozE44qu7hiLlqZZs66T
Cy/uEhds6FQLF6cfJhCzFq0tDC9wATgL08tiwZUPbZ0299w5EWy7b4qjh8oUCy5amwHLlhfEYuoiy5KbpWQdgsXGkDIGjDFz
dO4jlXvEhI+H5ByYdcapgRAhAwtBFcMxrdnl+3qb2wy2ep7eLaQY68g5LFmWYfMl3Vx2dZ/auLlb5DodPftd2sLwAhSA2UOf
A2/k+Fhd3nvHRPCjH4yah7ZOMzpSI/B1t+Ooi2Nxda2yxFUCNhhDhzHmTC1ugOAMqDSXcZ8sa5kzBGnup6uHvb8AGQpG0cCO
wDd3NJvBbW5TP6AskR8YTLDpom6uefGguPyqPtU/mGgJQxCYF6TP8IIQgFltP4fpRbHgyjt/NGZu/t6IfuCeSSYnGgjBikTC
us5x5MuE4Cpt6DbazOU4PUeTn11DP8OPd4aFkdEKv5wUSEHeGO5wXf29et2/1RgO9vbFuejSHm542Xx55U8NzFoGMysMLxSr
8LwWgEdhfPng/VPiu984Gdx2yyjDJ6oIwfJE0rrRduSrMVyujXHmbMksw4s5DP+cePQ5uP+0QIQWwkVwt+fqb9ZrwXeMMYfm
L0hxzfUDvPw1C9XmLT1mrlV4vgvC81IAjDboOTCnXPbUzd8ZNt/+2nH90LY8zYbuSiTVy2Mx9UbgOq1NfM42BGdo+OfFlsyx
EGpOiLQB3NpsBv9WrwXfjcXk9PrNXbzqdYvkS24cEpmsHbQEQYTWpC0A57XGN2jdYnwxNlKTX/+3Y8F3vn6C40cqWJbclExZ
75CS12ltBuc8uv8c1PJPhXWw5gjDqNZ8rVbz/8Xz9PbFS9K8/LULee0bF6vB+UkNmNAihA54WwDOX6gjThytyH///OHge986
ycRYXSZT1o3xuHqPMdygtZHPY03/pC2DlEILwc2NRvDZWs3/Tm9fQr/s1Qt4w9uWqUVL03ME4fkBjZ7zAhAEpzH+qRNV9cV/
PBh87xsnmM67TjpjvcVx5PuCwGw6Q9urFzDTP5YwBHOtglJiu+vqz1TL/pdyXY778tcs5K3vXKGGFqWCM/e+LQA88+HM2ZDd
dL6pvvSPB/V/feWomZ5sOums/WbLlr+uA7Muer65DmGb8c/NKghACiGQSuzyPf2pStn7cld3zH3tm5aIt7xzhezuiQVnnkVb
AJ4BuGNMuOG+r+V/fvEo//r3B/Sp41XSWfsXbUf+RhCYdVHsMpiD7dv0BPRMJBCK0CLs8jzzF5WS+/n5C1L8wrtWyte/dQm2
LXWYVHzuwaLnlADMMbni7tvG1Wc/ucd/aGueZMp6aSyuPhwE5rI24z8jgnBPsxF8uFYNvr9hcxfv+a211hXX9gez/sFzCRY9
JwRgrtafGKurz35yT/Cdr51ACFam0tafam1ep9uM/4wKggwjR1+rVvwPGcOBl//sQn71t9aqvoFEMFti8lyIFp33AjBX63/n
a8fV33xitz82Uo915JzfAj6otUmfkQVt0zMjCGHQSIoK8PFSwf3z/sFE81d/+wLrFa9f9JyxBuetAMwNbY6P1tVf/PGO4Aff
GSaRVNc6cfXpwDeb5oQzVZsnnx39NLv3yhLb3WbwgVo1uO3FL5/Pb/7RBtU/LxGc7yHT81IA5kYVbv7OsPWXf7LDHx+tJzpy
zoe15reMMYJ2OPO8C58KIYyU/Hmx4H64byBR//U/XG/dcOOQfz5His47AZg1m416IP/6Y7v4j389ouNxdWUsLj8b+GbDnOKv
Ntw5/2CRAISyxI5mQ7+nUQ/ufP3blsr/83vriCeUPh8h0XklALMbdORASX3kN7cGO7bN0Nnl/I4x/InWxkLgzyZq2nTeko/B
klL4QvAHM9Pun63f3MkfffIitXRlNjjfhOC8EIC5UZ4ffGfY+vjvb/crJa8vnbX/wff1q9pa/7lrDSxLfqtS9n4lnbYnPvin
m6wX3zjfP59yBs+6AMzBhuIf/nKv+pe/2u/HE+oa25FfCAKzuI31n/u+gVLimOfqtzXqwY/f/v5V1rt+fU0AmPPBL3hWBWB2
Axr1QPzpB7eJ//76Sd3ZHXu3MeYzxmBFzN+GPM91SASWEPhCiPfNTDf/7mdevUB+6BObTTyhjA4M8lmERM+aAMxiwanxhvy9
99ynt9+fp7Pb+Uzgm/caMKINeZ5XkMiE9XVCWeJvZvLu+zZd0s2ffnaL7O2PP6vO8bMiALMPfPRgSf3Ou+4NTh6rprI55998
T7+iDXme/5DIsuVNpYL7xqHFqeqf/d2lz6pz/IwLwOyD7npwWv3uu+8NijPuQCpt3+T7+mLAA+w2rzyvyQNsy5IPVCveK7I5
Z+zP/v5Ste7CrmdFCJ5RAZh9wAfumrQ+9P/d57uuXhuPq28EgVnZxvsvPL9AKXGg0Qhe4zhyz5/+7Rbr4it6/WdaCJ4xAQh8
g7IE9/54wvr9X73P15q1jiNvCQIzINrx/RekEBiDpZQYc119vZTs+ej/22Jdek2fP8srzxsBmJXq+26fsD707vt8BGttW94S
aDMg2rU8L2QKDCglxZjn6euNYc/H/naLteWavmfMEjztAjD7INvunrR+51fu9TGstWx5i9ZmoF3I1qZZHpBSjPmevh7Bnv/7
D5daF13+zMChp1UAZh9gz/YZ9ZtvvzvwPb3WdmaZX7SZv01zhMAoKcWY5+rrLVvu+eTnLldrN3U+7Y7x0yYAs0mu44fK6gNv
uSuolLzVsYS6VQdtzd+mx7AESow168F16ay979NfukItWp4Jns6M8dMiALNfOD/RkB9485169FRtMJGyfhz4ZrkQbeZv02P4
BAalLHGoXvWvGRhKjv7Vl6+U3X1x/XQJwVMuAOHbGZoNLX7zF+9mz4PTyUyHfZvvm4tEO9TZJs4hOgSWZYmt5aJ37QUXdtX+
/POXE4tLA099AZ18qnN9UaWf+OSHtqud9+fJdjj/HrSZv03nTpYAP/DNRdkO59933J/nk7+3XQkhhNZnHUH/xD/sKXd6LcG/
fma/uvkbp/yu3thnfN/cKIRoZ3jb9Hj50gsCc2NXT+yvb/7mqfctWJqx3va+lU95juApg0Cz3vqPvz9q/fH7HvAzWftdWpu/
a2d42/RkM8ZSineXS97ff/gzF1tXv3TwKQ2PPiUCMOugnDhSUf/n5+8IfE9fqSzxI6NfMANn28TTN6VOSEzgm5+ybHnnX331
KrVwafopiww9aQGY7ebyXC1/4y13mUN7il3JtLU9CMxQ1BnULmlu05PtLpNKiVO1ir9p+dqO6b/40hXCdqR+KrrK5FOk/cU/
f3Kv3Lt9xqQz9hd0YIYEBAKkOOPOoPZqr8e5pIBAB2YonbG/sHf7jPnnT+6VUkZO8bNpAWa7ee68ecz64/c+4Gc67A9qbf6s
jfvb9DT6A79TLrof/6O/ucS68oYB/8l2lD1hATBRj8/0ZEO9/3V3BJWSt8Wy5V0mfMN2Q0ubnpaGGiEQvmeuSGft+/76a1ep
rt54gDFP+PYa+WSwvxCIv/vYbvIT9VgsLr9gjFGC2ds72+a7vZ7SJQQIY1CxuPxCfqIR+7uP7UYIxJNxY+WTgT633jSsbv/v
kSCbc/4kCMxqIfAR4QTh9mqvp2EpIfCDwKzO5uw/uf2/R4JbvzOspBLowDwzEGgW+hTyTfX+190eVEve5cqSdxpjdDvk2aZn
LDQqhPR9fWU6Y9/91/91tcp1x54QFLKeCPSREvGvf7WfqbGG3dHp/FPgGyGEEG3mb9MzQCGfGUQspv4pP97Y9K9/tV//nz/Z
ILTGiKcTAmkdQp8d9+blLd84FXTknN/WgVkrBH475Nlez2hoVODrwKzN5pzfvuUbp4Id9+alVILHGxo9Zwg0m/DSgZEffOvd
5vCe4uJ40tpltIlzftyY3qYXHhQyQopGo+avW7a249jHv3i5kEo8rgSZfDzYX0rB//7XSbFv+4xJZay/NMYkQ2OEaKul9nqG
l0BgjDHJVMb6y33bZ8zNXz8ppBShn/pUWoDZl1SKrvrA6+4ISgXvRZYlbjGm3dzSpmedAiFQvmeuz3Y5P/z0f16p0h1OMHvV
61NiAUx059O3/vWomRiuy1hMfgITOhzt1V7P9sJgYnH5iYlTNfntfz1mhOCcrcBPtADh7wX5sYb1az93h++7+q1C8q+0tX+b
zqd+YoEyml+wHfnFT/3nVVZ3f9w/FysgzzXj+60vHNGlfNO2LPH7ItT+7Wxve50/WWKDsSzx+8V80/7WF47oMENsnhwE0jq8
6nJiuK5+9J1hnc7abzTarESgEcj2zrfXebIkAm20WZnO2m+87aZhPTFSV0IIjH4yFsAYhEB89yvHgsqMZ1uW/BAII8L7Pdr/
tP85n/4RIIxlyQ+VZzz7e18+HpyLFZCPnfEVzEw21e3fHTHJtPUmrc1KAbqd9Gqv87RvQGttVibT1ptu/+6wmZlsKikFjyUD
8rFrfhA/+PrJoDDVlI4jf1uAEXPKPdurvc67BcZx5G/PTDXlLV8/GSAQjxURkmfV/kpQr/rqxzcNm0TC+mmtzdpI+6u2tmmv
83SpyAqsTSTVT99207CpV30l1dmtgHW2mh+lBPfeMq5Hj9fIdjq/HgSa8/a67za16YwqiVjc+vXR47Xv3XfLuL72lfNbPH1O
FiDCTfK2bw1r25YXYLhOIEwb+7fXc8MXEAbDdbYtL/jRt4a1McizTZCQj6b9hYDDuwry4EMFEkn1bqONjJrc27H/9noudI4F
RhuZSKp3H9xR4PCuohSCR60UtR61xg7E7d8d9T036Iin1M9H3TbtrG+bniukAKQSP+81g9+/43sjxeXrOwTmkYMV5aM5v7Wy
rx68fULEk9YrjDa90ejqtgPQpucKCUIr0BtPWq/Y9uMJUSs/ujNsPaLoTQl23D2lJ4frJtPhvDUIjGlzfpueo76wicXkWyeH
61/aec+UvvSGgRaPP6oAREEeed8t41pKsQTBtbM/a+9mm55jJCNbcK2UYsl9Pxg/eukNAxKBflQLYAwIKSjmm3L/thkdT6hX
GW1i7bHmbXoOwyDfaBOLJ9Sr9m2b+XQx78qObkdHBZ5nCEBkGnbfm9fFqSbpnP1aHYTZ4PZetuk5LATYjnxtcar56d335fUV
PzP4MBgkH/5S5IO3T2khWAJc9rRcotGmNj3TMAguE4Il22+fDEf3iDMg0GzhW63sy8M7izqesG5AYwtEG/606TkPg9DY8YR1
w6EdxX+oVXyZTFstGGTNhT+HdxbM9HiDZNp6eZQQa8OfNj1fYNDLp8cb/3B4Z8Gsv7ynxfNztbvYe/90oH2dE4JrRBv+tOl5
BIOE4Brt69ze+2cK6y/vEbMpXwtAhAkCeXBHIXBicguGnBDtyy3a9LyxABpDzonJLQcfmvlfY5BCigBAGm0QQH60LsaOVXFi
6kVRukw/6fl1Iuwdk1Igo38/57+PXi9ewDhsdg+lFCh1ekn5+Pbyke/77O6tCMsUQr6Qp5+Jp/OWGWNwYupFY8eq5MfqYnZy
hGVM+IWO7S3patEn1WFfpQODeIKlD0KGzWnGgPY1gW/QJiwjVbZEWRKjzWN36ShB4BsCXyOEwHIkkkcvZpr9rOed3Y7S9r6r
8VwdTT82CCFQlsCOqXPay0d7Xx0YAi8selT22ff2aWH+iKtqJb8lCIEfjtxMpCyMiQp2zFPvByhLXFUtehzbU9Y9gwmMASv6
HHFkZ1EbTK8QbHwi2V+pwolczUaA7wZYtiSZtcl0OThxie9qZsabVAoeibSFsmbHLc552AiZVUsemZxN92ACt6mZGW9gNCTS
0QaZcDgkhLdTCkBa4jGZISxjDaXlJzFMa8KwMc+4cEkZzreslTykJeiZl2BgcZKugTh2TFIpeEwN1xk5UqUy8xh7eRY2qJXC
v8n1OQS+oTjZxJjTe4t5+hSKEOFo/cA3XHnjIOuv6iGTc5gYrvHgDyfZdXceJ6bCzi4VsYN5Sv2AjcaY3iO7CpMXX98nDBgr
Mj3yxP5yYFtyA4a0eByX20kp0CY8MMuSLFqVZs1l3ay6sJOhJRk6Op3Q0/BhYqzG/T8Y5/tfPE6jqLFsibAMyo4OUIMONK/6
laVc8bJBenuTNN2Aw3sLfP+Lx9l15zQxx0IoaPg+xkAyY4UMU/SwHEksoU5rM3Oa8b1m0NI0TkyCeOQIPSkFQWBw60FoHh2J
bUu0eeovaD6bEqlVfBxHcunPDHD5ywdZvb4LO/nIoxg/VeOu747ww6+epFE0WLZE2gZp8aiTEAzgNzUvfcsirnzlPPr7Unh+
wJH9RW7+8gl23pkn5lggDMo5rYx4iqd5GgO//JF1XHx9f+vHay7q4tpXDvHD/zzJN/9pP5alaBTD16vYU/I9Zv2AtG3LDSf2
l28BpJQiEMYYqiXP+uM33eNXy95vKyU+jnmM8ofZjRFR7qDiY9uSjdf2cNVr5rN2c3cLPGk0k7pKyW+SVjEGVQaAw7sK/OcX
t9IoG8onFPVpgZ2EZs3nbb9/AZe/bBCAsaBMVsVI4oCBr3xmJ/sPjNDISwZ6urj2dUMsXJ7F9zUHdxS49d9PcvJghVjs9EF6
zRBK9S9MkulyqBY9xo/XMNoQT1stYRFCUC/7xFOK/kVJrJhkerTB9GiDWEJhOQKtZ0eynrEXT+JYWml5AbWiz9rLu3nVu5ey
7IJcCBVw2VufZNgt4pmArIqzPNbNEqcLgGMHCtz0rQeZOelTOGzRmAYr8bDSdoQU1Ks+b/qt1fzUzw4BMGPqJIRNPDrmf//M
bnbtPAUNm+Lx8FmVE3mCT4EwSCWoFD1e9vbFvPY9K5h26/xL8X6O+zNsis3jTblNJKTN/bv3sOfIEbx8jGM/kkwflFjxp+R7
+AisIDAfTGXsT/zRVy6zUlnbtwAmTtVNueDixNTmaBDcT3iYcGZQteiz9rIubvyVJaxY3wnAdFDj9sox7quf4JCXZ0bXaZoA
S0jWOL38VudPsWxdjtf8xiK27d+LbMY4dadi302w4doeLn/ZIEW3wUenb2Frc5ikcHhjZiNv7ryQN7x/Nd++b4TuZCdXr9v8
sC86sCjFxdf1848f2c6pEzMIz6Z4StM1P8brP7CCDZf2omIC48H+HdPc9A9HOLC1iONYSAsaTZ/NL+rjxncuZWhpGoBqweP+
H47x7b8/Sm0mQFmRxXLmaNkne02nDJ0xt6F59XuWceM7lgJwvDnDf5Z2cmfjGONBBc8ELQc2KWw2xebxgc6rWLyykze9fwO3
brsXr6Q5+WPFydsthAUiNHQ0qgGrL+7ip352iIrn8ufTt3F34zhxYfH6zAbe2rmZn3vfSjJbx6nWGlROWRz4pkVlRIbPap7c
c4poxlQyY3HVK+djDHxi+kd8p7aXnExwa/0wJ/wCf9TzYlYvW8Sx/Alkj0/nSsHe/7AZvV9hJaI9f5L7bVlic7ngMXmqblJr
bSxAjB6pBH5Di3jCWh81v8jHgjyeG57+639tBS950yIATjaLfLW0gx/VDjMeVJAIHKGwhEQhwQjuqB1HcBt/1f9KBpIDSO8Q
0taseKWm0YBLrh0AA/9R2sF/Vw8woDKUdZNPzdzBylgvlySGGEgPsnbRMkDw1ZkdfL28i7i0eWv2Ql6cXc47Prqa/7n3DnzX
p7DX4dUvv5CBJUlqxuVwY5oFTo7VF3Wx7DM5vvT/tjGen6ZwRLJmQQ/v/r8bABj2SpSCBmtyffzUaxeweE2W//zyAwR+QOGw
ChkjZp4STGw0BL7hHR++gC0vGQDg89Nb+VLpQYq6QVLYJIXTipIYY9AY7qgf55g3w98OvJpBp5t5mfkcrZ9g1Wttkr2G/f9l
I+xQ+weeZv3V3RgDN5X38l/lXfRbGQq6yV/O3MEKp4fLkgvpjHcxM32SzqWKjb/k8uDfxmjkBdJ+clhcSIFbC1i4JkPf/CTj
QYX7G8MMyCwCiEmLO2vHmaFBt53EUQ61agPLEax4pUfxmKQ5I0J4Z56cHyClWO83AjF6pBosXpsVFsDo0SoI+oVgceRbirMx
v9sMSKQt3vGRday5uAttDF+Y3sa/lR9ixq+Rkg45kZiNPc35woKcSHLSLeFLQ9y2UZYkCDS1guGCGx0uvKgHH81t9aN0iSQY
iAubmvY57E1zSXKIgd5esskUe5uT/MX07ThCERjDR6ZuYUW8h0V2jlyyg1P1ca5+7VIG5iXZW5vgQ5P/y3hQISNj/GruMl6R
W8Pr3r+Smx+4A78hePHmUPN+aXo7/1C4FwMst7v5w57rWbKmk5f96hA7D+/H0jFO3q449r+hln1yAiBoNn3e8ccXcMkNA5S9
Jh+ZuoUfVg+TVXFyIoHGIIygrn00hpiwAEGPTHHSLfK5wlZ+r+86ls6fz7HxUzSKgvlX+lTHJSd/bKFShlhSsXx9DiHgvvop
MiKONIKEsKlrn6PeDJeJhdi2BQK8CsRzhoXX+uz7TycUdv3krFzgBSzf1AECHqyOUA5cOmQMjcEzmh6VIiEs/CAg0DqMVnlg
pw09qwNO/thGOU/qe4hI6SxG0D96rDI2KxVy8mQNS4nlGJKCR5/7KaXAdzXJtM37Pr2JNRd3Mdos896Rb/M30/fgBZqcTKJQ
YARNHRBo08LMwkBT+yy0cjhIys06vu+jpMD3fQa6e4nFLbbXRznSnMHBQhvwtSGOzYZ4aB0SsRgIuK92EmMEKREjI2L42jDh
V0LfRIVWpy/ZDwY+V9zKMbdAWsSoBC6fmr6TUa9MWmSxgxTJWJKuTJZJv8q/FB4AI0gIhwcbo3x25m6Mht54H7phYbRhyU/7
LLrBJ2iEh/tEeleVEtRKHq9811IuuWGAktfkN8f/m1srR+mWKYSRaAPaQCloMs/KssLuae2ppwMyIs7d1ZNUtEtvtpNUPIFB
4zcEQ1f7xHMGt27oHoyzYFmGinE57E639jbQBtsoljndob/RaIQ5AgWBK8gs0NjxkOmeyDPOmd6MsiSrLgr9lgfqw1HESiCM
pKkD1jh9JIXNZLlAw20iZzcWcDJPWa+wwZC0lFg+cbIeymbgGzE93sCy5fLwrguCR/xxlDQQwC9/bB0LV2Y5XJ/mV0e/zdba
CN0yiUQQmFBbFf0mvSpNUjiR4ygQSDxtuDA+L4xizOTxdQBCoJRi6eACAL5fPoivDcJIpJE0Ap9VTi9rYn1UGrUQTgE76+Oo
iElcrcnJBMti3RhjKFbKpJJJurNZysZlX2OKrIjja00cG09rJv0qQoIRms5sBwbYVhuhGnjEhI3WhoyIMe6Fr3MsFV3ILHDL
MP8Kn1SfQXutgUznvKQSNCo+F1zWxUvfthg/0Hx08tZwL1US3xiECWPzgTb8Ws9VfH7odXxuweu4IrmQWuAjjUShmAkaHHNn
UEqRiMfRRmN8QbzT0LVC0yxrFqzOYMUk+2qTTPk1bFQkRJpulWRNvBcdaAqVEkpJ5o4TfLzP9mi8oz1Nrtdh+bocPppdjQni
kRAKEzrcFyXmAzA6M4nW+mGRo2ZBPPnvEa5AYLBsuXx6rE7gGyHLM66oFDyUJVedvo314UsqSaMS8Mr3LGPlpk5GGmV+Y+x/
GHUrZEUCzxiMCW1H0W/yls5NfHTgBlytQ3tiwti2g8XmZPigE4U8Ukg836enI0dvRyfTfp07KydICIfAGDCSptb8dHoFAhie
niCmLDw0h5szxLDBCFytWWR30qUSlGoVPN9nsLsXISW76mNMeDUUChO9tlMmWRzrJAin/zK/px8BPFAbRuvI2TKCRhCw3OnB
YCg36wQ6wAt8MAIrAen5BhPIMG9wjqPLhAiDzHZM8Zr3r0Ai+MrMDm4uH6FTJnH16b1saM0f9F/HG3IbiEsbASy0O/G0xkR+
lac103491JS23WJeIQ3ZhQajYcWFOQzwYHWUpo48yWhvl9jdZGSM6WqRWqOBEjKMTFmG+pQkaIqwdv4JjmqTUuK5mgWrsySz
FgfqeU55JWysMNFnDCkRa/HFZGE61P4mdOL9hqB8UiEtOBt/Pq6FQFlyVaXgUym4QhYmm7pZCVAhBOLRoE+z6rN8U46fev0Q
XhDw0YnbGG6WSIsYvtERxBFUfI/3917O+3sv52Azz7TXwEKBDhlvwMqwKt6D7/sUyiUspdBas2xoEQL4n9JBxr1qpKEErg4Y
tDLckF2OMYajI6cwUUF3WsQo+y5GQ9FvclFiPgZIJpL83NUv4bJV6xHA1toontbhSF8jaQQB6+L9ZGUMJSWvuOQaFvcNEhjN
zvoEjrBbVssYwRXphQgEQ129/MyWq1nUPw8v8MNxxHWB0GGW+/Fo/3rF56IX97FgeYYTjSKfn3mQDhGPhB6UkRR9lzfmNnBD
ZjmlRpXpSjHUkG4ZaWSIjaK4uheFpKSQc/q7BU5Wk8parNjUiQAeqo9hozA6jCZ5WrMu1h8ppBmCIGgJqZSC2imFMPLJWwDf
sGJzKIRbKyPUIwsmjKAZBCyyO1nodFBrNihXq9gqTMpJG+oTgsakQNkRlOYpgGNKLG9WfAoTTS0LE03texopWThXSc0uGUUq
bnjbQpSUfH1mL/dUTpKTCXxtQAuUURR9l7d2beKtXZswGO6unMQi1CaS8EFXOz3EhcVEcYaG20RrTVe2g0W9gzS1z7cL+0lg
h6UTRlINPF6WWUmHijMyPcXY9BQTxWkUgg/2X836RD/CCF6aWcHrOi8IsbWUTJg6BeNSDly2VUeJRdpGmLC8YH18gELQYNQr
M0mdUtBkR32cYbdMzITwwNeaLplkqdNF3q8xpRt0ZTq4ct2FLOwboFiqYXf52BmNbopWyPHMpaw5dTxWCGrtmOTKV4ca78vT
Oyj5TaxZxtQhJl5gd/BL3ZvRxvDgwb1IE1YnHm0WcLAwOhxUKbQkFk2sCeZABwEYEdC3KMHggjTTQZ1DzZlwLyIrZ6PYmAgj
T5PF6VakyQs8amWPsT0BWvtIJc6qUFX0u1lnV53xWowhnrJYtbkLAWyrj2AZFZ2HxNUBG+MDSAQnJscoVSv42ifQGmVD+aQi
aAqkekpmhwohQEoW+p5mZrKprcJEw5jAWFKIPh2aT3E6fAVuI2BoZZoLLu2hErj8+8wuUiIWOmOERW61wGNtvJf/r/cSDIaq
9thbzxMTdnioQhJo2JgYxADjhTzaGASGNYuXoaTkOzMHONSYJqfiaG3w0PSpNK/vvAADHDh5FCUk2w/to7+zm3WJPj636DVM
B3V6rCQA5cDld0/dzO76JClpYwlJMWgSI9LqhOb23/M7+bf8TpraRyCIyTCSpIwMvaDTFVT8xsnv4+qAqnZ5c9cG3tl3EeuX
r8J2bJa8vc6powX2fVVRP+kgY1HUS0fhR19TLfstBgmFRLBgTYYla7LM+HV+XDlOSsSihFy0n77PK7tWk1IOh0dPUapU6Mxk
OeEWOdUshwJgZjuaFDkrHjKu77WK5IQMs99L1mcRCnYUxpn262RVDG3CyEu3TLE60YvWmlKlHMYrjGF+Xz8JlURcLjiyrcTY
sSqJlMWsgWmVXESlFU5CYTsStxHgNTWJjNV6Zq+p6RlKMrQ0TTFocqAxTVxYrZi+NJKLkvMIjMZxbFYtWorruRTLFRqNKlN7
LSw73Dt+UqnHOUaCpBB9JjBWYaLhW8XJJkCngO4zUztSCLymZvVlXSgluHP6BCfdEjkVJ2hlJQS+Nry9+0KsaIf21acYa1ZI
KQdtNNoYksJmY3IAAcyUi3i+z5LBIRb2DVINXL44tYN4xKhKSAp+nbf3X0iPnWJ0ZorhqXHSySTrl64iacda36/HSuIbjRKS
nbVxflw6Qb+dohJ4BBisM1IalhCUfbeVVAJDQwcYTMvBBoMkFIYZr4FC4BvDf83s5S09G8gl01y2OswZzCwr0JHeza0fbRJU
bYww2IlQcaSyNle+eh5DqzIEvuHkvjJ3fWOEoZVphBTcVxhmyqvToWIh/AECY8jKONd3hGHZfSeO0NfZHWL4yihl3yVnhXDJ
YEgIm24rFTqLrtuqkQKDCQQrNkeRl+pIqARkOE3fDXyWxDvpUDGmy0VK1SrZVJrL1m6ktyNMal56AXgNzW1fO8l3//FouCca
pAXSNviu4bo3LODilw6QyTrM5Btsu3mcu749ijACy5J4jYDF67JIS7CzOM6UVyOtYhhj8I2mV6W4ND2EEpKlffNZ2hdaRt/3
OT4xzmh8mMlqhXhggzRhKPSJ1wiJ6H+6gc7iRHPSqsx4SClyCJF5ZIVt+BBL13cAcE9lOJwQGi1BGO5c7HRyRWYh2hikENxf
GQlxtwxxt2sCBu0MS+OdeL7PVLFARzLN5pVrkQg+N7mdo40inVYcg6EW+KyK9fDzXRegjWHXkQNIIblmw8V0Z3M0TcD++iTz
nAw5FW/hu8WxHIucHCNuBUsIUtJ52DAwgaAcuMz2w80+ri0kcWmhW7sqCdBUfTeEgQga2ueq9EJi0uKW4lGmvBpXZIZYEMvx
kqsuofqee5g6Vad2wmH0PuhbkOKX/mwdfUPJ1udf/jK4/MZ51Os+ALsbk6EmlGFNhERQNwGr4t0sdDqo1GsUK2U2r1iDAO6v
joQNrUYgIuzfayfosZM0mk2antuyAEFgSMRjrFjXicbwUG0cR1hoHSk2bVif6AtLTmbyGAzXbLiIjlSGE80id5VP0m+l+anc
Il78lkXklsF9D+1Blx2mtlvkDxl+/ndXcFUE5TSGrnlxlq3PseSCDr75hT3EE9A8CMsvDMs6tlZHCbRpFRs2As2FyR6ONgvs
qk1Q1x4p6bA4lmNDqp9l8+bzq58c5Nbv7WP71pPUj8epnJIIFfoHRj/hBExGSpGrFLxJqzLjIoXomi1NmWsBjDY4cUnvvGSU
ni+2sOqsuW4GARsS/cSihFQYbRiLcGq42a7WrIx34wjF8elRdBBw1YWXkoknubc8zFemdodaUJvoCnD4tYHLSCibw6MnOTUx
zvplK+jO5jhSn+Z3T97KKbdEVsX41YFLuLFzBdoY5jkZ/nHpK9hTm2Lar/P341vxjG4NiHFNwM91XcCSWA5LSNJR1dc9lVPc
NH2ApLLDyASaDhXnPf2X4KCIK4uUdLgsM59PjdzDv04+RExYpJTNR4eu46qOhVx81WLu3/8Q8y/XdKyS/Mw1F9E3lGRneYJv
TO/DlopXdq7kgpW9rXMY8SqoyE8iunfHCzQL7GzomBancWyb/lw3Ve2xszoZwbmwLNrTmvl2FhvJdK2C53tYygpDnM2A3v4M
uQGbQ81pjjdLxEQInQxgIdmQDPH/aH6SBX2DdKQyHKjl+dVj/820X8dguL6whI8MXcfFly8gnzhGuVmlc2OTFUd6uerV86n4
Lp8cvptttVE2pwb5wMClXPzSAdxFoxwbO8XiQpzVW0IHeEdtPIz+6DCflRA2+2t53nX4O1S1x2wO1haSBbEsb+5Zz6u6VvHS
166le7PH/iMnqB1OcOJ/bOp5iRU3j1cIWpVsUoiuyoyLVa/6SEVWmFYVdisXrLUhllCkMzY+mpLvIo1EIyI4JggMLHBCC6GE
YNgtc6hewBE2gSGED9qwIRlGG5qey7WbL6U3m+NwY4Y/PHlbiL21QAnJlFvjnf0XsiUzn0qzzo7D+3Fsm/m94WF9bmIHe2t5
+u0URd/l46fuYlNqgCEnQ7FWYSCRZqAjze7aJGXfIyltDIYAQ0o6vHvgYlLSftiu7KhO4GpNUoZWoe77XJNZxM93X/Cw1424
Zb6ZP0C3SmMLyUzQ4J8mtnNVx0K64p0I16ZaD1h5eScLVmYYbpT5tRM3k/drSCTfLRziM4tfysZ0P1IIKr4P0bPP7qc2gowM
MX2lXqO7I4eUkodKw4y6VdLKQRuDItTiy2MhxJmplkO/KrolPWjCgiVdGAn3F0eoBB6dVjzC/4YulWRNsgeMoVApceGKNQD8
1/Q+prw6fXYKbQz/WzjKz+SW86KOJaSsDqYmK6AMF74qhzHw34VD/Mf0XvrtFF/N76VDxfnA4KUM5vo4cOw4Q0tSdHQmGHbL
HG2UWnwxy2bVwEeh6FR2izu1MQw3K/zRiR9zslHivQOXsGH+OkZHZ3DWVcksDjjw5RjlYwoVf9zZYSOMEUKRbVR8ZLPmI6Xo
j7xkfcZtG0gZjUsnbGxhDgQKVwghZml7ZZyi1wyxtwmLoBLCZn2yH20My+YvZDDXzd7aFB84cjNl38PGQiGZ8Rpck13Er/Rf
iMawbf9uKvUa2VSKvmwnVe3xUHWCnIzja0MCG08bxtwKAHft3s7B0RMExnDzzFFcrcPMZhT+XB3vISktpqsl7t77EF7g0zQB
d5ZOEZ8T/tQGLk6FodE9p45ycPQkgdHcXRqmEQTIKIRoo1pYVIjQUTNouhJdGAO3l0+Q9+r0Wim6rQS1wOemwsEWTlezNncu
rIzKHsK4vsP8nlBx3FUaDuFD9DpjBMpI1iZDizI2PUnTdWm6LnW3CRgWLexFAPdVRkPLPZt5DQIWOR3kVJypUgFtDPO7+/CN
5qHKBEnh4AYabcDBoqmDMAQvAWGwpKI30YsQcE9phIyMYaPIyBh5v46QIGWYUOtMhoKyvTJG0Z/li9PPK83pfEbJd3GDABN9
breV5J/GH+Lm4hEcW7FywWIaJY2dhJVvbpDo1RiPs0bgzrK0EKCk6G/UAiyvEWoNc2b5T9TF5TcN9ZpPqitBIorqzPUrhZGM
udXWf99fHo0OKfydZwJ67CSL4x2tg//m1H7+euQBGjogLi0kgqLXZE2ih48suAZbKnYdO8jJiTGUVHR1dKKU4qHSKGPNGmkV
Jnxco+lWCZYnutBa4/s+vdkcSgh2VCdaMEyIMKx5UWoQgeDY2DAThWlsZbG3NsVIs4IjwkqrwBgyMsZF6UGUkBw6eYyNy1aj
hOTe0kgrlDob2l2fDHH0dKWEH/gopejNhXU3D1UmsIwKM9uEYdisjLX2qlMlwps45elaeQvF0UYRbQwLewdAhNDtgcrYnGgW
re+5ItFFYAz9XT3k0llsy8KxbGzbpjObIe/X2VPNEycs45ARdNqSjhJPpQKZRJKY7bC7OsmJRolYVHXmR5+xMR1a33K1gsGQ
SiTo6eigFLjsr+UfVlpxUSosZZ8uF0FAX2c3QsDW8liLL+ZGcgQC32hsIdmcGuR4o0jRb+LIULkkhM0XxndyXW4xi/vmsfvo
QdyGj5MRLPxpl4Nfij/uKmkTKSyvobGCMAeQFY9SAidkGNoq5Jv0DCXot1Icqs8goovHDGEO4FQj1MA17Yc4NdKmUoTZ1I0d
/SSlzT2lEb48sYu7S8MklU1chMxf8BqsSnbzqaXXk7PjHBsfYcfh/cRsm6bntbTg3cXhsNwicnsbgcvlmV5yKsbI9CRSSnLp
LCebZY7Wi6cxr4GEcLgkEx7O+HSeRf1hScYD5VHqgU/csjBGUNcea5M9LIhlKVYrCAQLevopBy57avnTITxC7XVpxEhj05ME
WpNJJujJ5mjogP21aZxWyC98/YWpgdb+Lo13zrGq4cE4KMabNSraJRsLodDeWp7j9SJxGQq+RFLVHpvT/SyIhf7CmqElj3rY
2yvj5L06HVYs8tEEllGt6VAL+wbJJFMA3FcepaEDEtLGGEFTe2xI9TLPSVOqVijVqgggl+lACMHOygQTbp205eDr04oj3OMp
UvEE/R1deEazqzpFDAutxSO6VCSS/7v4Oi7NzuNEs8T/OXQzk14NW0gSwuZwvci+Wp51qV460lnGpycJGjYdqwIySzSV4wrl
PM7WUEk28DVW1HfbK85Sxee7mpEjFZZvyHFBso8fFI+TQ+IT4tB64LMwOoR91TwjjSrxSHpDE6qYchu89+DN3F8aASCr4ggT
ViblvQZXdMzno4uvptNOcGpqnHv2PISlLAJjSMTiDHZ24xvD1vJ4tImhcGljuDwTZoBPTozRFdX0bC2NUvI9clYY827qgIWx
LCsSXTQ9l0qtyvyVIb5/oDQWJmZ0iJ1drbkwFQrcqSj0KqVkR2GCiWaNtHIwEY7utZJsSPehtSZfLITPlspgWzb7KpOMNWvE
5GxizdCp4qxN9bT29+LMADKCAopwVYIGS2I5Msphe2Wcm2eOcaxRRBgZqbnQX5AmrK364tgufKMJjMEzAZ7WNIxPLfCpG5/D
9RkSs/COEN6lZYy/Gd5Gh4rzmt6VJCNBe6A8hn3GXmyONPrIzCSeF+YZ+rvCiPn9pdFW/qQeuKxKdrEgnqXaqDNdKtLX1Y1j
2+yt5hmOrOzcVJMUgpLf5HcXXsal2Xl4RrMwluUlnUv5x9HtdEb5DVdr9lZDAcikUozmJ0KEYhk6V/tUDivE4+0cE6JXexqL
MJWvH6OBgEP3znDNa4Z4ZfdyflA4xu7qFDGp8LTmwvQAb+4LmWlbeZxmEJCUVisiFBM228vjBMaQUk7LBtW0jzaGt/Wv471D
F2EJybHxEe7d81DoewhB0/Xo7+whZjvsqU5xvH7aPAfa0CHjXJqdj4hqSDYsWxXW9MwxtyFU0WxI9WEJyYn8BEoperI5ZvwG
B2ozoVaPTLNtFFsy86Lw4BTzu0OIc29pJMTgarZOyGNLepAOK8ZkcYZqo44Qgp6OTgywvTxOIwhIyPC9m4HPmkQPvXaScq2K
Uop1yV5u7FrB1yb3E5cK32i6rDi/NnQJ9cDnQ4d/zCm3TEraxKTVqvMxQEJY7KtO82B5vJXPYE52Y/ZnjlTYQj2swC2M3mke
KI/xmt6VgGHcrXGgOkNcRPVERuBgsSV72moCOJbDvFxP+IyVEGZioBloNqXCmqqxmTwNt0l/lL/YVh6j7gfEbauV75AIqoHP
RakBfrZnFTW3ycnJMVbOX0ivlQyvY5ztbNUw4dYASDixVqjGaEjND8LcgHl8vTJCoI0Gy4SXYZ9lmIQhkVIcuG+avffkWXNZ
N59d/hJumjrEmFtlebKTn+ldSiKsVGJbeTyqNREPw1sxYYc1IRF8aWif5YlOfnVoM5d1hMy2+/ghHjq0HyVVqN01CFsz2BNu
9j2FEepB6DMYE2afL8z0MS+WplAp4fke8zp7aGif3ZUQ82otkBEzbIngz6mpCbqyOYQQPFSeYMptkFEOxoBrAvrtFOsyvfhB
QLVeY0FPPxrDg+WJCM5EURYNl2TCzPbI9CR+4GMpRX9nmPLfXpkIQ5zR6z1t2JAKHdbjk6OUqxUuX7uJP1hyBRelB9hTmaLH
SfDSnqXMj6WZ8urUg4CMiIUhZm0edkmhHzXsp4TT2ufZTG4YSdHEpI0iLESc+7eeMSyN53htz0pCUCTYXp5g2m1EVhNcHTDP
SbM21Yvv+8yUS5GFS5NKJDneKHGsFoZWAx36LrMQc2x6EqUUA509YflDeby1F3NBuNHwy4MbEUKw9/hhGq7LqvmLaAZ+JACz
rxd4OuyIU1K1RrqgJXbWoOK0qnIfVzjIGCwRmdTHbiOT/MfH9vGzv72KdVf18Avz1z3CqZiMNEgsSrbMOtUh49Mq1qoELq/v
X8VvLrwkNIG1KtsP7ePExAiOZYcm3hhU0lDdn6B3TahV7i2OYaHQLfNs2JKZhwGOT46RTqawLIsdpXFGGtUwpq8NLoZOlWBT
NuwNyBdnWLdkRYh5i2MEGlBhYqnha9Zke0hJm5NT4zi2QyqR5GBthqP1Ugt+GQEp6XBJdhABTMyE2jERi9OTyVENPA5UC63E
kxACheTCTFR4NjPN4eHjxOwYFy5fzY29y7ixd9lp5taaHjvBby7cwt+deogZv4GKGIZIkSSVQ86KEZgw0qVEuByhcKQirRwO
1wtMujVsKVs5mbr2+YMll/PirkXEpIpCp3B3cbQVXRJAPQhYl+olLhWnpieoN8OK055caOEeKI5R8sPQatME9FhJ1mdCODhZ
mCabTNOd6aAcuOw7gy9klI2/NDvIlo5B6m6TgyePsTEKxY65tZAPIoExWhAXdlSn5ON6XngnqhYox0bZoF0RBmfM40sKWFKG
c2LOaj8MKDssifjyH+1h+UU5Fm3Mkkw76MECfYsSrOxfwvbSBDNus+VsndZUGisqsTWEBVjbS5OUA5e0cth2cA/Hx4ZJJZLo
QLd6bk/+wMIe7aXrzQmGG5XTUCViwISwuLxjHgIYnZpgfm/IXPcXx3ADTUqedpQ3pvrosRPky0U8z2Oouy/MjpYnT2dHEQQa
tmRDrT48NU5frqtlfaqeT6cdR2NoBgErEjmWJDuoNeoUK2UE0JHOoJRiX2mKiWadpJot+dX0WEnWpnswxtCRzrBh2WrGZ6b4
7n230Z/txz/Ygehq0ugdQ3oWV629iJf1LOV/88e5szDc8j0UgrLf5P0LNvPqvhVhUkvIR+1hffPO7zLeajwJM8fdVoIXdS4k
JhQj05MMdvZQ1z7bSxOtULAUoSBcmg2t8+j0JFobpJQMdoWh1QeKY2GlaFQ2viXTRVY5TBZnKFUrLJm3ACkluwtTTDbrpJTN
3CEcxgje0L8agP2njtH0XPqiEoxjtVKUIIyy9UbQ6yRbJRIL+gdJJRKUaxXGx4pRE9TDo2nnEgqSUmBJBTrg7HO5InhpWSL0
B+6fYf890wgtEB1NfumvNkA/3FcYi+rY50wjEIKMjFHwGyGG1YaEtNlZmuI/RvfzzgUbWNA3yMjUeDSsFLyi4OQP4gzfCS99
Xw4U3DM+StFzQ/MMNIOAJYkOVqa6aLhNKhFUAdhammg5W0KAHxguyvSHjvLkOKlEkkQszsHaDMfr5bDFUIeJsoxyuDgb1isV
yiU2r1gbWp/CGJZQrXlETT8IHVgEI9NToUZC0BsJzPbSRCiE6nTKf1O6s+WUX7R8TWt7T+SH+e5Xd3LgnxI4aei5qs7ql6YR
QnCqUWZ7aTJyYk0L+mRVjCty87GFpNqo40ahrkBrLNsiGUuwtTTOwWohZLwo/Nn0NSszXSSUxXB+gr3HjzCvq5edpSlGGlVS
UXjZN4YuK84lHWEX3lRhGoBUPEFfRye1wGd3dbrlOwWB4eLMACbym/wgaOH/B4rjeEE0jz8qlan7Phekerg8Nx/X8zh86gSd
mQ66Mh0U/SaHalEEL1J2MaFYmgjLKS5YvJy47bT27+CRUxx2jxLUwk42IUDGfvIYGwNSKrAsWxI0/cmfOGovesN4VBWoA0Ms
1sFQdy++0ewoT0VmLpTaAENCKj637qV8cWQv/z66n6zlEGhDRsX4Qf4Evzi0jgU9/TzkxHE9D8sReCVJcbeFk/FZuDoco7Kt
NB5FQUJMP8uASgiOTk1ggFwqw7TX4FithCPUaUshbS7pCJl6bHqSjnQGA+wu56l5Pjk7hkGEnWepThYmspRr1bBRJ5tjxm9y
sFqcU8EosIXi8s7T2hFjsC2Loe6osaY4Hjqe0V74gWFTpq/lgN5TGOVwtcDLepewsHs+V19pULFdxGSM4zfbJE4MIYTg/plx
Sq5Lzg6t6mzl7YZMD/NjaUq1Kt+//w5MlAFuei6Xr7uQZQND3DE9HDKejHIyUUZ+c6YPA4xOT9ETadyts0waWc164LEh3Uuf
k2S6XKJcC/M83VE+ZvvMCKONMB8TGENS2lwc7fH4dJ6447QsxUPlqeg8Tn+PZqB5Re9SlBAcGh+mWC1x0er1iGhvJpp1Oqww
4+1rQ4+dZHkyLKeI2w67ylMcrhW4oXsRK5YO8dMf8Ni2Zx+OdJh+yKJyxPqJQmCMmbRthbQdCVA612zaLJZxawHz1qZIdCoO
VGY41agQizKjAokbaBbHOxiIpXjfok0MxTK4gQYd4tQTtQr7KmGtS2cmS2ACjCtILQ5ILfVJJh2GVoTMeqxRjrKuUQYUyWW5
0OE6OTlGVyaLEYIT9RIlz21lG91AM99Jsyrdhed5FMol5vf0IYDD1WKr8ypszNBsyoS/O5WfiMLAklP1MiXPRUUC2Izec0Om
Bz8IwsrWwGdeTx/ZVJoT9RK7y9Ot0KMx4AjFhnTozD9UmuR9u2/lTw/fx2/vvx1XB6xc30ffOkl6TYNV726y4WdyUd5jFDkn
cyqMwA1MKzIznJ+g4TYRQqC1JhlPsKC7H98Y7iuMEY/gHVHbYWIOo04VZ8imwvEvR+dCDiPwA8NlHYMtAXc9DyUlK4bCCSA/
yp8iCAzSSJq+ZkEsy7JkjqbrMlmYZrCnn0wiydFakQOVmRa0EtGZDDopbuhZHM6IGj5BJpFmxfzwvb8zfhRpZuFPlMFPdpGx
HESkuN616xZ+d/+d/N6BO/GNZtOLBhjYIsltdln29hq9V7oY9+w9GiJsNy5ZjkQ6sShF/jj6aqQQ6ACWbgrT3PfPjFP3g+iw
wgZ4NzCsT4fthHFpcV3XAmq+j2S21zdga2EcA/TkusIpbQaUDfZAkzVX9pDudNhTynOsVo40cKgRclacFakujNYUyiXWLQlb
Jn8weRI3iPqJkbiBYUmiA1tIhqcnSSUSLOwdpBb43DUzSkKeZhBpBGtTYV3NWH6SeT2hxh5tVHEDHX7vSLCXJXLEpcXYzBRT
hRkGunvZFMGlrwzvp+r5KEJ87AWGHivJilTYlfX5U3sQRjLgpDlZq+AZg9IK4yoaZU3aSdPX00HRd9lVys9h4tmyEosrIusz
lp9ESYkQAj8I6OnoxLFt9lXyHK2WW4nAWcYbimVYkcrR9FxKlTKpKP5fdN0oHxF+Rkwo1mXCWP/JiVECHbBp5Vr6Ojo5Va/w
g6mTkU8SxuiXJjpQQjBRnMH1PC5YvDzM+I8dpuR50VgckEjqfsCLuhfSYTkcnxhlfCbPRavXkXRi3DMzyr0zY6Qj2DbbL3xF
Zxjs8I3mk0e2EWhDv5NiX3kG3xiUZ0FT4ddCZ3jgxU0SgxrjyUe92l0QKlInppDxlAXGjEfta/JcrIDRhnhSsfzCMOW/tTAZ
1ZqcbiVUSDZme5ktOr6qc16rdmY25f9QMY8A+nNdKBUOg/Sbht4NgmvfGk4w+9rIoUi4wj5WPwgjJD1OnGKtwtJ5C+jPdXOq
XuG7E8dIK6c1OSHQhsXxsFCv1mywacValJR8Y/QQR6qlFobVGuLSYnGyA4whnUxxwZLQwfza6KEW/p9lkJwdMo5Qii1rNnD9
5stIx+LcMnWSb44dIRN9h1lzvzCeIWfHuHnyBLdPjdBhxZhxm1zXvYCUspgozdD0miAMvZ1dgGBrYZzxZj2K4RPV8GgWxTtY
lQ59n+lyESVVOMMU0xLa2/MjrZqlEDYKGoFmQ7oHS0jGC9OnJy+cLhGLzi4MVOTssOdgXm8/L9lyFauHFuNpzUcP3kdlDlNr
DfNj6VZX2epFS+nr6GS0UeU748fIRFW+s9nuwMDSRHgmAXDF+s0sHZhP1ff41JEHw95tLVpC22MnuKFnIQL4xKGtPFScIqti
zDRdXt2/jLhUTJQLNLwmypLoIOxVSC/xMX40teOMNuXQsTbj8bSFlUgrMJSEFKB/8pXAQkRdPouSDCxOMeM12VcttMJcRFWK
OSvOmnRXK956Qaab+fEM440ajlI4wmJfZYai79KTzZFKJKjUagRuwCWXrqJ3KMG+ygzfnzpBRjn4UXTC15CzwvqPRDzJxqUr
Afjzw9soez4Zy26l/I0R9MYSBMawaHCIlO1wrFbmn0/sISUdgigsp6NcRUeEtTctX40tFV86tZ/7ZyZCDB4xtCMU+8oFAmOY
39nD/M4Q2nxt5BCfPrI9EpbZ0HLIeD/Vs4CxZo0/PfgAcWnTDDQdVpy3zA+jIIdGTqBNOAl7oCvMFN85PTqnN/l0WclFHX1Y
QnBieopGs0HMdgi0Ju7EmN/di8Zw98xs7f/pKlOM4NLcQBSnnyLQmqYXNgaFDTm0ejxqgcuOYp7FiSwbFoch4+O1Mp84vJX7
CxMtX06JsHo1bYV9FwsH5tOdCv22Tx5+kILnhq+NwjLaCGLC4tvjx/jpvsUs7QthVsX3+NC+uzlSLZGJXq+EpOq7vHZgOQWv
yUcO3Mctk6fodOIUPI816S5+YWgNBth/4sgj4L4JTk+SeAQLh35RKZG2sFI5B7SZFo+Y/Hn2yXC+q1m4LotQgu35SfJug0zk
tIRZRo+16Q56nQSTxRkarsuC3n4uzvbxtephYtLCEYqxRp2786P8dP8iVi9axrZ9u1i1ZDmr5i9Fa8NfHHoQLzA4lmxNhVZI
8m4zTLBZFtXA41OHtnP71CgdttNqLYRQi4w16ighSNkO+ysz/N6ee6j6AUl1ugFGRnHvabfBQCyJAr4+cpi/ObKDjIq1nFkD
xIXFwUqR9+38MZd39lPyXO4vTLCznCepLKQ5nVcJDHRacdLK4dd23kHV8+mwHSaadX5j2YXMT6SZKM4wHBX9xRyHeV09NHXA
g4Wp0xWqUa5GobiyKypNiPwUIvjT19VDwolzoFLgUCWMomgz2/xu6LYTbM71YYxhqjCDFJJCtcJQTz8rUjn+d/JUJGxhl9lf
H3mIo7USnVaMQ9Uid86MUvSaZK3T7bAGgYVkf7mAQNCTzlIPfD59eDs/mhwma59+7eyFEwlhsac0zS89eAvXdM8jLhU3T55k
f7XwsPcODKSkzb0zE9w0doyi59Jpx2n4PjGh+MOVW0haNgeHTzCSnyBmh2FiocCvCqpHFcp6RIbYtCa0azOdztlYmS4HEAUh
RBlB5icHgsKJAUs3h47afTMTkYNzumvf05qN2Z7IiZpiulRgQW8/L+9fzLdGj7XghCMsvnjyAC/qXcDKeQtZ2jcPywqzyn9x
aDsPzEySs8N+2TBhF05GO1Wt8v4dP2YglmR7cYoj1RJZO5xB1NCahFTRBjp8c+QoBbdJQwfcNT1KLQhIKZtmEITFZ0K25tF/
ZN/9bOjo4XitzLbCJHGpUEhqgY8jZTgJAkNcWDwwPcFdU6MgBDEhW9nkuR1o2kBCKf768EMUvDBHkm82uKZrPm8eWklgNA8d
3IsBAh0wP9eFpSwempngVK3aEtKwhVEzL5ZiY0cvQRCQL8ygornoxhjmdYdZ5jumRqj5Yc4iiKxKI/C5MNtLtxMnXypSrlWw
LEW+OAPANd3z+Zfj+4gGfKCQNHzN54/vi6wPJJVNWp6Gdiaa+peSNj+eGuG3d91FznbYXpzicLUYavIzpm+LaP+SwuZotcze
8p6waV5ZZOQjXy+RHK+WsaWk245T8T0A/u8Fl7Em08VMpcz2Q3uxo/CtCcBKGyZvjeNOWKikOT1U9+ET+cogCulOByvbE0MI
ZoA8kHksCyAJR1xkuhyWXpAjwPBQMY8zp/zBGIGN4qJceCAzlRJj+UnqbpNNuV6u7BrktqkRcnaMhBAcKBf4zZ138s7Fa1mY
yjBdLfGFE/u5afRYGDfXoUAB2FK1WhjvyY/jG0NcKjqsGL4Oe48vSHexpzxNQoWC5Aaab4wcDePYyiYtbSqeR388iSMlp+oV
EsrCERbHqxX2l4vYQpJSNlIIiq7LhbkejlVLNHQ45FcThv7C2iYTFf6ZR0zLlYTZZYMhIx2KrsuSRAcfXn0JlpTsPHqQ8Zk8
iViMhttkMKo7ujM/djqPMAf+bMz2kFQWw/lJqo06thUKSMxxWjVLd02Pt8rAZx0+PzBc1hnG6UfyE3iBT8x2mCxMU6nXWZXu
5EU9Q3xn7Di9sTiu1igEOSvWGmEdjrmM+omjfQhvUQm7p384MUyAISYV2ajx5kwKjGntX0xYJCwrKtAz0evFIwQmKUNIO9lo
MhhP8uE1l3BpVz+1ZoM7d26NSlAsdGBQcUP9pCJ/Z+xs4xxnPyQvBDPZ3hiyo9cRSglfYCYiP9mcNf4TDVrNDcZJddmcqJY5
Vau28P9s1KPfSbI+20MQBBTLJVzfY++JIwB8YNlGuuw4VS+MCKWlw935cd617TbedO/NvP2BW7lp5BgdloNAMtlo8AsLV/P/
LVnHZKMRNs0jyaoY3VacpLTxAs100+WNQyv5m41XsyrVRb7RRBmJLSRdVpwuK44tFGXPwxKKj629jI+s2YLWgrofoBAkpE23
FSejHDCCqUaDTR09/M3Ga/jlxRdQdD3cQLdCouHkNs7SKHS6bzomLAqux2AsxV+uv4KeWIKTk+PsOnKgheEtadEV4eeHCvko
EfTw95oLf3RUAhFE4c90Isloo8aRSum0P6bD7HZGxbiiezYXMoUUYeSo0Wyy79QREPCBpRtZmepkstFERlG0Wcd1ls39QDPV
aPCWBav44zWXUHI9fB0OHuiwwvNISRs30OE+Re8hosaXtHKoeH7435xuqJKEQZPZFc49ChOOM80mvja8anAJn7/oRVza1U+5
XuNH2++jVKu2mF9aEDQFozclwRetCzbOWBFvmwmlhN/R6wgr2xuTtiMDDCeEYMtjVVPM7RSbTer42uBE0QSFoBq4rE53krIs
xmbyVOq1MPN66hiL+gZZlM3xyQuu4Pd238two0ZKWVFvLpRdDykEHVaMuu9T9X3etGAF714aVpt6WvOF4weYbrqth9JAznb4
nZUX8pZFoUP8Fxuu4GP7tnL75FirJ3g2Qb06k+P31mxmXUfooP/Vhiv5+IHtHK+WH2ambSF59bylfHDVJhwpecOC5cSk4u+P
7GG8UccSgpgKC/cefX54mJySCPJukwuynXx8/WUMJdOMF6a5Z/eD0fzLSFNZBpRpMYTW4TxNdNiZlbNiXNIVYviJmTxKqtNw
S5yusAyiso7Z+8Xqvs/KTAeLU1kq9RqFyumBZPGEzZ7tJ+koDrLi4i7+34ar+cTB7dwxFfYFiDO08bxEkg+s2Mjrh8K6pT9a
cwmfObST6WazdR6eMQwlUnTYDvvKBbKWTSXw6Ysl+H+bruafju7lB+OncI1+lB2j1VqbUhZLklm2dPXxssGFrMp0Rnmfcbbu
30Wt2QgtYHC6QX70v1K4YwqVMGcbpT5bTnvCdiTZ3pi0sj2OjKVU0Cj7h6QlHjuFrA22I5k5Vac01WRBd5oX9czna8NH6XRC
770ZGF4xuHhODUmIQ01guHPng1x34aVs6urh8xe/iM8f28/tU6NMNhu4WrcO1JGShck0b1q4nNcMLW1NHXjHkjW8tH8ht0+N
crRSwjOGRak01/fNZyiZxgt8pssl+nNdfGrjlWydnuT+/CQTzRoxpVif6+bF/UM4UjJTKaGk4vKeAb7S+WJuGx9hb7lAJfDo
duJc0dPPhbmehz3+a+Yv4RXzFnHL+DB35cfZXsiTbzbmjCI5PTfHEmHYsh54vGLeYj64ehNpy2Z0eoo7d24NIx1SogODnYLp
/XC4UeHil3TwxqEVbJ3JU2i62FIy4zZ526KVdDthC2OpWgkFQBusmCB/xGVqoE7/ggQv7V3Av544QKcTQyAouB4vH1gUjZYM
2yZjjoMODMI2NE46fO1fDvD6P1nJ8ou7+OTGy9ldmOb+6UlG6lU8NJ12jNXZHJf3DJCxbDzfx0T7cUV3P7dNjHC4XMYjYEEy
zUsHFpBQFh/bu43thTxZK8b7V6xjaTrLx9ZfypsWrmDr9CQjjWrUtgq2lKQsm24nxvxEiiXpLIuSp13S6XKJfSeOcHx8GIHA
lhHsSRr8omTsG0lqRy1U4vQw37OV9mjfHEpkLLI9MSl8T1v//N7t/sSx2i/acfk581i3w0RRoHrJ4/Kfm89L3rWUhh/wuSP7
uSM/hkTwswsW8+qhJbi+x3/fezt1t9m6IdLzfcrf6+ZFP7eKFZeGEl0zPocKRUbqNWraDycCJNOsy3VhCYEX+Gw7sIdSrcKG
Zavpz3U96vcam8mz4/B+porTrF64jNVDS0gm4o+UYa05OHKCnYf3o5Ri47LV4SwadfYIcOgbFDhQLjLWqDHjuow3auTdJr5+
JNAMG949BuNJ3r18DTfOWxSFO0+ydf+u0NGUEu2HB+jlFce/kCQdT/LOf9hILKG4a2Kc/zx1hGm3wUVdvbxz6WoSlsWdu7dz
bPQUjm2HwpOBU9+yWJRawqt+dxleoPmXI/u4ZWIEz2heOjDEO5etQQLff+BOZspFLBUmFYVjGPtamtIuCxHTXPLKeVz8qkE6
++Nnqx/g2MQou48eRArJxuVrmNfd85hh82nXJWVZxKSk4bm4nks2mT6nas1qvcboTJ7hyXHGp6dwfR/HCkvrhRPue2W/zdTN
SbxpiUz8xCkRvhBYXkO/vW9J8vO/9JlNljDGqP/4o73BvrvyVyXS1u1a/+T7QGb7KV/y7iVc8up5j/yUIOCu3Q9yanIM27Ix
gUHEDO6ozbF/SiKEYdXV3Wx4SR+L1+Ye9Q4s1/U4PjnKgZPHKFRK0dWekt7uTnq7c8ixLPF5Pq5sMD4+w/h0PtSIloUXuKSz
cboS3VhHe8kMKuJLXYrFKmMTU8yUyuH8SQxaBPT0ZXGmuli9aAk9ixJYQjLZbPDdkRP8aHyUI9USZc8LZ/VHpceWkNhScOZF
oypi/p8eHOI3V28g58Roeh7bD+/j0Knj2JYVwiwdMn/jlMXY11IEVYnn+Sy5MMcrf2slYXTu4bT3xBEePLgX2zp9oZ2wYPgL
GcpH4fp3L+KK1w/NmWx3un1764Hd7DtxNBygGxUe+hXByX/OgB/i2nrZJ93lMHRBhoFlabrWWKSW+riuT7FYZXJ6mmKl3IJu
QkFfXycddCNHs6RX+nhWg7GxaTqSGZYMDNGZShMQMFbKs3P/QUq1Kr2dXXRlcqSScawEaD+s5/f9gFqzQbVep1yrUmvUcH0X
pMCxVXgRojDopqBx0qL4QIzqARtkmPw6hxEpRkoh6hX/6tVXdt/xcx9eo4QxRvzgH46aO//91EAqZx/WgUn+pFzAbFDcrQcs
v7SLdTf00r8ghUhoSvY0B46cIF8otg5KqLBCb/SraWoHbGTM0CgHSCXI9sXoGorTdxl0rDUYGVCvNymUylRrdZRUWJYCZRDK
0Cho8rc7FO6Nk1zkk93SILlAE8uocCqDNpimonpMMnWnRe1oiAkzG10yG1wSfeAkZBjGCwS6qhi/x9Dh9vL6D64n2WHxzVPH
+eyBEOs7SobhUCGjFGL48MGjRC7C5ntD2rL42tXXk7Udjk2MsvPwforVchir1iasRYkZyjscpv47ifYEwg4HYzVqPh19Mda/
pI+F6zuIJxVuZ5lTUyMcPzWOrVTrDFRGU7g7ztT3ksi4oVkNWHZJJxt/pp95S9NYSSjJIgePnuDU+Dh2ND1aCFBpw+R3kxTu
iSEj2CBVGORwmxrtG2TMkFnnkdnQxOnVOEmBssLPN57ALwmKBwWFB2zcMUV8oU/u0ibJxQEyrrEdi5jj4JWhMuMS79coKxR0
Iw1BSVDaFiM2FBAb8JGOgWh8pBQSJSRCy1A4KgJvWtI4ZVE7auOOhwWPMmYe7kD8hF54qUStWvCWXfXGobHr37lECGOMeOh/
x823Pn5ApHL2Lh2YtZzjLZEimhxtDDhxhXAMmavKdGzycRIhRkVAUBNM/zBBaVusVaUXVh6G4/UCL8T/8QU+qVUe8XkBsQ6B
FQ/dV+2BX5TUjllUd8XwphUybjBulLrvCFA5jYxpjCfwZiT+jEJIEc7r1KAbAukYrM4AldUIBboucKckflnyS3+/kd7FCb50
5BAf37ODjG2H/bxhoBNPG1wd9twGxoRmXamHhfssKck3Gnxo3UZ+fvEyTuUnuHXbvdhKoVS4HzJmCGqS6R/FKW2LIWxzeu7l
nEibWw9QjkRoQWJ1g67r6qT6FCZyeI0nKD/kkP9BeN/t7NzRZjXE5/FUePdZ6rIymQubxJJW6zyMD4W748zclkDYZ1RNClqz
hYwmHPxrgZ0LUBmNiG5p8SsCv6AIahJphxpYN8PzsDo0dk4jYgGBZ/CmFdQtkitdEos9ZBz8GUVll0NjWCFjBjunsTIhUhDC
oAMwvkA3IagLgppEN0Q0mtEg7DlREM7xsmyQUok91YK37tW/s9JsuKFfWIDpXZRUTkwGRrNTwDkLADqc/Ds7Rc64kvLNOdxd
PrGFHippCMqS2mEbLy/DIUZmTpYIsGxJVJGKHnOoDEPVDhlFOOGBaQ90LdQE0gYZD0eLCTvsO/MrEq8gW3Zr1uKE8zEjXB5p
OW9K4U6oCD4IvKbPki1pehcnOFGp8LcH9pGzY63xgVXfQxvoisVYns6yNJNhbUeOGdfli0cOtSyAEoJS0+Oynj5+duESfK3Z
dXg/1izzB+Ez1Q7aTP1PEq8Q7ceZ2ksblCVJdkiIElPegRRTp5KUF3vYnQHGEzSGFc1hK7QcotUP2ToPHRh8D0o/yNLcExBf
6mKlNUFdUj9s0ThlhRrXPIqeNKfTeTI6M29G4k6d3mMkCGVQifBLmuD0eQQVgV9UYEIFIiwQwlDZ4VDZ4bT6eaUFKhWeZfj+
Z9zAOSuQknAuaMycrlV4/INyNSCNZqcTk6ZnYVIBgQXQOS8hUjmHesXfppT4+cc1Y0XP0RoqDOc1x8INnn0IaRtUgtM9oeLR
30M6pxlCuwKap18vLLCiGfFGi4df16rOcNvNbP3LnM+a/Qz79M+kgmbd0LMwHC573+QUVS+g0wnHfEgheMnAfH56/hCbu7vp
iBoxHshP8eUdDxHoMLEjRFj9mrUcfm/dRiwp2XXsEFPFAjEngj0W+FXJ1PdSBBWJlTStGvlHA5tz8ayMh1awtsdp/VxYRApF
PCwK29pLGbUI2obmmKJxKtHas9m/bTUwiZ/ANiJkVuyz7PGZ1+ee5TxU4pHCNnuWj3h/HuWz5nyfJ3JbpAhnpm5LdTp0zksI
AMsYSGQs0z2U4MTO4lbLtkAb+fjm7Z7RauOYcEwFDx+nfdaeG8EjNGE4hexMzTTn1nce5fePMgb4Ub+nOf3/grDlE6Dq+a0e
gUBrco7DjUMLWZhKM1Ktc1t5nJtHhrljYgJHSmJShZuqDW6g+fjmi1iczjBRnGH30YOnb2wxIBxD8YcJgrJEJUPLJM71mtUI
4siEecSePmw/zvE8ZtsGz+nzf9IeP57XmkcPqJztbx71rZ/4NalSSIFuBFu7hxIkMpYxBqwwIiD0wPIUxx4s7JCCioY0P1k3
PLa7YR5jox7P+zyNNDv6sZp3QcDKjo5o8luY+Sw0Pd5/732oaJK0qzVKhNWPrSI6XxMYzUcuvJCr+weoNhvcs3t7OMBKyhD6
JAz1wzaVbbFQawdPcE/0E9xTcw7M+/wmE0XwK9o3OwaWpUOwqU3LUJn5a7JSypFJ4CEhuDLabvW83hVjsOOK4d1l3EbAJT3d
XNHbx21jY/TG4xgBtnV6pk5KPXwsyXTTYzCZ4A83refK/n4anscdO7ZSqdfCCFgQOmtBWTLzP8nTXXVteqZplpcfklJMzl+b
kbPqxJqd1T6wMi0TWVtrX98hhLjy6de/54MAgO0ICsMNtn17jMt+bj4f2bSRP3wQ7hifDMeMKImKuFYbjac1njakbItXL1zA
e9asYiCZoNKoc+fObUwVZ0LoE8wO0YL8TWn8GSty3tsS8CxZAExg7khkbQZWpCWghRRYsxop2xczPQsSjB6o/NCOyw+ax+MH
PEdpFpfG0xZ3ffkkPQsTLL+si89eeSn/c3yE/x0Z5Wi5TNn3wzp5y2IgEWdTdxcvGRpkZUe2NUJx6/5dVBuNVoZ2dgJ7/ltp
mkfsqD6lzfzPEkkhBX5D/7BvSYJsX5g8EAKEMSY8MCXEbf983NzzH6dyyQ77qA5M7kn5Ac8lQRCEcWdtuOxNQ1z8qkHseIj+
fAylhocGUrZFQslH1qeMDYfDr6L6HJkIw7/T303TOGy3QrBteta0v5BKFGpFb8llPz9UuPYdi4QOjJFKRD5AVMq/cGOHuv+/
hgsYfizglS8EP6A1/EuBkYI7PnecfT+cZPlV3Szc2EHvggRdnSps9XQD8pUyk8UZRvOTTMzk8Xwfx7YR0oAdFnbV9zsUf5jE
n1Gt4qw2Pcv43/BjpURh4cYOBbRKXa3Z4i2AeWsyoqMvRq3ofVcq8coXgh9wpiVIZG2KY03u+fJJ7v+PYeJZi+wmn+SFTUTG
xdMevh8gEFgJKxx+qzW6IXCP2NQejNM45IDkdOKvjXyeXfUmQPv6ux19Meatzoi5PN+yAEYbYiml563JsO+2/M3xtPKMNjYv
tCPUYDkSOx7CGb+umfqRQj0Qx1lgERsMsDo0WAY/gKAi8acU3oiFNxVOSj5dn9Lm/PMA/lhCCM9t+jfPW5slllLazLmoz5ob
ERGgl27pkvt+NHVUCO4xcPULBgadmXkML7IKL7hOAb7CPaBw90UJAHFGcs4iHNMtnsTthW16WuCPENyDMUeXbemU0RVkLY1u
zS1sA1i0qUOmux3t1YOvCyWufliX9wtZj0iDjEdzkcwjM5lmTn1KO9Z/3sGfr2e6HRZu6miFP+f2bbcO0mhDstPWQ+uy+A39
LSlEU4StIubc58Y9j9fsLfDm9ELP+Vl7j86nZcK78ETTb+hvDa3LkszZIfyZo6CsMxNDAvTKK7vlwdvzR4XgNgQ3vCBhUJue
D/BHCsFtwNEVV3U/Av48QgBkZBoWbs7J3EDc1AreF6UlXtIGQW16jmY6ReCZL+YG4mLhhTkJaHnGRQDyzNRoFA0KllySM149
uElKMRlp/7YYtOm55LUpKcWkXw9uWrKl08RSKphtCOJsFmDuG6x6Ua+1+/sTRYz5qhC8l3CWqdXe2zY9ByjkVWO+asdlcfV1
PRbgc5Zhb49oc8TAwIq0HlydwWvov5MS3XaG2+s55fxKtNcI/m5wdYb+FekQ+z/KPUiPqtG1Nkgl9JoX98rhnaXdQshbQV8P
Img7w206/51fo4SQPzR+sHvN9b0SgTaz1zT9JAsw1xledkWX7BxKELj6U0KKtnppr+fEElIQuPpTnUMJll3RJefy9DkJACJs
qrYTKlh1XY/wG8H/SCn2iHBQcNDe4/Y6T1cgQEop9viN4H9WXdcj7IQKtD77LajWY408AczaG/qs3d8b972G/oSQfL5tYdt0
vgc/tW8+ke529Nobeq1wGpw464vlY1VGGm1IdtnBimu7hVfzv6KUOBBZAd3WNu11ni0tQColDng1/ysrru0RyS4nODPze84W
4HRiALP+xgHrwA/znvbNnwopvoBpV7i36bys+5Ha508THY63/sZ+C4P/kwqz5GNPfgsbxzN9sWDldT3Srfn/JpU4gIguS2mr
nfY6P5ZGIKUSB9ya/2+rruuRmb5YMDsG8gkLwGkshNnwqgGZytme9s1HZy+LbO97e51HsX+hffPRVM721r9qIBz+eg5lucKY
c5gqGjUQPPDlU3LbV4dJ5Oz7tG82RxcstvMCbXp2s74GKS2xrV7wtmx+w3wuftPQw5peHousc+0VNAbWv3JAHLotHzRK3m9L
S9zSrg5q03lBEhG4+rezg3G9/hUDyhjOuSnDOtdeWaMNsYwVbHrtoLrjb4/9MN5hf0sH5lUirLtoW4E2PSva34RFb99y694P
N719UMUyVnCu2v+cIdDpeZIGo5Hf/f19Jn+kutiKq11GmzhPeFxpm9r0pCo+jZCi4deDdd3LUsde/tHVQki0OMsN2U/MCT5j
mKS0hL74LUMSzVEBH2tnh9vr2cz6CvgYhqMXv2VISkvoxzv49NwtwMMdYnHnZ4/JAz+YkLGMvd08jks12tQmnqpuLyX2NEve
ppU39Okr37NYG23MuUKfx+cEP0pYdPOb5jPyYNFrVoNflpa4M2qeb0/BadMzAn0QGO2ZX073xrzNb5qvzjXs+cQh0Fz+N4ZE
zg4u/oUFVtDQd0spPhn1C7ShUHs9E9BHSSk+GTT03Re/dYGVyNnnlPR6SiDQmVDotr84LI/fPWPFMtZ2HZjVtKNCbXp6O72U
VGJfs+xvWnR5p3/tbyx7QtDniUOgM6DQlncsZOpApelWgrdJS9xl2lCoTU9n1EcQaFe/LdVtN7e8Y+EThj5PGAI9Agp12sGW
dyyygqa+TwjxIQFWGwq119MEfSwhxIeCpr5vyy8tshKdTxz6PGkIdCYUeuBzJ9Xe74z78Q77OyYwL29DoTY91dBHKPHdRtG7
cc2N/dbFb18QPBno85QJwGyCTPtG3vxHB8zM0VqXnVDbtTZDoh0abdNTEPI0YZfXKa8ebOpampx+8YdXCmmJx5Xwesoh0JnX
MSpH6ivet1jaSZXXgX6DlPiIMFzVtt/t9QSXQWCkxNeBfoOTVPnL37tYKkfqsPmXp6CM6CkgIUMolJ0XDy591yIraOo7heC9
7dBoez0VIU8heG/Q1HduefciKzsvHtX6PDXm5clDoLloKBo9setro9bOfxv2Yzn7MyYw7wU8zn4Ncpva9GjkAbZQ4m8aBe99
G94431r3ukH/bONNzgsBmOsU3/2ZY+r47dNBLGt92wTmRsLJXO3Jcm06F/IBSyjxnWbJf+Wiq7rU5e9f/JQ4vU8LBHp4eFRg
DGbLuxYGvavTeBX/DVKJrRHz++2zbdO5ML9UYqtX8d/QuzrNlncvDIzBiKfh4oWn3AK0xqwLaMx48taPHNTVieaglVA/NoFZ
3g6Ptukcwp2H/HpwTaovNnrdH66Q8U5bm6fp4pGnRQDmtlGWhhvqto8eDLxqsFo58lajzUBbCNp0VuaXYixw9XV2Uu279g9W
qOz8+ONqcDlvBGCuEEwfqqrb/+/hQPtmrbLFLW0haNNZmd8z10tL7Ln6d5epruWpp5X5n3YBmBsZmtxdse765BEfWCutthC0
6ZHMr31zPbDn8t9cavVdkH7KIz7PiBP8CAlTAhMYei9I+5f92hILY/ZoX18vJGMR8wdtHnihMz9j2tfXY8yey35t8TPG/M+I
BTjTEozvKFn3ffqYb7RZK205awnaIVJeoKFOKca0p69HsufS/7PE6t+YfcaY/xkVgDPh0H2fPuIHnlmrHPkNo83KthC8IJn/
QODq1yhb7NnygSVW7wWZZ5T5n3EBmCsEM4dq6t5PHQ3cij9gJdRNJjAX084Y8wLK8D7g14NXOGk1tuXXl4QO7zPM/M+KAMyN
DpWHG+q+vzwWVMeaKTut/k375hVC4Ee+QbuhhuddQ0tgDJa0xE1uJXhjeiBW3fKBxSozFH/aoz3nlQDMFYLGjCcf+Mwxnd9X
JZa1PmMC817TunO9XUrN82eKgxAghBJ/0yz57+teleLi9y8Ok1zPEvM/qwIQCkFYSRq4Wjz0jyfFyTumdSxrvRvDZ4xplU60
/YLnA94X+AjxvmbJ/7uhKzvlpncuMComzSwPPFv0rArA3LIJQOz/+pg6+M1xXznyGmmJLxhtFkcb2IZEz1HIEzm7x7Rv3hY0
9Y9XvLrfWvWzAwFhH9XTUt7wnBKAVldZZCNH7ytYOz837Pu1oM9Kqn8wgXkVbUj0nIQ8hJDnW34t+BUrqSbW/+J8a/DSnG9M
q4/qWafzQwDO8Asqww310D+eDAoHazgZ63cM5k/QWAh8TBsSndc0e0YSXyD+wC37f5ZbnmTjryxQ6fnPnrP7nBCAuUIQuFru
++ooJ26e0tKRV0pHftYEZkPbGjwntP4O7er3aFffufDFPXL1GwZRjtTnG/OflwJwhl/A2H0Fa+9XRv1G3k3YaevDGPNbJuwy
bvsG5xvWFxiE+HOv4n843mXXV795njW4JeefeaZtAXgc0yaEFDSmPbXvKyPB2H1FVExeK23xaaPNJubUk7T5kGetlie6Vne7
9swH/Ka+bWBLB2veNE/Fu+zolkZx3qqp81cAzoBEgBi5c0Yd/NqYX897MTulfgshPog26cj80oZFzyjcCfdbigrGfNyrBn8e
77abK352wJp/VWcY5TkPIc9zTgDOjBI1C5469F/jwcidMwArrYT6U6PN6zAtjSTagvC0Mr4BFAKEFF/z68GHjOHAvCs7WfGz
/SrWaQfnU5Tn+SEAj2IN8rsq6tA3xv3iwSoqLl8qHflho81lbUF4Rhj/Hu3qDwcN/f2O5UmWv7bf6l6Xec5o/eesAJz2DaJZ
RIGRp26d5vj/TOrahIudVL8olPgNo826ORi1LQhPBeOHOH+XCcxfeLXg88leh0U/0yuHrutCKKGNjpzc51hI4rknAGeUUQC4
ZV+d+P6UHvnxjHGLvmMl5ZuFEr9uNOvOOEjZjhqdU1RHz1UcQrLLBHzKrwVfdjosd941nWLhS3qkk7WCM8/iuUbPWQF4FFhE
fdJVJ2/OB2N3F3DLvmPF1VukLd5ntNk050rXdvj0J4QzZ0deCim2a998xq8HX3Iyltt/WY6FL+lWiV4nOHPvn6v0nBeAM0Om
gKiPu/LUD/PB+L1FmgVPqpi8UdryPWBuMLoFh4I5kSPxAtf2nIY5aBA3a09/Nmjq78Q6bN13aQdD13epZH9Mt3D+eRzafOEJ
wFkEoTntyZHbZ4LxewrUxppIJTapuHwHQrwOYwbNw62CeIEIg5kDCa3Zux4QYhRjvhY09L/owGxPDsTovyzH4NWdKt5lP+8Y
//kpAI8uCPh1rSYfKJqxuwq6dLiG9nSXismXS1u+EbguuuuY57FleISmj5zaBnCr9vS/BU39XWnL6ezSBANXdMreS7LCSqjT
UOd5xvjPbwE4iyAAsnioJibuLQbTO8rUJ10QYrmKyRulJV6N4XJjjNNimZBp9HPQOpgzHH85+82FwEWIu7Vvvhk09XcwHIr3
2HRvSNN3aU51rEi2hOX5zPgvDAE4uyAIvxrI6d0VM7WtpIsHarhFH2CFcsR1whYvE4irjDHdmEeEBfUZFkKcF9eGPvx7ybn3
Nwgh8gZzh/HN94KmuRXMQafDpmNFkp7NWdm5Li3slJoVmBcE47+wBOCM8Ck83Cq4BU8W9lWD/ENlUz5SpzHtYQLTLS1xsbTl
tUKJq4ANYDpm8xCPEj2Ze2XIXMEQTwGDz2X0uZ/+sGhWq9hMiCKwwwTmDu3p27RvHhBK5GOdNtllCbrWZ0RuTUrFOm09V9uD
eM6GM9sC8AStAkLMrVKUfjWQpSN1U9xfDUoHq9TGXPxqgDFmQCpxgbDFRVKJzQixDlgMJvUoQvFYGprHMbTsrBbmdNJJVIFj
GLNLB2ab8cxWHZjdQogxKyVJDMToWJ6kY3VaZZcmhBVqej1boYl54Wj7tgD8JGF4uAYUgGxMuqJyohGUD9dM5USD+oSLV/LR
ngbDPCHFEmGJlUKJVUKyDCEWCEEf0A1kZ+uYTuty85PvnBJnmA5BCcgbwwTGnDSawyYw+01gDpjAHAVGpCOxMxaJPofUwjjZ
ZQmRXphQ8T5nrj9w2gK+gJm+LQDnJAycmeQRgPQrgahPuqY+0gxqo03qEy7NvIdX9gnqGu0ZjDY2hg4E3UKQQ4q0EAwikAiR
FoLus/RB5DGmgkEbwyjaVIyhAOSBopDCk7ZAxSV21iLWZRPvc0gOxkjOi6l4ryPsjHoYw5+GN7SZvi0AT1IgHs5ALaxvAiO8
ckBzxjNuwdPNad+4BQ+vHISCUQvw6xrtaoxv0L4JNfHs3ovQ8khLICyBdCRWQqISCjutsDssnJxNLGeJWJctnZwl7KyFUMI8
wjc4+/dt06PQ/w+9aMORIQYfEwAAAABJRU5ErkJggg==]]

    local asset, resolved = nil, false

    function KH.logoAsset()
        if resolved then return asset end
        resolved = true
        if type(getcustomasset) ~= "function" then return nil end

        local ok, result = pcall(function()
            -- A truncated file from a half-finished write would resolve to an
            -- asset that draws nothing, so check it looks like the image before
            -- trusting it.
            if type(isfile) == "function" and isfile(FILE) then
                local read, existing = pcall(readfile, FILE)
                if read and type(existing) == "string" and #existing > 1000 then
                    return getcustomasset(FILE)
                end
            end
            if not KH.X.writefile then return nil end
            writefile(FILE, decode(DATA))

            -- Best effort: an earlier version of the mark is dead weight now.
            if type(delfile) == "function" and type(isfile) == "function" then
                for _, old in ipairs(STALE) do
                    if isfile(old) then pcall(delfile, old) end
                end
            end

            return getcustomasset(FILE)
        end)

        asset = ok and result or nil
        return asset
    end
end

-- ─── src/_shared/98_splash.lua ─────────────────────────────────────

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
