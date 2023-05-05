local common = require("mer.fishing.common")
local logger = common.createLogger("FishingService")
local config = require("mer.fishing.config")
local FishingSpot = require("mer.fishing.Fishing.FishingSpot")
local FishingStateManager = require("mer.fishing.Fishing.FishingStateManager")
local FishingRod = require("mer.fishing.FishingRod.FishingRod")
local SwimService = require("mer.fishing.Fish.SwimService")
local FishGenerator = require("mer.fishing.Fish.FishGenerator")
local TrophyMenu = require("mer.fishing.ui.TrophyMenu")
local LineManager = require("mer.fishing.FishingLine.LineManager")
local Animations = require("mer.fishing.Fish.Animations")
local FightManager = require("mer.fishing.Fishing.FightManager")

---@class Fishing.FishingService
local FishingService = {}

local function getBiteDuration()
    local min = 0.1
    local max = 1.0
    return math.random(min*100, max*100)/100
end

---@param lure tes3reference
---@param landCallback function
local function launchLure(lure, landCallback)
    do --update speed opn object (TODO: Fix this with praticle bindings later)
        local mesh = tes3.loadMesh("mer_fishing\\LureParticle.nif")
        local particles = mesh:getObjectByName("Particles")

        local castStrength = FishingStateManager.getCastStrength()
        particles.controller.speed = math.remap(castStrength, 0, 1, 100, 700)
    end

    local vfx = tes3.createVisualEffect{
        object = "mer_lure_particle",
        position = lure.position,
    }
    local effectNode = vfx.effectNode
    local particles = effectNode:getObjectByName("Particles") --[[@as niParticles]]
    local controller = particles.controller --[[@as niParticleSystemController]]

    effectNode.rotation:toRotationZ(tes3.player.orientation.z)

    logger:debug("Setting lure speed to %s", controller.speed)

    local safeLure = tes3.makeSafeObjectHandle(lure)
    local safeParticle = tes3.makeSafeObjectHandle(vfx)
    local updateLurePosition
    local function cancel()
        event.unregister("simulate", updateLurePosition)
        if safeLure and safeLure:valid() then
            lure:delete()
        end
    end
    updateLurePosition = function()
        if not (safeLure and safeLure:valid()) then
            logger:debug("Lure is not valid, stopping updateLurePosition")
            cancel()
            return
        end
        if not (safeParticle and safeParticle:valid()) then
            logger:debug("Particle is not valid, stopping updateLurePosition")
            cancel()
            return
        end
        local transform = vfx.effectNode.worldTransform
        local vertex = particles.data.vertices[1]
        lure.position = transform * vertex

        --check for collision with ground
        local result = tes3.rayTest{
            position = lure.position + tes3vector3.new(0, 0, 10),
            direction = tes3vector3.new(0, 0, -1),
            ignore = { lure },
        }
        if result then
            local hitGround =  result.intersection.z > lure.cell.waterLevel
                and result.distance < 10
            if hitGround then
                logger:debug("Lure hit ground, stopping updateLurePosition")
                FishingStateManager.setState("IDLE")
                cancel()
                return
            end
        end
        if lure.position.z < lure.cell.waterLevel then
            logger:debug("Lure is underwater, stopping updateLurePosition")
            event.unregister("simulate", updateLurePosition)
            landCallback()
            return
        end
    end
    event.register("simulate", updateLurePosition)
end

local function spawnLure(lurePosition)
    logger:debug("Spawning lure")
    if not lurePosition then
        logger:error("Could not get lure position")
        return
    end
    local lure = tes3.createReference({
        object = "mer_lure_01",
        position = lurePosition,
        cell = tes3.player.cell,
    })
    FishingStateManager.setLure(lure)
    return lure
end

---Cast a line if player attacks with a fishing rod
--- and there is valid water in front of them
local function startCasting()
    logger:debug("Casting fishing rod")
    local state = FishingStateManager.getCurrentState()
    if not state == "IDLE" then
        logger:debug("Not Idle, can't cast")
        return
    end
    FishingStateManager.setCastStrength()

    local lurePosition = FishingRod.getPoleEndPosition()
    local castStrength = FishingStateManager.getCastStrength()
    FishingRod.playCastSound(castStrength)
    Animations.clampWaves()

    local lure = spawnLure(lurePosition)
    if lure then
        -- common.disablePlayerControls()
        FishingStateManager.setState("CASTING")
        launchLure(lure, function()
            Animations.lureLand(lure)
            logger:debug("Finished casting")
            FishingStateManager.setState("WAITING")
        end)
        timer.start{
            duration = 0.1,
            callback = function()
                lure = FishingStateManager.getLure()
                if lure then
                    LineManager.attachLines(lure)
                end
            end
        }
    else
        logger:error("Could not spawn lure")
        FishingService.endFishing()
    end
end


---Calculate the chance a bite is real or just a nibble
local function calculateRealBiteChance()
    --TODO: base on skill etc
    return math.random() < 0.50
end

local function endBite()
    local state = FishingStateManager.getCurrentState()
    if state == "BITING" then
        logger:debug("Fish stopped biting")
        FishingStateManager.setState("WAITING")
    else
        logger:debug("Not biting, state is %s", state)
    end
end

local function realBite()
    logger:debug("Fish is biting")
    FishingStateManager.setState("BITING")
    local lure = FishingStateManager.getLure()
    if lure then
        logger:debug("Playing bite animation")
        Animations.lureBite(lure)
        timer.start{
            duration = getBiteDuration(),
            callback = function()
                endBite()
            end
        }
    end
end

local function startFish()
    logger:debug("Starting fish")
    local lure = FishingStateManager.getLure()
    if not lure then
        logger:warn("No lure found")
        return
    end
    local depth = FishingSpot.getDepth(lure.position)
    local fish = FishGenerator.generate{ depth = depth }
    if not fish then
        logger:warn("Unable to generate fish")
        return
    end
    FishingStateManager.setActiveFish(fish)


    local to = lure.position
    local from = SwimService.findTargetPosition(to)
    if from then
        SwimService.startSwimming{
            from = from,
            to = to,
            callback = function()
                timer.start{
                    duration = 0.4,
                    callback = realBite
                }
            end
        }
    else
        logger:warn("Unable to find start position")
        FishingService.endFishing()
    end
end

function FishingService.triggerFish()
    local state = FishingStateManager.getCurrentState()
    if state == "WAITING" then
        if calculateRealBiteChance() then
            logger:debug("SwimService is biting")
            startFish()
        else
            logger:debug("SwimService is nibbling")
            local lure = FishingStateManager.getLure()
            if lure then
                Animations.lureNibble(lure)
            end
        end
    end
end

function FishingService.endFishing()
    logger:debug("Cancelling fishing")
    FishingStateManager.removeLure()
    -- common.enablePlayerControls()
    Animations.unclampWaves()
    FishingStateManager.clearData()
    --give time for waves to settle
    FishingStateManager.setState("BLOCKED")
    timer.start{
        duration = 0.5,
        callback = function()
            FishingStateManager.setState("IDLE")
        end
    }
end

function FishingService.release()
    logger:debug("Releasing Swing")
    local state = FishingStateManager.getCurrentState()
    if state == "IDLE" then
        timer.start{
            duration = 0.020,
            callback = function()
                logger:debug("IDLE - start casting")
                startCasting()
                logger:debug("Activate blocked by state - %s", state)
            end
        }
    end
end

local function catchFish()
    logger:debug("Catching fish")
    FishingStateManager.setState("CATCHING")
    local fish = FishingStateManager.getCurrentFish()
    if not fish then
        logger:warn("No fish found")
        return
    end
    local fishObj = fish:getInstanceObject()
    local lure = FishingStateManager.getLure()
    if not lure then
        logger:warn("No lure found")
        return
    end
    Animations.splash(lure.position, fish:getSplashSize())
    Animations.rodSnap()
    timer.start{
        duration = 0.75,
        callback = function()
            TrophyMenu.createMenu(fish.fishType, function()
                tes3.addItem{
                    reference = tes3.player,
                    item = fishObj,
                    count = 1,
                }
                FishingService.endFishing()
            end)
        end
    }
end

local function startFight()
    logger:debug("Starting fight")
    local fish = FishingStateManager.getCurrentFish()
    if not fish then
        logger:warn("No fish to fight")
        return
    end
    FightManager.new{
        fish = fish,
        callback = catchFish
    }:start()
end

function FishingService.startSwing()
    local state = FishingStateManager.getCurrentState()
    if (state == "WAITING") or (state == "CHASING") then
        logger:debug("CHASING - cancel fishing")
        tes3.messageBox("You fail to catch anything.")
        FishingService.endFishing()
        local lure = FishingStateManager.getLure()
        if not lure then
            logger:warn("No lure found")
            return
        end
        local fish = FishingStateManager.getCurrentFish()
        if not fish then
            logger:warn("No fish found")
            return
        end
        Animations.splash(lure.position, fish:getSplashSize())
        Animations.rodSnap()
    elseif state == "BITING" then
        logger:debug("BITING - catch a fish")
        startFight()
    else
        logger:debug("Activate blocked by state - %s", state)
    end
end

return FishingService