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

local CUT_BUSH_TIME = 75

local function onCleanVegMenu(worldobjects, square, player, areaSize)
    local bo = CleanVegCursor:new("", "", player, areaSize)

    getCell():setDrag(bo, player:getPlayerNum())
end

-- Vanilla's own "Remove Bush" option (under Gardening) only offers itself for
-- outdoor vegetation - it never appears for bushes WorldDecay places indoors,
-- even though the object itself is identical. This gives indoor bushes an
-- equivalent option, using the same tracked removal as Clean Vegetation so it
-- stays gone permanently.
local function hasIndoorBush(square)
    if not square:getRoom() then
        return false
    end

    local function listHasBush(objects)
        if not objects then
            return false
        end

        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            local modData = object and object:getModData()
            local cleanableType = modData and modData["WDecay_Cleanable"]

            if cleanableType == "bush" or cleanableType == "trash" then
                return true
            end
        end

        return false
    end

    return listHasBush(square:getObjects()) or listHasBush(square:getSpecialObjects())
end

local function onRemoveIndoorBush(worldobjects, square, player)
    if luautils.walkAdj(player, square, true) then
        ISTimedActionQueue.add(CleanVegAction:new(player, square, CUT_BUSH_TIME))
    end
end

local function addCleanVegMenu(player, context, worldobjects)
    local player = getSpecificPlayer(player)
    local square

    if player:getVehicle() then
        return
    end

    for i, v in ipairs(worldobjects) do
        square = v:getSquare()
    end

    if not square then
        return
    end

    if not WDecay_CleanVegetation.hasCleanable(square) then
        return
    end

    local submenuOption = context:addOption(getText('UI_REMOVE_VEG'), worldobjects, nil)
    local subMenu = ISContextMenu:getNew(context)

    context:addSubMenu(submenuOption, subMenu)
    subMenu:addOption(getText('UI_CLEAN_TILE'), worldobjects, onCleanVegMenu, square, player, nil)
    subMenu:addOption(getText('UI_CLEAN_AREA_3'), worldobjects, onCleanVegMenu, square, player, 3)
    subMenu:addOption(getText('UI_CLEAN_AREA_5'), worldobjects, onCleanVegMenu, square, player, 5)
    subMenu:addOption(getText('UI_CLEAN_AREA_10'), worldobjects, onCleanVegMenu, square, player, 10)

    if hasIndoorBush(square) then
        context:addOption(getText('UI_REMOVE_BUSH'), worldobjects, onRemoveIndoorBush, square, player)
    end
end

Events.OnFillWorldObjectContextMenu.Add(addCleanVegMenu)
