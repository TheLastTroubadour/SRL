local mq    = require 'mq'
local State = require 'core.State'
local Help  = require 'core.Help'

local CommandBus = {}
CommandBus.handlers = {}

-- Armor type / role group → set of class short names (keys are lowercase for case-insensitive lookup)
local ARMOR_TYPES = {
    silk    = { WIZ=true, MAG=true, NEC=true, ENC=true },
    leather = { DRU=true, MNK=true, BST=true, ROG=true },
    chain   = { RNG=true, SHM=true, BRD=true },
    plate   = { WAR=true, PAL=true, SHD=true, CLR=true },
    melee   = { WAR=true, PAL=true, SHD=true, MNK=true, ROG=true, BER=true, RNG=true, BST=true, BRD=true },
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
    if ARMOR_TYPES[token:lower()] then
        return ARMOR_TYPES[token:lower()][myClass] == true
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

    local function stripItemLink(text)
        -- EQ item links: \x12 (1 byte) + 91 bytes of hex link data + item name + \x12 (1 byte)
        if text:byte(1) == 0x12 then
            local name = text:sub(93, -2)
            if name ~= '' then return name end
        end
        return text
    end

    local function splitItemArgs(args)
        local nameParts, kvArgs = {}, {}
        for _, a in ipairs(args) do
            if a:match('^[^=]+=') then
                table.insert(kvArgs, a)
            else
                table.insert(nameParts, a)
            end
        end
        return stripItemLink(table.concat(nameParts, ' ')), kvArgs
    end

    -- Simple broadcast helpers
    local function broadcast(event, extra)
        mq.cmdf('/dgae /srlevent %s sender=%s%s', event, mq.TLO.Me.Name(), extra or '')
    end

    -- /srl <subcommand> [args...]
    mq.unbind('/srl')
    mq.bind('/srl', function(subcmd, ...)
        if not subcmd then
            print('[SRL] Usage: /srl <command> [args]')
            return
        end
        subcmd = subcmd:lower()
        local args = { ... }
        local extra = buildExtra(args, { sender=true })
        local me = mq.TLO.Me.Name()

        -- Combat
        if subcmd == 'assiston' then
            local xtra = buildExtra(args, { sender=true, id=true, generation=true })
            mq.cmdf('/dgze /srlevent Assist id=%s generation=%s sender=%s%s',
                mq.TLO.Target.ID(), State.assist.generation + 1, me, xtra)

        elseif subcmd == 'backoff' then
            broadcast('BackOff', extra)

        -- Movement
        elseif subcmd == 'follow' then
            local followId = mq.TLO.Me.ID()
            for _, a in ipairs(args) do
                local k, v = a:match('([^=]+)=([^=]+)')
                if k == 'id' then followId = tonumber(v) or followId end
            end
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgze /srlevent Follow id=%s sender=%s%s', followId, me, xtra)

        elseif subcmd == 'stop' then
            broadcast('Stop', extra)

        elseif subcmd == 'move' then
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgze /srlevent Move id=%s sender=%s%s', mq.TLO.Me.ID(), me, xtra)

        elseif subcmd == 'navfollow' then
            broadcast('NavFollow', extra)

        elseif subcmd == 'mtt' then
            if not mq.TLO.Target() then return end
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgze /srlevent MoveToTarget id=%s sender=%s%s',
                mq.TLO.Target.ID(), me, xtra)

        -- Save currently equipped weapons to a named set in YAML
        elseif subcmd == 'saveweaponset' then
            local set = args[1]
            if not set or set == '' then
                print('[SRL] Usage: /srl saveweaponset <setname>')
                return
            end
            mq.cmdf('/srlevent WeaponSet set=%s sender=%s', set, me)

        -- Weapon swap
        elseif subcmd == 'swapweapons' then
            local set = args[1]
            if not set or set == '' then
                print('[SRL] Usage: /srl swapweapons <setname>')
                return
            end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true, set=true })
            mq.cmdf('/dgze /srlevent SwapWeapons set=%s sender=%s%s', set, me, xtra)
            mq.cmdf('/srlevent SwapWeapons set=%s sender=%s%s', set, me, xtra)

        -- Burns
        elseif subcmd == 'castcombatbuffs' then broadcast('CastCombatBuffs', extra)
        elseif subcmd == 'quickburn' then broadcast('QuickBurn', extra)
        elseif subcmd == 'longburn'  then broadcast('LongBurn',  extra)
        elseif subcmd == 'fullburn'  then broadcast('FullBurn',  extra)
        elseif subcmd == 'epicburn'  then broadcast('EpicBurn',  extra)

        -- AAs
        elseif subcmd == 'lesson'    then broadcast('Lesson',    extra)
        elseif subcmd == 'armor'     then broadcast('Armor',     extra)
        elseif subcmd == 'staunch'   then broadcast('Staunch',   extra)
        elseif subcmd == 'intensity' then broadcast('Intensity', extra)
        elseif subcmd == 'expedient' then broadcast('Expedient', extra)
        elseif subcmd == 'throne'    then broadcast('Throne',    extra)
        elseif subcmd == 'infusion'  then broadcast('Infusion',  extra)
        elseif subcmd == 'fellowship' then broadcast('Fellowship', extra)

        -- Bard
        elseif subcmd == 'melody' then
            local name = args[1]
            if not name or name == '' then return end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true })
            mq.cmdf('/dgae /srlevent PlayMelody name=%s sender=%s%s', name, me, xtra)

        elseif subcmd == 'stopmelody' then broadcast('StopMelody', extra)

        elseif subcmd == 'medon' then
            mq.cmdf('/dgze /srlevent MedOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent MedOn sender=%s%s', me, extra)

        elseif subcmd == 'medoff' then
            mq.cmdf('/dgze /srlevent MedOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent MedOff sender=%s%s', me, extra)

        elseif subcmd == 'reson' then
            mq.cmdf('/dgze /srlevent ResourceOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent ResourceOn sender=%s%s', me, extra)

        elseif subcmd == 'resoff' then
            mq.cmdf('/dgze /srlevent ResourceOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent ResourceOff sender=%s%s', me, extra)

        elseif subcmd == 'moveon' then
            local seconds = args[1] or '60'
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true, seconds=true })
            mq.cmdf('/dgze /srlevent SuppressMed seconds=%s sender=%s%s', seconds, me, xtra)
            mq.cmdf('/srlevent SuppressMed seconds=%s sender=%s%s', seconds, me, xtra)

        elseif subcmd == 'stickpoint' then
            local point = args[1]
            if not point or point == '' then return end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true })
            mq.cmdf('/dgze /srlevent StickPoint point=%s sender=%s%s', point, me, xtra)
            mq.cmdf('/srlevent StickPoint point=%s sender=%s%s', point, me, xtra)

        elseif subcmd == 'stickdist' then
            local dist = args[1]
            if not dist or dist == '' then return end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true })
            mq.cmdf('/dgze /srlevent StickDist dist=%s sender=%s%s', dist, me, xtra)
            mq.cmdf('/srlevent StickDist dist=%s sender=%s%s', dist, me, xtra)

        elseif subcmd == 'mount' then
            mq.cmdf('/dgze /srlevent Mount sender=%s%s', me, extra)
            mq.cmdf('/srlevent Mount sender=%s%s', me, extra)

        elseif subcmd == 'buffme' then
            mq.cmdf('/dgae /srlevent BuffMe sender=%s%s', me, extra)
            mq.cmdf('/srlevent BuffMe sender=%s%s', me, extra)

        elseif subcmd == 'buffit' then
            local target = mq.TLO.Target.CleanName()
            if not target or target == '' then
                print('[SRL] buffit: no target selected')
                return
            end
            local xtra = buildExtra(args, { sender=true, name=true })
            mq.cmdf('/dgae /srlevent BuffIt name=%s sender=%s%s', (target:gsub(' ', '_')), me, xtra)
            mq.cmdf('/srlevent BuffIt name=%s sender=%s%s', (target:gsub(' ', '_')), me, xtra)

        -- Spell set
        elseif subcmd == 'set' then
            local set = args[1]
            if not set or set == '' then return end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true })
            mq.cmdf('/dgae /srlevent SetSpellSet set=%s sender=%s%s', set, me, xtra)

        -- CC
        elseif subcmd == 'maxmobs' then
            local n = args[1]
            if not n then return end
            local xtra = buildExtra({ unpack(args, 2) }, { sender=true, n=true })
            mq.cmdf('/dgae /srlevent CCMaxMobs n=%s sender=%s%s', tostring(n), me, xtra)

        elseif subcmd == 'addnomez' then
            if not mq.TLO.Target() then return end
            if mq.TLO.Target.Type() ~= 'NPC' then return end
            local id   = mq.TLO.Target.ID()
            local name = (mq.TLO.Target.CleanName() or ''):gsub(' ', '_')
            mq.cmdf('/dgae /srlevent AddNoMez id=%s name=%s sender=%s', id, name, me)
            mq.cmdf('/srlevent AddNoMez id=%s name=%s sender=%s', id, name, me)

        elseif subcmd == 'addnoslow' then
            if not mq.TLO.Target() then return end
            if mq.TLO.Target.Type() ~= 'NPC' then return end
            local id   = mq.TLO.Target.ID()
            local name = (mq.TLO.Target.CleanName() or ''):gsub(' ', '_')
            mq.cmdf('/dgae /srlevent AddNoSlow id=%s name=%s sender=%s', id, name, me)
            mq.cmdf('/srlevent AddNoSlow id=%s name=%s sender=%s', id, name, me)

        -- Item search
        elseif subcmd == 'clickitem' then
            local itemName, kvArgs = splitItemArgs(args)
            if itemName == '' then
                print('[SRL] Usage: /srl clickitem <item name> [id=<targetId>]')
                return
            end
            local targetId = mq.TLO.Target.ID() or 0
            for _, a in ipairs(kvArgs) do
                local k, v = a:match('([^=]+)=([^=]+)')
                if k == 'id' then targetId = tonumber(v) or targetId end
            end
            if not targetId or targetId == 0 then
                print('[SRL] clickitem: no target selected')
                return
            end
            local xtra = buildExtra(kvArgs, { sender=true, id=true })
            mq.cmdf('/dgae /srlevent ClickItem item=%s id=%s sender=%s%s',
                itemName:gsub(' ', '_'), targetId, me, xtra)
            mq.cmdf('/srlevent ClickItem item=%s id=%s sender=%s%s',
                itemName:gsub(' ', '_'), targetId, me, xtra)

        elseif subcmd == 'fi' then
            local itemName, kvArgs = splitItemArgs(args)
            if itemName == '' then return end
            local xtra = buildExtra(kvArgs, { sender=true })
            mq.cmdf('/dgae /srlevent FindItem item=%s sender=%s%s',
                itemName:gsub(' ', '_'), me, xtra)
            mq.cmdf('/srlevent FindItem item=%s sender=%s%s',
                itemName:gsub(' ', '_'), me, xtra)

        elseif subcmd == 'fmi' then
            local itemName, kvArgs = splitItemArgs(args)
            if itemName == '' then return end
            local xtra = buildExtra(kvArgs, { sender=true })
            mq.cmdf('/dgae /srlevent FindMissingItem item=%s sender=%s%s',
                itemName:gsub(' ', '_'), me, xtra)
            mq.cmdf('/srlevent FindMissingItem item=%s sender=%s%s',
                itemName:gsub(' ', '_'), me, xtra)

        elseif subcmd == 'findslot' then
            local slot = args[1]
            if not slot or slot == '' then return end
            local kvArgs = { unpack(args, 2) }
            local xtra = buildExtra(kvArgs, { sender=true, slot=true })
            mq.cmdf('/dgae /srlevent FindSlot slot=%s sender=%s%s', slot, me, xtra)
            mq.cmdf('/srlevent FindSlot slot=%s sender=%s%s', slot, me, xtra)

        -- Status
        elseif subcmd == 'status' then
            local threshold, kvArgs = nil, {}
            for _, a in ipairs(args) do
                local k, v = a:match('^([^=]+)=(.+)$')
                if k == 'threshold' then threshold = v
                elseif k then table.insert(kvArgs, a)
                elseif not threshold then threshold = a
                end
            end
            local xtra = buildExtra(kvArgs, { sender=true })
            local t = threshold and (' threshold=' .. threshold) or ''
            mq.cmdf('/dgae /srlevent Status sender=%s%s%s', me, t, xtra)

        -- NPC interaction
        elseif subcmd == 'turnin' then
            if not mq.TLO.Target() then return end
            if mq.TLO.Target.Type() ~= 'NPC' then return end
            local itemName, kvArgs = splitItemArgs(args)
            if itemName == '' then return end
            local xtra = buildExtra(kvArgs, { sender=true, id=true })
            mq.cmdf('/dgae /srlevent TurnIn id=%s item=%s sender=%s%s',
                mq.TLO.Target.ID(), itemName:gsub(' ', '_'), me, xtra)

        elseif subcmd == 'say' then
            if not mq.TLO.Target() then return end
            local phrase, kvArgs = splitItemArgs(args)
            if phrase == '' then return end
            local xtra = buildExtra(kvArgs, { sender=true, id=true, msg=true })
            mq.cmdf('/dgae /srlevent SayPhrase id=%s msg=%s sender=%s%s',
                mq.TLO.Target.ID(), phrase:gsub(' ', '_'), me, xtra)

        -- Config / admin
        elseif subcmd == 'reload' then
            broadcast('ReloadConfig', extra)

        elseif subcmd == 'debug' then
            mq.cmd('/srlevent ToggleDebug')

        elseif subcmd == 'overlay' then
            mq.cmd('/srlevent ToggleGroupStatus')

        elseif subcmd == 'config' then
            mq.cmd('/srlevent ToggleConfigEditor')

        elseif subcmd == 'debuffon' then
            local targetId = mq.TLO.Target.ID() or 0
            if targetId == 0 then
                print('[SRL] debuffon: no target selected')
                return
            end
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgze /srlevent DebuffOn id=%s sender=%s%s', targetId, me, xtra)
            mq.cmdf('/srlevent DebuffOn id=%s sender=%s%s', targetId, me, xtra)

        elseif subcmd == 'debuffoff' then
            mq.cmdf('/dgze /srlevent DebuffOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent DebuffOff sender=%s%s', me, extra)

        elseif subcmd == 'doton' then
            local targetId = mq.TLO.Target.ID() or 0
            if targetId == 0 then
                print('[SRL] doton: no target selected')
                return
            end
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgze /srlevent DotOn id=%s sender=%s%s', targetId, me, xtra)
            mq.cmdf('/srlevent DotOn id=%s sender=%s%s', targetId, me, xtra)

        elseif subcmd == 'dotoff' then
            mq.cmdf('/dgze /srlevent DotOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent DotOff sender=%s%s', me, extra)

        elseif subcmd == 'aeon' then
            mq.cmdf('/dgze /srlevent AEOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent AEOn sender=%s%s', me, extra)

        elseif subcmd == 'aeoff' then
            mq.cmdf('/dgze /srlevent AEOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent AEOff sender=%s%s', me, extra)

        elseif subcmd == 'expmode' then
            local state = args[1] and args[1]:lower()
            local stateArg = (state == 'on' or state == 'off') and (' state=' .. state) or ''
            mq.cmdf('/dgze /srlevent ExpMode sender=%s%s', me, stateArg)
            mq.cmdf('/srlevent ExpMode sender=%s%s', me, stateArg)

        elseif subcmd == 'rez' then
            local targetId = mq.TLO.Target.ID()
            if not targetId or targetId == 0 then
                print('[SRL] rez: no target selected')
                return
            end
            if mq.TLO.Target.Type() ~= 'Corpse' then
                print('[SRL] rez: target must be a PC corpse')
                return
            end
            local rawName   = mq.TLO.Target.CleanName() or ''
            local charName  = rawName:match("^(.+)'s [Cc]orpse$") or rawName
            local nameArg   = (charName:gsub(' ', '_'))
            mq.cmdf('/dgae /srlevent RezTarget id=%s name=%s', targetId, nameArg)
            mq.cmdf('/srlevent RezTarget id=%s name=%s', targetId, nameArg)
            print(string.format('[SRL] rez: requesting rez for %s (id %s)', charName, targetId))

        elseif subcmd == 'puller' then
            State.flags.isPuller = not State.flags.isPuller
            print(string.format('[SRL] Puller mode: %s', State.flags.isPuller and 'ON' or 'OFF'))

        elseif subcmd == 'count' then
            local peerString = mq.TLO.DanNet.Peers() or ''
            local inZone, outOfZone = {}, {}
            for name in peerString:gmatch('[^|]+') do
                if name and name ~= '' then
                    local charName = name:match('_(.+)') or name
                    local spawn = mq.TLO.Spawn('pc =' .. charName)
                    if spawn() then
                        table.insert(inZone, { name = charName, dist = spawn.Distance() or 0 })
                    else
                        table.insert(outOfZone, charName)
                    end
                end
            end
            table.sort(inZone, function(a, b) return a.dist < b.dist end)
            print(string.format('[SRL] === Bot Count: %d in zone | %d out of zone ===', #inZone, #outOfZone))
            if #inZone > 0 then
                print('[SRL] In Zone:')
                for _, e in ipairs(inZone) do
                    print(string.format('[SRL]   %-20s  %.0f units', e.name, e.dist))
                end
            end
            if #outOfZone > 0 then
                print('[SRL] Out of Zone:')
                for _, name in ipairs(outOfZone) do print('[SRL]   ' .. name) end
            end

        elseif subcmd == 'help' then
            Help.show(args[1] and args[1]:lower() or 'topics')

        elseif subcmd == 'restart' then
            -- Schedule self restart before stopping (timed persists after lua stops)
            mq.cmd('/timed 30 /lua run srl')
            -- Stop all peers
            mq.cmdf('/dgae /lua stop srl')
            -- Give peers 2 seconds to fully stop before telling them to start
            mq.delay(2000)
            -- Start peers (self timed restart already queued)
            mq.cmdf('/dgae /lua run srl')
            -- Stop self last
            mq.cmd('/lua stop srl')

        else
            print('[SRL] Unknown command: ' .. subcmd)
        end
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
