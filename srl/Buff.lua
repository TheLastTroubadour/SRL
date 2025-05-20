local mq = require 'mq'
local Logging = require 'Write'
local CastUtil = require 'srl/util/CastUtil'
local DanNet = require 'srl/DanNet'
buff_export = {}

local function castSelfBuffs(selfBuffs)
    if(ASSISTING == true) then return end
    if(selfBuffs ~= nil) then
        if(#selfBuffs > 0) then
            for _, i in ipairs(selfBuffs) do
                --This will never change probably will put it on object at creation
                local splits = StringUtil.split(i, "/")
                local spellToCastName = splits[1]

                local characterToBuff = mq.TLO.Me.CleanName()
                local characterToBuffId = mq.TLO.Me.ID()

                local query = ('Me.Buff[%s].Duration.TotalSeconds'):format(spellToCastName)
                DanNet.create_observer(characterToBuff, query, 40)
                local duration = DanNet.read_observer(characterToBuff, query, 40)

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

local function castBotBuffs(selfBuffs)
    if(ASSISTING == true) then return end
    if(selfBuffs ~= nil) then
        if(#selfBuffs > 0) then
            for _, i in ipairs(selfBuffs) do
                --This will never change probably will put it on object at creation
                local splits = StringUtil.split(i, "/")
                local spellToCastName = splits[1]

                local characterToBuff = splits[2]
                local characterToBuffId = mq.TLO.NetBots(characterToBuff).ID()


                local query = ('Me.Buff[%s].Duration.TotalSeconds'):format(spellToCastName)
                DanNet.create_observer(characterToBuff, query, 40)
                local duration = DanNet.read_observer(characterToBuff, query, 40)

                if(duration == 'NULL') then
                    duration = 0
                end

                --In ticks
                if(tonumber(duration) < 30) then
                    local gemNumber = StringUtil.getValueByName(i, "/Gem")
                    CastUtil.srl_cast(spellToCastName, gemNumber, characterToBuffId)
                end
            end
        end
    end
end

function buff_export.check_buff()
    --self buffs
    local selfBuffs = BUFFS_2D[IniHelper.SELF_BUFF_KEY]
    --bot buffs
    local botBuffs = BUFFS_2D[IniHelper.BOT_BUFF_KEY]
    --combat buffs

    Logging.loglevel = 'debug'
    castSelfBuffs(selfBuffs)
    castBotBuffs(botBuffs)
    Logging.loglevel = 'info'
end

return buff_export