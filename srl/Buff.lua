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

                local duration = mq.TLO.Me.Buff(spellToCastName).Duration.TotalSeconds()

                if(duration == nil) then
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

local function castBotBuffs(botBuffs)
    if(ASSISTING == true) then return end
    if(botBuffs ~= nil) then
        if(#botBuffs > 0) then
            local promises = {}
            for _, i in ipairs(botBuffs) do
                local splits = StringUtil.split(i, "/")
                local spellToCastName = splits[1]
                local characterToBuff = splits[2]
                table.insert(promises, buffService:poll(characterToBuff, spellToCastName, i))
            end

            local replies = Promise.all(promises):await()

            for i, reply in ipairs(replies) do
                if reply.data.hasBuff then
                end

                -- Refresh 60 seconds before expiration
                local refreshWindow = 60

                local nextTime = now + ((reply.data.duration - refreshWindow) * 1000)

                if reply.data.duration <= refreshWindow then
                    self:enqueue(target, spell, iniSpellLine)
                else
                    self.nextCheck[k] = nextTime
                end

            end

        else
            -- No buff → cast immediately
            self:enqueue(target, spell, iniSpellLine)
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