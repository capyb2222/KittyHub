-- ============================================================================
--
--   ██╗  ██╗██╗████████╗████████╗██╗   ██╗    ██╗  ██╗██╗   ██╗██████╗
--   ██║ ██╔╝██║╚══██╔══╝╚══██╔══╝╚██╗ ██╔╝    ██║  ██║██║   ██║██╔══██╗
--   █████╔╝ ██║   ██║      ██║    ╚████╔╝     ███████║██║   ██║██████╔╝
--   ██╔═██╗ ██║   ██║      ██║     ╚██╔╝      ██╔══██║██║   ██║██╔══██╗
--   ██║  ██╗██║   ██║      ██║      ██║       ██║  ██║╚██████╔╝██████╔╝
--   ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝      ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
--
--   Murder Mystery 2  ·  native Roblox UI, no Drawing API
--   build 3.0.0+c3810c94  ·  2026-09-01 03:54 UTC
--
--   GENERATED FILE — do not edit directly.
--   Sources live in src/mm2/ ; rebuild with `python build.py`.
--
-- ============================================================================

-- ─── src/mm2/01_prelude.lua ────────────────────────────────────────────

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

-- ─── src/mm2/02_config.lua ─────────────────────────────────────────────

-- ============================================================================
--  CONFIG — defaults, deep-merge, and on-disk profiles
-- ============================================================================

local S -- the settings table every other module reads

do
    local HttpService = KH.Services.HttpService
    local X = KH.X

    -- Defaults double as the schema: a saved profile is backfilled from here
    -- and keys that no longer exist are dropped, so upgrades never half-migrate.
    local DEFAULTS = {
        -- No line-of-sight or range gate on purpose: the server resolves the
        -- position, so the murderer can be hit through a wall across the map.
        Aim = {
            Enabled       = true,
            Target        = "Murderer",  -- Murderer | Nearest | Crosshair
            Mode          = "Press",     -- Press | Hold | Toggle | Always
            Key           = "C",
            Method        = "Mouse",     -- Remote | Mouse
            CameraSnap    = true,        -- Mouse method: face the target first
            MouseSpeed    = 0.4,         -- 1 snaps, lower eases the turn and walk
            Prediction    = 2.8,         -- studs of lead per unit of velocity
            PingComp      = true,        -- scale lead by measured ping
            FireRate      = 0.10,        -- seconds between shots
            KeepEquipped  = true,        -- re-draw the gun if it gets stowed
            SilentAim     = false,       -- redirect your own manual shots
            SilentMode    = "Auto",      -- Auto | Hook | Takeover | Click
            AimAtHead     = false,       -- Head instead of HumanoidRootPart
            NotifyShot    = false,
        },
        Knife = {
            AutoThrow     = false,
            ThrowDelay    = 1.2,
            ThrowRange    = 70,          -- past this the knife is just thrown away
            Aura          = false,
            AuraRadius    = 18,
            AuraDelay     = 0.15,
            TpStab        = false,
            TpRange       = 150,         -- how far a blink is worth making
            SkipSheriff   = false,
            TargetSheriff = false,
        },
        ESP = {
            Enabled       = true,
            Boxes         = true,
            BoxStyle      = "Corner",    -- Corner | Full
            Names         = true,
            Roles         = true,
            Distance      = true,
            Health        = false,
            Tracers       = false,
            TracerOrigin  = "Bottom",    -- Bottom | Center
            Chams         = false,
            ChamsFill     = 0.55,
            OffScreen     = false,       -- edge arrows for off-screen players
            MaxDistance   = 2000,
            OnlyRoles     = false,       -- hide plain innocents
            TextSize      = 13,
            CoinESP       = false,
            GunESP        = true,
            TrapESP       = true,
            ColorMurderer = Color3.fromRGB(255, 64, 64),
            ColorSheriff  = Color3.fromRGB(64, 148, 255),
            ColorInnocent = Color3.fromRGB(112, 232, 128),
            ColorHero     = Color3.fromRGB(255, 196, 64),
        },
        Farm = {
            CoinFarm      = false,
            CoinMode      = "Teleport",  -- Teleport | Smooth | Walk
            CoinSpeed     = 90,
            CoinDelay     = 0.08,
            Magnet        = false,
            MagnetRadius  = 30,
            AutoGrabGun   = true,
            GrabReturn    = true,        -- snap back after grabbing
            AntiAFK       = true,
            LobbyFarm     = true,
        },
        Safety = {
            ProximityAlert = true,
            AlertDistance  = 45,
            AlertSound     = true,
            AlertFlash     = true,
            AutoDodge      = false,
            DodgeDistance  = 14,
            DodgeHeight    = 55,
            RoleNotify     = true,
        },
        Move = {
            SpeedEnabled  = false,
            Speed         = 32,
            SpeedMode     = "Humanoid",  -- Humanoid | CFrame
            JumpEnabled   = false,
            Jump          = 70,
            InfJump       = false,
            Bhop          = false,
            Noclip        = false,
            NoclipKey     = "N",
            Fly           = false,
            FlyKey        = "F",
            FlySpeed      = 70,
            Spinbot       = false,
        },
        Visual = {
            Fullbright    = false,
            Brightness    = 2,
            NoFog         = false,
            FovEnabled    = false,
            Fov           = 90,
            Xray          = false,
            XrayTransp    = 0.72,
            LowDetail     = false,
        },
        UI = {
            MenuKey       = "X",
            Accent        = Color3.fromRGB(178, 118, 255),
            Watermark     = true,
            KeybindList   = true,
            Notifications = true,
            AutoSave      = true,
            Profile       = "default",
        },
    }
    KH.Defaults = DEFAULTS

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

-- ─── src/mm2/03_util.lua ───────────────────────────────────────────────

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

    -- MM2 characters are R15, so the torso part name differs from R6. Aim and
    -- prediction both want the mass centre rather than the head.
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

    function U.keyHeld(name)
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

-- ─── src/mm2/04_game.lua ───────────────────────────────────────────────

-- ============================================================================
--  GAME — everything that knows what Murder Mystery 2 actually looks like
--
--  Verified against the live game's structure:
--    roles   ReplicatedStorage.GetPlayerData:InvokeServer() -> {[name] = {Role=...}}
--            ReplicatedStorage.Remotes.Gameplay.PlayerDataChanged (push)
--    shoot   Character.Gun.KnifeLocal.CreateBeam.RemoteFunction:InvokeServer(1, pos, "AH2")
--    stab    Character.Knife.Stab:FireServer("Down")
--    throw   Character.Knife.Events.KnifeThrown:FireServer(fromCF, toCF)
--    map     the workspace child owning both `CoinContainer` and `Spawns`
--    gun     a BasePart named `GunDrop`, parented into the map when a sheriff dies
-- ============================================================================

local Game = {}
KH.Game = Game

do
    local RS          = KH.Services.ReplicatedStorage
    local Players     = KH.Services.Players
    local U           = KH.U
    local LocalPlayer = KH.LocalPlayer

    Game.Data     = {}   -- [playerName] = {Role = ..., Killed = ..., Dead = ...}
    Game.Murderer = nil  -- player name, or nil before roles are dealt
    Game.Sheriff  = nil
    Game.Hero     = nil

    -- ------------------------------------------------------------- signals
    local listeners = {}

    function Game.on(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end

    local function emit(event, ...)
        for _, fn in ipairs(listeners[event] or {}) do
            KH.safe("event:" .. event, fn, ...)
        end
    end

    -- ------------------------------------------------------------- remotes
    -- MM2 moves these between updates, so resolve by recursive name lookup
    -- and re-resolve if the cached instance gets reparented.
    local remoteCache = {}
    local function findRemote(name)
        local cached = remoteCache[name]
        if cached and cached.Parent then return cached end
        local ok, found = pcall(function() return RS:FindFirstChild(name, true) end)
        if ok and found then
            remoteCache[name] = found
            return found
        end
        return nil
    end

    -- --------------------------------------------------------- role tracking
    local function applyData(data)
        if typeof(data) ~= "table" then return end
        Game.Data = data

        local murderer, sheriff, hero
        for name, entry in pairs(data) do
            if typeof(entry) == "table" then
                local role = entry.Role
                if role == "Murderer" then murderer = name
                elseif role == "Sheriff" then sheriff = name
                elseif role == "Hero" then hero = name end
            end
        end

        local changed = (murderer ~= Game.Murderer)
            or (sheriff ~= Game.Sheriff)
            or (hero ~= Game.Hero)

        Game.Murderer, Game.Sheriff, Game.Hero = murderer, sheriff, hero
        if changed then emit("RoleChange", murderer, sheriff, hero) end
    end
    Game.applyData = applyData

    function Game.refreshRoles()
        local remote = findRemote("GetPlayerData")
        if not remote then return false end
        local ok, data = pcall(function() return remote:InvokeServer() end)
        if ok and typeof(data) == "table" then
            applyData(data)
            return true
        end
        return false
    end

    -- The server pushes the whole table on any state change, which is how the
    -- murderer is known before their knife is visible to anyone.
    KH.spawn(function()
        local gameplay = findRemote("PlayerDataChanged")
        if gameplay and gameplay:IsA("RemoteEvent") then
            KH.track(gameplay.OnClientEvent:Connect(applyData))
        end
        Game.refreshRoles()
    end)

    -- Poll as a safety net: the push event is the fast path, but if it is ever
    -- renamed we still recover roles within a couple of seconds.
    KH.loop(2, function()
        if not Game.Murderer then Game.refreshRoles() end
    end)

    -- ------------------------------------------------- tool-based fallback
    -- No remote needed, and the only way to spot a Hero the moment they pick
    -- the gun up. Cached briefly: ESP asks for every role every frame.
    local toolCache, toolCacheAt = {}, 0

    local function toolRole(player)
        local char = U.charOf(player)
        local backpack = player:FindFirstChildOfClass("Backpack")
        if (char and char:FindFirstChild("Knife"))
            or (backpack and backpack:FindFirstChild("Knife")) then
            return "Murderer"
        end
        if (char and char:FindFirstChild("Gun"))
            or (backpack and backpack:FindFirstChild("Gun")) then
            return "Sheriff"
        end
        return nil
    end

    local function cachedToolRole(player)
        local now = os.clock()
        if now - toolCacheAt > 0.25 then
            toolCache, toolCacheAt = {}, now
        end
        local hit = toolCache[player]
        if hit == nil then
            hit = toolRole(player) or false
            toolCache[player] = hit
        end
        return hit or nil
    end

    function Game.roleOf(player)
        if not player then return "Innocent" end
        local entry = Game.Data[player.Name]
        local role = entry and entry.Role or nil
        local held = cachedToolRole(player)

        if role == nil or role == "Innocent" then
            if held == "Murderer" then
                role = "Murderer"
            elseif held == "Sheriff" then
                -- An innocent holding a gun picked it up off a dead sheriff.
                role = (role == "Innocent") and "Hero" or "Sheriff"
            end
        end
        return role or "Innocent"
    end

    function Game.colorOf(player)
        local role = Game.roleOf(player)
        local S = KH.S
        if role == "Murderer" then return S.ESP.ColorMurderer, role end
        if role == "Sheriff"  then return S.ESP.ColorSheriff,  role end
        if role == "Hero"     then return S.ESP.ColorHero,     role end
        return S.ESP.ColorInnocent, role
    end

    function Game.isAlive(player)
        local entry = Game.Data[player.Name]
        if entry and (entry.Killed or entry.Dead) then return false end
        return U.isAliveChar(player)
    end

    function Game.myRole() return Game.roleOf(LocalPlayer) end
    function Game.amSheriff()
        local role = Game.myRole()
        return role == "Sheriff" or role == "Hero"
    end
    function Game.amMurderer() return Game.myRole() == "Murderer" end

    -- Resolve names to live Player objects, skipping the dead.
    local function playerByName(name, requireAlive)
        if not name then return nil end
        local player = Players:FindFirstChild(name)
        if not player then return nil end
        if requireAlive and not Game.isAlive(player) then return nil end
        return player
    end

    function Game.murdererPlayer()
        local player = playerByName(Game.Murderer, true)
        if player then return player end
        -- Fallback for the window before role data arrives.
        for _, other in ipairs(U.otherPlayers()) do
            if cachedToolRole(other) == "Murderer" and Game.isAlive(other) then return other end
        end
        return nil
    end

    function Game.sheriffPlayer()
        return playerByName(Game.Sheriff, true) or playerByName(Game.Hero, true)
    end

    -- ------------------------------------------------------------------ map
    -- Whichever workspace child owns a CoinContainer. The lobby has one too,
    -- so it is matched separately.
    local function isMapModel(obj)
        return obj:FindFirstChild("CoinContainer") ~= nil
    end

    function Game.map()
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj.Name ~= "Lobby" and isMapModel(obj) then return obj end
        end
        return nil
    end

    function Game.lobby()
        local lobby = workspace:FindFirstChild("Lobby")
        if lobby and isMapModel(lobby) then return lobby end
        return nil
    end

    function Game.inRound() return Game.map() ~= nil end

    function Game.roundTime()
        local part = workspace:FindFirstChild("RoundTimerPart")
        if not part then return nil end
        local ok, value = pcall(function() return part:GetAttribute("Time") end)
        if ok and typeof(value) == "number" then return value end
        return nil
    end

    -- ---------------------------------------------------------------- coins
    -- Coin entries come in two shapes depending on map age: a bare BasePart, or
    -- a `Coin_Server` model wrapping `CoinVisual.MainCoin`.
    local function coinPart(obj)
        if obj:IsA("BasePart") then return obj end
        local visual = obj:FindFirstChild("CoinVisual")
        if visual then
            local main = visual:FindFirstChild("MainCoin")
            if main and main:IsA("BasePart") then return main end
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    Game.coinPart = coinPart

    function Game.coinContainers()
        local out = {}
        local map = Game.map()
        if map then
            local container = map:FindFirstChild("CoinContainer")
            if container then out[#out + 1] = container end
        end
        if KH.S.Farm.LobbyFarm then
            local lobby = Game.lobby()
            local container = lobby and lobby:FindFirstChild("CoinContainer")
            if container then out[#out + 1] = container end
        end
        return out
    end

    -- Returns {model = Instance, part = BasePart} pairs.
    function Game.coins()
        local out = {}
        for _, container in ipairs(Game.coinContainers()) do
            for _, obj in ipairs(container:GetChildren()) do
                local part = coinPart(obj)
                if part then out[#out + 1] = {model = obj, part = part} end
            end
        end
        return out
    end

    function Game.nearestCoin(skip)
        local root = U.myRoot()
        if not root then return nil end
        local best, bestDist = nil, math.huge
        for _, coin in ipairs(Game.coins()) do
            if not (skip and skip[coin.model]) then
                local dist = (coin.part.Position - root.Position).Magnitude
                if dist < bestDist then best, bestDist = coin, dist end
            end
        end
        return best, bestDist
    end

    -- ------------------------------------------------ dropped gun and traps
    -- By event, not by scanning: `GunDrop` appears at most once a round and a
    -- per-frame sweep of an MM2 map is expensive.
    Game.GunDrop = nil
    Game.Traps   = {}

    local function noteDescendant(obj)
        if obj.Name == "GunDrop" and obj:IsA("BasePart") then
            Game.GunDrop = obj
            emit("GunDropped", obj)
        elseif obj.Name == "Trap" and obj:IsA("BasePart") then
            Game.Traps[obj] = true
            emit("TrapPlaced", obj)
        end
    end

    local function forgetDescendant(obj)
        if obj == Game.GunDrop then
            Game.GunDrop = nil
            emit("GunTaken", obj)
        elseif Game.Traps[obj] then
            Game.Traps[obj] = nil
        end
    end

    KH.track(workspace.DescendantAdded:Connect(noteDescendant))
    KH.track(workspace.DescendantRemoving:Connect(forgetDescendant))

    -- Catch a gun already lying on the ground when the script is executed.
    KH.spawn(function()
        local map = Game.map()
        if map then
            local existing = map:FindFirstChild("GunDrop", true)
            if existing and existing:IsA("BasePart") then Game.GunDrop = existing end
        end
    end)

    -- --------------------------------------------------------- round change
    KH.track(workspace.ChildAdded:Connect(function(obj)
        task.wait(0.5) -- CoinContainer is parented in a frame or two after the model
        if obj.Parent == workspace and obj.Name ~= "Lobby" and isMapModel(obj) then
            Game.Traps = {}
            Game.GunDrop = nil
            emit("RoundStart", obj)
        end
    end))

    KH.track(workspace.ChildRemoved:Connect(function(obj)
        if obj.Name ~= "Lobby" and obj:FindFirstChild("CoinContainer") then
            Game.Data = {}
            Game.Murderer, Game.Sheriff, Game.Hero = nil, nil, nil
            Game.Traps = {}
            Game.GunDrop = nil
            emit("RoundEnd")
        end
    end))

    -- ---------------------------------------------------------------- tools
    local function findTool(name)
        local char = U.charOf(LocalPlayer)
        local held = char and char:FindFirstChild(name)
        if held then return held, true end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        local stowed = backpack and backpack:FindFirstChild(name)
        if stowed then return stowed, false end
        return nil, false
    end

    function Game.gunTool()   return findTool("Gun") end
    function Game.knifeTool() return findTool("Knife") end

    function Game.equip(tool)
        if not tool then return false end
        local char = U.charOf(LocalPlayer)
        if not char then return false end
        if tool.Parent == char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        return pcall(function() hum:EquipTool(tool) end)
    end

    -- ---------------------------------------------------------------- shoot
    -- A RemoteFunction taking a world position; the server does the hit test.
    -- Aim means sending the right coordinates, not moving the camera.
    local beamCache
    local function beamRemote(gun)
        if beamCache and beamCache.Parent and beamCache:IsDescendantOf(gun) then
            return beamCache
        end
        local remote
        local knifeLocal = gun:FindFirstChild("KnifeLocal")
        local createBeam = knifeLocal and knifeLocal:FindFirstChild("CreateBeam")
        if createBeam then
            remote = createBeam:FindFirstChild("RemoteFunction")
                or (createBeam:IsA("RemoteFunction") and createBeam)
        end
        -- Loose fallback in case the tool's internals get renamed again.
        if not remote then
            remote = gun:FindFirstChildWhichIsA("RemoteFunction", true)
        end
        beamCache = remote
        return remote
    end
    Game.beamRemote = beamRemote

    -- Older builds of the gun expect the tag "AH"; current ones want "AH2".
    -- Start on the current one and latch onto whichever the server accepts.
    local SHOT_TAGS = {"AH2", "AH"}
    local tagIndex = 1
    local equipPending = false
    Game.ShotsFired = 0

    function Game.shoot(position)
        local gun, equipped = Game.gunTool()
        if not gun then return false, "no gun" end
        if not equipped then
            -- One waiter at a time, or a held aim key stacks a fresh one every
            -- frame and they all fire at once when the gun lands.
            if equipPending then return false, "equipping" end
            -- MM2 rejects a shot from a gun that is not actually held, so draw
            -- it first. It stays out afterwards — nothing here ever stows it.
            if not Game.equip(gun) then return false, "could not equip" end
        end

        local remote = beamRemote(gun)
        if not remote then return false, "no shot remote" end

        -- InvokeServer blocks until the server replies. Off the render thread it
        -- goes, or a laggy round would freeze the whole menu.
        KH.detach(function()
            -- EquipTool is not instant, and the server drops a shot from a gun
            -- it does not yet think we hold — the first shot after a pickup.
            if not equipped then
                equipPending = true
                local char = U.charOf(LocalPlayer)
                local began = os.clock()
                while gun.Parent ~= char and os.clock() - began < 0.35 do
                    task.wait()
                    char = U.charOf(LocalPlayer)
                end
                equipPending = false
            end

            local ok = pcall(function()
                remote:InvokeServer(1, position, SHOT_TAGS[tagIndex])
            end)
            if not ok then
                tagIndex = (tagIndex % #SHOT_TAGS) + 1
                pcall(function()
                    remote:InvokeServer(1, position, SHOT_TAGS[tagIndex])
                end)
            end
        end)

        Game.ShotsFired = Game.ShotsFired + 1
        return true
    end

    -- ---------------------------------------------------------------- knife
    function Game.stab()
        local knife, equipped = Game.knifeTool()
        if not knife then return false, "no knife" end
        if not equipped and not Game.equip(knife) then return false, "could not equip" end

        local stab = knife:FindFirstChild("Stab")
        if not stab or not stab:IsA("RemoteEvent") then return false, "no stab remote" end

        pcall(function() stab:FireServer("Down") end)
        -- The swing is a down/up pair; without the release the tool can stick.
        KH.detach(function()
            task.wait(0.06)
            pcall(function() stab:FireServer("Up") end)
        end)
        return true
    end

    function Game.throwKnife(targetPos)
        local knife, equipped = Game.knifeTool()
        if not knife then return false, "no knife" end
        if not equipped and not Game.equip(knife) then return false, "could not equip" end

        local char = U.charOf(LocalPlayer)
        local hand = char and (char:FindFirstChild("RightHand")
            or char:FindFirstChild("Right Arm")
            or char:FindFirstChild("HumanoidRootPart"))
        if not hand then return false, "no hand" end

        local events = knife:FindFirstChild("Events")
        local thrown = events and events:FindFirstChild("KnifeThrown")
        if not thrown then thrown = knife:FindFirstChild("Throw") end
        if not thrown or not thrown:IsA("RemoteEvent") then return false, "no throw remote" end

        pcall(function()
            thrown:FireServer(CFrame.new(hand.Position), CFrame.new(targetPos))
        end)
        return true
    end
end

-- ─── src/mm2/05_ui_core.lua ────────────────────────────────────────────

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
            tween(entry.icon, 0.14, {TextTransparency = on and 0 or 0.35})
        end
        indicator.Visible = true
        tween(indicator, 0.2, {
            Position = UDim2.fromOffset(0, tab.button.AbsolutePosition.Y
                - Sidebar.AbsolutePosition.Y + tab.button.AbsoluteSize.Y / 2),
        }, Enum.EasingStyle.Back)
    end

    function UI.addTab(name, icon)
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

        local iconLabel = make("TextLabel", {
            Text = icon or "•",
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = C.Text,
            TextTransparency = 0.35,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(9, 0),
            Size = UDim2.fromOffset(20, 34),
            Parent = button,
        })
        local textLabel = make("TextLabel", {
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = C.TextDim,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(32, 0),
            Size = UDim2.new(1, -38, 1, 0),
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

        local tab = {name = name, button = button, page = page, label = textLabel, icon = iconLabel, sections = {}}
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

-- ─── src/mm2/06_ui_controls.lua ────────────────────────────────────────

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

-- ─── src/mm2/07_esp.lua ────────────────────────────────────────────────

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

-- ─── src/mm2/08_combat.lua ─────────────────────────────────────────────

-- ============================================================================
--  COMBAT — aimbot, silent aim, knife. MM2's gun is server-authoritative: the
--  shot is a RemoteFunction carrying a world position, so aiming means sending
--  good coordinates, not pointing a camera.
-- ============================================================================

do
    local UI          = KH.UI
    local U           = KH.U
    local Game        = KH.Game
    local S           = KH.S
    local LocalPlayer = KH.LocalPlayer

    local Combat = {}
    KH.Combat = Combat

    -- ===================================================== TARGET SELECTION
    local function shootableParts(player)
        local char = U.charOf(player)
        if not char then return nil end
        local part = S.Aim.AimAtHead and char:FindFirstChild("Head") or U.torsoOf(char)
        return char, part
    end

    -- char, part, distance when the player can be shot right now. No line of
    -- sight or range test on purpose: the server resolves the position, so
    -- walls and distance do not stop the shot.
    local function validate(player)
        if not player or player == LocalPlayer then return nil end
        if not Game.isAlive(player) then return nil end

        local char, part = shootableParts(player)
        if not char or not part then return nil end

        local myRoot = U.myRoot()
        local distance = myRoot and (myRoot.Position - part.Position).Magnitude or 0
        return char, part, distance
    end

    -- Angular distance from the crosshair, in pixels, or nil when off-screen.
    local function screenOffset(part)
        local cam = KH.camera()
        local pos, onScreen = U.toScreen(part.Position)
        if not onScreen then return nil end
        local centre = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        return (pos - centre).Magnitude
    end

    function Combat.pickTarget()
        local mode = S.Aim.Target

        if mode == "Murderer" then
            local murderer = Game.murdererPlayer()
            if not murderer then return nil end
            local char, part, distance = validate(murderer)
            if not char then return nil end
            return murderer, char, part, distance
        end

        local bestPlayer, bestChar, bestPart, bestDistance
        local bestScore = math.huge

        for _, player in ipairs(U.otherPlayers()) do
            local char, part, distance = validate(player)
            if char then
                local score
                if mode == "Crosshair" then
                    score = screenOffset(part)
                else -- Nearest
                    score = distance
                end
                if score and score < bestScore then
                    bestScore = score
                    bestPlayer, bestChar, bestPart, bestDistance = player, char, part, distance
                end
            end
        end
        return bestPlayer, bestChar, bestPart, bestDistance
    end

    function Combat.aimPoint(char, part)
        return U.predict(char, S.Aim.Prediction, S.Aim.PingComp, part) or part.Position
    end

    -- ============================================================== AIMBOT
    local lastShot = 0
    local toggleArmed = false
    Combat.LastTarget = nil

    function Combat.isEngaged()
        if not S.Aim.Enabled then return false end
        local mode = S.Aim.Mode
        if mode == "Always" then return true end
        if mode == "Toggle" then return toggleArmed end
        -- Press is one shot per key press, fired from the key handler. Never
        -- engaged, so the render loop leaves it alone.
        if mode == "Press" then return false end
        return U.keyHeld(S.Aim.Key)
    end

    function Combat.setToggle(on)
        toggleArmed = on
        if on then
            UI.notify({title = "Aimbot", text = "Locked on — auto-firing.", kind = "good", duration = 2})
        end
    end
    function Combat.toggleArmedState() return toggleArmed end

    -- Disarm at the end of a round: otherwise the lock grabs the camera again
    -- the moment the next murderer is known, before you have touched the key.
    Game.on("RoundEnd", function()
        if toggleArmed then
            toggleArmed = false
            UI.refreshKeybinds()
        end
    end)

    -- One cooldown for every shot the script sends: MM2 drops shots that land
    -- too close together, and the one it drops could be either feature's.
    function Combat.fireAt(position, force)
        local now = os.clock()
        if not force and now - lastShot < S.Aim.FireRate then return false, "cooldown" end
        lastShot = now
        return Game.shoot(position)
    end

    -- ========================================================== MOUSE AIM
    -- For the executors where the remote shot above never lands. Builds no shot
    -- at all: turns the camera onto the target, drives the real cursor onto
    -- them and clicks, so MM2's own gun fires it. Needs no hook, only synthetic
    -- mouse input. The cost is subtlety — the camera visibly snaps.
    local Mouse = {Firing = false, Turning = false}
    Combat.Mouse = Mouse

    do
        local GuiService = game:GetService("GuiService")
        local Players = KH.Services.Players

        -- Plain globals; one the executor lacks reads back nil.
        local moveRel = type(mousemoverel) == "function" and mousemoverel or nil
        local moveAbs = type(mousemoveabs) == "function" and mousemoveabs or nil
        local press   = type(mouse1press) == "function" and mouse1press or nil
        local release = type(mouse1release) == "function" and mouse1release or nil
        local click   = type(mouse1click) == "function" and mouse1click or nil

        -- The engine's own input injector, open to the elevated context an
        -- executor runs as. Touched now so a stripped service fails here
        -- rather than mid-shot.
        local VIM = (function()
            local ok, service = pcall(function() return game:GetService("VirtualInputManager") end)
            if not ok or typeof(service) ~= "Instance" then return nil end
            local fine = pcall(function() return service.SendMouseButtonEvent end)
            return fine and service or nil
        end)()

        Mouse.CanMove = (moveRel ~= nil) or (moveAbs ~= nil) or (VIM ~= nil)

        function Mouse.support()
            if not Mouse.CanMove then return "none — this executor cannot move the cursor" end
            local mover = moveRel and "mousemoverel"
                or moveAbs and "mousemoveabs"
                or "VirtualInputManager"
            local clicker = (press and release) and "mouse1press"
                or click and "mouse1click"
                or VIM and "VirtualInputManager"
                or "Tool:Activate"
            return mover .. " + " .. clicker
        end

        local mouseObj
        local function project(pos)
            local point, onScreen = KH.camera():WorldToViewportPoint(pos)
            -- Behind the camera the X/Y come back mirrored: chasing them walks
            -- the cursor the wrong way, so depth has to agree.
            return Vector2.new(point.X, point.Y), onScreen and point.Z > 0
        end

        -- Where the cursor is, in the same space the target is projected into.
        --
        -- mouse.X/Y are plain screen coordinates and never lag, but they and
        -- WorldToViewportPoint disagree about the topbar on some clients, and a
        -- constant offset between the two is a constant aim error. Projecting
        -- the world point under the cursor lands in the right space but lags a
        -- frame behind the camera, because that point is computed before the
        -- lock turns the view. So take the difference between the two on the
        -- frames where the camera is still — the frames where both readings are
        -- good — and carry it. Right space, no lag, nothing assumed.
        local offset = Vector2.zero
        local function cursor()
            mouseObj = mouseObj or LocalPlayer:GetMouse()
            local raw = Vector2.new(mouseObj.X, mouseObj.Y)
            if not Mouse.Turning then
                local ok, hit = pcall(function() return mouseObj.Hit.Position end)
                if ok and typeof(hit) == "Vector3" then
                    local point, onScreen = project(hit)
                    if onScreen then offset = point - raw end
                end
            end
            return raw + offset, mouseObj
        end

        -- What a viewport pixel is worth to the cursor. A relative move is in OS
        -- pixels and the projection is in viewport pixels, and on a scaled
        -- display those are not the same unit — so rather than assume, watch
        -- what the last move actually achieved and correct the next one.
        local gain = 1
        local function learn(want, got)
            if not moveRel then return end
            if want.Magnitude < 8 or got.Magnitude < 2 then return end
            -- A real display scale lives near 1. Anything wilder is a dropped
            -- frame or a cursor that hit the edge of the window, and folding
            -- that into the gain is how the aim runs away.
            local ratio = want.Magnitude / got.Magnitude
            if ratio < 0.4 or ratio > 2.5 then return end
            gain = U.clamp(gain * ratio, 0.5, 2)
        end

        -- Drag the cursor back inside the window. Once it is out there — put
        -- there by an earlier bad move, or by the player in windowed mode —
        -- mouse.X/Y stick to the border, so every reading is the same pixel and
        -- the walk cannot tell where it is or how far it moved. A big move
        -- inwards is the only way back. Gain is deliberately not applied: in
        -- this state it is the value least worth trusting.
        local function sweepHome(here)
            if not moveRel then return false end   -- absolute movers cannot lose it
            local view = KH.camera().ViewportSize
            local push = Vector2.new(view.X * 0.5, view.Y * 0.5) - here
            if push.Magnitude < 1 then return false end
            local far = push.Unit * (view.Magnitude * 0.75)
            return (pcall(moveRel, math.floor(far.X + 0.5), math.floor(far.Y + 0.5)))
        end

        -- The cursor has to stay somewhere Roblox can still see it. Outside the
        -- window mouse.X/Y stop moving, so every further move reads as achieving
        -- nothing at all.
        local function clampToView(point)
            local view = KH.camera().ViewportSize
            return Vector2.new(
                U.clamp(point.X, 6, math.max(view.X - 6, 6)),
                U.clamp(point.Y, 6, math.max(view.Y - 6, 6)))
        end

        local function moveTo(here, point)
            if moveRel then
                local delta = (point - here) * gain
                return (pcall(moveRel, math.floor(delta.X + 0.5), math.floor(delta.Y + 0.5)))
            end
            local inset = GuiService:GetGuiInset()
            local x, y = point.X + inset.X, point.Y + inset.Y
            if moveAbs then
                return (pcall(moveAbs, math.floor(x + 0.5), math.floor(y + 0.5)))
            end
            if VIM then
                return (pcall(function() VIM:SendMouseMoveEvent(x, y, game) end))
            end
            return false
        end

        -- Down, then up: MM2 shoots on the press, but a button left held means
        -- the next press never arrives.
        local function shootHere()
            if press and release then
                if pcall(press) then
                    -- MM2 shoots on the press, so the release only has to
                    -- happen; waiting here would just delay the next shot.
                    KH.detach(function()
                        task.wait(0.04)
                        pcall(release)
                    end)
                    return true
                end
                pcall(release)
            end
            if click and pcall(click) then return true end
            if VIM then
                local point = cursor()
                local inset = GuiService:GetGuiInset()
                local x, y = point.X + inset.X, point.Y + inset.Y
                local ok = pcall(function()
                    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                    task.wait(0.04)
                    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
                end)
                if ok then return true end
            end
            -- Last resort. MM2 reads the cursor either way, so this still lands
            -- where we pointed — unless the gun listens for the raw button.
            local gun, equipped = Game.gunTool()
            if gun and equipped then
                return (pcall(function() gun:Activate() end))
            end
            return false
        end

        local TOLERANCE = 4     -- pixel floor for "close enough"
        local MAX_STEPS = 16
        local LEAD      = 0.7   -- share of a frame's drift to aim ahead by

        -- Where to point. Not Combat.aimPoint: prediction leads the target for
        -- the remote route's flight and ping, and a client raycast has neither,
        -- so the lead only walks the ray off the body — hardest on a falling
        -- target, whose damped -Y velocity drags the aim metres underneath them.
        local function livePoint(part)
            return part.Position
        end
        Mouse.livePoint = livePoint

        -- Where the target sits on screen right now, for the camera lock.
        function Mouse.screenOf(part)
            return project(livePoint(part))
        end

        -- How big they look from here. The cursor has to end up on their body,
        -- not on a point: four pixels is nothing to a target crossing twenty a
        -- frame, and the walk would never call itself close enough.
        local function bodyRadius(part, point)
            local ok, edge = pcall(function()
                return project(part.Position + Vector3.new(0, part.Size.Y * 0.5, 0))
            end)
            if not ok then return TOLERANCE end
            return U.clamp((edge - point).Magnitude, TOLERANCE, 150)
        end

        -- A press projects before the camera lock has had a frame to run, so a
        -- target who is off screen this instant may simply not have been turned
        -- to yet. Give the lock a few frames before writing them off.
        local function waitVisible(part)
            local speed = U.clamp(S.Aim.MouseSpeed or 1, 0.1, 1)
            for _ = 1, math.clamp(math.ceil(6 / speed), 6, 30) do
                local _, onScreen = project(livePoint(part))
                if onScreen then return true end
                if not S.Aim.CameraSnap then return false end
                task.wait()
            end
            return false
        end

        -- Walks the cursor onto the target and says whether it got there. Not
        -- one jump: a relative move only lands next frame, and the target keeps
        -- moving while we close on it.
        local function pointAt(char, part)
            if not waitVisible(part) then return false, "off screen" end
            local speed = U.clamp(S.Aim.MouseSpeed or 1, 0.1, 1)
            local steps = math.clamp(math.ceil(1 / speed), 1, MAX_STEPS)
            local lastFrom, lastWant, lastPoint
            local lastGap, worse, stuck = nil, 0, 0

            for step = 1, MAX_STEPS do
                if not (char.Parent and part.Parent) then return false, "target gone" end

                local here, m = cursor()

                -- Asked it to move and it did not. That means the cursor is
                -- outside the Roblox window, where its reported position stops
                -- changing — so every later move would be computed from a
                -- position that is no longer real. Sweep it back in, throw away
                -- the calibration that put it there, and start the walk over.
                local recovering = false
                if lastWant and lastWant.Magnitude >= 8 and (here - lastFrom).Magnitude < 1 then
                    stuck = stuck + 1
                    if stuck >= 2 then
                        stuck, gain = 0, 1
                        lastFrom, lastWant, lastPoint, lastGap = nil, nil, nil, nil
                        if not sweepHome(here) then return false, "cursor is off the window" end
                        recovering = true
                    end
                else
                    stuck = 0
                end

                if recovering then
                    task.wait()
                else
                    -- The camera belongs to the lock below; two writers a frame
                    -- is how the cursor ends up chasing a point that moves.
                    local point, onScreen = project(livePoint(part))
                    if not onScreen then return false, "off screen" end

                    if lastWant then learn(lastWant, here - lastFrom) end

                    -- Walking away from the target three steps running means
                    -- the calibration is wrong rather than the aim. Drop it and
                    -- start over instead of chasing the cursor round the screen.
                    local gap = (point - here).Magnitude
                    if lastGap and gap > lastGap + 2 then
                        worse = worse + 1
                        if worse >= 3 then
                            gain = 1
                            return false, "cursor ran away — recalibrated"
                        end
                    else
                        worse = 0
                    end
                    lastGap = gap

                    -- Being on their body is the test that matters. The pixel
                    -- distance is the fallback for when something in front of
                    -- them owns the cursor's ray.
                    local hit = m.Target
                    if hit and hit:IsDescendantOf(char) then return true, "on target" end
                    if gap <= bodyRadius(part, point) then
                        -- MM2 shoots where the cursor's ray stops. A wall costs
                        -- a wasted shot, but another player standing in the line
                        -- costs the round: a sheriff who shoots an innocent dies
                        -- for it. Hold fire and let the next press try again.
                        local blocker = hit and hit:FindFirstAncestorOfClass("Model")
                        local owner = blocker and Players:GetPlayerFromCharacter(blocker)
                        if owner and owner ~= LocalPlayer then
                            return false, "holding fire — " .. owner.DisplayName .. " is in the line"
                        end
                        return true, hit and ("through " .. hit.Name) or "on target"
                    end

                    -- Aim where they will be once this move lands, not where
                    -- they were when it was projected: without this the cursor
                    -- trails a running target forever. Short of a full frame,
                    -- though — while the camera is easing the drift is slowing
                    -- down, and leading it in full overshoots and comes back.
                    local aim = lastPoint and (point + (point - lastPoint) * LEAD) or point
                    lastPoint = point

                    -- A fixed fraction of the gap never arrives; a share of the
                    -- steps left arrives exactly on the last one.
                    local left = math.max(1, steps - step + 1)
                    local dest = clampToView(here + (aim - here) / left)
                    -- Learn against what was actually asked for, which is the
                    -- clamped move, not the one we would have liked to make.
                    lastFrom, lastWant = here, dest - here
                    if not moveTo(here, dest) then
                        return false, "no mouse control"
                    end
                    task.wait()
                end
            end
            gain = 1
            return false, "could not reach"
        end

        local busy = false
        local activePart

        -- The part the in-flight sequence is aiming at, or nil between shots.
        function Mouse.active() return activePart end

        -- One at a time: the walk yields across frames, and the render loop
        -- would otherwise have a dozen of them fighting over the cursor.
        function Mouse.fire(player, char, part, force)
            if busy then return false, "aiming" end
            if not Mouse.CanMove then return false, "no mouse control" end

            local now = os.clock()
            if not force and now - lastShot < S.Aim.FireRate then return false, "cooldown" end
            lastShot = now
            busy = true
            activePart = part

            local function sequence()
                local gun, equipped = Game.gunTool()
                if gun and not equipped then
                    -- The click needs a gun that is actually out, and EquipTool
                    -- does not land in the same frame.
                    Game.equip(gun)
                    local began = os.clock()
                    while not select(2, Game.gunTool()) and os.clock() - began < 0.35 do
                        task.wait()
                    end
                end

                local reached, why = pointAt(char, part)
                if not reached then
                    Combat.LastResult = "mouse aim — " .. why
                    -- No shot went out; do not charge the next one a cooldown.
                    lastShot = 0
                    return
                end

                Mouse.Firing = true
                local sent = shootHere()
                Combat.LastResult = sent
                    and ("mouse shot at " .. player.DisplayName .. " — " .. why)
                    or "cursor on target but the click went nowhere"
            end

            KH.detach(function()
                -- Both flags have to clear even if the walk throws. A stuck
                -- busy refuses every later shot, and a stuck Firing makes the
                -- silent-aim handler ignore every real click.
                local ok, err = pcall(sequence)
                Mouse.Firing = false
                activePart = nil
                busy = false
                if not ok then Combat.LastResult = "mouse aim error: " .. tostring(err) end
            end)
            return true
        end
    end

    -- Fires once at the current best target. Returns true when a shot went out.
    function Combat.fireOnce(force)
        local gun = Game.gunTool()
        if not gun then
            Combat.LastResult = "no gun — you are not holding one"
            return false, "no gun"
        end

        local player, char, part = Combat.pickTarget()
        if not player then
            Combat.LastResult = "no target"
            return false, "no target"
        end
        Combat.LastTarget = player

        local ok, err
        if S.Aim.Method == "Mouse" then
            -- Mouse.fire reports its own result, several frames from now.
            ok, err = Mouse.fire(player, char, part, force)
        else
            ok, err = Combat.fireAt(Combat.aimPoint(char, part), force)
            if ok then
                Combat.LastResult = "remote shot at " .. player.DisplayName
            elseif err ~= "cooldown" then
                -- A cooldown is the fire rate doing its job, not a failure.
                Combat.LastResult = tostring(err)
            end
        end
        if not ok then return false, err end

        if S.Aim.NotifyShot then
            UI.notify({title = "Shot", text = "Fired at " .. player.DisplayName, duration = 1.5})
        end
        return ok, err
    end

    -- Why the aimbot is or is not shooting. A dead key, no gun and a shot the
    -- server drops all look identical, and only the last one means anything.
    function Combat.aimStatus()
        if not S.Aim.Enabled then return "off" end
        if not Combat.isEngaged() then
            local key = tostring(S.Aim.Key)
            if S.Aim.Mode == "Press" then
                -- The last press is the only thing worth reporting here.
                return "ready — press " .. key .. (Combat.LastResult and (" · last: " .. Combat.LastResult) or "")
            end
            if S.Aim.Mode == "Toggle" then return "not armed — press " .. key end
            if S.Aim.Mode == "Hold" then return "waiting for " .. key end
            return "idle"
        end
        return "engaged — " .. (Combat.LastResult or "...")
    end

    -- Bound after Roblox's own camera step rather than onto KH's render job.
    -- The job runs before the camera module, so every lock we wrote there was
    -- overwritten in the same frame — the aim fighting itself, once per frame.
    do
        local RunService = KH.Services.RunService
        local BIND = "KittyHubAimCam"

        -- Start turning at the edge of the view, stop well inside it. The gap
        -- between the two is what stops a target hovering near the border from
        -- switching the lock on and off every frame.
        local TURN_IN, TURN_OUT = 0.10, 0.28

        local turning = false
        local held              -- the rotation we are driving, nil when hands off

        -- How far into the view the target is: 0 at the border, 0.5 dead
        -- centre, negative off screen.
        local function inset(part)
            local point, onScreen = Combat.Mouse.screenOf(part)
            if not onScreen then return -1 end
            local view = KH.camera().ViewportSize
            return math.min(
                math.min(point.X, view.X - point.X) / math.max(view.X, 1),
                math.min(point.Y, view.Y - point.Y) / math.max(view.Y, 1))
        end

        -- What the lock should be aiming at, or nil for hands off. Ordered
        -- cheapest test first: this runs every rendered frame of the session,
        -- and in Press mode it answers nil on the second line nearly always.
        local function lockTarget()
            if S.Aim.Method ~= "Mouse" or not S.Aim.CameraSnap then return nil end

            -- While a shot is in flight, hold that shot's target. Between
            -- shots only the sustained triggers keep the camera, which is what
            -- lets Press lock on, fire, and hand it straight back.
            local part = Combat.Mouse.active()
            if not part then
                if not Combat.isEngaged() then return nil end
                local _, _, picked = Combat.pickTarget()
                part = picked
            end
            -- Last, because it is the only test that walks the character.
            if part and Game.gunTool() then return part end
            return nil
        end

        local function lockCamera(dt)
            local part = lockTarget()
            if part then
                -- Turn only when there is something to turn for: a target
                -- already well inside the view needs no camera work at all,
                -- and a view that stays still is both smoother and far less
                -- obvious than one that snaps on every shot.
                local depth = inset(part)
                if depth < TURN_IN then turning = true
                elseif depth > TURN_OUT then turning = false end
            else
                turning = false
            end
            -- The walk needs to know: while this is true its projected cursor
            -- reading is a frame behind the camera and must not be trusted.
            Combat.Mouse.Turning = turning
            if not (turning or held) then return end

            local cam = KH.camera()
            local speed = U.clamp(S.Aim.MouseSpeed or 1, 0.1, 1)
            -- The same share of the gap per second rather than per frame, so
            -- the turn lasts the same at 30 fps as at 144.
            local alpha = speed >= 1 and 1
                or U.clamp(1 - (1 - speed) ^ ((dt or 1 / 60) * 60), 0, 1)

            -- Position belongs to the camera module, which has already written
            -- it this frame; we only ever replace the rotation, carried forward
            -- from wherever the module has just put the camera.
            held = CFrame.new(cam.CFrame.Position) * (held or cam.CFrame).Rotation

            if turning then
                held = held:Lerp(CFrame.new(cam.CFrame.Position, Combat.Mouse.livePoint(part)), alpha)
                cam.CFrame = held
                return
            end

            -- Turned far enough, but the shot is still in the air: hold this
            -- rotation rather than starting to give it back. Drifting towards
            -- the player's angles now would walk the target across the screen
            -- while the cursor is still closing on it, and the two would spend
            -- the rest of the shot chasing each other.
            if Combat.Mouse.active() then
                cam.CFrame = held
                return
            end

            -- Hand it back over a few frames rather than dropping it. The
            -- module still holds the angles the player left it at, so letting
            -- go in one frame snaps the view — easing into its CFrame, which is
            -- what we just read, turns that snap into a turn.
            held = held:Lerp(cam.CFrame, alpha)
            if held.LookVector:Dot(cam.CFrame.LookVector) > 0.9995 then
                held = nil
                return
            end
            cam.CFrame = held
        end

        -- A bind left over from a session that failed to unload would make
        -- this one error out and leave the camera unlocked.
        pcall(function() RunService:UnbindFromRenderStep(BIND) end)
        pcall(function()
            RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
                if KH.Alive then KH.safe("aimcam", lockCamera, dt) end
            end)
        end)
        KH.undo(function() pcall(function() RunService:UnbindFromRenderStep(BIND) end) end)
    end

    KH.onFrame("aimbot", function()
        if not Combat.isEngaged() then return end
        Combat.fireOnce(false)
    end, 30)

    -- MM2 stows your tool on respawn and when a round flips, which would
    -- leave the next round's first shot doing nothing but re-equipping.
    KH.loop(0.5, function()
        if not (S.Aim.Enabled and S.Aim.KeepEquipped) then return end
        local gun, equipped = Game.gunTool()
        if gun and not equipped then Game.equip(gun) end
    end)

    -- =========================================================== SILENT AIM
    -- The shot *you* fire by hand lands on the target instead of under your
    -- cursor. Three routes, best available wins:
    --   hook      rewrite the position argument in flight. Invisible, but needs
    --             a real hookmetamethod or a writable game metatable.
    --   takeover  no hook: switch MM2's gun script off so your click stops
    --             producing a shot of its own, and fire the aimed one from that
    --             same click. One shot, out of a plain property write.
    --   click     neither: an aimed shot beside your real one, two beams.
    do
        local X = KH.X
        local UIS = KH.Services.UserInputService

        -- --------------------------------------------------------- route probe
        -- Takeover needs one thing: switching a client script off. A throwaway
        -- instance settles that without going near the gun.
        local canDisableScripts = (function()
            local ok, disabled = pcall(function()
                local probe = Instance.new("LocalScript")
                probe.Disabled = true
                local value = probe.Disabled
                probe:Destroy()
                return value
            end)
            return ok and disabled == true
        end)()

        local hookReady = false      -- set by the install self-test below
        local suppressed = {}        -- [BaseScript] = true, ones we turned off

        -- Which route is live. The manual settings exist because "installed"
        -- and "works" are not the same claim on these executors.
        local function effectiveMode()
            local want = S.Aim.SilentMode or "Auto"
            if want == "Click" then return "click" end
            -- Takeover switches MM2's gun script off; the mouse aimbot fires
            -- that same script. They cannot both be on, and the aimbot wins.
            local canTakeover = canDisableScripts and S.Aim.Method ~= "Mouse"
            if want == "Takeover" then return canTakeover and "takeover" or "click" end
            if hookReady then return "hook" end
            -- Auto and Hook both prefer the hook, and both fall back the same
            -- way when there isn't one.
            return canTakeover and "takeover" or "click"
        end
        Combat.effectiveMode = effectiveMode

        -- ------------------------------------------------------ route 1: hook
        -- Must never throw — an error here breaks the call it wrapped, leaving
        -- the gun unable to shoot — and must ignore our own calls, or Kill All
        -- would have every shot rewritten onto one target. No reliable unhook
        -- exists, so it stays installed and passes through once KH.Alive drops.
        local oldNamecall            -- the original, set by whichever route installs
        local verifying = true       -- flipped off once the install self-test is done
        local sawCall = false

        local function onNamecall(self, ...)
            if verifying then sawCall = true end
            if not oldNamecall then return end
            if not KH.Alive or not S.Aim.SilentAim then
                return oldNamecall(self, ...)
            end
            -- Forced onto another route: leave the shot exactly as it was sent.
            if not verifying and effectiveMode() ~= "hook" then
                return oldNamecall(self, ...)
            end
            if X.checkcaller and checkcaller() then
                -- Our own Game.shoot() call; already aimed.
                return oldNamecall(self, ...)
            end

            local ok, redirected = pcall(function(...)
                if getnamecallmethod() ~= "InvokeServer" then return nil end

                -- Only the gun's own beam remote is of interest.
                local parent = typeof(self) == "Instance" and self.Parent or nil
                if not parent or parent.Name ~= "CreateBeam" then return nil end

                local args = table.pack(...)
                if typeof(args[2]) ~= "Vector3" then return nil end

                local player, char, part = Combat.pickTarget()
                if not (player and char and part) then return nil end

                args[2] = Combat.aimPoint(char, part)
                Combat.LastTarget = player
                return args
            end, ...)

            if ok and redirected then
                return oldNamecall(self, table.unpack(redirected, 1, redirected.n))
            end
            return oldNamecall(self, ...)
        end

        -- Two ways in: the convenience wrapper, then the raw metatable for
        -- executors that only expose the primitives.
        local function installHook()
            local cb = onNamecall
            if X.newcclosure then
                -- Some executors reject a plain Lua closure as a metamethod.
                local ok, wrapped = pcall(newcclosure, cb)
                if ok and type(wrapped) == "function" then cb = wrapped end
            end

            if X.hookmetamethod then
                local ok, old = pcall(hookmetamethod, game, "__namecall", cb)
                if ok and type(old) == "function" then
                    oldNamecall = old
                    return "hookmetamethod"
                end
            end

            if X.rawmeta then
                local ok = pcall(function()
                    local mt = getrawmetatable(game)
                    local old = rawget(mt, "__namecall")
                    if type(old) ~= "function" then error("__namecall is not a function") end
                    setreadonly(mt, false)
                    oldNamecall = old
                    mt.__namecall = cb
                    setreadonly(mt, true)
                end)
                if ok then return "getrawmetatable" end
                oldNamecall = nil
            end
        end

        local route = installHook()
        if route then
            -- Reporting success and never firing is the normal failure here,
            -- so prove it runs on a harmless call before trusting it.
            pcall(function() return game:GetService("Players") end)
            verifying = false
            hookReady = sawCall
            Combat.SilentRoute = route
            if not sawCall then
                Combat.SilentReason = "the " .. route .. " hook installed but never fires"
            end
        else
            verifying = false
            Combat.SilentReason = (X.hookmetamethod or X.rawmeta)
                and "this executor's metamethod hook could not be installed"
                or "this executor exposes no metamethod hook"
        end
        Combat.HookAvailable = hookReady

        -- -------------------------------------------------- route 2: takeover
        -- Client-side property writes do not replicate, so the server's view of
        -- the tool is untouched — it just stops hearing from the script that
        -- spoke for your mouse. You lose the local shot sound and muzzle flash;
        -- the beam and the kill are the server's work and look normal.
        local function isClientScript(inst)
            if inst:IsA("LocalScript") then return true end
            if not inst:IsA("Script") then return false end
            -- A re-upload could use a client-context Script instead.
            local ok, ctx = pcall(function() return inst.RunContext end)
            return ok and ctx == Enum.RunContext.Client
        end

        -- Only record scripts *we* turned off, so restoring never switches on
        -- something MM2 disabled for its own reasons.
        local function suppress(gun)
            -- Every round destroys the old Gun, so drop the dead entries or the
            -- table grows for the whole session.
            for inst in pairs(suppressed) do
                if not inst.Parent then suppressed[inst] = nil end
            end

            for _, inst in ipairs(gun:GetDescendants()) do
                local ok, isClient = pcall(isClientScript, inst)
                if ok and isClient and not inst.Disabled then
                    if pcall(function() inst.Disabled = true end) and inst.Disabled then
                        suppressed[inst] = true
                    end
                end
            end
        end

        local function restore()
            if not next(suppressed) then return end
            for inst in pairs(suppressed) do
                pcall(function() inst.Disabled = false end)
            end
            suppressed = {}

            -- Re-enabling restarts the script from the top. One that only
            -- connects from Equipped would sit dead until the gun is next
            -- drawn, so hand it that event rather than guess which it is.
            local gun, equipped = Game.gunTool()
            if gun and equipped then
                KH.detach(function()
                    local char = U.charOf(LocalPlayer)
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hum then return end
                    pcall(function() hum:UnequipTools() end)
                    task.wait(0.1)
                    Game.equip(gun)
                end)
            end
        end
        KH.undo(restore)

        -- On a timer, not once: the Gun is a fresh instance every round, and
        -- the toggle and unload have to hand it back at any moment.
        KH.loop(0.3, function()
            if KH.Alive and S.Aim.SilentAim and effectiveMode() == "takeover" then
                local gun = Game.gunTool()
                if gun then suppress(gun) end
            elseif next(suppressed) then
                restore()
            end
        end)

        -- --------------------------------------------------------- your click
        -- Under takeover this *is* the gun — MM2's script is off, so if this
        -- does not fire, nothing does. Under the hook it stays out of the way.
        local mouse
        local function mousePoint()
            local ok, point = pcall(function()
                mouse = mouse or LocalPlayer:GetMouse()
                return mouse.Hit.Position
            end)
            if ok and typeof(point) == "Vector3" then return point end
            return nil
        end

        KH.track(UIS.InputBegan:Connect(function(input, processed)
            -- Touch counts: no-hook executors are also the phone ones.
            local kind = input.UserInputType
            if kind ~= Enum.UserInputType.MouseButton1
                and kind ~= Enum.UserInputType.Touch then return end
            if processed then return end          -- the input landed on the menu
            if Combat.Mouse.Firing then return end -- our own synthetic click
            if not (KH.Alive and S.Aim.SilentAim) then return end

            local mode = effectiveMode()
            if mode == "hook" then return end     -- the hook already redirected it

            -- Only with the gun genuinely in hand. Drawing it here would yank
            -- a murderer's knife away mid-round.
            local gun, equipped = Game.gunTool()
            if not (gun and equipped) then return end

            local ok, err = Combat.fireOnce(false)
            if not ok and err == "no target" and mode == "takeover" then
                -- Nothing to redirect onto and MM2's script is off, so put the
                -- round where you actually pointed.
                local point = mousePoint()
                if point then Combat.fireAt(point, false) end
            end
        end))

        -- ------------------------------------------------------------- status
        -- Both real routes give one shot on target; only "click" has to apologise.
        Combat.SilentDesc = hookReady
            and "Redirects the shot you fire by hand onto the target. One shot, and nothing on screen moves."
            or (canDisableScripts
                and "No working hook on this executor, so Kitty Hub switches MM2's gun script off and fires the aimed shot on your click itself. Still one shot; you lose the local shot sound."
                or "No route on this executor — your click fires an aimed shot beside your real one, so two beams go out.")

        function Combat.silentStatus()
            local mode = effectiveMode()
            if mode == "hook" then
                return "hook (" .. tostring(Combat.SilentRoute) .. ")"
            elseif mode == "takeover" then
                return "takeover" .. (next(suppressed) and " — gun script off" or " — waiting for gun")
            end
            -- Only say *why* when it was forced on us.
            if S.Aim.SilentMode == "Click" then return "click aim, two shots — your choice" end
            if canDisableScripts and S.Aim.Method == "Mouse" then
                return "click aim, two shots — takeover is off while Fire Method is Mouse"
            end
            return "click aim, two shots — " .. (Combat.SilentReason or "no route")
        end
    end

    -- ============================================================= KILL ALL
    -- Sequential, not a burst: MM2 rate-limits the shot remote.
    local killAllRunning = false
    function Combat.killAll()
        if killAllRunning then return end
        if not Game.gunTool() then
            UI.notify({title = "Kill All", text = "You are not holding a gun.", kind = "bad"})
            return
        end
        killAllRunning = true
        KH.detach(function()
            local count = 0
            for _, player in ipairs(U.otherPlayers()) do
                if not KH.Alive then break end
                if Game.isAlive(player) then
                    local char, part = shootableParts(player)
                    if char and part then
                        Game.shoot(Combat.aimPoint(char, part))
                        count = count + 1
                        task.wait(0.12)
                    end
                end
            end
            killAllRunning = false
            UI.notify({title = "Kill All", text = ("Fired at %d players."):format(count), kind = "good"})
        end)
    end

    -- =============================================================== KNIFE
    local function knifeTargets()
        local out = {}
        local myRoot = U.myRoot()
        if not myRoot then return out end

        for _, player in ipairs(U.otherPlayers()) do
            if Game.isAlive(player) then
                local role = Game.roleOf(player)
                local isSheriff = (role == "Sheriff" or role == "Hero")
                -- Prioritising the sheriff is the sort's job, below. Filtering
                -- here as well left an empty list whenever no sheriff was alive.
                if not (S.Knife.SkipSheriff and isSheriff) then
                    local char = U.charOf(player)
                    local part = char and U.torsoOf(char)
                    if part then
                        out[#out + 1] = {
                            player = player, char = char, part = part,
                            distance = (myRoot.Position - part.Position).Magnitude,
                            sheriff = isSheriff,
                        }
                    end
                end
            end
        end

        -- Sheriff first when asked for, then by proximity.
        table.sort(out, function(a, b)
            if S.Knife.TargetSheriff and a.sheriff ~= b.sheriff then return a.sheriff end
            return a.distance < b.distance
        end)
        return out
    end
    Combat.knifeTargets = knifeTargets

    function Combat.throwAtNearest()
        if not Game.knifeTool() then return false end
        local target = knifeTargets()[1]
        if not target then return false end
        -- A thrown knife is gone until it comes back, so it is only worth
        -- throwing at a range the throw can actually cover.
        if target.distance > (S.Knife.ThrowRange or 70) then return false end
        local point = U.predict(target.char, S.Aim.Prediction + 1, S.Aim.PingComp) or target.part.Position
        return Game.throwKnife(point)
    end

    -- Auto throw
    KH.loop(0.1, function()
        if not S.Knife.AutoThrow then return end
        if not Game.knifeTool() then return end
        Combat.throwAtNearest()
        task.wait(math.max(S.Knife.ThrowDelay, 0.2))
    end)

    -- Knife aura: stab anything that wanders into range.
    KH.loop(0.05, function()
        if not S.Knife.Aura then return end
        if not Game.knifeTool() then return end
        local targets = knifeTargets()
        local nearest = targets[1]
        if nearest and nearest.distance <= S.Knife.AuraRadius then
            Game.stab()
            task.wait(math.max(S.Knife.AuraDelay, 0.05))
        end
    end)

    -- Blink to the target, swing, blink back. The return hop is what keeps it
    -- from reading as a teleport to everyone else.
    local tpStabRunning = false
    function Combat.tpStab()
        if tpStabRunning then return end
        if not Game.knifeTool() then
            UI.notify({title = "Knife", text = "You are not holding a knife.", kind = "bad"})
            return
        end
        local target = knifeTargets()[1]
        if not target then return end
        -- Blinking the length of the map to reach someone is not a stab, it is
        -- a teleport everyone can see.
        if target.distance > (S.Knife.TpRange or 150) then return end

        tpStabRunning = true
        KH.detach(function()
            local root = U.myRoot()
            if root then
                local origin = root.CFrame
                -- Already within swinging distance: no reason to blink at all.
                if target.distance > 6 then
                    root.CFrame = target.part.CFrame * CFrame.new(0, 0, 2.5)
                    task.wait(0.08)
                end
                Game.stab()
                task.wait(0.12)
                -- Same body only. Dying mid-blink would otherwise drag the
                -- fresh spawn back to where the old one was standing.
                if U.myRoot() == root then root.CFrame = origin end
            end
            tpStabRunning = false
        end)
    end

    KH.loop(0.1, function()
        if S.Knife.TpStab and Game.knifeTool() then
            Combat.tpStab()
            task.wait(0.35)
        end
    end)
end

-- ─── src/mm2/09_farm.lua ───────────────────────────────────────────────

-- ============================================================================
--  FARM — coin collection, the coin magnet, gun-drop grabbing, anti-AFK
-- ============================================================================

do
    local UI          = KH.UI
    local U           = KH.U
    local Game        = KH.Game
    local S           = KH.S
    local X           = KH.X
    local VirtualUser = KH.Services.VirtualUser
    local LocalPlayer = KH.LocalPlayer

    local Farm = {}
    KH.Farm = Farm
    Farm.Collected = 0

    -- Coins that were touched but whose model has not despawned yet. Without
    -- this the farm re-targets the same coin forever.
    local claimed = {}
    Game.on("RoundStart", function() claimed = {} end)
    Game.on("RoundEnd", function() claimed = {} end)

    -- ------------------------------------------------------------- collect
    local function touch(part)
        if not X.firetouch then return false end
        local root = U.myRoot()
        if not root or not part or not part.Parent then return false end
        local ok = pcall(function()
            firetouchinterest(root, part, 0)
            firetouchinterest(root, part, 1)
        end)
        return ok
    end
    Farm.touch = touch

    local function markCollected(coin)
        if claimed[coin.model] then return end
        claimed[coin.model] = os.clock()
        Farm.Collected = Farm.Collected + 1
    end

    -- Stale claims are released after a few seconds so a coin we failed to pick
    -- up does not get ignored for the rest of the round.
    KH.loop(2, function()
        local now = os.clock()
        for model, at in pairs(claimed) do
            if not model.Parent or now - at > 6 then claimed[model] = nil end
        end
    end)

    -- ============================================================ COIN FARM
    local function moveTeleport(coin)
        U.moveTo(coin.part.Position + Vector3.new(0, 2.5, 0), true)
        task.wait(math.max(S.Farm.CoinDelay, 0))
    end

    -- Interpolated hop: still a teleport, but spread over several frames so it
    -- reads as fast movement rather than a snap.
    local function moveSmooth(coin)
        local root = U.myRoot()
        if not root then return end
        local startPos = root.Position
        local endPos = coin.part.Position + Vector3.new(0, 2.5, 0)
        local distance = (endPos - startPos).Magnitude
        local duration = distance / math.max(S.Farm.CoinSpeed, 1)
        local began = os.clock()

        while S.Farm.CoinFarm and KH.Alive do
            local elapsed = os.clock() - began
            if elapsed >= duration then break end
            if not coin.part.Parent then break end
            local current = U.myRoot()
            if not current then break end
            current.CFrame = CFrame.new(startPos:Lerp(endPos, elapsed / duration))
            task.wait()
        end
    end

    local function moveWalk(coin)
        local hum = U.myHum()
        if not hum then return end
        hum:MoveTo(coin.part.Position)
        local began = os.clock()
        while S.Farm.CoinFarm and KH.Alive and os.clock() - began < 6 do
            local root = U.myRoot()
            if not root or not coin.part.Parent then break end
            if (root.Position - coin.part.Position).Magnitude < 4 then break end
            task.wait(0.15)
        end
    end

    KH.loop(0.05, function()
        if not S.Farm.CoinFarm then return end
        if not U.myRoot() then return end

        local coin = Game.nearestCoin(claimed)
        if not coin then
            task.wait(1)
            return
        end

        local mode = S.Farm.CoinMode
        if mode == "Smooth" then moveSmooth(coin)
        elseif mode == "Walk" then moveWalk(coin)
        else moveTeleport(coin) end

        touch(coin.part)
        markCollected(coin)
    end)

    -- =========================================================== COIN MAGNET
    -- Fires touch events on every coin inside the radius without moving. Much
    -- less conspicuous than teleporting, and it stacks with normal play.
    KH.loop(0.2, function()
        if not S.Farm.Magnet then return end
        local root = U.myRoot()
        if not root then return end

        local radius = S.Farm.MagnetRadius
        for _, coin in ipairs(Game.coins()) do
            if (coin.part.Position - root.Position).Magnitude <= radius then
                if touch(coin.part) then markCollected(coin) end
            end
        end
    end)

    -- ========================================================= GUN GRABBING
    local grabbing = false

    function Farm.grabGun(announce)
        local drop = Game.GunDrop
        if not drop or not drop.Parent then
            if announce then
                UI.notify({title = "Gun Drop", text = "No dropped gun right now.", kind = "warn"})
            end
            return false
        end
        if grabbing then return false end
        if Game.gunTool() then return false end -- already armed

        -- The murderer cannot pick the gun up. Going anyway means teleporting
        -- onto the sheriff's body seconds after killing them, standing there
        -- while the pickup that will never happen times out, and teleporting
        -- back — in front of whoever is watching.
        if Game.amMurderer() then
            if announce then
                UI.notify({title = "Gun Drop", text = "You are the murderer — that gun is not yours to take.", kind = "warn"})
            end
            return false
        end

        grabbing = true
        KH.detach(function()
            local root = U.myRoot()
            if root then
                local origin = root.CFrame
                root.CFrame = CFrame.new(drop.Position + Vector3.new(0, 2.5, 0))

                -- Wait for the pickup to actually register before hopping back.
                local began = os.clock()
                repeat
                    task.wait(0.08)
                until Game.gunTool() or not drop.Parent or os.clock() - began > 2.5

                if S.Farm.GrabReturn then
                    local current = U.myRoot()
                    if current then current.CFrame = origin end
                end

                if Game.gunTool() then
                    UI.notify({title = "Gun Drop", text = "Picked up the dropped gun.", kind = "good"})
                end
            end
            grabbing = false
        end)
        return true
    end

    Game.on("GunDropped", function()
        UI.notify({title = "Gun Dropped", text = "The sheriff went down — gun is on the floor.", kind = "warn", duration = 5})
        if S.Farm.AutoGrabGun then
            task.wait(0.6) -- let the part settle where it lands
            Farm.grabGun(false)
        end
    end)

    Game.on("GunTaken", function()
        local hero = Game.Hero and Game.Hero or nil
        UI.notify({
            title = "Gun Taken",
            text = hero and (hero .. " picked up the gun.") or "Someone picked up the gun.",
            duration = 4,
        })
    end)

    -- ============================================================= ANTI-AFK
    KH.track(LocalPlayer.Idled:Connect(function()
        if not S.Farm.AntiAFK then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))
end

-- ─── src/mm2/10_safety.lua ─────────────────────────────────────────────

-- ============================================================================
--  SAFETY — murderer proximity warning, auto-dodge, round/role announcements
--
--  The half of an MM2 script that actually keeps you alive as an innocent,
--  which most feature lists skip entirely.
-- ============================================================================

do
    local UI   = KH.UI
    local C    = UI.C
    local make = UI.make
    local U    = KH.U
    local Game = KH.Game
    local S    = KH.S

    local Safety = {}
    KH.Safety = Safety
    Safety.MurdererDistance = math.huge

    -- ------------------------------------------------------------ vignette
    -- Four edge bars, each fading inward, make a red pulse around the screen
    -- border. No image assets, and it never obscures the middle of the view.
    local vignette = make("Frame", {
        Name = "Alert",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = UI.Overlay,
    })

    local bars = {}
    local EDGES = {
        {size = UDim2.new(1, 0, 0, 90), pos = UDim2.fromScale(0, 0),    rot = 90},
        {size = UDim2.new(1, 0, 0, 90), pos = UDim2.new(0, 0, 1, -90),  rot = 270},
        {size = UDim2.new(0, 120, 1, 0), pos = UDim2.fromScale(0, 0),   rot = 0},
        {size = UDim2.new(0, 120, 1, 0), pos = UDim2.new(1, -120, 0, 0), rot = 180},
    }
    for _, edge in ipairs(EDGES) do
        local bar = make("Frame", {
            Size = edge.size,
            Position = edge.pos,
            BackgroundColor3 = Color3.fromRGB(255, 40, 40),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = vignette,
        })
        make("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Rotation = edge.rot,
            Parent = bar,
        })
        bars[#bars + 1] = bar
    end

    local function setAlertLevel(intensity)
        local visible = intensity > 0.01
        vignette.Visible = visible
        if not visible then return end
        for _, bar in ipairs(bars) do
            bar.BackgroundTransparency = 1 - (0.55 * intensity)
        end
    end

    -- ==================================================== PROXIMITY WARNING
    local ALERT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
    local lastBeep, lastNotify, lastDodge = 0, 0, 0
    local wasClose = false

    KH.onFrame("proximity", function()
        local murderer = Game.murdererPlayer()
        local myRoot = U.myRoot()

        if not murderer or not myRoot or murderer == KH.LocalPlayer then
            Safety.MurdererDistance = math.huge
            setAlertLevel(0)
            wasClose = false
            return
        end

        local part = U.rootOf(murderer)
        if not part then
            Safety.MurdererDistance = math.huge
            setAlertLevel(0)
            return
        end

        local distance = (myRoot.Position - part.Position).Magnitude
        Safety.MurdererDistance = distance

        -- --------------------------------------------------------- warning
        if S.Safety.ProximityAlert then
            local threshold = S.Safety.AlertDistance
            if distance <= threshold then
                -- Intensity ramps as they close in, so the screen tells you how
                -- much trouble you are in without reading a number.
                local intensity = 1 - (distance / threshold)
                setAlertLevel(S.Safety.AlertFlash and intensity or 0)

                local now = os.clock()
                if not wasClose and now - lastNotify > 4 then
                    lastNotify = now
                    UI.notify({
                        title = "Murderer Nearby",
                        text = ("%s is %dm away."):format(murderer.DisplayName, math.floor(distance)),
                        kind = "bad",
                        duration = 3,
                    })
                end
                -- Beep faster the closer they get.
                if S.Safety.AlertSound then
                    local interval = 0.18 + (distance / threshold) * 0.9
                    if now - lastBeep > interval then
                        lastBeep = now
                        U.playSound(ALERT_SOUND, 0.35)
                    end
                end
                wasClose = true
            else
                setAlertLevel(0)
                wasClose = false
            end
        else
            setAlertLevel(0)
        end

        -- ------------------------------------------------------ auto dodge
        -- Only bails when we are not the one hunting: as murderer or an armed
        -- sheriff, launching yourself into the air is worse than useless.
        if S.Safety.AutoDodge
            and distance <= S.Safety.DodgeDistance
            and os.clock() - lastDodge > 1.5
            and not Game.amMurderer()
            and not Game.gunTool() then
            local root = U.myRoot()
            if root then
                lastDodge = os.clock()
                -- Straight up, away from the knife, keeping our facing intact.
                root.CFrame = root.CFrame + Vector3.new(0, S.Safety.DodgeHeight, 0)
                UI.notify({title = "Dodged", text = "Bailed out of knife range.", kind = "warn", duration = 2})
            end
        end
    end, 40)

    -- ================================================ ROLE ANNOUNCEMENTS
    Game.on("RoleChange", function(murderer, sheriff)
        if not S.Safety.RoleNotify then return end
        if not murderer and not sheriff then return end

        local me = KH.LocalPlayer.Name
        if murderer == me then
            UI.notify({title = "You are the MURDERER", text = "Knife tools are on the Knife tab.", kind = "bad", duration = 6})
        elseif sheriff == me then
            UI.notify({title = "You are the SHERIFF", text = "Aimbot is armed — check the Aimbot tab.", kind = "good", duration = 6})
        end

        local lines = {}
        if murderer then lines[#lines + 1] = "Murderer: " .. murderer end
        if sheriff then lines[#lines + 1] = "Sheriff: " .. sheriff end
        if #lines > 0 then
            UI.notify({
                title = "Roles Revealed",
                text = table.concat(lines, "\n"),
                kind = "warn",
                duration = 7,
            })
        end
    end)

    Game.on("RoundStart", function()
        if S.Safety.RoleNotify then
            UI.notify({title = "Round Started", text = "Waiting for roles…", duration = 3})
        end
    end)

    Game.on("TrapPlaced", function()
        if S.ESP.TrapESP then
            UI.notify({title = "Trap Placed", text = "The murderer set a trap.", kind = "warn", duration = 4})
        end
    end)
end

-- ─── src/mm2/11_movement.lua ───────────────────────────────────────────

-- ============================================================================
--  MOVEMENT — speed, jump, noclip, fly, spinbot, teleports, waypoints
-- ============================================================================

do
    local UI               = KH.UI
    local U                = KH.U
    local Game             = KH.Game
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
            if not noclipConn then
                noclipConn = RunService.Stepped:Connect(noclipStep)
                KH.track(noclipConn)
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

    function Move.tpMurderer() return tpToPlayer(Game.murdererPlayer(), "Moved to the murderer.") end
    function Move.tpSheriff()  return tpToPlayer(Game.sheriffPlayer(), "Moved to the sheriff.") end

    function Move.tpGunDrop()
        local drop = Game.GunDrop
        if not drop or not drop.Parent then
            UI.notify({title = "Teleport", text = "No dropped gun right now.", kind = "warn"})
            return false
        end
        return tpTo(drop.Position, "Moved to the dropped gun.")
    end

    function Move.tpCoin()
        local coin = Game.nearestCoin()
        if not coin then
            UI.notify({title = "Teleport", text = "No coins found.", kind = "warn"})
            return false
        end
        return tpTo(coin.part.Position, "Moved to the nearest coin.")
    end

    local function anySpawn(container)
        local spawns = container and container:FindFirstChild("Spawns")
        if not spawns then return nil end
        local options = spawns:GetChildren()
        if #options == 0 then return nil end
        local pick = options[math.random(1, #options)]
        return pick:IsA("BasePart") and pick.Position or nil
    end

    function Move.tpLobby()
        local position = anySpawn(Game.lobby())
        if not position then
            UI.notify({title = "Teleport", text = "Could not find the lobby.", kind = "warn"})
            return false
        end
        return tpTo(position, "Moved to the lobby.")
    end

    function Move.tpRandomSpawn()
        local position = anySpawn(Game.map())
        if not position then
            UI.notify({title = "Teleport", text = "No map spawns available.", kind = "warn"})
            return false
        end
        return tpTo(position, "Moved to a random spawn.")
    end

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

-- ─── src/mm2/12_visuals.lua ────────────────────────────────────────────

-- ============================================================================
--  VISUALS — fullbright, fog, field of view, x-ray walls, detail stripping
--
--  Every effect here records what it changed and restores it on unload, so
--  unloading the script leaves the game looking exactly as it did before.
-- ============================================================================

do
    local S        = KH.S
    local Lighting = KH.Services.Lighting
    local Game     = KH.Game
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
                    pcall(function() effect.Density = 0 end)
                end
            end
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
        local map = Game.map()
        if not map then return end
        for _, part in ipairs(map:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.9 and not isProtected(part) then
                if xraySaved[part] == nil then xraySaved[part] = part.Transparency end
                part.Transparency = S.Visual.XrayTransp
            end
        end
        xrayOn = true
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
    Game.on("RoundStart", function()
        if S.Visual.Xray then
            task.wait(1)
            xraySaved = {}
            applyXray()
        end
    end)

    KH.loop(1, function()
        if S.Visual.Xray and not xrayOn then
            applyXray()
        elseif not S.Visual.Xray and xrayOn then
            clearXray()
        end
    end)

    -- ============================================================ LOW DETAIL
    -- Turns effects off rather than destroying them, so it is fully reversible.
    local detailSaved = {}
    local lowDetailOn = false

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
            workspace.Terrain.WaterWaveSize = 0
            workspace.Terrain.WaterReflectance = 0
        end)
        lowDetailOn = true
    end

    local function clearLowDetail()
        for obj in pairs(detailSaved) do
            if obj.Parent then pcall(function() obj.Enabled = true end) end
        end
        detailSaved = {}
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

-- ─── src/mm2/13_menu.lua ───────────────────────────────────────────────

-- ============================================================================
--  MENU — every tab, section and control
-- ============================================================================

do
    local UI     = KH.UI
    local C      = UI.C
    local make   = UI.make
    local U      = KH.U
    local S      = KH.S
    local Game   = KH.Game
    local Combat = KH.Combat
    local Farm   = KH.Farm
    local Move   = KH.Move
    local Safety = KH.Safety
    local Config = KH.Config
    local Players = KH.Services.Players
    local LocalPlayer = KH.LocalPlayer

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

    -- ========================================================== AIMBOT TAB
    do
        local tab = UI.addTab("Aimbot", "🎯")

        local targeting = UI.section(tab, "Targeting")
        UI.label(targeting, "Draws your gun, then shoots the murderer wherever they are — through walls, across the map, no mouse movement. MM2's shot is a world position the server resolves, so nothing needs to be on screen.")
        UI.toggle(targeting, opt("Aim", "Enabled", {
            text = "Aimbot Enabled",
            desc = "Master switch for automatic firing.",
        }))
        UI.dropdown(targeting, opt("Aim", "Target", {
            text = "Target",
            desc = "Nearest and Crosshair will shoot innocents too.",
            options = {"Murderer", "Nearest", "Crosshair"},
        }))
        UI.dropdown(targeting, opt("Aim", "Mode", {
            text = "Trigger",
            desc = "Press: one lock-and-shot per key press — it aims, fires once, and gives the camera straight back. Hold: keeps firing while the key is down. Toggle: press once to stay locked on, again to stop. Always: never stops.",
            options = {"Press", "Hold", "Toggle", "Always"},
        }))
        UI.keybind(targeting, opt("Aim", "Key", {text = "Aim Key"}))
        UI.dropdown(targeting, opt("Aim", "Method", {
            text = "Fire Method",
            desc = "Mouse (default) turns the camera onto the target, puts the cursor on them and clicks, so MM2's own gun fires the shot — the one that works without a hook. Remote hands the server the position instead: silent, shoots through walls, and does nothing at all on an executor the game does not accept built shots from.",
            options = {"Remote", "Mouse"},
        }))
        UI.toggle(targeting, opt("Aim", "KeepEquipped", {
            text = "Keep Gun Equipped",
            desc = "Re-draw the gun if a respawn or round change stows it.",
        }))

        local accuracy = UI.section(tab, "Accuracy")
        UI.slider(accuracy, opt("Aim", "Prediction", {
            text = "Prediction",
            desc = "Studs of lead, Remote method only. Mouse aim points at where the target actually is — leading a client raycast just walks it off their body.",
            min = 0, max = 8, step = 0.1,
        }))
        UI.toggle(accuracy, opt("Aim", "PingComp", {
            text = "Ping Compensation",
            desc = "Scale the lead by your measured ping.",
        }))
        UI.toggle(accuracy, opt("Aim", "AimAtHead", {
            text = "Aim At Head",
            desc = "Target the head instead of the torso.",
        }))
        UI.slider(accuracy, opt("Aim", "FireRate", {
            text = "Fire Rate", min = 0.05, max = 1, step = 0.05, suffix = "s",
        }))

        local mouseAim = UI.section(tab, "Mouse Aim")
        UI.label(mouseAim, "Only used when Fire Method is Mouse. Your camera snaps onto the target and the cursor is driven there, so this one is visible — to you and to anyone watching you.")
        UI.toggle(mouseAim, opt("Aim", "CameraSnap", {
            text = "Turn Camera",
            desc = "Turn towards the target when they are near the edge of your view or behind you, so they do not have to be on screen already. Anyone already well inside the view is left to the cursor alone and the camera stays still. Off, the aimbot can only shoot what you can see.",
        }))
        UI.slider(mouseAim, opt("Aim", "MouseSpeed", {
            text = "Aim Speed",
            desc = "Governs the turn and the cursor together. 1 is an instant snap; lower eases both, which looks far smoother for a few frames' delay. 0.4 lands in about a tenth of a second.",
            min = 0.1, max = 1, step = 0.05,
        }))
        UI.readout(mouseAim, {
            text = "Mouse Control",
            get = function() return Combat.Mouse.support() end,
        })

        local extras = UI.section(tab, "Extras")
        UI.toggle(extras, opt("Aim", "SilentAim", {
            text = "Silent Aim",
            desc = Combat.SilentDesc,
        }))
        UI.dropdown(extras, opt("Aim", "SilentMode", {
            text = "Silent Aim Route",
            desc = "Auto picks the best one your executor can do. Takeover needs no hook at all — switch to it by hand if Auto's hook reports success but your shots still miss.",
            options = {"Auto", "Hook", "Takeover", "Click"},
        }))
        UI.readout(extras, {
            text = "Route In Use",
            get = function() return Combat.silentStatus() end,
        })
        UI.toggle(extras, opt("Aim", "NotifyShot", {text = "Notify On Shot"}))
        UI.readout(extras, {
            text = "Aimbot Status",
            get = function() return Combat.aimStatus() end,
        })
        UI.readout(extras, {
            text = "Current Target",
            get = function()
                local target = Combat.LastTarget
                if target and target.Parent then return target.DisplayName end
                return "none"
            end,
        })
        UI.button(extras, {
            text = "Kill All",
            desc = "Fire at every living player in sequence.",
            kind = "danger",
            callback = function() Combat.killAll() end,
        })
    end

    -- =========================================================== KNIFE TAB
    do
        local tab = UI.addTab("Knife", "🔪")
        UI.label(UI.section(tab, "Murderer Only"),
            "These do nothing unless you are holding the knife.")

        local throwing = UI.section(tab, "Throwing")
        UI.toggle(throwing, opt("Knife", "AutoThrow", {
            text = "Auto Throw",
            desc = "Throw at the closest valid target on a timer.",
        }))
        UI.slider(throwing, opt("Knife", "ThrowDelay", {
            text = "Throw Delay", min = 0.2, max = 5, step = 0.1, suffix = "s",
        }))
        UI.slider(throwing, opt("Knife", "ThrowRange", {
            text = "Throw Range",
            desc = "Do not throw at anyone further away than this. The knife is gone until it comes back, so a throw that cannot reach costs you the weapon for nothing.",
            min = 20, max = 200, step = 5, suffix = " studs",
        }))
        UI.button(throwing, {
            text = "Throw Now",
            callback = function()
                if not Combat.throwAtNearest() then
                    UI.notify({title = "Knife", text = "No knife or no target.", kind = "warn"})
                end
            end,
        })

        local melee = UI.section(tab, "Melee")
        UI.toggle(melee, opt("Knife", "Aura", {
            text = "Knife Aura",
            desc = "Stab anyone who walks into range.",
        }))
        UI.slider(melee, opt("Knife", "AuraRadius", {
            text = "Aura Radius", min = 5, max = 40, step = 1, suffix = " studs",
        }))
        UI.slider(melee, opt("Knife", "AuraDelay", {
            text = "Aura Delay", min = 0.05, max = 1, step = 0.05, suffix = "s",
        }))
        UI.toggle(melee, opt("Knife", "TpStab", {
            text = "Teleport Stab",
            desc = "Blink to the target, swing, blink back. Anyone already within swinging distance is stabbed where they stand.",
        }))
        UI.slider(melee, opt("Knife", "TpRange", {
            text = "Teleport Range",
            desc = "How far a blink is worth making. Crossing the map to reach someone is not a stab, it is a teleport everyone sees.",
            min = 20, max = 400, step = 10, suffix = " studs",
        }))

        local targets = UI.section(tab, "Target Filter")
        UI.toggle(targets, opt("Knife", "TargetSheriff", {
            text = "Prioritise Sheriff",
            desc = "Go for whoever is holding the gun first, then everyone else by distance.",
        }))
        UI.toggle(targets, opt("Knife", "SkipSheriff", {
            text = "Never Target Sheriff",
            desc = "Avoid the gun holder entirely.",
        }))
    end

    -- ============================================================= ESP TAB
    do
        local tab = UI.addTab("ESP", "👁")

        local players = UI.section(tab, "Players")
        UI.toggle(players, opt("ESP", "Enabled", {text = "ESP Enabled"}))
        UI.toggle(players, opt("ESP", "Boxes", {text = "Boxes"}))
        UI.dropdown(players, opt("ESP", "BoxStyle", {
            text = "Box Style", options = {"Corner", "Full"},
        }))
        UI.toggle(players, opt("ESP", "Names", {text = "Names"}))
        UI.toggle(players, opt("ESP", "Roles", {text = "Role Labels"}))
        UI.toggle(players, opt("ESP", "Distance", {text = "Show Distance"}))
        UI.toggle(players, opt("ESP", "Health", {text = "Health Bars"}))
        UI.toggle(players, opt("ESP", "Tracers", {text = "Tracers"}))
        UI.dropdown(players, opt("ESP", "TracerOrigin", {
            text = "Tracer Origin", options = {"Bottom", "Center"},
        }))
        UI.toggle(players, opt("ESP", "Chams", {
            text = "Chams", desc = "Fill characters with their role colour.",
        }))
        UI.slider(players, opt("ESP", "ChamsFill", {
            text = "Cham Opacity", min = 0, max = 0.95, step = 0.05,
        }))
        UI.toggle(players, opt("ESP", "OffScreen", {
            text = "Off-Screen Arrows",
            desc = "Edge markers pointing at players behind you.",
        }))
        UI.toggle(players, opt("ESP", "OnlyRoles", {
            text = "Hide Innocents",
            desc = "Only draw the murderer, sheriff and hero.",
        }))
        UI.slider(players, opt("ESP", "MaxDistance", {
            text = "Max Distance", min = 100, max = 5000, step = 50, suffix = " studs",
        }))
        UI.slider(players, opt("ESP", "TextSize", {
            text = "Text Size", min = 8, max = 22, step = 1,
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("ESP", "CoinESP", {text = "Coin ESP"}))
        UI.toggle(world, opt("ESP", "GunESP", {
            text = "Gun Drop ESP", desc = "Highlight the gun when a sheriff dies.",
        }))
        UI.toggle(world, opt("ESP", "TrapESP", {
            text = "Trap ESP", desc = "Reveal the murderer's traps.",
        }))

        local colours = UI.section(tab, "Colours")
        UI.colorpicker(colours, opt("ESP", "ColorMurderer", {text = "Murderer"}))
        UI.colorpicker(colours, opt("ESP", "ColorSheriff", {text = "Sheriff"}))
        UI.colorpicker(colours, opt("ESP", "ColorHero", {text = "Hero"}))
        UI.colorpicker(colours, opt("ESP", "ColorInnocent", {text = "Innocent"}))
    end

    -- ============================================================ FARM TAB
    do
        local tab = UI.addTab("Farm", "💰")

        local coins = UI.section(tab, "Coins")
        UI.toggle(coins, opt("Farm", "CoinFarm", {
            text = "Auto Coin Farm",
            desc = "Travel to every coin on the map and collect it.",
        }))
        UI.dropdown(coins, opt("Farm", "CoinMode", {
            text = "Travel Mode",
            desc = "Teleport is fastest; Walk is the least obvious.",
            options = {"Teleport", "Smooth", "Walk"},
        }))
        UI.slider(coins, opt("Farm", "CoinSpeed", {
            text = "Smooth Speed", min = 20, max = 300, step = 10, suffix = " s/s",
        }))
        UI.slider(coins, opt("Farm", "CoinDelay", {
            text = "Teleport Delay", min = 0, max = 1, step = 0.02, suffix = "s",
        }))
        UI.toggle(coins, opt("Farm", "LobbyFarm", {
            text = "Include Lobby",
            desc = "Also collect the coins in the lobby between rounds.",
        }))

        local magnet = UI.section(tab, "Coin Magnet")
        UI.label(magnet, "Collects nearby coins without moving you. Slower, but it stacks with playing normally.")
        UI.toggle(magnet, opt("Farm", "Magnet", {text = "Coin Magnet"}))
        UI.slider(magnet, opt("Farm", "MagnetRadius", {
            text = "Magnet Radius", min = 5, max = 120, step = 5, suffix = " studs",
        }))

        local gun = UI.section(tab, "Dropped Gun")
        UI.toggle(gun, opt("Farm", "AutoGrabGun", {
            text = "Auto Grab Gun",
            desc = "Rush the gun the moment a sheriff dies.",
        }))
        UI.toggle(gun, opt("Farm", "GrabReturn", {
            text = "Return After Grab",
            desc = "Snap back to where you were standing.",
        }))
        UI.button(gun, {text = "Grab Gun Now", callback = function() Farm.grabGun(true) end})

        local session = UI.section(tab, "Session")
        UI.toggle(session, opt("Farm", "AntiAFK", {
            text = "Anti-AFK", desc = "Block the twenty-minute idle kick.",
        }))
        UI.readout(session, {text = "Coins Collected", get = function() return Farm.Collected end})
        UI.readout(session, {text = "Shots Fired", get = function() return Game.ShotsFired end})
    end

    -- ========================================================== SAFETY TAB
    do
        local tab = UI.addTab("Safety", "🛡")

        local warning = UI.section(tab, "Murderer Warning")
        UI.label(warning, "The half of an MM2 script that keeps you alive when you are just an innocent.")
        UI.toggle(warning, opt("Safety", "ProximityAlert", {
            text = "Proximity Alert",
            desc = "Warn when the murderer closes in.",
        }))
        UI.slider(warning, opt("Safety", "AlertDistance", {
            text = "Alert Distance", min = 10, max = 150, step = 5, suffix = " studs",
        }))
        UI.toggle(warning, opt("Safety", "AlertSound", {
            text = "Alert Beep", desc = "Beeps faster the closer they get.",
        }))
        UI.toggle(warning, opt("Safety", "AlertFlash", {
            text = "Screen Edge Flash",
            desc = "Red vignette that intensifies with proximity.",
        }))
        UI.readout(warning, {
            text = "Murderer Distance",
            get = function()
                local distance = Safety.MurdererDistance
                if distance == math.huge then return "unknown" end
                return ("%dm"):format(math.floor(distance))
            end,
        })

        local dodge = UI.section(tab, "Auto Dodge")
        UI.toggle(dodge, opt("Safety", "AutoDodge", {
            text = "Auto Dodge",
            desc = "Launch upward if the knife gets too close. Off while armed.",
        }))
        UI.slider(dodge, opt("Safety", "DodgeDistance", {
            text = "Trigger Distance", min = 5, max = 40, step = 1, suffix = " studs",
        }))
        UI.slider(dodge, opt("Safety", "DodgeHeight", {
            text = "Dodge Height", min = 10, max = 200, step = 5, suffix = " studs",
        }))

        local announce = UI.section(tab, "Announcements")
        UI.toggle(announce, opt("Safety", "RoleNotify", {
            text = "Role Reveal",
            desc = "Name the murderer and sheriff the moment roles are dealt.",
        }))
    end

    -- ======================================================== MOVEMENT TAB
    do
        local tab = UI.addTab("Movement", "🏃")

        local speed = UI.section(tab, "Speed & Jump")
        UI.toggle(speed, opt("Move", "SpeedEnabled", {
            text = "Speed Hack", onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Speed", {
            text = "Walk Speed", min = 16, max = 250, step = 1,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.dropdown(speed, opt("Move", "SpeedMode", {
            text = "Speed Mode",
            desc = "CFrame ignores server speed clamps but looks less natural.",
            options = {"Humanoid", "CFrame"},
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "JumpEnabled", {
            text = "Jump Hack", onSet = function() Move.applyHumanoid() end,
        }))
        UI.slider(speed, opt("Move", "Jump", {
            text = "Jump Power", min = 50, max = 400, step = 5,
            onSet = function() Move.applyHumanoid() end,
        }))
        UI.toggle(speed, opt("Move", "InfJump", {text = "Infinite Jump"}))
        UI.toggle(speed, opt("Move", "Bhop", {
            text = "Bunny Hop", desc = "Auto-jump while holding space.",
        }))

        local clip = UI.section(tab, "Noclip & Fly")
        UI.toggle(clip, opt("Move", "Noclip", {
            text = "Noclip", onSet = function(v) Move.setNoclip(v) end,
        }))
        UI.keybind(clip, opt("Move", "NoclipKey", {text = "Noclip Key"}))
        UI.toggle(clip, opt("Move", "Fly", {
            text = "Fly",
            desc = "WASD to move, Space up, Left Shift down.",
            onSet = function(v) Move.setFly(v) end,
        }))
        UI.keybind(clip, opt("Move", "FlyKey", {text = "Fly Key"}))
        UI.slider(clip, opt("Move", "FlySpeed", {
            text = "Fly Speed", min = 10, max = 300, step = 5,
        }))
        UI.toggle(clip, opt("Move", "Spinbot", {
            text = "Spinbot", desc = "Constantly rotate your character.",
        }))

        local teleport = UI.section(tab, "Teleport")
        UI.button(teleport, {text = "To Murderer", callback = function() Move.tpMurderer() end})
        UI.button(teleport, {text = "To Sheriff", callback = function() Move.tpSheriff() end})
        UI.button(teleport, {text = "To Dropped Gun", callback = function() Move.tpGunDrop() end})
        UI.button(teleport, {text = "To Nearest Coin", callback = function() Move.tpCoin() end})
        UI.button(teleport, {text = "To Lobby", callback = function() Move.tpLobby() end})
        UI.button(teleport, {text = "To Random Spawn", callback = function() Move.tpRandomSpawn() end})

        local waypoints = UI.section(tab, "Waypoints")
        local pendingName = {value = ""}
        local selected = {value = ""}
        local waypointDropdown

        local function refreshWaypoints()
            local names = Move.waypointNames()
            if #names == 0 then names = {"(none saved)"} end
            if waypointDropdown then waypointDropdown.setOptions(names) end
        end

        UI.input(waypoints, {
            text = "Waypoint Name",
            placeholder = "e.g. roof camp",
            get = function() return pendingName.value end,
            set = function(v) pendingName.value = v end,
        })
        UI.button(waypoints, {
            text = "Save Current Position",
            callback = function()
                if Move.saveWaypoint(pendingName.value) then refreshWaypoints() end
            end,
        })
        waypointDropdown = UI.dropdown(waypoints, {
            text = "Saved Waypoints",
            options = {"(none saved)"},
            get = function() return selected.value ~= "" and selected.value or "(none saved)" end,
            set = function(v) selected.value = v end,
        })
        UI.button(waypoints, {
            text = "Teleport To Waypoint",
            callback = function() Move.gotoWaypoint(selected.value) end,
        })
        UI.button(waypoints, {
            text = "Delete Waypoint",
            kind = "danger",
            callback = function()
                if Move.deleteWaypoint(selected.value) then
                    selected.value = ""
                    refreshWaypoints()
                end
            end,
        })
        refreshWaypoints()
    end

    -- ========================================================= VISUALS TAB
    do
        local tab = UI.addTab("Visuals", "✨")

        local lighting = UI.section(tab, "Lighting")
        UI.toggle(lighting, opt("Visual", "Fullbright", {
            text = "Fullbright", desc = "Flatten the lighting so nowhere is dark.",
        }))
        UI.slider(lighting, opt("Visual", "Brightness", {
            text = "Brightness", min = 0.5, max = 6, step = 0.1,
        }))
        UI.toggle(lighting, opt("Visual", "NoFog", {text = "Remove Fog"}))

        local camera = UI.section(tab, "Camera")
        UI.toggle(camera, opt("Visual", "FovEnabled", {text = "Custom Field Of View"}))
        UI.slider(camera, opt("Visual", "Fov", {
            text = "Field Of View", min = 40, max = 120, step = 1, suffix = "°",
        }))

        local world = UI.section(tab, "World")
        UI.toggle(world, opt("Visual", "Xray", {
            text = "X-Ray Walls",
            desc = "Make the map semi-transparent. Players stay solid.",
        }))
        UI.slider(world, opt("Visual", "XrayTransp", {
            text = "Wall Transparency", min = 0.2, max = 0.95, step = 0.05,
        }))
        UI.toggle(world, opt("Visual", "LowDetail", {
            text = "Low Detail Mode",
            desc = "Disable particles, trails and shadows for more frames.",
        }))
    end

    -- ========================================================= PLAYERS TAB
    do
        local tab = UI.addTab("Players", "👥")
        local section = UI.section(tab, "In This Server")
        UI.label(section, "Live roster with roles. Click a name to spectate, or use the arrow to teleport.")

        local listHolder = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = section.body,
        })
        UI.list(listHolder, 4)

        local spectating = nil
        local function setSpectate(player)
            local cam = KH.camera()
            if spectating == player or player == nil then
                spectating = nil
                local hum = U.myHum()
                if hum then cam.CameraSubject = hum end
                UI.notify({title = "Spectate", text = "Back to your own view.", duration = 2})
            else
                local hum = U.humOf(player)
                if not hum then
                    UI.notify({title = "Spectate", text = "No character to watch.", kind = "warn"})
                    return
                end
                spectating = player
                cam.CameraSubject = hum
                UI.notify({title = "Spectate", text = "Watching " .. player.DisplayName .. ".", duration = 2})
            end
        end
        KH.undo(function() setSpectate(nil) end)

        local rows = {}

        local function buildRow(player)
            local row = make("Frame", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = C.Row,
                BackgroundTransparency = 0.55,
                BorderSizePixel = 0,
                Parent = listHolder,
            })
            UI.corner(row, 7)

            local dot = make("Frame", {
                Position = UDim2.fromOffset(10, 13),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = C.TextDim,
                BorderSizePixel = 0,
                Parent = row,
            })
            UI.corner(dot, 4)

            local name = make("TextButton", {
                Text = player.DisplayName,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextColor3 = C.Text,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Position = UDim2.fromOffset(26, 0),
                Size = UDim2.new(1, -140, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = row,
            })
            name.MouseButton1Click:Connect(function() setSpectate(player) end)

            local info = make("TextLabel", {
                Text = "",
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextColor3 = C.TextDim,
                BackgroundTransparency = 1,
                RichText = true,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -40, 0.5, 0),
                Size = UDim2.fromOffset(120, 20),
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })

            local tp = make("TextButton", {
                Text = "→",
                Font = Enum.Font.GothamBold,
                TextSize = 15,
                TextColor3 = C.TextDim,
                BackgroundColor3 = C.Card,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(26, 22),
                Parent = row,
            })
            UI.corner(tp, 6)
            tp.MouseButton1Click:Connect(function() Move.tpToPlayer(player) end)
            tp.MouseEnter:Connect(function() tp.TextColor3 = C.Text end)
            tp.MouseLeave:Connect(function() tp.TextColor3 = C.TextDim end)

            return {row = row, dot = dot, name = name, info = info, player = player}
        end

        local function refreshList()
            local present = {}
            for _, player in ipairs(Players:GetPlayers()) do
                present[player] = true
                if not rows[player] then rows[player] = buildRow(player) end
            end
            for player, entry in pairs(rows) do
                if not present[player] then
                    pcall(function() entry.row:Destroy() end)
                    rows[player] = nil
                end
            end

            local myRoot = U.myRoot()
            for player, entry in pairs(rows) do
                local color, role = Game.colorOf(player)
                entry.dot.BackgroundColor3 = color

                local bits = {}
                if player == LocalPlayer then
                    bits[#bits + 1] = "you"
                elseif myRoot then
                    local part = U.rootOf(player)
                    if part then
                        bits[#bits + 1] = ("%dm"):format(
                            math.floor((myRoot.Position - part.Position).Magnitude))
                    end
                end
                if not Game.isAlive(player) then bits[#bits + 1] = "dead" end

                entry.info.Text = ('<font color="#%s">%s</font>  %s')
                    :format(color:ToHex(), role, table.concat(bits, " · "))
                entry.name.TextColor3 = (spectating == player) and color or C.Text
            end
        end

        KH.loop(0.6, function()
            if UI.IsOpen and UI.ActiveTab == "Players" then refreshList() end
        end)
        refreshList()
    end

    -- ======================================================== SETTINGS TAB
    do
        local tab = UI.addTab("Settings", "⚙")

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
        UI.readout(session, {
            text = "Silent Aim Support",
            get = function() return Combat.silentStatus() end,
        })
        UI.readout(session, {
            text = "Mouse Control",
            get = function() return Combat.Mouse.support() end,
        })
        UI.readout(session, {
            text = "Metamethod Hook",
            get = function()
                if Combat.HookAvailable then return tostring(Combat.SilentRoute) end
                return "none — " .. (Combat.SilentReason or "not exposed")
            end,
        })
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
    end

    UI.selectTab("Aimbot")
end

-- ─── src/mm2/14_main.lua ───────────────────────────────────────────────

-- ============================================================================
--  MAIN — hotkeys, the single render loop, HUD readouts, and unload
-- ============================================================================

do
    local UI               = KH.UI
    local C                = UI.C
    local U                = KH.U
    local S                = KH.S
    local Game             = KH.Game
    local Combat           = KH.Combat
    local Move             = KH.Move
    local Safety           = KH.Safety
    local Config           = KH.Config
    local RunService       = KH.Services.RunService
    local UserInputService = KH.Services.UserInputService
    local TeleportService  = KH.Services.TeleportService
    local HttpService      = KH.Services.HttpService
    local LocalPlayer      = KH.LocalPlayer

    -- =============================================================== HOTKEYS
    UI.registerKeybind("Menu", function() return S.UI.MenuKey end, function() return UI.IsOpen end)
    -- Press mode is never "engaged", so light the chip while its shot is in
    -- flight instead — otherwise the key would look dead every time it works.
    UI.registerKeybind("Aimbot", function() return S.Aim.Key end, function()
        return Combat.isEngaged() or Combat.Mouse.active() ~= nil
    end)
    UI.registerKeybind("Noclip", function() return S.Move.NoclipKey end, function() return S.Move.Noclip end)
    UI.registerKeybind("Fly", function() return S.Move.FlyKey end, function() return S.Move.Fly end)
    UI.refreshKeybinds()

    KH.track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        -- A keybind picker or a focused text box owns this press.
        if UI.Capturing then return end
        if processed then return end

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
        -- In Toggle mode the aim key arms the aimbot rather than firing once.
        if key == U.keyCode(S.Aim.Key) and S.Aim.Enabled then
            if S.Aim.Mode == "Toggle" then
                Combat.setToggle(not Combat.toggleArmedState())
                UI.refreshKeybinds()
            elseif S.Aim.Mode == "Press" or S.Aim.Mode == "Hold" then
                -- Both shoot on the press. Hold then keeps going from the
                -- render loop while the key is down; Press is done here.
                Combat.fireOnce(true)
            end
        end
    end))

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

    local function roleColorHex()
        local role = Game.myRole()
        if role == "Murderer" then return S.ESP.ColorMurderer:ToHex(), role end
        if role == "Sheriff" then return S.ESP.ColorSheriff:ToHex(), role end
        if role == "Hero" then return S.ESP.ColorHero:ToHex(), role end
        return S.ESP.ColorInnocent:ToHex(), role
    end

    local function clockText()
        local seconds = Game.roundTime()
        if not seconds then return nil end
        seconds = math.max(math.floor(seconds), 0)
        return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
    end

    KH.loop(0.25, function()
        local hex, role = roleColorHex()
        local dim = C.TextDim:ToHex()

        -- Watermark
        if S.UI.Watermark then
            local parts = {
                ('<font color="#%s">Kitty Hub</font>'):format(C.Accent:ToHex()),
                ('<font color="#%s">MM2</font>'):format(dim),
                ("%d fps"):format(fps),
                ("%d ms"):format(math.floor(U.ping())),
                ('<font color="#%s">%s</font>'):format(hex, role),
            }
            local clock = clockText()
            if clock then parts[#parts + 1] = clock end
            UI.WatermarkText.Text = table.concat(parts, ('  <font color="#%s">·</font>  '):format(dim))
        end

        -- Sidebar status strip
        UI.RoleLabel.Text = role
        UI.RoleLabel.TextColor3 = Color3.fromHex(hex)

        local bits = {}
        local distance = Safety.MurdererDistance
        if distance and distance ~= math.huge then
            bits[#bits + 1] = ("murderer %dm"):format(math.floor(distance))
        elseif Game.inRound() then
            bits[#bits + 1] = "in round"
        else
            bits[#bits + 1] = "lobby"
        end
        local clock = clockText()
        if clock then bits[#bits + 1] = clock end
        UI.StatLabel.Text = table.concat(bits, " · ")

        -- Live readouts, only while their tab is actually on screen.
        if UI.IsOpen then
            for _, readout in ipairs(UI.Readouts or {}) do
                KH.safe("readout", readout.refresh)
            end
        end
    end)

    -- ============================================================== SESSION
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

    -- ================================================================ BOOT
    if Config.available then
        local ok = Config.load(S.UI.Profile)
        if ok then
            UI.refreshAll()
            UI.applyAccent(S.UI.Accent)
        end
    end

    -- Bring the world into line with whatever the loaded profile says.
    Move.applyHumanoid()
    if S.Move.Noclip then Move.setNoclip(true) end
    UI.refreshKeybinds()
    UI.setOpen(true)

    -- The sidebar indicator is placed from AbsolutePosition, which is still
    -- zero until the window has been laid out for a frame.
    task.delay(0.35, function()
        if KH.Alive then UI.selectTab(UI.ActiveTab or "Aimbot") end
    end)

    if game.PlaceId ~= 142823291 then
        UI.notify({
            title = "Not Murder Mystery 2",
            text = "This build targets MM2. Most features will do nothing here.",
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
    print(("[Kitty Hub] [%s] menu · [%s] aim · [%s] noclip · [%s] fly")
        :format(S.UI.MenuKey, S.Aim.Key, S.Move.NoclipKey, S.Move.FlyKey))
end
