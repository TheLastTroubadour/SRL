local mq = require 'mq'

local CureDecision = {}
CureDecision.__index = CureDecision

function CureDecision:new(config)
    local self = setmetatable({}, CureDecision)
    self.name         = "CureDecision"
    self.config       = config
    self.spells       = self:loadSpells()
    self.queue        = {}
    self.pendingEntry = nil
    self.pendingSpell = nil
    return self
end

-- Loads Cures.Spells from YAML. Each entry must have name, type, and either
-- gem (spell) or leave gem nil for AA abilities (type='aa').
-- Example YAML:
--   Cures:
--     Spells:
--       - name: Purified Blood
--         type: Poison
--         gem: 4
--       - name: Radiant Cure
--         type: Poison,Disease,Curse
--         spelltype: aa
function CureDecision:loadSpells()
    local list = self.config:get('Cures.Spells') or {}
    local result = {}
    for _, v in ipairs(list) do
        if v.name and v.type then
            table.insert(result, {
                name      = v.name,
                type      = v.type,          -- comma-separated cure types this spell covers
                gem       = v.gem,           -- nil for AA
                spelltype = v.spelltype or 'spell',  -- 'spell' or 'aa'
            })
        end
    end
    return result
end

-- Called by the CommandBus NeedCure handler when another bot broadcasts a request.
-- Upserts by targetId so re-broadcasts refresh the types list.
function CureDecision:addRequest(targetId, targetName, types)
    local id = tonumber(targetId)
    if not id then return end

    for i, entry in ipairs(self.queue) do
        if entry.targetId == id then
            self.queue[i] = { targetId = id, targetName = targetName, types = types }
            return
        end
    end

    table.insert(self.queue, { targetId = id, targetName = targetName, types = types })
end

function CureDecision:score(ctx)
    self.pendingEntry = nil
    self.pendingSpell = nil

    if ctx.casting then return 0 end
    if #self.spells == 0 then return 0 end
    if #self.queue == 0 then return 0 end

    for _, entry in ipairs(self.queue) do
        local spell = self:findSpell(entry.types)
        if spell and self:isReady(spell) then
            self.pendingEntry = entry
            self.pendingSpell = spell
            return 95
        end
    end

    return 0
end

function CureDecision:execute(ctx)
    if not self.pendingEntry or not self.pendingSpell then return end

    local entry = self.pendingEntry
    local spell = self.pendingSpell

    -- Remove immediately; if target is still afflicted they will re-broadcast
    for i, e in ipairs(self.queue) do
        if e.targetId == entry.targetId then
            table.remove(self.queue, i)
            break
        end
    end

    if mq.TLO.Target.ID() ~= entry.targetId then
        mq.cmdf('/target id %s', entry.targetId)
        mq.delay(100)
    end

    if spell.spelltype == 'aa' then
        mq.cmdf('/alt activate "%s"', spell.name)
    else
        mq.cmdf('/casting "%s"|%s', spell.name, spell.gem)
    end
end

-- Find the first configured spell that covers at least one of the requested types.
-- typesStr is a comma-separated string like "Poison,Disease".
function CureDecision:findSpell(typesStr)
    for _, spell in ipairs(self.spells) do
        -- Check each cure type this spell covers against the requested types
        for coverType in spell.type:gmatch('[^,]+') do
            coverType = coverType:match('^%s*(.-)%s*$')
            if typesStr:find(coverType, 1, true) then
                return spell
            end
        end
    end
    return nil
end

function CureDecision:isReady(spell)
    if spell.spelltype == 'aa' then
        return mq.TLO.Me.AltAbilityReady(spell.name)() == true
    end
    return mq.TLO.Cast.Ready(spell.name)() == true
end

return CureDecision
