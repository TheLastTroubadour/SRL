local State = {}

State.assist = {
    generation = 0,
    targetID   = nil,
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
    followId = nil,
}

-- ===== Burn State =====
State.burn = {
    active     = false,
    generation = 0,
}

-- ===== Local Toggles =====
State.flags = {
    paused = false,
}

------------------------------------------------
-- Follow Helpers
------------------------------------------------

function State:setFollow(payload)
    self.follow.followId = payload.id
    self.follow.active = true
end

function State:stopFollow()
    self.follow.active = false
    self.follow.followId = nil
end

function State:stopAssist()
    self.assist.active = false
end

function State:updateAssistState(payload)
    self.assist.generation = payload.generation
    self.assist.targetID = payload.id
    self.assist.sender = payload.sender
    self.assist.active = true
end

function State:updateCombatState(state)
    self.combat.combatState = state
end

return State
