require('TimedActions/ISBaseTimedAction')

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
    self:setActionAnim(self.actionAnim or "RemoveGrass")
    self:setOverrideHandModels(nil, nil)
    self.square:playSound("RemovePlant")
    self.character:reportEvent("EventCleanVeg")
end

function CleanVegAction:stop()
    ISBaseTimedAction.stop(self)
end

function CleanVegAction:perform()
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

function CleanVegAction:new(character, square, time, actionAnim)
    local o = {}

    setmetatable(o, self)

    self.__index = self
    o.character = character
    o.square = square
    o.stopOnWalk = false
    o.stopOnRun = true
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
