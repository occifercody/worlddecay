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

-- Same tag vanilla requires to remove a wall vine or an outdoor bush -
-- machete, axe, knife, etc - and the same "not broken" check.
local function predicateCutPlant(item)
    return item ~= nil and not item:isBroken() and item:hasTag(ItemTag.CUT_PLANT)
end

local function findCuttingTool(player)
    local handItem = player:getPrimaryHandItem()

    if predicateCutPlant(handItem) then
        return handItem
    end

    local inv = player:getInventory()

    return inv and inv:getFirstEvalRecurse(predicateCutPlant) or nil
end

-- Mirrors vanilla's ISRemoveBush:start() animation choice so cutting an
-- indoor bush looks the same as cutting one outdoors.
local function actionAnimFor(weapon)
    if not weapon then
        return "RemoveBush"
    end

    local scriptItem = weapon:getScriptItem()

    if not scriptItem then
        return "RemoveBush"
    end

    if scriptItem:containsWeaponCategory(WeaponCategory.AXE) then
        return "RemoveBushAxe"
    elseif scriptItem:containsWeaponCategory(WeaponCategory.LONG_BLADE) then
        return "RemoveBushLongBlade"
    elseif scriptItem:containsWeaponCategory(WeaponCategory.SMALL_BLADE) then
        return "RemoveBushKnife"
    end

    return "RemoveBush"
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

-- Requires the same CUT_PLANT-tagged tool vanilla requires for Remove Wall
-- Vine/outdoor Remove Bush (auto-equipping one from inventory if needed),
-- and plays the matching weapon-specific swing animation - but queues our
-- own CleanVegAction rather than vanilla's ISRemoveBush timed action.
--
-- (A previous version of this routed straight through vanilla's
-- ISWorldObjectContextMenu.doRemovePlant/ISRemoveBush, which gets the tool
-- and animation "for free" - but that action's own isValid()/waitToStart()
-- gate got the character stuck standing there indoors with the weapon drawn
-- and no swing, likely a vanilla edge case with indoor facing/validity we
-- can't safely patch around. CleanVegAction's isValid() is unconditionally
-- true and its waitToStart() is the same faceLocation+shouldBeTurning
-- pattern already proven reliable indoors, so it doesn't hit that gate.)
local function onRemoveIndoorBush(worldobjects, square, player)
    local tool = findCuttingTool(player)

    if not tool then
        return
    end

    if player:getPrimaryHandItem() ~= tool then
        ISWorldObjectContextMenu.equip(player, player:getPrimaryHandItem(), tool, true)
    end

    if luautils.walkAdj(player, square, true) then
        ISTimedActionQueue.add(CleanVegAction:new(player, square, CUT_BUSH_TIME, actionAnimFor(tool)))
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

    local bushSquare = findIndoorBushSquare(worldobjects)

    if bushSquare then
        context:addOption(getText('UI_REMOVE_BUSH'), worldobjects, onRemoveIndoorBush, bushSquare, player)
    end
end

Events.OnFillWorldObjectContextMenu.Add(addCleanVegMenu)
