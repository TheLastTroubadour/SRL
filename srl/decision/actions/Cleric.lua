local mq = require 'mq'

-- Handles CLR emergency equalization abilities reserved for saving the tank:
--   Divine Arbitration (AA)  - equalizes HP across the group
--   Epic 2.0 click (item)    - similar equalization + cure effect
--
-- Fires only when the primary tank is alive, in group, and below the
-- configured threshold. Scores 108 — above single heals (105) but below
-- group heal (110), so it fires as an emergency before burning a single heal slot.

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

    local tank = self:findTank()
    if not tank then return 0 end

    -- DA and the epic only redistribute existing HP — they're useless if no one
    -- has HP to donate. Require non-tank group members to average above the
    -- minimum donor threshold before allowing either ability.
    local donorMin = self.config:get('Cleric.DonorMinPct') or 60
    if not self:hasSufficientDonors(tank.name, donorMin) then return 0 end

    -- Epic first: it equalizes AND cures, making it the stronger save
    local epicName      = self.config:get('Cleric.EpicName')
    local epicThreshold = self.config:get('Cleric.EpicPct') or 35
    if epicName and epicName ~= '' and tank.hp <= epicThreshold then
        if mq.TLO.FindItem('=' .. epicName)() then
            self.pendingAction = { type = 'epic', name = epicName, targetId = tank.id }
            return 108
        end
    end

    -- Divine Arbitration fallback
    local daThreshold = self.config:get('Cleric.DivineArbitrationPct') or 35
    if tank.hp <= daThreshold then
        if mq.TLO.Me.AltAbilityReady('Divine Arbitration')() then
            self.pendingAction = { type = 'aa' }
            return 108
        end
    end

    return 0
end

-- Returns true if non-tank group members average above minPct HP,
-- meaning there is meaningful HP to redistribute to the tank.
function ClericDecision:hasSufficientDonors(tankName, minPct)
    local total, count = 0, 0
    for i = 1, mq.TLO.Group.Members() do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            if m.CleanName():lower() ~= tankName:lower() then
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
        -- DA is a self-cast group ability; no targeting needed
        mq.cmd('/alt activate "Divine Arbitration"')

    elseif self.pendingAction.type == 'epic' then
        if mq.TLO.Target.ID() ~= self.pendingAction.targetId then
            mq.cmdf('/target id %s', self.pendingAction.targetId)
            mq.delay(100)
        end
        mq.cmdf('/useitem "%s"', self.pendingAction.name)
    end
end

-- Returns the primary tank's current status from the group, or nil if not found/dead.
function ClericDecision:findTank()
    local tanks = self.config:get('Heals.Tanks') or {}
    local tankName = tanks[1]
    if not tankName then return nil end

    for i = 1, mq.TLO.Group.Members() do
        local m = mq.TLO.Group.Member(i)
        if m() and m.Spawn() and not m.Dead() then
            if m.CleanName():lower() == tankName:lower() then
                return {
                    id   = m.ID(),
                    name = m.CleanName(),
                    hp   = m.PctHPs(),
                }
            end
        end
    end
    return nil
end

return ClericDecision
