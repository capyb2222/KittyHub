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
            MouseSpeed    = 0.6,         -- camera turn only; the cursor always snaps
            Prediction    = 2.8,         -- studs of lead per unit of velocity
            PingComp      = true,        -- scale lead by measured ping
            FireRate      = 0.10,        -- seconds between shots
            KeepEquipped  = true,        -- re-draw the gun if it gets stowed
            SilentAim     = false,       -- redirect your own manual shots
            SilentMode    = "Auto",      -- Auto | Hook | Takeover | Click
            DryRun        = false,       -- aim and report, never shoot
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
