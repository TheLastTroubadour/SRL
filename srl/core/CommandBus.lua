local mq    = require 'mq'
local State = require 'srl.core.State'

local CommandBus = {}
CommandBus.handlers = {}

-- Armor type → set of class short names
local ARMOR_TYPES = {
    Silk    = { WIZ=true, MAG=true, NEC=true, ENC=true },
    Leather = { DRU=true, MNK=true, BST=true, ROG=true },
    Chain   = { RNG=true, SHM=true, BRD=true },
    Plate   = { WAR=true, PAL=true, SHD=true, CLR=true },
}

-- Build "key=val key=val ..." string from a list of raw arg tokens,
-- excluding any keys in the skip set (those are set by the bind itself).
local function buildExtra(args, skip)
    local parts = {}
    for _, token in ipairs(args) do
        local k, v = token:match("([^=]+)=([^=]+)")
        if k and v and not (skip and skip[k]) then
            table.insert(parts, k .. '=' .. v)
        end
    end
    return #parts > 0 and (' ' .. table.concat(parts, ' ')) or ''
end

-- Returns true if token matches the character by name, class, armor type, or group.
local function matchesToken(token, myClass, myName, sender)
    token = token:match('^%s*(.-)%s*$')  -- trim whitespace
    if token:lower() == 'group' then
        return sender ~= nil and mq.TLO.Group.Member(sender)() ~= nil
    end
    if ARMOR_TYPES[token] then
        return ARMOR_TYPES[token][myClass] == true
    end
    if myName:lower() == token:lower() then return true end
    return myClass == token:upper()
end

-- exclude always takes priority over include.
-- exclude=X  → skip if character matches X
-- include=X  → only process if character matches X
-- neither    → process everyone
-- Tokens: character name, class short name, armor type (Silk/Leather/Chain/Plate), Group
function CommandBus:matchesFilter(include, exclude, sender)
    local myClass = mq.TLO.Me.Class.ShortName()
    local myName  = mq.TLO.Me.Name()

    if exclude then
        for token in exclude:gmatch('[^,]+') do
            if matchesToken(token, myClass, myName, sender) then return false end
        end
    end

    if include then
        for token in include:gmatch('[^,]+') do
            if matchesToken(token, myClass, myName, sender) then return true end
        end
        return false
    end

    return true
end

function CommandBus:init()
    mq.unbind('/srlevent')
    local commandBus = self
    mq.bind('/srlevent', function(...)
        local args = { ... }
        local command = table.remove(args, 1)
        if not command then return end
        local payload = {}
        for _, token in ipairs(args) do
            local k, v = token:match("([^=]+)=([^=]+)")
            if k and v then payload[k] = v end
        end
        commandBus:dispatch(command, payload)
    end)

    mq.unbind('/assiston')
    mq.bind('/assiston', function(...)
        local extra = buildExtra({...}, { sender=true, id=true, generation=true })
        mq.cmdf('/dgae /srlevent Assist id=%s generation=%s sender=%s%s',
            mq.TLO.Target.ID(), State.assist.generation + 1, mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/followme')
    mq.bind('/followme', function(...)
        local extra = buildExtra({...}, { sender=true, id=true })
        mq.cmdf('/dgae /srlevent Follow id=%s sender=%s%s',
            mq.TLO.Me.ID(), mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/srlstop')
    mq.bind('/srlstop', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Stop sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/srlmove')
    mq.bind('/srlmove', function(...)
        local extra = buildExtra({...}, { sender=true, id=true })
        mq.cmdf('/dgae /srlevent Move id=%s sender=%s%s',
            mq.TLO.Me.ID(), mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/srlbackoff')
    mq.bind('/srlbackoff', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent BackOff sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/srlmaxmobs')
    mq.bind('/srlmaxmobs', function(n, ...)
        local extra = buildExtra({...}, { sender=true, n=true })
        mq.cmdf('/dgae /srlevent CCMaxMobs n=%s sender=%s%s',
            tostring(n), mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/quickburn')
    mq.bind('/quickburn', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent QuickBurn sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/longburn')
    mq.bind('/longburn', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent LongBurn sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/fullburn')
    mq.bind('/fullburn', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent FullBurn sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/epicburn')
    mq.bind('/epicburn', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent EpicBurn sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/lesson')
    mq.bind('/lesson', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Lesson sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/armor')
    mq.bind('/armor', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Armor sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/staunch')
    mq.bind('/staunch', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Staunch sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/intensity')
    mq.bind('/intensity', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Intensity sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/expedient')
    mq.bind('/expedient', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Expedient sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/throne')
    mq.bind('/throne', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent Throne sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    -- /playmelody <name> [include=X] [exclude=Y]
    -- First arg is the melody name; remaining key=value args are forwarded as filters.
    mq.unbind('/playmelody')
    mq.bind('/playmelody', function(name, ...)
        if not name or name == '' then return end
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent PlayMelody name=%s sender=%s%s',
            name, mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/stopmelody')
    mq.bind('/stopmelody', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent StopMelody sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/srlreload')
    mq.bind('/srlreload', function(...)
        local extra = buildExtra({...}, { sender=true })
        mq.cmdf('/dgae /srlevent ReloadConfig sender=%s%s', mq.TLO.Me.Name(), extra)
    end)

    local function splitItemArgs(args)
        local nameParts, kvArgs = {}, {}
        for _, a in ipairs(args) do
            if a:match('^[^=]+=') then
                table.insert(kvArgs, a)
            else
                table.insert(nameParts, a)
            end
        end
        return table.concat(nameParts, ' '), kvArgs
    end

    mq.unbind('/fi')
    mq.bind('/fi', function(...)
        local itemName, kvArgs = splitItemArgs({...})
        if itemName == '' then return end
        local extra = buildExtra(kvArgs, { sender=true })
        mq.cmdf('/dgae /srlevent FindItem item=%s sender=%s%s', itemName:gsub(' ', '_'), mq.TLO.Me.Name(), extra)
    end)

    mq.unbind('/fmi')
    mq.bind('/fmi', function(...)
        local itemName, kvArgs = splitItemArgs({...})
        if itemName == '' then return end
        local extra = buildExtra(kvArgs, { sender=true })
        mq.cmdf('/dgae /srlevent FindMissingItem item=%s sender=%s%s', itemName:gsub(' ', '_'), mq.TLO.Me.Name(), extra)
    end)
end

function CommandBus:register(command, handler)
    self.handlers[command] = handler
end

function CommandBus:dispatch(command, payload)
    if not self:matchesFilter(payload.include, payload.exclude, payload.sender) then return end
    local handler = self.handlers[command]
    if not handler then
        print("No handler registered for:", command)
        return
    end
    handler(payload)
end

return CommandBus
