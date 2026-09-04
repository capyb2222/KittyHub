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
