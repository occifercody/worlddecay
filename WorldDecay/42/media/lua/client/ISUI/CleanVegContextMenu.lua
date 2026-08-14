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

local function onCleanVegMenu(worldobjects, square, player, areaSize)
    local bo = CleanVegCursor:new("", "", player, areaSize)

    getCell():setDrag(bo, player:getPlayerNum())
end

-- Vanilla's own "Remove Bush" option (under Gardening) only offers itself for
-- outdoor vegetation - it never appears for bushes WorldDecay places indoors,
-- even though the object itself is identical. This gives indoor bushes an
-- equivalent option, using the same tracked removal as Clean Vegetation so it
-- stays gone permanently.
--
-- Deliberately does NOT require square:getRoom() - in a badly decayed
-- building (missing walls, blown-out windows/doors) the engine can stop
-- recognizing the square as an enclosed room at all, even though it's still
-- "inside" as far as the player and WorldDecay's own placement logic are
-- concerned. Checking for the tagged object directly works regardless of
-- how damaged the structure around it is.
local function hasIndoorBush(square)
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

-- A single right-click can bundle multiple nearby/overlapping objects into
-- one worldobjects list (e.g. a bush tile and an adjacent vine-covered wall
-- tile). Search specifically for a square that actually has a tagged bush,
-- rather than reusing whichever square the generic Clean Vegetation logic
-- happened to resolve to last - that mismatch was why "Remove Bush" could
-- end up cleaning a wall vine on a different tile instead.
local function findIndoorBushSquare(worldobjects)
    local seen = {}

    for i, v in ipairs(worldobjects) do
        local sq = v:getSquare()

        if sq and not seen[sq] then
            seen[sq] = true

            if hasIndoorBush(sq) then
                return sq
            end
        end
    end

    return nil
end

-- Route through vanilla's own bush-removal flow - the exact same one the
-- outdoor "Remove Bush" option (under Gardening) and "Remove Wall Vine" use
-- (ISWorldObjectContextMenu.doRemovePlant -> ISRemoveBush timed action).
-- That means: requires a tool tagged CUT_PLANT (machete, axe, knife, etc -
-- whatever vanilla accepts for wall vines), auto-equips one from inventory
-- if the player isn't already holding one, and plays the correct
-- weapon-specific swing animation instead of a generic toolless action.
-- It also fires vanilla's own removal networking, which
-- removePlantServer.lua already listens for to mark the square cleaned so
-- the bush won't grow back.
local function onRemoveIndoorBush(worldobjects, square, player)
    -- `player` here is already the resolved IsoPlayer object (addCleanVegMenu
    -- shadows the raw playerNum with getSpecificPlayer before wiring up any
    -- menu option), so it's passed straight through.
    ISWorldObjectContextMenu.doRemovePlant(player, square, false)
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

    local bushSquare = findIndoorBushSquare(worldobjects)

    if bushSquare then
        context:addOption(getText('UI_REMOVE_BUSH'), worldobjects, onRemoveIndoorBush, bushSquare, player)
    end
end

Events.OnFillWorldObjectContextMenu.Add(addCleanVegMenu)
