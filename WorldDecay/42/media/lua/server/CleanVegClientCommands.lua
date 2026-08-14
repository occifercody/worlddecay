require('luautils')
local WDecay_CleanVegetation = require('wdecay_cleanvegetation/wdecay_cleanvegetation')

local cachedDebugMode = nil

local function isCleanDebug()
    if cachedDebugMode == nil then
        local opt = getSandboxOptions():getOptionByName('WDecay.debugMode')
        cachedDebugMode = opt and opt:getValue() or false
    end

    return cachedDebugMode
end

local function cleanLog(msg)
    if isCleanDebug() then
        print("[WDecay-Clean] " .. msg)
    end
end

local REMOVABLE_MARKER_TYPES = {
    grass = true,
    bush = true,
    trash = true,
    vine = true,
    indoorGrass = true
}

local function hasContainer(object)
    local container = nil

    pcall(function()
        container = object:getContainer()
    end)

    return container ~= nil
end

local function removeCleanableDecorations(object)
    if not object then
        return false
    end

    local changed = false
    local attached = object:getAttachedAnimSprite()

    if attached then
        for i = attached:size() - 1, 0, -1 do
            local anim = attached:get(i)
            local name = WDecay_CleanVegetation.getAttachedSpriteName(anim)

            if WDecay_CleanVegetation.isCleanableDecorationSpriteName(name) then
                object:RemoveAttachedAnim(i)
                changed = true
            end
        end
    end

    local overlayName = WDecay_CleanVegetation.getOverlaySpriteName(object)

    if WDecay_CleanVegetation.isCleanableDecorationSpriteName(overlayName) then
        object:setOverlaySprite(nil, -1.0, -1.0, -1.0, -1.0, true)
        changed = true
    end

    if changed then
        object:transmitUpdatedSpriteToClients()
    end

    local modData = object:getModData()

    if modData and modData["WDecay_OverlayApplied"] ~= nil then
        modData["WDecay_OverlayApplied"] = nil
        object:transmitModData()
    end

    return changed
end

local function isSpecialObject(square, object)
    local specialObjects = square:getSpecialObjects()

    if not specialObjects then
        return false
    end

    for i = 0, specialObjects:size() - 1 do
        if specialObjects:get(i) == object then
            return true
        end
    end

    return false
end

local function tryCleanObject(square, object)
    if not object then
        return false
    end

    local spriteNameForLog = isCleanDebug() and WDecay_CleanVegetation.getObjectSpriteName(object) or nil

    if hasContainer(object) then
        cleanLog("tryCleanObject: skipped " .. tostring(spriteNameForLog) .. " - has a container")

        return false
    end

    local changed = removeCleanableDecorations(object)

    if isSpecialObject(square, object) then
        cleanLog("tryCleanObject: " .. tostring(spriteNameForLog) .. " is a special object, decorationsChanged=" .. tostring(changed))

        return changed
    end

    local modData = object:getModData()
    local cleanableType = modData and modData["WDecay_Cleanable"]

    if object ~= square:getFloor() and WDecay_CleanVegetation.isCleanableMainObject(object) then
        cleanLog("tryCleanObject: removing " .. tostring(spriteNameForLog) .. " (WDecay_Cleanable=" .. tostring(cleanableType) .. ")")
        square:transmitRemoveItemFromSquare(object)

        return true
    end

    if REMOVABLE_MARKER_TYPES[cleanableType] then
        modData["WDecay_Cleanable"] = nil
        object:transmitModData()
    end

    return changed
end

function WDecay_CleanSquare(square)
    if not square then
        return false
    end

    local changed = false
    local floor = square:getFloor()

    if floor and removeCleanableDecorations(floor) then
        changed = true
    end

    local objects = square:getObjects()

    if objects then
        for i = objects:size() - 1, 0, -1 do
            if tryCleanObject(square, objects:get(i)) then
                changed = true
            end
        end
    end

    local specialObjects = square:getSpecialObjects()

    if specialObjects then
        for i = specialObjects:size() - 1, 0, -1 do
            local object = specialObjects:get(i)

            if object and object:getObjectIndex() ~= -1 and tryCleanObject(square, object) then
                changed = true
            end
        end
    end

    square:getModData()["WDecay_cleaned"] = true
    square:setOverlayDone(true)
    square:RecalcAllWithNeighbours(true)

    return changed
end

local function validCoordinate(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function isReachable(player, square)
    if not player or not square or player:getZ() ~= square:getZ() then
        return false
    end

    local playerSquare = player:getSquare()

    if not playerSquare then
        cleanLog("isReachable: player has no square")
        return false
    end

    local dx = math.abs(playerSquare:getX() - square:getX())
    local dy = math.abs(playerSquare:getY() - square:getY())

    -- On a dedicated server this command can arrive slightly after the
    -- client's local timed action already finished (network latency,
    -- position resync), by which point the player may have taken another
    -- step. A strict 1-tile radius rejected legitimate removals outright
    -- with zero feedback. Allow up to 2 tiles, keeping the precise
    -- line-of-sight check only for the immediately-adjacent case it was
    -- meant for.
    if dx > 2 or dy > 2 then
        cleanLog(string.format(
            "isReachable: rejected dx=%d dy=%d square=(%d,%d,%d) player=(%d,%d,%d)",
            dx, dy, square:getX(), square:getY(), square:getZ(),
            playerSquare:getX(), playerSquare:getY(), playerSquare:getZ()))

        return false
    end

    if dx <= 1 and dy <= 1 then
        if dx == 0 and dy == 0 then
            return true
        end

        return not playerSquare:isBlockedTo(square)
    end

    return true
end

local function onCleanVegCommand(module, command, player, args)
    if module ~= "CleanVeg" or command ~= "CleanVegCommand" or type(args) ~= "table" then
        return
    end

    local x = args.x
    local y = args.y
    local z = args.z

    if not validCoordinate(x) or not validCoordinate(y) or not validCoordinate(z) then
        cleanLog("onCleanVegCommand: invalid coordinates in command")
        return
    end

    local square = getCell():getGridSquare(x, y, z)

    if not square then
        cleanLog(string.format("onCleanVegCommand: no square at (%d,%d,%d)", x, y, z))
        return
    end

    if not isReachable(player, square) then
        cleanLog(string.format("onCleanVegCommand: square (%d,%d,%d) rejected as unreachable, clean aborted", x, y, z))
        return
    end

    local objectsBefore = square:getObjects()
    local objectCountBefore = objectsBefore and objectsBefore:size() or 0

    local changed = WDecay_CleanSquare(square)

    cleanLog(string.format(
        "onCleanVegCommand: cleaned square (%d,%d,%d) objectsBefore=%d changed=%s",
        x, y, z, objectCountBefore, tostring(changed)))
end

Events.OnClientCommand.Add(onCleanVegCommand)
