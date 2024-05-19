-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

-- Define colors for console output
colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    yellow = "\27[33m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Function to add logs
function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Find the weakest player with health less than 70%
function findWeakestPlayer()
    local weakestOpponent = nil
    local lowestHealth = math.huge

    for id, state in pairs(LatestGameState.Players) do
        if id == ao.id then
            goto continue
        end

        local opponent = state

        if opponent.health < lowestHealth and opponent.health < 0.7 then
            weakestOpponent = opponent
            lowestHealth = opponent.health
        end

        ::continue::
    end

    return weakestOpponent
end

-- Check if the player is within attack range
function isPlayerInAttackRange(player)
    local self = LatestGameState.Players[ao.id]

    return inRange(self.x, self.y, player.x, player.y, 1)
end

-- Attack the weakest player using proportional energy
function attackWeakestPlayer()
    local weakestOpponent = findWeakestPlayer()

    if weakestOpponent then
        local attackEnergy = LatestGameState.Players[ao.id].energy * weakestOpponent.health
        print(colors.red .. "Attacking weakest opponent with energy: " .. attackEnergy .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) }) -- Attack with energy proportional to opponent's health
        InAction = false -- Reset InAction after attacking
        return true
    end

    return false
end

-- Move towards a specified direction
function moveToDirection(direction)
    local self = LatestGameState.Players[ao.id]
    local moveDirection = normalizeDirection(direction)
    ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = moveDirection })
end

-- Normalize direction vector
function normalizeDirection(direction)
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    return { x = direction.x / length, y = direction.y / length }
end

-- Decides the next action based on player proximity, health, and energy.
function decideNextAction()
    local self = LatestGameState.Players[ao.id]

    if self.health > 0.7 then
        -- Aggressive mode: attack any player with health < 70%
        if not attackWeakestPlayer() then
            print("No weak opponents found. Continuing to search.")
        end
    elseif self.health > 0.3 then
        -- Conservative mode: attack only players with health < 50%
        local opponent = findWeakestPlayer()
        if opponent and opponent.health < 0.5 then
            local attackEnergy = LatestGameState.Players[ao.id].energy * opponent.health
            print(colors.red .. "Attacking opponent with energy: " .. attackEnergy .. colors.reset)
            ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) })
        else
            print("No suitable opponents found. Continuing to search.")
        end
    else
        -- Defensive mode: move away from any opponent
        local strongestOpponent = findStrongestPlayer()
        if strongestOpponent then
            local avoidDirection = { x = self.x - strongestOpponent.x, y = self.y - strongestOpponent.y }
            moveToDirection(avoidDirection)
            print(colors.blue .. "Moving away from stronger opponent." .. colors.reset)
        else
            print("No opponents found. Staying put.")
        end
    end
end

-- Find the strongest player
function findStrongestPlayer()
    local strongestOpponent = nil
    local highestHealth = 0

    for id, state in pairs(LatestGameState.Players) do
        if id == ao.id then
            goto continue
        end

        local opponent = state

        if opponent.health > highestHealth then
            strongestOpponent = opponent
            highestHealth = opponent.health
        end

        ::continue::
    end

    return strongestOpponent
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true  -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print 'LatestGameState' for detailed view.")
        print("energy:" .. LatestGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("game not start")
            InAction = false -- InAction logic added
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            InAction = true  -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == undefined then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) }) -- Attack with full energy
            end
            InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
