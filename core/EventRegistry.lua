local mq = require 'mq'

local EventRegistry = {}
EventRegistry.__index = EventRegistry

function EventRegistry:new()
    local self = setmetatable({}, EventRegistry)
    return self
end

function EventRegistry:init(services)
    local buffService   = services.buffService
    local inviteService = services.inviteService
    local config        = services.config
    local trustService  = services.trustService

    -- Food/drink warnings: broadcast to console at most once per minute
    local consumableCooldown = {}
    local function warnConsumable(kind)
        local now = mq.gettime()
        if consumableCooldown[kind] and now < consumableCooldown[kind] then return end
        consumableCooldown[kind] = now + 60000
        mq.cmdf('/dgt all [%s] is out of %s!', mq.TLO.Me.Name(), kind)
    end

    mq.event('SRL_OutOfFood',       'You are out of food.',           function() warnConsumable('food')             end)
    mq.event('SRL_OutOfDrink',      'You are out of drink.',          function() warnConsumable('drink')            end)
    mq.event('SRL_OutOfFoodDrink',  'You are out of food and drink.', function() warnConsumable('food and drink')   end)

    -- Debuff immunity: back off that spell on that target for the session
    mq.event('SRL_DebuffImmune', 'Your target is immune to#*#', function()
        mq.cmd('/srlevent DebuffImmune')
    end)

    -- Death: clear own buff timers so everything repolls on rez
    mq.event('SRL_Death', 'You have been slain by#*#', function()
        if buffService then buffService:reset() end
    end)

    -- Nearby death: reset buff cooldowns for that character so they get rebuffed after rez
    mq.event('SRL_NearbyDeath', '#1# has been slain by#*#', function(line, name)
        if buffService and name then buffService:resetForTarget(name) end
    end)

    -- Group / raid invites
    mq.event('GroupInvite', '#1# invites you to join a group.#*#', function(line, inviter)
        if inviteService then inviteService:handleGroupInvite(inviter) end
    end)

    mq.event('RaidInvite', '#1# invites you to join a raid.#*#', function(line, inviter)
        if inviteService then inviteService:handleRaidInvite(inviter) end
    end)


    if not config then return end

    local function isTrusted(sender)
        return trustService:isTrusted(sender)
    end

    -- Register one event per trigger word using a literal pattern.
    -- Avoids #2# capture which does not reliably fire in MQNext.

    -- Group buff trigger
    local groupTrigger = (config:get('GroupBuffs.TellTrigger') or 'buffs'):lower()
    -- Debounce table: prevents the same tell from firing multiple times per tick
    local tellCooldown = {}

    mq.event('SRL_TellHandler', '#1# tells you, #2#', function(line, sender, message)
        -- Guard: empty captures happen when other chat lines partially match
        if not sender or sender == '' then return end
        -- #2# is unreliable in MQNext (especially for short messages); parse line as fallback
        if not message or message == '' then
            message = line:match('tells you, (.+)$') or ''
        end
        if message == '' then return end

        -- Debounce: ignore same sender within 3 seconds
        local now = mq.gettime()
        local key = sender:lower() .. ':' .. (message:lower():gsub('%s+', ''))
        if tellCooldown[key] and now < tellCooldown[key] then return end
        tellCooldown[key] = now + 3000

        if not isTrusted(sender) then return end

        -- Strip any surrounding punctuation/quotes left by EQ
        local request = message:lower():match('^[%\'%"%s]*(.-)%s*[%\'%"%.]?%s*$') or message:lower()

        local me = mq.TLO.Me.Name()

        if request == groupTrigger then
            mq.cmdf('/dgae /srlevent TellBuff target=%s sender=%s', sender, me)
            mq.cmdf('/srlevent TellBuff target=%s sender=%s', sender, me)
            return
        end

        local aliases = config:get('GroupBuffs.Aliases') or {}
        local matchedAlias = nil
        for k in pairs(aliases) do
            if k:lower() == request then matchedAlias = k; break end
        end
        if matchedAlias then
            mq.cmdf('/dgae /srlevent TellSpell trigger=%s target=%s sender=%s', matchedAlias, sender, me)
            mq.cmdf('/srlevent TellSpell trigger=%s target=%s sender=%s', matchedAlias, sender, me)
            return
        end

        local tlTrigger = config:get('Translocate.Trigger')
        if tlTrigger and tlTrigger:lower() == request then
            mq.cmdf('/dgae /srlevent TellTL target=%s sender=%s', sender, me)
            mq.cmdf('/srlevent TellTL target=%s sender=%s', sender, me)
            return
        end

        -- TL tell:   "/tell WizName tl iceclad"   → single target translocate
        -- Port tell: "/tell WizName port iceclad" → group portal
        local tlDest   = request:match('^tl%s+(.+)$')
        local portDest = request:match('^port%s+(.+)$')
        if tlDest then
            local dest = tlDest:gsub('%s+', '_')
            mq.cmdf('/dgae /srlevent TellPort type=tl dest=%s target=%s sender=%s', dest, sender, me)
            mq.cmdf('/srlevent TellPort type=tl dest=%s target=%s sender=%s', dest, sender, me)
            return
        end
        if portDest then
            local dest = portDest:gsub('%s+', '_')
            mq.cmdf('/dgae /srlevent TellPort type=portal dest=%s target=%s sender=%s', dest, sender, me)
            mq.cmdf('/srlevent TellPort type=portal dest=%s target=%s sender=%s', dest, sender, me)
            return
        end
    end)
end

return EventRegistry
