local mq    = require 'mq'
local LFS   = require 'lfs'
local State = require 'core.State'

-- Diagnostic tool: measures how responsive the heal pipeline actually is,
-- tying together the groupHealLock fix and the emergency-interrupt fix.
-- Primary signal is single-target "hurt -> visibly healed" latency; group
-- heal firings and emergency interrupts are logged too as secondary context.
-- Armed/disarmed manually via /srl healbench start|stop, samples only while
-- the raid is fighting (same signal as HpBenchService).
--
-- Latency is measured as a black box: time from crossing this healer's own
-- configured threshold for that person's role (tank/normal/top-off, whatever
-- actually applies) to HP ticking back up by UPTICK_THRESHOLD — not time
-- until HealDecision *decides* to target them. Decision-making reacts within
-- one ~50ms tick by construction, so watching HealDecision.job would always
-- read ~0 and say nothing about the real bottleneck (queue contention,
-- cast time, interrupts) that the fixes above actually target.

local HealBenchService = {}
HealBenchService.__index = HealBenchService

local DEFAULT_THRESHOLD = 50 -- fallback only if a role has no configured heal at all
local UPTICK_THRESHOLD  = 5  -- hp% rise that counts as "visibly healed"

local function ensureDir(path)
    local current = ''
    for segment in path:gmatch('[^\\]+') do
        current = current == '' and segment or (current .. '\\' .. segment)
        if not LFS.attributes(current) then
            LFS.mkdir(current)
        end
    end
end

function HealBenchService:new(healDecision, castService)
    local self = setmetatable({}, HealBenchService)
    self.healDecision = healDecision
    self.castService  = castService
    self.active        = false
    self.file           = nil
    self.path           = nil
    self.hurtSince       = {} -- name -> timestamp episode started
    self.hurtHpAtStart   = {} -- name -> hp% when episode started
    self.recorded        = {} -- name -> already logged a latency for this episode
    self.latencyStats    = {} -- per name: { count, sum, max }
    self.groupHealCount  = 0
    self.interruptCount  = 0
    self.lastGroupHealPending = false
    self.lastInterruptSeen    = 0
    self.thresholds           = {}
    self.primed               = false
    return self
end

function HealBenchService:start()
    if self.active then
        print('[SRL] healbench: already running')
        return
    end
    self.active               = true
    self.file                 = nil -- lazy-opened on first row
    self.hurtSince             = {}
    self.hurtHpAtStart         = {}
    self.recorded              = {}
    self.primed                = false
    self.latencyStats          = {}
    self.groupHealCount        = 0
    self.interruptCount        = 0
    self.lastGroupHealPending  = self.healDecision.groupHealPending or false
    self.lastInterruptSeen     = self.castService.lastInterruptAt or 0
    self.lastDebugPrint        = nil
    self.thresholds            = self:buildThresholds()
    print('[SRL] healbench: started (samples only while fighting)')
end

-- Per role, the highest configured combat-heal threshold for that role —
-- i.e. the HP% at which this healer's own system first considers the person
-- heal-eligible during a fight. Same source data HealDecision itself reads,
-- so "hurt" here means what it actually means to the live decision logic,
-- not an arbitrary flat number.
--
-- Heals.TopOff is deliberately excluded: HealDecision only fires it when
-- ctx.numberOfAggresiveInXTar == 0 (i.e. out of combat), and this benchmark
-- only samples while fighting — a condition under which TopOff can never
-- actually trigger. Folding its (usually very high, e.g. 90%+) threshold in
-- here would start the "hurt" clock long before the real combat heal logic
-- considers the person eligible, inflating latency with time that has
-- nothing to do with heal responsiveness.
function HealBenchService:buildThresholds()
    local config = self.healDecision.config
    local spells = (config and config:get('Heals.Spells')) or {}
    local thresholds = {}

    for role, roleSpells in pairs(spells) do
        local maxT = 0
        for _, s in ipairs(roleSpells) do
            if type(s.threshold) == 'number' and s.threshold > maxT then
                maxT = s.threshold
            end
        end
        if maxT > 0 then thresholds[role] = maxT end
    end

    return thresholds
end

function HealBenchService:thresholdFor(role)
    return self.thresholds[role] or self.thresholds.normal or DEFAULT_THRESHOLD
end

function HealBenchService:openFile()
    local dir = mq.configDir .. '\\srl\\logs\\'
    ensureDir(dir)
    local path = dir .. 'healbench_' .. mq.TLO.Me.Name() .. '_' .. os.date('%Y%m%d_%H%M%S') .. '.csv'
    local f = io.open(path, 'w')
    if not f then
        print('[SRL] healbench: failed to open ' .. path)
        return
    end
    f:write('time,type,name,hp,latencyMs\n')
    self.file = f
    self.path = path
end

function HealBenchService:writeRow(eventType, name, hp, latencyMs)
    if not self.file then
        self:openFile()
    end
    if not self.file then return end
    self.file:write(string.format('%s,%s,%s,%s,%s\n',
        os.date('%H:%M:%S'), eventType, name or '',
        hp and tostring(hp) or '', latencyMs and tostring(latencyMs) or ''))
    self.file:flush()
end

function HealBenchService:recordLatency(name, latencyMs, now)
    local stat = self.latencyStats[name]
    if not stat then
        stat = { count = 0, sum = 0, max = 0 }
        self.latencyStats[name] = stat
    end
    stat.count = stat.count + 1
    stat.sum   = stat.sum + latencyMs
    if latencyMs > stat.max then stat.max = latencyMs end
    self:writeRow('HEAL', name, nil, latencyMs)
end

function HealBenchService:averageHp(targets)
    local total, n = 0, 0
    for _, t in ipairs(targets) do
        if t.hp then total = total + t.hp; n = n + 1 end
    end
    return n > 0 and (total / n) or 0
end

function HealBenchService:worstMember(targets)
    local worst = nil
    for _, t in ipairs(targets) do
        if t.hp and (not worst or t.hp < worst.hp) then worst = t end
    end
    return worst
end

function HealBenchService:debugPrint(fmt, ...)
    print('[SRL] healbench DEBUG: ' .. string.format(fmt, ...))
end

function HealBenchService:tick(ctx)
    if not self.active then return end

    local now = mq.gettime()
    local verbose = (not self.lastDebugPrint) or (now - self.lastDebugPrint >= 2000)
    if verbose then self.lastDebugPrint = now end

    local fighting = ctx.inCombat
        or (ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0)
        or (State.assist.targetId ~= nil)
    if not fighting then
        if verbose then self:debugPrint('not fighting, skipping') end
        return
    end

    if not ctx.roles or not ctx.roles['healer'] then
        if verbose then self:debugPrint('ctx.roles.healer is false/nil, skipping') end
        return
    end

    local targets = ctx.self.heal and ctx.self.heal.group and ctx.self.heal.group.memberStatus
    if not targets then
        if verbose then
            self:debugPrint('ctx.self.heal.group.memberStatus is nil (self.heal=%s, self.heal.group=%s)',
                tostring(ctx.self.heal), tostring(ctx.self.heal and ctx.self.heal.group))
        end
        return
    end

    if verbose then
        local parts = {}
        for _, t in ipairs(targets) do
            table.insert(parts, string.format('%s=%s%%', t.name, tostring(t.hp)))
        end
        self:debugPrint('fighting, %d targets: %s', #targets, table.concat(parts, ' '))
    end

    -- True only for this very first tick after start() — used below to avoid
    -- treating "already hurt when we started tracking" as a fresh episode,
    -- which would count time before start() as part of the latency.
    local isFirstTick = not self.primed
    self.primed = true

    -- Single-target: hurt -> visibly healed latency (primary signal).
    -- "Hurt" is this person's own configured heal threshold for their role,
    -- not a flat number, so tank/normal/top-off heals are all covered at
    -- their real trigger points.
    for _, t in ipairs(targets) do
        if t.hp then
            local threshold = self:thresholdFor(t.role)
            if t.hp < threshold then
                if not self.hurtSince[t.name] then
                    -- New hurt episode: arm the clock and record the baseline HP.
                    -- If already hurt on the first tick, we don't know their true
                    -- onset time — pre-mark as recorded so this contaminated
                    -- episode is tracked (for reset purposes) but never logged.
                    self.hurtSince[t.name]     = now
                    self.hurtHpAtStart[t.name] = t.hp
                    self.recorded[t.name]      = isFirstTick
                elseif not self.recorded[t.name]
                    and t.hp >= self.hurtHpAtStart[t.name] + UPTICK_THRESHOLD then
                    -- Still below threshold overall, but HP just visibly climbed —
                    -- that's a heal landing. Record once per episode, don't re-fire
                    -- on every subsequent tick of the same episode.
                    local latency = now - self.hurtSince[t.name]
                    self:recordLatency(t.name, latency, now)
                    self.recorded[t.name] = true
                end
            else
                -- Back to safe. If HP jumped straight back over threshold
                -- without ever climbing a full UPTICK_THRESHOLD while still under
                -- it (e.g. dipped to 49% then went straight to 55%), the uptick
                -- branch above never had a chance to fire — this recovery is
                -- itself the "visibly healed" signal, so record it here instead.
                if self.hurtSince[t.name] and not self.recorded[t.name] then
                    local latency = now - self.hurtSince[t.name]
                    self:recordLatency(t.name, latency, now)
                end
                self.hurtSince[t.name]     = nil
                self.hurtHpAtStart[t.name] = nil
                self.recorded[t.name]      = nil
            end
        end
    end

    -- Group-wide: log every time a group heal actually fires
    local groupHealPending = self.healDecision.groupHealPending or false
    if groupHealPending and not self.lastGroupHealPending then
        self.groupHealCount = self.groupHealCount + 1
        self:writeRow('GROUPHEAL', nil, self:averageHp(targets), nil)
    end
    self.lastGroupHealPending = groupHealPending

    -- Emergency interrupts: watch CastService's own timestamp for changes
    local interruptAt = self.castService.lastInterruptAt or 0
    if interruptAt ~= self.lastInterruptSeen then
        self.lastInterruptSeen = interruptAt
        self.interruptCount = self.interruptCount + 1
        local worst = self:worstMember(targets)
        self:writeRow('INTERRUPT', worst and worst.name, worst and worst.hp, nil)
    end
end

function HealBenchService:stop()
    if not self.active then
        print('[SRL] healbench: not running')
        return
    end
    self.active = false

    print('[SRL] === healbench summary ===')
    print(string.format('[SRL]   group heals fired: %d   emergency interrupts: %d',
        self.groupHealCount, self.interruptCount))

    local any = false
    for name, stat in pairs(self.latencyStats) do
        any = true
        local avg = stat.sum / stat.count / 1000
        print(string.format('[SRL]   %-16s heals=%d  avgLatency=%.2fs  maxLatency=%.2fs',
            name, stat.count, avg, stat.max / 1000))
    end
    if not any then
        print('[SRL]   no single-target heal latency samples recorded')
    end

    if self.file then
        self.file:close()
        print('[SRL] healbench: log saved to ' .. self.path)
        self.file = nil
    end
end

return HealBenchService
