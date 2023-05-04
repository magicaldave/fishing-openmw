local common = require("mer.fishing.common")
local logger = common.createLogger("LineManager")
local FishingLine = require("mer.fishing.FishingLine.FishingLine")
local FishingStateManager = require("mer.fishing.FishingStateManager")

local LineManager = {}

function LineManager.attachLines(lure)
    logger:debug("Spawning fishing line")
    local attachFishingLine1st = tes3.player1stPerson.sceneNode:getObjectByName("AttachFishingLine") --[[@as niNode]]
    local attachFishingLine3rd = tes3.player.sceneNode:getObjectByName("AttachFishingLine") --[[@as niNode]]
    if not attachFishingLine1st then
        logger:error("Could not find AttachFishingLine node on player 1st person")
        return
    end
    if not attachFishingLine3rd then
        logger:error("Could not find AttachFishingLine node on player 3rd person")
        return
    end

    local fishingLine = FishingLine.new()

    local updateFishingLine
    local lureSafeRef = tes3.makeSafeObjectHandle(lure)

    local function cancel()
        logger:debug("Cancelling fishing line")
        event.unregister("simulate", updateFishingLine)
        fishingLine:remove()
    end

    local lureAttachPoint = lure.sceneNode:getObjectByName("LureAttachFishingLine") --[[@as niNode]]
    if not lureAttachPoint then
        logger:error("Could not find LureAttachFishingLine node on lure")
        cancel()
        return
    end

    local landed = false

    updateFishingLine = function()
        -- Ensure the fishing line is attached to the correct parent (1st/3rd).
        local parent = tes3.is3rdPerson() and attachFishingLine3rd or attachFishingLine1st
        if fishingLine.sceneNode.parent ~= parent then
            fishingLine:attachTo(parent)
        end

        local attachPosition = lureAttachPoint.worldTransform.translation
        if not (lureSafeRef and lureSafeRef:valid()) then
            logger:debug("Lure is not valid, stopping fishing line")
            cancel()
            return
        end
        if FishingStateManager.isState("IDLE") then
            logger:debug("Player is idle, stopping fishing line")
            cancel()
            return
        end
        if FishingStateManager.isState("WAITING") then
            if not landed then
                logger:debug("Lure has landed, transitioning tension")
                fishingLine:updateTension(0.3, 0.75)
                landed = true
                return
            end
        end
        fishingLine:updateEndPoint(attachPosition:copy())
    end
    event.register("simulate", updateFishingLine)
end

return LineManager
