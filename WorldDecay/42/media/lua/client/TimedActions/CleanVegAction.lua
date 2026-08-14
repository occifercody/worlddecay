require('TimedActions/ISBaseTimedAction')

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

CleanVegAction = ISBaseTimedAction:derive("CleanVegAction")

function CleanVegAction:isValid()
    return true
end

function CleanVegAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())

    return self.character:shouldBeTurning()
end

function CleanVegAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CleanVegAction:start()
    cleanLog("CleanVegAction:start at " .. self.square:getX() .. "," .. self.square:getY() .. " anim=" .. tostring(self.actionAnim))
    self:setActionAnim(self.actionAnim or "RemoveGrass")
    self:setOverrideHandModels(nil, nil)
    self.square:playSound("RemovePlant")
    self.character:reportEvent("EventCleanVeg")
end

function CleanVegAction:stop()
    -- This is a CLIENT-side log (check your own client console/log, not the
    -- server's) - if this line ever shows up, the action was cancelled
    -- (e.g. by the stopOnRun/stopOnWalk flags, or getting invalidated) and
    -- perform() below never ran, so no command was ever sent to the server.
    cleanLog("CleanVegAction:stop at " .. self.square:getX() .. "," .. self.square:getY() .. " - action cancelled before completion")
    ISBaseTimedAction.stop(self)
end

function CleanVegAction:perform()
    cleanLog("CleanVegAction:perform at " .. self.square:getX() .. "," .. self.square:getY() .. " - sending CleanVegCommand to server")

    sendClientCommand(self.character, "CleanVeg", "CleanVegCommand", {
        x = self.square:getX(),
        y = self.square:getY(),
        z = self.square:getZ()
    })

    ISBaseTimedAction.perform(self)

    if self.onCompleteFunc then
        local args = self.onCompleteArgs
        self.onCompleteFunc(args[1], args[2], args[3], args[4])
    end
end

function CleanVegAction:setOnComplete(func, arg1, arg2, arg3, arg4)
    self.onCompleteFunc = func
    self.onCompleteArgs = { arg1, arg2, arg3, arg4 }
end

function CleanVegAction:new(character, square, time, actionAnim, stopOnRun)
    local o = {}

    setmetatable(o, self)

    self.__index = self
    o.character = character
    o.square = square
    o.stopOnWalk = false
    -- Defaults to true (existing behavior for Clean Vegetation tile/area
    -- cleanup, which deliberately lets the player break off by running).
    -- Callers can pass false to disable this - a single precision action
    -- like cutting one specific bush shouldn't risk silently aborting from
    -- a momentary run-state flicker (e.g. under MP network jitter), which
    -- would skip perform() entirely and never notify the server.
    if stopOnRun == nil then
        stopOnRun = true
    end
    o.stopOnRun = stopOnRun
    o.maxTime = time
    o.caloriesModifier = 10
    -- Optional override for the play animation (e.g. "RemoveBushAxe"). Falls
    -- back to the default "RemoveGrass" anim in start() when not given, so
    -- every existing caller (Clean Vegetation tile/area cleanup) is
    -- unaffected.
    o.actionAnim = actionAnim

    if character:isTimedActionInstant() then
        o.maxTime = 1
    end

    return o
end
