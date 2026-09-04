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
