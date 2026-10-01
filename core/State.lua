local mq = require 'mq'
local State = {}

State.lastActivity = mq.gettime()

State.assist = {
    generation = 0,
    targetId   = nil,
    targetName = nil, -- EQ recycles spawn IDs once a mob despawns, so a later mob
                       -- can legitimately reuse an old target's ID -- name is the
                       -- tiebreaker for "is this actually the same engagement."
    scope      = nil,
    active = false,
    sender = nil,
}


--Combat State
State.combat = {
    combatState = false
}


-- ===== Follow State =====
State.follow = {
    followName = nil,
    active     = false,
    followId   = nil,
    mode       = 'stick',  -- 'stick' | 'nav'
}

-- ===== Move State =====
State.move = {
    active   = false,
    targetId = nil,
}

-- ===== Charm State =====
State.charm = {
    petId = nil,
}

-- ===== Burn State =====
State.burn = {
    active     = false,
    generation = 0,
}

-- ===== Pull State =====
State.pull = {
    camp = nil,   -- { x=, y=, z= } via /srl setcamp. In-memory only, resets on restart.
}

function State:setCamp(x, y, z)
    self.pull.camp = { x = x, y = y, z = z }
end

function State:clearCamp()
    self.pull.camp = nil
end

-- ===== Spell Set =====
State.spellSet = 'Main'

-- ===== Local Toggles =====
State.flags = {
    paused                = false,
    manualMode            = false,  -- true = all automation suspended, /srl manualmode to toggle
    automode              = nil,   -- nil = off, else 'puller' | 'tank' | 'assist'
    aeEnabled             = false,
    expMode               = false,
    medDisabled           = false,
    buffDisabled          = false,
    curesDisabled         = false,
    epicDisabled          = false,
    groupHealDisabled     = false,
    lootDisabled          = false,
    commandDebuffTargetId = nil,
    commandDotTargetId    = nil,
    castInFlight          = false,
}

State.caster = {
    medMode = false
}

------------------------------------------------
-- Follow Helpers
------------------------------------------------

function State:setFollow(payload)
    self.follow.followId = payload.id
    self.follow.active   = true
    self.follow.mode     = payload.mode or 'stick'
end

function State:stopFollow()
    self.follow.active = false
    self.follow.followId = nil
end

function State:stopAssist()
    self.assist.active = false
    self.assist.targetId = nil
    self.assist.targetName = nil
    self.assist.sender = nil
end

function State:updateAssistState(payload)
    self.assist.generation = self.assist.generation + 1
    self.assist.targetId = payload.id
    self.assist.targetName = payload.name
    self.assist.sender = payload.sender
    self.assist.active = true
end

function State:updateCombatState(state)
    self.combat.combatState = state
end

function State:clearCombatState()
    self.assist.generation = self.assist.generation + 1
    self.assist.targetId = nil
    self.assist.targetName = nil
    self.assist.active = false
end

function State:setMedMode(state)
    self.caster.medMode = state
end

function State:setMove(payload)
    self.move.active   = true
    self.move.targetId = payload and payload.id or nil
end

function State:clearMove()
    self.move.active   = false
    self.move.targetId = nil
end

function State:updateLastActivity()
    self.lastActivity = mq.gettime()
end


return State
