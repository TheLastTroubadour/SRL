local mq    = require 'mq'
local State = require 'core.State'
local Job   = require 'model.Job'
local Target = require 'service.TargetService'

local CommandRegistry = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function senderInRange(payload, config)
    if not payload.sender or payload.sender == mq.TLO.Me.Name() then return true end
    local spawn = mq.TLO.Spawn('pc =' .. payload.sender)
    if not spawn() then return false end
    local maxDist = config:get('General.DistanceSetting') or 250
    return spawn.Distance() <= maxDist
end

-- ---------------------------------------------------------------------------
-- Setup
-- rt fields used:
--   combatController, followController, followService, castService,
--   combatService, burnService, melodyService, cureDecision,
--   nukeDecision, context, ccDecision, memSwapDecision, debugState { visible }
-- ---------------------------------------------------------------------------

local function hasMana()
    local maxMana = mq.TLO.Me.MaxMana() or 0
    if maxMana == 0 then return true end  -- melee class, no mana resource
    return (mq.TLO.Me.PctMana() or 0) >= 20
end

function CommandRegistry:setup(commandBus, rt, config)

    commandBus:register('Assist', function(payload)
        rt.combatController:assist(payload)
    end)

    commandBus:register('Follow', function(payload)
        rt.followController:follow(payload)
    end)

    commandBus:register('NavFollow', function(payload)
        local sender = payload.sender
        if not sender or sender == mq.TLO.Me.Name() then return end
        local spawn = mq.TLO.Spawn('pc =' .. sender)
        if not spawn() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end
        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        mq.cmdf('/nav id %s', spawn.ID())
        State:setFollow({ id = spawn.ID(), sender = sender, mode = 'nav' })
    end)

    commandBus:register('Stop', function()
        rt.followController:stop()
        rt.castService:clearCombatQueue()
    end)

    commandBus:register('Move', function(payload)
        State:setMove(payload)
    end)

    commandBus:register('CCMaxMobs', function(payload)
        rt.ccDecision:setMaxTankedMobs(payload.n)
    end)

    commandBus:register('AddNoMez', function(payload)
        local id = tonumber(payload.id)
        if not id or id == 0 then return end
        local name = (payload.name or ''):gsub('_', ' ')
        rt.ccDecision:addImmune(id, name)
    end)

    commandBus:register('ReloadConfig', function()
        config:reload()
    end)

    commandBus:register('ToggleDebug', function()
        rt.debugState.visible = not rt.debugState.visible
    end)

    commandBus:register('ToggleGroupStatus', function()
        rt.groupStatusWindow:toggle()
    end)

    commandBus:register('ToggleConfigEditor', function()
        rt.configEditorWindow:toggle()
    end)


    commandBus:register('SetSpellSet', function(payload)
        local set = payload.set
        if not set or set == '' then return end
        State.spellSet = set
        rt.nukeDecision:reloadSet(set)
        rt.context:reloadSet(set)
        rt.combatService:reloadSet(set)
        if rt.memSwapDecision then rt.memSwapDecision:reloadSet(set) end
        print(string.format('[SRL] Spell set changed to: %s', set))
    end)

    commandBus:register('Fellowship', function(payload)
        if not senderInRange(payload, config) then return end
        local item = mq.TLO.FindItem('=Fellowship Registration Insignia')
        if item() and (item.TimerReady() or 1) == 0 then
            mq.cmdf('/useitem "Fellowship Registration Insignia"')
        end
    end)

    commandBus:register('BackOff', function()
        State:clearCombatState()
        mq.cmd('/attack off')
        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        mq.cmd('/stopcast')
        mq.cmd('/target clear')
    end)

    commandBus:register('AEOn', function(payload)
        if not senderInRange(payload, config) then return end
        State.flags.aeEnabled = true
        print('[SRL] AE enabled')
    end)

    commandBus:register('AEOff', function(payload)
        if not senderInRange(payload, config) then return end
        State.flags.aeEnabled = false
        print('[SRL] AE disabled')
    end)

    commandBus:register('CastCombatBuffs', function(payload)
        if not senderInRange(payload, config) then return end
        if not rt.buffService then return end
        rt.buffService:reset()
        rt.buffService:processCategory('combatBuffs', false)
    end)

    commandBus:register('WeaponSet', function(payload)
        local setName = payload.set
        if not setName or setName == '' then return end
        local main = mq.TLO.InvSlot(13).Item.Name() or ''
        local off  = mq.TLO.InvSlot(14).Item.Name() or ''
        config:patchCharacterYaml('SwapItems.' .. setName, { Main = main, Offhand = off })
        print(string.format('[SRL] WeaponSet "%s": Main=%s Offhand=%s',
            setName,
            main ~= '' and main or '(empty)',
            off  ~= '' and off  or '(empty)'))
    end)

    commandBus:register('SwapWeapons', function(payload)
        if not senderInRange(payload, config) then return end
        local setName = payload.set
        if not setName or setName == '' then return end
        if not rt.weaponSwapService then return end
        rt.weaponSwapService:swap(setName)
    end)

    commandBus:register('QuickBurn', function(payload)
        if not senderInRange(payload, config) then return end
        rt.burnService:activate('Burn.QuickBurn')
    end)

    commandBus:register('LongBurn', function(payload)
        if not senderInRange(payload, config) then return end
        rt.burnService:activate('Burn.LongBurn')
    end)

    commandBus:register('FullBurn', function(payload)
        if not senderInRange(payload, config) then return end
        rt.burnService:activate('Burn.FullBurn')
    end)

    commandBus:register('EpicBurn', function(payload)
        if not senderInRange(payload, config) then return end
        rt.burnService:clickEpic()
    end)

    commandBus:register('Lesson', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Lesson of the Devoted"')
    end)

    commandBus:register('Armor', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Armor of Experience"')
    end)

    commandBus:register('Staunch', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Staunch Recovery"')
    end)

    commandBus:register('Intensity', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Intensity of the Resolute"')
    end)

    commandBus:register('Expedient', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Expedient Recovery"')
    end)

    commandBus:register('Throne', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Throne of Heroes"')
    end)

    commandBus:register('Infusion', function(payload)
        if not senderInRange(payload, config) then return end
        mq.cmd('/alt activate "Infusion of the Faithful"')
    end)

    commandBus:register('PlayMelody', function(payload)
        if not payload.name then return end
        local sender = payload.sender and mq.TLO.Spawn('pc =' .. payload.sender)
        if not sender or not sender() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if sender.Distance() > maxDist then return end
        rt.melodyService:play(payload.name)
    end)

    commandBus:register('StopMelody', function()
        rt.melodyService:stop()
    end)

    local VALID_STICK_POINTS = {
        behind=true, front=true, left=true, right=true,
        behindleft=true, behindright=true, frontleft=true, frontright=true,
    }

    commandBus:register('StickPoint', function(payload)
        local point = payload.point and payload.point:lower()
        if not point or not VALID_STICK_POINTS[point] then
            print(string.format('[SRL] Invalid stickpoint "%s". Valid: behind, front, left, right, behindleft, behindright, frontleft, frontright', tostring(payload.point)))
            return
        end
        rt.combatService:setStickPoint(point)
        rt.context:setStickPoint(point)
    end)

    commandBus:register('StickDist', function(payload)
        local dist = tonumber(payload.dist)
        if not dist or dist < 1 or dist > 200 then
            print(string.format('[SRL] Invalid stickdist "%s". Must be a number between 1 and 200.', tostring(payload.dist)))
            return
        end
        rt.combatService:setStickDist(dist)
        rt.context:setStickDist(dist)
    end)

    commandBus:register('Mount', function()
        if not mq.TLO.Me.CanMount() then return end
        local mountName = config:get('Mount')
        if not mountName or mountName == '' then return end
        local buffName = config:get('MountBuff') or mountName
        if mq.TLO.Me.Buff(buffName)() then return end
        if not mq.TLO.FindItem('=' .. mountName)() then return end
        mq.cmdf('/useitem "%s"', mountName)
    end)

    commandBus:register('MedOn', function()
        State:setMedMode(true)
        rt.melodyService:stop()
        mq.cmd('/sit')
    end)

    commandBus:register('MedOff', function()
        State:setMedMode(false)
        if not (State.flags.isPuller and mq.TLO.Me.Feigning()) then
            mq.cmd('/stand')
        end
    end)

    commandBus:register('ResourceOff', function()
        State.flags.medDisabled = true
        print('[SRL] Resource regen disabled')
    end)

    commandBus:register('ResourceOn', function()
        State.flags.medDisabled = false
        print('[SRL] Resource regen enabled')
    end)

    commandBus:register('SuppressMed', function(payload)
        local seconds = tonumber(payload.seconds) or 60
        if rt.resourceDecision then
            rt.resourceDecision:suppressFor(seconds)
        end
    end)

    local inventoryCooldown = {}
    local function inventoryDedup(key)
        local now = mq.gettime()
        if inventoryCooldown[key] and now < inventoryCooldown[key] then return true end
        inventoryCooldown[key] = now + 1000
        return false
    end

    local function totalItemCount(itemName)
        local inv  = mq.TLO.FindItemCount(itemName)() or 0
        local bank = mq.TLO.FindBankItemCount(itemName)() or 0
        return inv + bank
    end

    local function findItemAnywhere(itemName)
        local item = mq.TLO.FindItem(itemName)
        if item() then return item end
        return mq.TLO.FindBankItem(itemName)
    end

    local function scanItemLocations(searchTerm)
        local lower   = searchTerm:lower()
        local totals  = {}
        local order   = {}

        local function record(name, count, location)
            if not totals[name] then
                totals[name] = { count = 0, locations = {} }
                table.insert(order, name)
            end
            totals[name].count = totals[name].count + count
            table.insert(totals[name].locations, location)
        end

        local function checkSlot(item, label)
            if not item() then return end
            local name = item.Name() or ''
            if name:lower():find(lower, 1, true) then
                record(name, item.Stack() or 1, label)
            end
            for s = 1, (item.Container() or 0) do
                local sub = item.Item(s)
                if sub() then
                    local subName = sub.Name() or ''
                    if subName:lower():find(lower, 1, true) then
                        record(subName, sub.Stack() or 1, label .. ' slot ' .. s)
                    end
                end
            end
        end

        for slot = 0,  21 do checkSlot(mq.TLO.Me.Inventory(slot), 'equip '  .. slot)        end
        for slot = 22, 31 do checkSlot(mq.TLO.Me.Inventory(slot), 'bag '    .. (slot - 21)) end
        for slot = 1,  24 do checkSlot(mq.TLO.Me.Bank(slot),      'bank '   .. slot)        end

        return totals, order
    end

    commandBus:register('FindItem', function(payload)
        local itemName = (payload.item or ''):gsub('_', ' ')
        if itemName == '' then return end
        if inventoryDedup('fi:' .. itemName:lower()) then return end
        local me = mq.TLO.Me.Name()
        local totals, order = scanItemLocations(itemName)
        if #order == 0 then return end
        local parts = {}
        for _, name in ipairs(order) do
            local t = totals[name]
            table.insert(parts, string.format('%s x%d (%s)', name, t.count, table.concat(t.locations, ', ')))
        end
        mq.cmdf('/dgt all [%s] %s', me, table.concat(parts, ' | '))
    end)

    commandBus:register('FindMissingItem', function(payload)
        local itemName = (payload.item or ''):gsub('_', ' ')
        if itemName == '' then return end
        if inventoryDedup('fmi:' .. itemName:lower()) then return end
        local me    = mq.TLO.Me.Name()
        local count = totalItemCount(itemName)
        if count == 0 then
            mq.cmdf('/dgt all [%s] missing %s', me, itemName)
            return
        end
        local item      = findItemAnywhere(itemName)
        local foundName = item() and item.Name() or itemName
        mq.cmdf('/dgt all [%s] %s x%d', me, foundName, count)
    end)

    commandBus:register('ClickItem', function(payload)
        local targetId = tonumber(payload.id)
        local itemName = (payload.item or ''):gsub('_', ' ')
        if not targetId or targetId == 0 or itemName == '' then return end

        local item = mq.TLO.FindItem('=' .. itemName)
        if not item() then return end
        if (item.TimerReady() or 1) ~= 0 then return end

        local targetSpawn = mq.TLO.Spawn('id ' .. targetId)
        if not targetSpawn() then return end

        if mq.TLO.Target.ID() ~= targetId then
            Target:getTargetById(targetId)
        end

        mq.cmdf('/useitem "%s"', itemName)

        local me = mq.TLO.Me.Name()
        local targetName = targetSpawn.CleanName() or tostring(targetId)
        local msg = string.format('%s clicking %s on %s', me, itemName, targetName)
        if (mq.TLO.Raid.Members() or 0) > 0 then
            mq.cmdf('/rsay %s', msg)
        else
            mq.cmdf('/gsay %s', msg)
        end
    end)

    commandBus:register('ClaimCure', function(payload)
        local targetId = tonumber(payload.id)
        if not targetId or targetId == 0 then return end
        rt.cureDecision:claimTarget(targetId)
    end)

    commandBus:register('DebuffImmune', function()
        if rt.debuffDecision then rt.debuffDecision:markLastCastImmune() end
    end)

    commandBus:register('AddNoSlow', function(payload)
        local id = tonumber(payload.id)
        local name = (payload.name or ''):gsub('_', ' ')
        if not id or id == 0 then return end
        if rt.debuffDecision then rt.debuffDecision:addNoSlow(id, name) end
    end)

    commandBus:register('ClaimRez', function(payload)
        local corpseId = tonumber(payload.id)
        if not corpseId or corpseId == 0 then return end
        if rt.rezDecision then rt.rezDecision:claimCorpse(corpseId) end
    end)

    commandBus:register('RezTarget', function(payload)
        local corpseId   = tonumber(payload.id)
        local corpseName = (payload.name or ''):gsub('_', ' ')
        if not corpseId or corpseId == 0 then return end
        if rt.rezDecision then rt.rezDecision:queueManualRez(corpseId, corpseName) end
    end)

    commandBus:register('ClaimAbility', function(payload)
        if not rt.abilityDecision then return end
        local targetId = tonumber(payload.targetId)
        local durationMs = tonumber(payload.duration)
        if not targetId or targetId == 0 then return end
        if not durationMs or durationMs <= 0 then return end
        local name = (payload.name or ''):gsub('_', ' ')
        if name == '' then return end
        rt.abilityDecision:addClaim(name, targetId, durationMs)
    end)

    commandBus:register('NeedCure', function(payload)
        local targetId = tonumber(payload.id)
        if not targetId or targetId == 0 then return end
        if not mq.TLO.Spawn('id ' .. targetId)() then return end
        rt.cureDecision:addRequest(payload.id, payload.name, payload.types, payload.buff)
    end)

    commandBus:register('MoveToTarget', function(payload)
        local targetId = tonumber(payload.id)
        if not targetId or targetId == 0 then return end
        if not mq.TLO.Spawn('id ' .. targetId)() then return end
        mq.cmd('/stick off')
        mq.cmd('/nav stop')
        mq.cmdf('/nav id %s', targetId)
    end)

    commandBus:register('Status', function(payload)
        local me = mq.TLO.Me.Name()
        local aa = mq.TLO.Me.AAPoints() or 0
        local threshold = payload.threshold and tonumber(payload.threshold)
        if threshold and aa < threshold then return end
        mq.cmdf('/dgt all [%s] Unspent AAs: %d', me, aa)
    end)

    commandBus:register('TellSpell', function(payload)
        local targetName = payload.trigger and payload.target
        local trigger    = payload.trigger
        if not targetName or not trigger then return end

        -- Only the bot that received the tell sends the acknowledgment
        if payload.sender == mq.TLO.Me.Name() then
            if not hasMana() then
                mq.cmdf('/tell %s Not enough mana, try again later.', targetName)
                return
            end
            mq.cmdf('/dgt all [SRL] Casting %s on %s', trigger, targetName)
            mq.cmdf('/tell %s %s incoming!', targetName, trigger)
        end

        -- Resolve trigger → spell name(s) from global aliases (case-insensitive key match)
        local aliases = config:get('GroupBuffs.Aliases') or {}
        local resolved = nil
        local lowerTrigger = trigger:lower()
        for k, v in pairs(aliases) do
            if k:lower() == lowerTrigger then resolved = v; break end
        end
        if not resolved then return end
        if type(resolved) == 'string' then resolved = { resolved } end

        local mySpells = config:get('Buffs.GroupBuff') or {}
        if #mySpells == 0 then return end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end

        -- Cast the first alias spell this bot has configured
        for _, spellName in ipairs(resolved) do
            for _, entry in ipairs(mySpells) do
                if entry.spell == spellName then
                    local job = Job:new(spawn.ID(), targetName, entry.spell,
                        entry.type or 'spell', 0, entry.gem or 8)
                    job.force = true
                    rt.castService:enqueue(job)
                    break
                end
            end
        end
    end)

    commandBus:register('TellTL', function(payload)
        local targetName = payload.target
        if not targetName or targetName == '' then return end

        if not hasMana() then
            if payload.sender == mq.TLO.Me.Name() then
                mq.cmdf('/tell %s Not enough mana, try again later.', targetName)
            end
            return
        end

        if payload.sender == mq.TLO.Me.Name() then
            mq.cmdf('/dgt all [SRL] Translocating %s', targetName)
            mq.cmdf('/tell %s Translocate incoming!', targetName)
        end

        if not config:get('Translocate.Enabled') then return end

        local spellName = config:get('Translocate.Spell')
        local gem       = config:get('Translocate.Gem') or 8
        if not spellName then return end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end

        local job = Job:new(spawn.ID(), targetName, spellName, 'spell', 0, gem)
        rt.castService:enqueue(job)
    end)

    commandBus:register('TellPort', function(payload)
        local targetName = payload.target
        local dest       = (payload.dest or ''):gsub('_', ' '):lower()
        local portType   = payload.type or 'tl'   -- 'tl' or 'portal'
        if not targetName or targetName == '' or dest == '' then return end

        if not config:get('Port.Enabled') then return end

        local aliasSection = portType == 'portal' and 'Port.Wizard.Portal' or 'Port.Wizard.TL'
        local aliases      = config:get(aliasSection) or {}
        local spellName    = nil
        for k, v in pairs(aliases) do
            if k:lower() == dest then spellName = v; break end
        end

        if not spellName then
            if payload.sender == mq.TLO.Me.Name() then
                mq.cmdf('/tell %s Unknown destination: %s', targetName, dest)
            end
            return
        end

        if not hasMana() then
            if payload.sender == mq.TLO.Me.Name() then
                mq.cmdf('/tell %s Not enough mana, try again later.', targetName)
            end
            return
        end

        local action = portType == 'portal' and 'Portaling' or 'TLing'
        local label  = portType == 'portal' and 'Portal' or 'TL'
        if payload.sender == mq.TLO.Me.Name() then
            mq.cmdf('/dgt all [SRL] %s %s to %s', action, targetName, dest)
            mq.cmdf('/tell %s %s to %s incoming!', targetName, label, dest)
        end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end

        local gem = config:get('Port.Gem') or 8
        local job = Job:new(spawn.ID(), targetName, spellName, 'spell', 0, gem)
        rt.castService:enqueue(job)
    end)

    commandBus:register('BuffMe', function(payload)
        local targetName = payload.sender
        if not targetName or targetName == '' then return end
        if targetName == mq.TLO.Me.Name() then return end

        local spells = config:get('Buffs.GroupBuff')
        if not spells or #spells == 0 then return end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end
        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end

        local targetId = spawn.ID()
        for _, entry in ipairs(spells) do
            if entry.spell then
                local job = Job:new(targetId, targetName, entry.spell,
                    entry.type or 'spell', 0, entry.gem or 8)
                rt.castService:enqueue(job)
            end
        end
    end)

    local tellBuffAnnounceCooldown = {}
    commandBus:register('TellBuff', function(payload)
        local targetName = payload.target
        if not targetName or targetName == '' then return end

        if not hasMana() then
            if payload.sender == mq.TLO.Me.Name() then
                mq.cmdf('/tell %s Not enough mana, try again later.', targetName)
            end
            return
        end

        -- Dedup: /dgae sends to self so this handler fires twice on the originating bot
        if payload.sender == mq.TLO.Me.Name() then
            local now = mq.gettime()
            local key = 'tellbuff:' .. targetName:lower()
            if tellBuffAnnounceCooldown[key] and now < tellBuffAnnounceCooldown[key] then
                -- skip announcement, but still enqueue buffs below
            else
                tellBuffAnnounceCooldown[key] = now + 3000
                mq.cmdf('/dgt all [SRL] Buffing %s', targetName)
                mq.cmdf('/tell %s Buffs incoming!', targetName)
            end
        end

        local spells = config:get('Buffs.GroupBuff')
        if not spells or #spells == 0 then return end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end

        local maxDist = config:get('General.DistanceSetting') or 250
        if spawn.Distance() > maxDist then return end

        local targetId = spawn.ID()
        for _, entry in ipairs(spells) do
            if entry.spell then
                local job = Job:new(targetId, targetName, entry.spell,
                    entry.type or 'buff', 0, entry.gem or 8)
                job.force = true
                rt.castService:enqueue(job)
            end
        end
    end)

    commandBus:register('TurnIn', function(payload)
        local npcId   = tonumber(payload.id)
        local itemName = (payload.item or ''):gsub('_', ' ')
        local amount   = payload.amount and tonumber(payload.amount)
        if not npcId or npcId == 0 or itemName == '' then return end

        rt.castService.scheduler:spawn(function()
            -- Stagger bots so they don't all open trade windows simultaneously
            mq.delay(math.random(500, 5000))

            -- Verify NPC still exists
            if not mq.TLO.Spawn('id ' .. npcId)() then return end

            -- Find the item in inventory (slots 22-31 = pack1-10, skip gear slots 0-21)
            local foundBag, foundSlot = nil, nil
            for bag = 22, 31 do
                local inv = mq.TLO.Me.Inventory(bag)
                if inv() then
                    local name = inv.Name() or ''
                    if name:lower():find(itemName:lower(), 1, true) then
                        local count = inv.Stack() or 1
                        if not amount or count == amount then
                            foundBag, foundSlot = bag, -1
                            break
                        end
                    end
                    local containerSize = inv.Container() or 0
                    if containerSize > 0 then
                        for s = 1, containerSize do
                            local sub = inv.Item(s)
                            if sub() then
                                local subName = sub.Name() or ''
                                if subName:lower():find(itemName:lower(), 1, true) then
                                    local count = sub.Stack() or 1
                                    if not amount or count == amount then
                                        foundBag, foundSlot = bag, s
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if foundBag then break end
            end

            if not foundBag then return end

            -- Target the NPC
            Target:getTargetById(npcId)
            if mq.TLO.Target.ID() ~= npcId then return end

            -- Pick up the item onto cursor (bag slots 22-31 = pack1-10)
            if foundSlot == -1 then
                mq.cmdf('/itemnotify pack%s leftmouseup', foundBag - 21)
            else
                mq.cmdf('/itemnotify pack%s %s leftmouseup', foundBag - 21, foundSlot)
            end
            mq.delay(200)

            -- Give item directly to NPC
            mq.cmd('/click left target')
        end)
    end)

    commandBus:register('SayPhrase', function(payload)
        local targetId = tonumber(payload.id)
        local msg = (payload.msg or ''):gsub('_', ' ')
        if not targetId or targetId == 0 or msg == '' then return end
        if not mq.TLO.Spawn('id ' .. targetId)() then return end

        rt.castService.scheduler:spawn(function()
            -- Stagger: each bot waits a random interval so they don't all say at once
            mq.delay(math.random(500, 20000))

            if mq.TLO.Target.ID() ~= targetId then
                Target:getTargetById(targetId)
            end

            -- Substitute %t with the target's name
            local targetName = mq.TLO.Target.CleanName() or ''
            local resolved = msg:gsub('%%t', targetName)
            mq.cmdf('/say %s', resolved)
        end)
    end)

    commandBus:register('AEOn', function()
        State.flags.aeEnabled = true
        print('[SRL] AE: enabled')
    end)

    commandBus:register('AEOff', function()
        State.flags.aeEnabled = false
        print('[SRL] AE: disabled')
    end)

    commandBus:register('BuffIt', function(payload)
        local targetName = (payload.name or ''):gsub('_', ' ')
        if targetName == '' then return end

        local spells = config:get('Buffs.GroupBuff')
        if not spells or #spells == 0 then return end

        local spawn = mq.TLO.Spawn('pc =' .. targetName)
        if not spawn() then return end
        local tid = spawn.ID()

        -- Target them to read buff status locally
        if mq.TLO.Target.ID() ~= tid then
            Target:getTargetById(tid)
        end
        if mq.TLO.Target.ID() ~= tid then return end

        for _, entry in ipairs(spells) do
            if entry.spell then
                local buffName = entry.spell
                if (entry.type or 'spell') == 'item' then
                    local clickySpell = mq.TLO.FindItem('=' .. entry.spell).Clicky.Spell.Name()
                    if clickySpell then buffName = clickySpell end
                end

                local buff = mq.TLO.Target.Buff(buffName)
                if not buff() then
                    local job = Job:new(tid, targetName, entry.spell, entry.type or 'spell', 0, entry.gem or 8)
                    job.buffName = buffName
                    job.category = 'groupBuff'
                    job.key      = entry.spell .. ':' .. tostring(tid)
                    rt.castService:enqueue(job)
                end
            end
        end
    end)

    commandBus:register('DebuffOn', function(payload)
        local id = tonumber(payload.id)
        if not id or id == 0 then return end
        State.flags.commandDebuffTargetId = id
        print(string.format('[SRL] Command debuff: targeting id=%d', id))
    end)

    commandBus:register('DebuffOff', function()
        State.flags.commandDebuffTargetId = nil
        print('[SRL] Command debuff: cleared')
    end)

    commandBus:register('DotOn', function(payload)
        local id = tonumber(payload.id)
        if not id or id == 0 then return end
        State.flags.commandDotTargetId = id
        print(string.format('[SRL] Command dot: targeting id=%d', id))
    end)

    commandBus:register('DotOff', function()
        State.flags.commandDotTargetId = nil
        print('[SRL] Command dot: cleared')
    end)

    commandBus:register('COMBAT_ENDED', function()
        State:clearCombatState()
        rt.castService:interruptCasting()
        rt.followService:resumeFollow()

        mq.cmd('/attack off')
    end)
end

return CommandRegistry
