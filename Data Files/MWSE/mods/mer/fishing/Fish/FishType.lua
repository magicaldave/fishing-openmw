local FishInstance = require("mer.fishing.Fish.FishInstance")
local Niche = require("mer.fishing.Fish.Niche")
local common = require("mer.fishing.common")
local logger = common.createLogger("FishType")
local Bait = require("mer.fishing.Bait.Bait")
local Ashfall = include("mer.ashfall.interop")
local Harvest = require("mer.fishing.Harvest")

---@alias Fishing.FishType.rarity
---| '"common"'
---| '"uncommon"'
---| '"rare"'
---| '"legendary"'

---@alias Fishing.FishType.class
---| '"small"' Small fish are used as bait for catching larger fish
---| '"medium"' Medium fish are good for eating or selling
---| '"large"' Large fish are hard to catch, but highly valuable
---| '"loot"' Not a fish, but sometimes you catch random loot

---@class Fishing.FishType.Harvestable
---@field id string The id of the object that is harvested
---@field min number The minimum amount of the object that is harvested
---@field max number The maximum amount of the object that is harvested
---@field isMeat boolean If true, the object is treated as meat for Ashfall cooking purposes

---@class Fishing.FishType.new.params
---@field baseId string The id of the base object representation of the fish
---@field previewMesh? string The mesh to be displayed in the trophy menu
---@field description string The description to be displayed when the fish is caught
---@field speed number The base speed of the fish, in units per second
---@field size number A multiplier on the size of the ripples. Default 1.0
---@field difficulty number The difficulty of catching the fish, out of 100. Default 10 (easy)
---@field class Fishing.FishType.class The class of the fish. Default "medium"
---@field rarity Fishing.FishType.rarity The rarity of the fish. Default "common"
---@field niche? Fishing.FishType.Niche The niche where the fish can be found
---@field harvestables? Fishing.FishType.Harvestable[] The item that can be harvested from the fish
---@field isBaitFish? boolean If true, this fish can be used as live bait

---@class Fishing.FishType : Fishing.FishType.new.params
local FishType = {
    --- A list of all registered fish types
    ---@type table<string, Fishing.FishType>
    registeredFishTypes = {},
    --- A list of multipliers for each rarity
    ---@type table<Fishing.FishType.rarity, number>
    rarityValues = {
        common = 1.0,
        uncommon = 0.5,
        rare = 0.25,
        legendary = 0.1
    }
}

---@param e Fishing.FishType
function FishType.new(e)
    logger:assert(type(e.baseId) == "string", "FishType must have a baseId")
    logger:assert(type(e.description) == "string", "FishType must have a description")
    logger:assert(type(e.speed) == "number", "FishType must have a speed")
    if e.previewMesh then
        logger:assert(tes3.getFileExists(string.format("Meshes\\%s", e.previewMesh)), "Preview mesh does not exist")
    end

    local self = setmetatable({}, { __index = FishType })
    self.baseId = e.baseId:lower()
    self.previewMesh = e.previewMesh
    self.description = e.description
    self.speed = e.speed or 100
    self.size = e.size or 1.0
    self.difficulty = e.difficulty or 10
    self.class = e.class or "medium"
    self.rarity = e.rarity or "common"
    self.niche = Niche.new(e.niche)
    self.harvestables = e.harvestables
    self.isBaitFish = e.isBaitFish

    Harvest.registerFish(self)
    if Ashfall then
        local obj = self:getBaseObject()
        if obj.objectType == tes3.objectType.ingredient then
             logger:debug("Registering %s as meat", obj.id)
             Ashfall.registerFoods{
                 [obj.id] = "meat"
             }
        end
        --register isMeat harvestables
        if self.harvestables then
            for _, harvestable in ipairs(self.harvestables) do
                if harvestable.isMeat then
                    logger:debug("Registering %s as meat", harvestable.id)
                    Ashfall.registerFoods{
                        [harvestable.id] = "meat"
                    }
                end
            end
        end
    end
    return self
end

function FishType.get(id)
    return FishType.registeredFishTypes[id:lower()]
end

---Register a new type of fish
function FishType.register(e)
    local fish = FishType.new(e)
    FishType.registeredFishTypes[fish.baseId] = fish

    if fish.isBaitFish then
        Bait.register{
            id = fish.baseId,
            type = "baitfish",
            uses = 10,
        }
    end
    return fish
end

function FishType:getStartingFatigue()
    return math.remap(self.difficulty, 0, 100, 50, 200)
end

function FishType:getBaseObject()
    return tes3.getObject(self.baseId) --[[@as tes3misc]]
end

function FishType:canHarvest()
    return self.harvestables
        and #self.harvestables > 0
end

---Create an instance of a fish
---@return Fishing.FishType.instance|nil
function FishType:instance()
    return FishInstance.new(self)
end

--Return a catch multiplier based on rarity
function FishType:getRarityEffect()
    return FishType.rarityValues[self.rarity] or 1.0
end

return FishType