local Dannet = require 'srl/DanNet'
local CastUtil = require 'srl/util/CastUtil'

local healing_export = {}
local CURRENT_HPS_QUERY = 'Me.PctHPs'

local function healListWithTankHealingInformation(healList, healingInformation)
    areObserverablesCreated = false;
    if(healList ~= nil) then
        if(#healList> 0) then
            for _, i in ipairs(healList) do
                local tankHealth = tonumber(Dannet.query(i, CURRENT_HPS_QUERY, 40))
                local tankHealInformation = HEALING_2D[IniHelper.TANK_HEAL_KEY]
                --This will never change probably will put it on object at creation
                for _, j in ipairs(tankHealInformation) do
                    local splits = StringUtil.split(j, "/")
                    local healName = splits[1]
                    local gem = splits[2]:gsub("|", "")
                    local healPctInformation = StringUtil.split(splits[3], "|")
                    local healPctToCheck = tonumber(healPctInformation[2])
                    if(tankHealth <= healPctToCheck) then
                        local tankId = mq.TLO.NetBots(i).ID()
                        if(tankId ~= nil and tankId ~= 0) then
                            CastUtil.srl_cast(healName, gem, tankId)
                        end
                    end
                end
            end
        end
    end
end

local function createObservables(list1, list2)
    if(list1 ~= nil and #list1 > 0) then
        for _, i in ipairs(list1) do
            if areObserverablesCreated == false then
                Dannet.create_observer(i, CURRENT_HPS_QUERY, 40)
            end
        end
    end

    if(list2 ~= nil and #list2 > 0) then
        for _, i in ipairs(list2) do
            if areObserverablesCreated == false then
                Dannet.create_observer(i, CURRENT_HPS_QUERY, 40)
            end
        end
    end

    areObserverablesCreated = true
end

function healing_export.check_healing()
    if(areObserverablesCreated == nil or areObserverablesCreated == false)then
        createObservables(tankList, importantBotList)
    end
    local tankList = HEALING_2D[IniHelper.TANK_KEY]
    local tankHealInformation = HEALING_2D[IniHelper.TANK_HEAL_KEY]
    local importantBotList = HEALING_2D[IniHelper.IMPORTANT_BOT_KEY]
    local importantBotHealInformation = HEALING_2D[IniHelper.IMPORTANT_BOT_KEY]

    healListWithTankHealingInformation(tankList, tankHealInformation)
    healListWithTankHealingInformation(importantBotList, importantBotHealInformation)
end

return healing_export