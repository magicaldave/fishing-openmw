
require("mer.fishing.mcm")

local common = require("mer.fishing.common")
local logger = common.createLogger("main")
local config = require("mer.fishing.config")


local function isLuaFile(file) return file:sub(-4, -1) == ".lua" end
local function isInitFile(file) return file == "init.lua" end
local function initAll(path)
    path = "Data Files/MWSE/mods/mer/fishing/" .. path .. "/"
    for file in lfs.dir(path) do
        if isLuaFile(file) and not isInitFile(file) then
            logger:debug("Executing file: %s", file)
            dofile(path .. file)
        end
    end
end

event.register("initialized", function()

    --Integrations
    initAll("integrations")

    ---event handlers
    require("mer.fishing.PlayerAnimations")
    require("mer.fishing.Fishing.eventHandler")
    require("mer.fishing.Bait.eventHandler")
    require("mer.fishing.ui.eventHandler")
    require("mer.fishing.Merchant.eventHandler")
    require("mer.fishing.FishingRod.eventHandler")
    require("mer.fishing.FishingSkill.eventHandler")

    local version = config.metadata.package.version
    logger:info("initialized %s", version)
end)
