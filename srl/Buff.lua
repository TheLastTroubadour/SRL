local mq = require 'mq'
local Logging = require 'Write'
local CastUtil = require 'srl/util/CastUtil'
local StringUtil = require 'srl/Util/StringUtil'
local iniHelper = require "srl/ini/BaseIni"
buff_export = {}

local function castSelfBuffs(selfBuffs)
    if(ASSISTING == true) then return end
    if(selfBuffs ~= nil) then
        if(#selfBuffs > 0) then
            for _, i in ipairs(selfBuffs) do
                --This will never change probably will put it on object at creation
                local splits = StringUtil.split(i, "/")
                local spellToCastName = splits[1]

                local characterToBuffId = mq.TLO.Me.ID()

                local duration = mq.TLO.Me.Buff(spellToCastName).Duration()

                if(duration == 'NULL') then
                    duration = 0
                end
                --In ticks
                if(tonumber(duration) < 30) then
                    local gemNumber = StringUtil.getValueByName(i, "/Gem")
                    print(("Spell to cast name: %s Gem Number %s Character to Buff %s"):format(spellToCastName, gemNumber, characterToBuffId))
                    CastUtil.srl_cast(spellToCastName, gemNumber, characterToBuffId)
                end
            end
        end
    end
end

local function castBotBuffs(botBuffs)
    if(ASSISTING == true) then return end
    if(botBuffs ~= nil) then
        if(#botBuffs > 0) then
            for _, i in ipairs(botBuffs) do
                --This will never change probably will put it on object at creation
                local splits = StringUtil.split(i, "/")
                local spellToCastName = splits[1]

                local characterToBuff = splits[2]
                print("Trying to Buff ", characterToBuff, ' with ', spellToCastName)

                CONTROLLER:checkBuff(spellToCastName, characterToBuff, i)
            end
        end
    end
end

function buff_export.check_buff()
    --self buffs
    local selfBuffs = BUFFS_2D[iniHelper.SELF_BUFF_KEY]
    --bot buffs
    local botBuffs = BUFFS_2D[iniHelper.BOT_BUFF_KEY]
    --combat buffs

    Logging.loglevel = 'debug'
    castSelfBuffs(selfBuffs)
    castBotBuffs(botBuffs)
    Logging.loglevel = 'info'
end

return buff_export