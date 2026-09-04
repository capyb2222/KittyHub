-- ============================================================================
--  DEFAULTS — the MM2 settings schema
-- ============================================================================

KH.GameTag  = "MM2"
KH.GameName = "Murder Mystery 2"

do

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
            AutoThrow     = false,       -- master switch, like Aim.Enabled
            ThrowMode     = "Press",     -- Press | Always
            ThrowDelay    = 1.2,         -- Always mode only
            ThrowRange    = 70,          -- past this the knife is just thrown away
            ThrowKey      = "G",         -- one press, one throw
            ThrowAnim     = true,        -- play MM2's own wind-up with the throw
            ThrowRelease  = 55,          -- percent of it before the knife leaves the hand
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
end
