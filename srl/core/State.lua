local State = {}

State.assist = {
    generation = 0,
    targetID   = nil,
    scope      = nil,
    sender = nil,
}

-- ===== Follow State =====
State.follow = {
    targetName = nil,
    active     = false,
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

function State:setFollow(targetName)
    self.follow.targetName = targetName
    self.follow.active = true
end

function State:stopFollow()
    self.follow.active = false
end

function State:updateAssistState(payload)
    self.assist.generation = payload.generation
    self.assist.targetID = payload.id
    self.assist.sender = payload.sender
end

return State
