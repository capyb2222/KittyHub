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
            Noclip        = true,            -- hold noclip for the whole job
            Lasers        = true,            -- switch off laser hazards on arrival
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
