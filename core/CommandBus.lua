local mq            = require 'mq'
local State         = require 'core.State'
local Help          = require 'core.Help'
local AssistUtil    = require 'util.AssistUtil'
local BroadcastUtil = require 'util.BroadcastUtil'

local CommandBus = {}
CommandBus.handlers = {}

-- Armor type / role group → set of class short names (keys are lowercase for case-insensitive lookup)
local ARMOR_TYPES = {
    silk    = { WIZ=true, MAG=true, NEC=true, ENC=true },
    leather = { DRU=true, MNK=true, BST=true, ROG=true },
    chain   = { RNG=true, SHM=true, BRD=true },
    plate   = { WAR=true, PAL=true, SHD=true, CLR=true },
    melee   = { WAR=true, PAL=true, SHD=true, MNK=true, ROG=true, BER=true, RNG=true, BST=true, BRD=true },
    healers = { CLR=true, DRU=true, SHM=true },
    casters = { WIZ=true, MAG=true, NEC=true, ENC=true },
}

-- Valid /srl automode <role> values
local VALID_AUTOMODES = { puller = true, tank = true, assist = true, tankpuller = true }

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

-- Returns true if token matches the character by name, class, armor type,
-- group, raid, or "me" (sender only).
local function matchesToken(token, myClass, myName, sender)
    token = token:match('^%s*(.-)%s*$')  -- trim whitespace
    if token:lower() == 'group' then
        return sender ~= nil and mq.TLO.Group.Member(sender)() ~= nil
    end
    if token:lower() == 'raid' then
        return sender ~= nil and mq.TLO.Raid.Member(sender)() ~= nil
    end
    if token:lower() == 'me' then
        return sender ~= nil and myName:lower() == sender:lower()
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
-- Tokens: character name, class short name, armor type (Silk/Leather/Chain/Plate),
-- Group (sender's EQ group), Raid (sender's raid), Me (sender only)
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

function CommandBus:init(config)
    self.config = config
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
            -- Only restricted once opted into automode at all -- automode off
            -- (never touched /srl automode) can still call assist freely; once
            -- in automode, only tank/puller/tankpuller (not assist) are allowed to.
            if State.flags.automode and State.flags.automode ~= 'tank' and State.flags.automode ~= 'puller'
                    and State.flags.automode ~= 'tankpuller' then
                print('[SRL] assiston: automode is "' .. State.flags.automode
                    .. '" -- only tank/puller/tankpuller automode can call assist')
                return
            end
            local targetId = mq.TLO.Target.ID()
            if not targetId or targetId == 0 then
                print('[SRL] assiston: no target selected')
                return
            end
            local xtra = buildExtra(args, { sender=true, id=true, generation=true })
            AssistUtil.broadcastAssist(targetId, xtra)

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

        -- Save currently memmed gems (or specific gem numbers) to a named GemSwap set in YAML
        elseif subcmd == 'gemswap' then
            local setName = args[1]
            if not setName or setName == '' then
                print('[SRL] Usage: /srl gemswap <SetName> [gem gem ...]  (no gems = capture all)')
                return
            end
            local gems = {}
            for i = 2, #args do
                local n = tonumber(args[i])
                if n then table.insert(gems, tostring(n)) end
            end
            mq.cmdf('/srlevent GemSwapSave set=%s gems=%s sender=%s', setName, table.concat(gems, ','), me)

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

        elseif subcmd == 'med' then
            local mode = args[1] and args[1]:lower()
            local modeExtra = buildExtra({ unpack(args, 2) }, { sender=true })
            if mode == 'on' then
                mq.cmdf('/dgze /srlevent MedOn sender=%s%s', me, modeExtra)
                mq.cmdf('/srlevent MedOn sender=%s%s', me, modeExtra)
            elseif mode == 'off' then
                mq.cmdf('/dgze /srlevent MedOff sender=%s%s', me, modeExtra)
                mq.cmdf('/srlevent MedOff sender=%s%s', me, modeExtra)
            elseif mode == 'full' then
                mq.cmdf('/dgze /srlevent MedFull sender=%s%s', me, modeExtra)
                mq.cmdf('/srlevent MedFull sender=%s%s', me, modeExtra)
            else
                print('[SRL] Usage: /srl med on|off|full [include=X] [exclude=X]')
            end

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

        elseif subcmd == 'buffon' then
            mq.cmdf('/dgze /srlevent BuffOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent BuffOn sender=%s%s', me, extra)

        elseif subcmd == 'buffoff' then
            mq.cmdf('/dgze /srlevent BuffOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent BuffOff sender=%s%s', me, extra)

        elseif subcmd == 'cureson' then
            mq.cmdf('/dgze /srlevent CuresOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent CuresOn sender=%s%s', me, extra)

        elseif subcmd == 'curesoff' then
            mq.cmdf('/dgze /srlevent CuresOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent CuresOff sender=%s%s', me, extra)

        elseif subcmd == 'lootoff' then
            mq.cmdf('/dgze /srlevent LootOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent LootOff sender=%s%s', me, extra)

        elseif subcmd == 'looton' then
            mq.cmdf('/dgze /srlevent LootOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent LootOn sender=%s%s', me, extra)

        elseif subcmd == 'epicon' then
            mq.cmdf('/dgze /srlevent EpicOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent EpicOn sender=%s%s', me, extra)

        elseif subcmd == 'epicoff' then
            mq.cmdf('/dgze /srlevent EpicOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent EpicOff sender=%s%s', me, extra)

        elseif subcmd == 'grouphealon' then
            mq.cmdf('/dgze /srlevent GroupHealOn sender=%s%s', me, extra)
            mq.cmdf('/srlevent GroupHealOn sender=%s%s', me, extra)

        elseif subcmd == 'grouphealoff' then
            mq.cmdf('/dgze /srlevent GroupHealOff sender=%s%s', me, extra)
            mq.cmdf('/srlevent GroupHealOff sender=%s%s', me, extra)

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

        -- Emergency burst heal: clerics dump their Heals.CallHeal spell(s) on
        -- the given/targeted character for a short window, ignoring normal
        -- tier/threshold logic entirely. Any target, not just tanks.
        elseif subcmd == 'healcall' then
            local target = args[1] and args[1]:gsub('_', ' ') or mq.TLO.Target.CleanName()
            if not target or target == '' then
                print('[SRL] healcall: no target specified and none selected')
                return
            end
            mq.cmdf('/dgae /srlevent HealCall name=%s sender=%s', (target:gsub(' ', '_')), me)
            mq.cmdf('/srlevent HealCall name=%s sender=%s', (target:gsub(' ', '_')), me)

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

        elseif subcmd == 'hail' then
            if not mq.TLO.Target() then return end
            local xtra = buildExtra(args, { sender=true, id=true })
            mq.cmdf('/dgae /srlevent Hail id=%s sender=%s%s',
                mq.TLO.Target.ID(), me, xtra)

        -- Config / admin
        elseif subcmd == 'respawn' then
            mq.cmdf('/dgze /srlevent Respawn sender=%s%s', me, extra)
            mq.cmdf('/srlevent Respawn sender=%s%s', me, extra)

        elseif subcmd == 'rebuff' then
            broadcast('Rebuff', extra)
            mq.cmdf('/srlevent Rebuff sender=%s', me)

        elseif subcmd == 'reload' then
            broadcast('ReloadConfig', extra)

        elseif subcmd == 'debug' then
            mq.cmd('/srlevent ToggleDebug')

        elseif subcmd == 'overlay' then
            mq.cmd('/srlevent ToggleGroupStatus')

        elseif subcmd == 'manualmode' then
            mq.cmd('/srlevent ToggleManualMode')

        elseif subcmd == 'benchhps' then
            local mode = args[1] and args[1]:lower()
            if mode == 'start' then
                mq.cmd('/srlevent BenchHpsStart')
            elseif mode == 'stop' then
                mq.cmd('/srlevent BenchHpsStop')
            else
                print('[SRL] Usage: /srl benchhps start|stop')
            end

        elseif subcmd == 'healbench' then
            local mode = args[1] and args[1]:lower()
            if mode == 'start' then
                mq.cmd('/srlevent HealBenchStart')
            elseif mode == 'stop' then
                mq.cmd('/srlevent HealBenchStop')
            else
                print('[SRL] Usage: /srl healbench start|stop')
            end

        elseif subcmd == 'config' then
            mq.cmd('/srlevent ToggleConfigEditor')

        elseif subcmd == 'charmon' then
            local npcId    = args[1]
            local enchanter = args[2]
            if not npcId or npcId == '' or not enchanter or enchanter == '' then
                print('[SRL] Usage: /srl charmon <npcId> <enchanterName>')
                return
            end
            mq.cmdf('/dgae /srlevent CharmOn id=%s include=%s sender=%s', npcId, enchanter, me)
            mq.cmdf('/srlevent CharmOn id=%s include=%s sender=%s', npcId, enchanter, me)

        elseif subcmd == 'charmoff' then
            local enchanter = args[1]
            if enchanter and enchanter ~= '' then
                mq.cmdf('/dgae /srlevent CharmOff include=%s sender=%s', enchanter, me)
                mq.cmdf('/srlevent CharmOff include=%s sender=%s', enchanter, me)
            else
                mq.cmdf('/dgae /srlevent CharmOff sender=%s', me)
                mq.cmdf('/srlevent CharmOff sender=%s', me)
            end

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

        elseif subcmd == 'automode' then
            local role = args[1] and args[1]:lower()
            if not role or role == '' then
                print(string.format('[SRL] Usage: /srl automode <puller|tank|assist>|off  (current: %s)',
                    State.flags.automode or 'off'))
                return
            end
            if role == 'off' or role == 'none' then
                State.flags.automode = nil
            elseif not VALID_AUTOMODES[role] then
                print(string.format('[SRL] Unknown automode "%s". Valid: puller, tank, assist, off', role))
                return
            elseif State.flags.automode == role then
                State.flags.automode = nil
            else
                State.flags.automode = role
            end
            print(string.format('[SRL] Automode: %s', State.flags.automode or 'OFF'))

        elseif subcmd == 'broadcastscope' then
            local scope = args[1] and args[1]:lower()
            if not scope or scope == '' then
                print(string.format('[SRL] Usage: /srl broadcastscope <group|zone|raid|all>  (current: %s)',
                    State.flags.broadcastScope or (commandBus.config and commandBus.config:get('Automode.BroadcastScope')) or 'zone'))
                return
            end
            if scope == 'default' or scope == 'reset' then
                State.flags.broadcastScope = nil
            elseif not BroadcastUtil.SCOPE_PREFIX[scope] then
                print(string.format('[SRL] Unknown broadcast scope "%s". Valid: group, zone, raid, all, default', scope))
                return
            else
                State.flags.broadcastScope = scope
            end
            print(string.format('[SRL] Automode broadcast scope: %s',
                State.flags.broadcastScope or (commandBus.config and commandBus.config:get('Automode.BroadcastScope')) or 'zone'))

        elseif subcmd == 'backgroundassist' then
            local val = args[1] and args[1]:lower()
            if not val or val == '' then
                local configVal = commandBus.config and commandBus.config:get('AssistSettings.enabled')
                local current = State.flags.backgroundAssist
                if current == nil then current = (configVal == nil) or configVal end
                print(string.format('[SRL] Usage: /srl backgroundassist <on|off|default>  (current: %s)',
                    current and 'on' or 'off'))
                return
            end
            if val == 'default' or val == 'reset' then
                State.flags.backgroundAssist = nil
            elseif val == 'on' or val == 'true' or val == '1' then
                State.flags.backgroundAssist = true
            elseif val == 'off' or val == 'false' or val == '0' then
                State.flags.backgroundAssist = false
            else
                print(string.format('[SRL] Unknown value "%s". Valid: on, off, default', val))
                return
            end
            local configVal = commandBus.config and commandBus.config:get('AssistSettings.enabled')
            local current = State.flags.backgroundAssist
            if current == nil then current = (configVal == nil) or configVal end
            print(string.format('[SRL] Background assist (auto-follow assist while not foregrounded, outside automode): %s',
                current and 'on' or 'off'))

        elseif subcmd == 'mez' then
            local val = args[1] and args[1]:lower()
            if not val or val == '' then
                local configVal = commandBus.config and commandBus.config:get('CrowdControl.Enabled')
                local current = State.flags.mezEnabled
                if current == nil then current = configVal == true end
                print(string.format('[SRL] Usage: /srl mez <on|off|default>  (current: %s)',
                    current and 'on' or 'off'))
                return
            end
            if val == 'default' or val == 'reset' then
                State.flags.mezEnabled = nil
            elseif val == 'on' or val == 'true' or val == '1' then
                State.flags.mezEnabled = true
            elseif val == 'off' or val == 'false' or val == '0' then
                State.flags.mezEnabled = false
            else
                print(string.format('[SRL] Unknown value "%s". Valid: on, off, default', val))
                return
            end
            local configVal = commandBus.config and commandBus.config:get('CrowdControl.Enabled')
            local current = State.flags.mezEnabled
            if current == nil then current = configVal == true end
            print(string.format('[SRL] Mezzing (CrowdControl): %s', current and 'on' or 'off'))

        elseif subcmd == 'clearxtar' then
            local val = args[1] and args[1]:lower()
            if not val or val == '' then
                local configVal = commandBus.config and commandBus.config:get('Automode.ClearXTarget')
                local current = State.flags.clearXTarget
                if current == nil then current = configVal == true end
                print(string.format('[SRL] Usage: /srl clearxtar <on|off|default>  (current: %s)',
                    current and 'on' or 'off'))
                return
            end
            if val == 'default' or val == 'reset' then
                State.flags.clearXTarget = nil
            elseif val == 'on' or val == 'true' or val == '1' then
                State.flags.clearXTarget = true
            elseif val == 'off' or val == 'false' or val == '0' then
                State.flags.clearXTarget = false
            else
                print(string.format('[SRL] Unknown value "%s". Valid: on, off, default', val))
                return
            end
            local configVal = commandBus.config and commandBus.config:get('Automode.ClearXTarget')
            local current = State.flags.clearXTarget
            if current == nil then current = configVal == true end
            print(string.format('[SRL] Auto chain-assist through remaining xtarget adds: %s',
                current and 'on' or 'off'))

        elseif subcmd == 'setcamp' then
            local me = mq.TLO.Me
            local x, y, z = me.X(), me.Y(), me.Z()
            State:setCamp(x, y, z)
            mq.cmdf('%s /srlevent Camp x=%.2f y=%.2f z=%.2f sender=%s', BroadcastUtil.prefix(commandBus.config), x, y, z, me.Name())
            print(string.format('[SRL] Camp set at %.1f, %.1f, %.1f (broadcast)', x, y, z))

        elseif subcmd == 'clearcamp' then
            State:clearCamp()
            mq.cmdf('%s /srlevent ClearCamp sender=%s', BroadcastUtil.prefix(commandBus.config), me)
            print('[SRL] Camp cleared (broadcast)')

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
