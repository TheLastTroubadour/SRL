local mq = require 'mq'
local Target = require 'service.TargetService'

-- Handles CLR emergency equalization abilities:
--   Divine Arbitration (AA)  - equalizes HP across the group
--   Epic 2.0 click (item)    - similar equalization + cure effect
--
-- Fires when any group member (including self) drops below the configured
-- threshold and there are sufficient donors to make equalization worthwhile.
-- Scores 108 — above single heals (105) but below group heal (110).

local ClericDecision = {}
ClericDecision.__index = ClericDecision

function ClericDecision:new(config)
    local self = setmetatable({}, ClericDecision)
    self.name          = "ClericDecision"
    self.config        = config
    self.pendingAction = nil
    return self
end

function ClericDecision:score(ctx)
    self.pendingAction = nil

    if ctx.casting then return 0 end
    if mq.TLO.Me.Class.ShortName() ~= 'CLR' then return 0 end

    local target = self:findCriticalTarget()
    if not target then return 0 end

    -- DA and the epic only redistribute existing HP — they're useless if no one
    -- has HP to donate. Require other group members to average above the
    -- minimum donor threshold before allowing either ability.
    local donorMin = self.config:get('Cleric.DonorMinPct') or 60
    if not self:hasSufficientDonors(target.name, donorMin) then return 0 end

    -- Epic first: it equalizes AND cures, making it the stronger save
    local epicName      = self.config:get('Cleric.EpicName')
    local epicThreshold = self.config:get('Cleric.EpicPct') or 35
    if type(epicName) == 'string' and epicName ~= '' and target.hp <= epicThreshold then
        if mq.TLO.FindItem('=' .. epicName)() then
            self.pendingAction = { type = 'epic', name = epicName, targetId = target.id }
            return 108
        end
    end

    -- Divine Arbitration fallback
    local daThreshold = self.config:get('Cleric.DivineArbitrationPct') or 35
    if target.hp <= daThreshold then
        if mq.TLO.Me.AltAbilityReady('Divine Arbitration')() then
            self.pendingAction = { type = 'aa' }
            return 108
        end
    end

    return 0
end

-- Returns true if group members other than the critical target average above
-- minPct HP, meaning there is meaningful HP to redistribute.
function ClericDecision:hasSufficientDonors(targetName, minPct)
    local total, count = 0, 0

    -- Include self
    if mq.TLO.Me.Name():lower() ~= targetName:lower() then
        total = total + mq.TLO.Me.PctHPs()
        count = count + 1
    end

    for i = 1, mq.TLO.Group.Members() do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            if m.CleanName():lower() ~= targetName:lower() then
                total = total + m.PctHPs()
                count = count + 1
            end
        end
    end

    if count == 0 then return false end
    return (total / count) >= minPct
end

function ClericDecision:execute(ctx)
    if not self.pendingAction then return end

    if self.pendingAction.type == 'aa' then
        mq.cmd('/alt activate "Divine Arbitration"')

    elseif self.pendingAction.type == 'epic' then
        if mq.TLO.Target.ID() ~= self.pendingAction.targetId then
            Target:getTargetById(self.pendingAction.targetId)
        end
        mq.cmdf('/useitem "%s"', self.pendingAction.name)
    end
end

-- Returns the lowest-HP group member (including self), or nil if no one is
-- below the stricter of the two thresholds.
function ClericDecision:findCriticalTarget()
    local epicThreshold = self.config:get('Cleric.EpicPct') or 35
    local daThreshold   = self.config:get('Cleric.DivineArbitrationPct') or 35
    local threshold     = math.max(epicThreshold, daThreshold)

    local worst = nil

    -- Check self
    if not mq.TLO.Me.Dead() then
        local hp = mq.TLO.Me.PctHPs()
        if hp <= threshold then
            worst = { id = mq.TLO.Me.ID(), name = mq.TLO.Me.Name(), hp = hp }
        end
    end

    for i = 1, mq.TLO.Group.Members() do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            local hp = m.PctHPs()
            if hp <= threshold and (not worst or hp < worst.hp) then
                worst = { id = m.ID(), name = m.CleanName(), hp = hp }
            end
        end
    end

    return worst
end

return ClericDecision
