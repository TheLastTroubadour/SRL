local mq = require 'mq'
local Logging = require 'srl/core/Write'
local CastUtil = require 'srl/util/CastUtil'
local StringUtil = require 'srl/Util/StringUtil'
local iniHelper = require "srl/ini/IniHelper"
local Promise = require 'srl/core/Promise'
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
            scheduler:spawn(function()
                local promises = {}
                local requests = {}
                for _, iniSpellLine in ipairs(botBuffs) do
                    local splits = StringUtil.split(iniSpellLine, "/")
                    local spell = splits[1]
                    local target = splits[2]
                    local p = buffService:pollIfDue(target, spell, iniSpellLine)

                    if p then
                        table.insert(requests, {
                            spell = spell,
                            iniSpellLine = iniSpellLine,
                            promise = p,
                        })
                    end
                end

                if #requests == 0 then
                    return
                end

                for _, r in ipairs(requests) do
                    table.insert(promises, r.promise)
                end

                local replies = Promise.all(promises):await()

                for i, reply in ipairs(replies) do
                    buffService:handlePollResult(reply.data.name, requests[i], reply)
                end
            end)
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