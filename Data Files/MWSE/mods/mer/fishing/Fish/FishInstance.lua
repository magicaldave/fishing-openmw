local common = require("mer.fishing.common")
local logger = common.createLogger("FishInstance")

---@class Fishing.FishType.instance
---@field fishType Fishing.FishType
---@field fatigue number How much fatigue the fish has left
local FishInstance = {}

---@param fishType Fishing.FishType
---@return Fishing.FishType.instance | nil
function FishInstance.new(fishType)
    local self = setmetatable({}, { __index = FishInstance })
    local baseObject = fishType:getBaseObject()
    if not baseObject then
        logger:warn("Could not find base object for %s", fishType.baseId)
        return nil
    end
    self.fishType = fishType
    self.fatigue = fishType:getStartingFatigue()
    return self
end

function FishInstance:getInstanceObject()
    return tes3.getObject(self.fishType.baseId) --[[@as tes3misc]]
end

function FishInstance:getSplashSize()
    return math.remap(self.fishType.size, 1.0, 5.0, 1.0, 6.0)
end

function FishInstance:getRippleSize()
    return self.fishType.size
end

return FishInstance