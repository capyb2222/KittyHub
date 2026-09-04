-- ============================================================================
--  TELEPORTS — the MM2-specific destinations, on top of shared movement
-- ============================================================================

do
    local UI   = KH.UI
    local Game = KH.Game
    local Move = KH.Move
    local tpTo, tpToPlayer = Move.tpTo, Move.tpToPlayer

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

end
