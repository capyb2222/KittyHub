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
    -- Our own role is latched for the round. MM2 empties our hands the moment
    -- the knife is thrown and the role table can arrive late, in pieces, or
    -- still holding last round's answer — one unlucky read must never turn the
    -- murderer back into an innocent.
    local myLatch = nil

    local function latch(role)
        if role == "Murderer" or role == "Sheriff" or role == "Hero" then
            myLatch = role
        end
    end

    local function clearRoles()
        Game.Data = {}
        Game.Murderer, Game.Sheriff, Game.Hero = nil, nil, nil
        myLatch = nil
    end
    Game.clearRoles = clearRoles

    local function recompute()
        local murderer, sheriff, hero
        for name, entry in pairs(Game.Data) do
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

        local me = LocalPlayer.Name
        if murderer == me then latch("Murderer")
        elseif sheriff == me then latch("Sheriff")
        elseif hero == me then latch("Hero") end

        if changed then emit("RoleChange", murderer, sheriff, hero) end
    end

    -- Only a payload that actually carries roles may replace what we have; a
    -- partial push used to wipe the table and leave us knowing nothing.
    local function applyData(data)
        if typeof(data) ~= "table" then return end

        local fresh, roles = {}, 0
        for name, entry in pairs(data) do
            if typeof(name) == "string" and typeof(entry) == "table" then
                fresh[name] = entry
                if typeof(entry.Role) == "string" then roles = roles + 1 end
            end
        end
        if roles == 0 then return end

        Game.Data = fresh
        recompute()
    end
    Game.applyData = applyData

    -- Some builds push one player's entry instead of the whole table.
    local function applyOne(who, entry)
        local name = who
        if typeof(who) == "Instance" and who:IsA("Player") then name = who.Name end
        if typeof(name) ~= "string" or typeof(entry) ~= "table" then return end
        if typeof(entry.Role) ~= "string" then return end
        Game.Data[name] = entry
        recompute()
    end

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
            KH.track(gameplay.OnClientEvent:Connect(function(first, second)
                if typeof(first) == "table" then applyData(first) else applyOne(first, second) end
            end))
        end
        Game.refreshRoles()
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

        -- Only the murderer ever holds a knife, so that outranks the table —
        -- including a table left standing from the round before.
        if held == "Murderer" then return "Murderer" end

        if role == nil or role == "Innocent" then
            if held == "Sheriff" then
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

    function Game.myRole()
        local role = Game.roleOf(LocalPlayer)
        latch(role)
        if role == "Innocent" and myLatch then return myLatch end
        return role
    end

    function Game.amSheriff()
        local role = Game.myRole()
        return role == "Sheriff" or role == "Hero"
    end

    -- Asked from every angle: a wrong "no" walks the murderer onto the gun.
    function Game.amMurderer()
        if myLatch == "Murderer" then return true end
        if Game.Murderer == LocalPlayer.Name then return true end
        if Game.knifeTool() then return true end
        return Game.myRole() == "Murderer"
    end

    -- Lets callers tell "innocent" apart from "no idea yet".
    function Game.selfKnown()
        if myLatch then return true end
        local entry = Game.Data[LocalPlayer.Name]
        return typeof(entry) == "table" and typeof(entry.Role) == "string"
    end

    -- Latch our role even when nothing asks: the knife is only ours briefly.
    KH.loop(0.5, function() Game.myRole() end)

    -- Poll until we know who the murderer is *and* what we are, then keep
    -- re-asking slowly: a missed round boundary would otherwise leave last
    -- round's roles standing for the whole of this one.
    local polledAt = 0
    KH.loop(2, function()
        if Game.Murderer and Game.selfKnown() and os.clock() - polledAt < 10 then return end
        polledAt = os.clock()
        Game.refreshRoles()
    end)

    -- A fresh body means a fresh round; stale roles are worse than none.
    KH.track(LocalPlayer.CharacterAdded:Connect(function()
        clearRoles()
        task.wait(1)
        Game.refreshRoles()
    end))

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
            clearRoles()
            emit("RoundStart", obj)
            KH.detach(Game.refreshRoles)
        end
    end))

    KH.track(workspace.ChildRemoved:Connect(function(obj)
        if obj.Name ~= "Lobby" and obj:FindFirstChild("CoinContainer") then
            clearRoles()
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

    -- ------------------------------------------------------ throw animation
    -- The throw remote makes the knife fly; it does nothing to your character.
    -- MM2 plays the wind-up from its own client script, off an input we never
    -- make, so a scripted throw looks like a knife leaving a statue's hand.
    --
    -- The asset id is never hardcoded — it is read off whatever animation MM2
    -- ships on the tool, so a game update that renames or replaces it is
    -- picked up rather than silently played wrong. Resolved once per knife and
    -- loaded once per character: a throw pays for none of this twice.
    local anim = {tool = nil, source = nil, animator = nil, track = nil}

    local function findThrowAnimation(knife)
        local only, count
        for _, inst in ipairs(knife:GetDescendants()) do
            if inst:IsA("Animation") and inst.AnimationId ~= "" then
                if inst.Name:lower():find("throw") or inst.Name:lower():find("toss") then
                    return inst
                end
                count, only = (count or 0) + 1, inst
            end
        end
        -- One animation on a throwing knife is the throw. Two or more and
        -- guessing means playing a stab or an idle instead, which looks worse
        -- than playing nothing.
        return count == 1 and only or nil
    end

    local function animatorOf(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end
        return hum:FindFirstChildOfClass("Animator") or hum
    end

    -- Resolve and load without playing. The track's length is what the release
    -- delay is measured from and it reads zero until Roblox has actually
    -- fetched the asset, so doing this ahead of time is the difference between
    -- the first throw of a round looking right and looking like the rest.
    function Game.primeThrowAnimation(knife)
        knife = knife or Game.knifeTool()
        if not knife then return nil end

        if anim.tool ~= knife then
            anim.tool, anim.source, anim.track = knife, findThrowAnimation(knife), nil
        end
        if not anim.source then return nil end

        local animator = animatorOf(U.charOf(LocalPlayer))
        if not animator then return nil end
        if anim.animator ~= animator then
            anim.animator, anim.track = animator, nil
        end
        if not anim.track then
            local ok, track = pcall(function() return animator:LoadAnimation(anim.source) end)
            if not ok or not track then return nil end
            anim.track = track
        end
        return anim.track
    end

    -- Nobody throws a knife on the first frame of the wind-up. Play it, then
    -- say how long the knife should stay in the hand — the arm has to come back
    -- before anything leaves it, and firing the remote immediately is what made
    -- the throw read as a script no matter how good the animation looked.
    --
    -- A hard ceiling regardless of the slider: a knife still in your hand most
    -- of a second after you decided to throw it is a bug, not a style.
    local RELEASE_CAP = 0.75

    local function playThrowAnimation()
        if not KH.S.Knife.ThrowAnim then return 0 end
        local track = Game.primeThrowAnimation()
        if not track then return 0 end

        -- Restart rather than stack: two throws in quick succession should look
        -- like two throws, not one blended into itself.
        local ok = pcall(function()
            if track.IsPlaying then track:Stop(0) end
            track:Play(0.05)
        end)
        if not ok then return 0 end

        -- Still no length means the asset has not landed yet. That throw goes
        -- out immediately rather than waiting on a delay nothing can measure —
        -- exactly what it did before the animation existed.
        local length = track.Length
        if typeof(length) ~= "number" or length <= 0 then return 0 end

        local point = U.clamp((KH.S.Knife.ThrowRelease or 55) / 100, 0, 1)
        return math.min(length * point, RELEASE_CAP)
    end

    -- Leaving a wind-up frozen on the character is the one thing unloading
    -- must not do.
    KH.undo(function()
        if anim.track then pcall(function() anim.track:Stop(0) end) end
    end)

    -- One throw in the air at a time. The hold below yields, and a second call
    -- landing inside it would restart the animation under a knife that has
    -- already been committed.
    local holding = false

    -- `refresh`, when given, is asked for the aim again at the moment the knife
    -- actually leaves the hand. Without it a held throw would fly at wherever
    -- the target stood when the arm started moving.
    function Game.throwKnife(targetPos, refresh)
        if holding then return false, "mid-throw" end

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

        -- Built at the moment of release, not before it: both the hand and the
        -- target have moved by then.
        --
        -- Orientation, not just position: MM2 flies the knife along the CFrame
        -- it is handed, and a bare CFrame.new(position) faces down the world
        -- axis rather than at the target. Degenerate when the two points
        -- coincide, so that case keeps the old bare frame.
        local function send(point)
            local from = CFrame.new(hand.Position)
            if (point - hand.Position).Magnitude > 0.5 then
                from = CFrame.new(hand.Position, point)
            end
            pcall(function()
                thrown:FireServer(from, CFrame.new(point) * (from - from.Position))
            end)
        end

        local hold = playThrowAnimation()
        if hold <= 0 then
            send(targetPos)
            return true
        end

        holding = true
        KH.detach(function()
            -- pcall, or one error leaves the flag stuck on forever.
            pcall(function()
                task.wait(hold)
                -- Dying mid-wind-up, stowing the knife, or unloading the script
                -- cancels the throw rather than firing a remote from a hand
                -- that is not there any more.
                if not KH.Alive then return end
                if not (hand.Parent and knife.Parent == U.charOf(LocalPlayer)) then return end
                send(refresh and refresh() or targetPos)
            end)
            holding = false
        end)
        return true
    end
end
