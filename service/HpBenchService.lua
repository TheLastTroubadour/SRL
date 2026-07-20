local mq    = require 'mq'
local LFS   = require 'lfs'
local State = require 'core.State'

-- Diagnostic tool: compares mq.TLO.Raid.Member().PctHPs() (raid frame data)
-- against the live mq.TLO.Spawn().PctHPs() for the same person, to measure
-- how stale raid-frame HP actually is for out-of-group raid members.
-- Not wired into the decision engine — armed/disarmed manually via
-- /srl benchhps start|stop and only samples while the raid is fighting
-- (personal combat flag, aggressive XTarget, or an active assist target).

local HpBenchService = {}
HpBenchService.__index = HpBenchService

local function ensureDir(path)
    local current = ''
    for segment in path:gmatch('[^\\]+') do
        current = current == '' and segment or (current .. '\\' .. segment)
        if not LFS.attributes(current) then
            LFS.mkdir(current)
        end
    end
end

function HpBenchService:new()
    local self = setmetatable({}, HpBenchService)
    self.active       = false
    self.file         = nil
    self.path         = nil
    self.last         = {}
    self.stats        = {}
    self.spawnIdCache = {}
    return self
end

function HpBenchService:start()
    if self.active then
        print('[SRL] benchhps: already running')
        return
    end
    self.active       = true
    self.last         = {}
    self.stats        = {}
    self.spawnIdCache = {}
    self.file         = nil -- lazy-opened on first sample
    self.lastDebugPrint = nil
    print('[SRL] benchhps: started (samples only while in combat)')
end

function HpBenchService:openFile()
    local dir = mq.configDir .. '\\srl\\logs\\'
    ensureDir(dir)
    local path = dir .. 'hpbench_' .. mq.TLO.Me.Name() .. '_' .. os.date('%Y%m%d_%H%M%S') .. '.csv'
    local f = io.open(path, 'w')
    if not f then
        print('[SRL] benchhps: failed to open ' .. path)
        return
    end
    f:write('time,name,raidHP,spawnHP,delta,tickMs\n')
    self.file = f
    self.path = path
end

function HpBenchService:writeRow(name, raidHP, spawnHP, delta, now)
    if not self.file then
        self:openFile()
    end
    if not self.file then return end
    self.file:write(string.format('%s,%s,%d,%d,%d,%s\n',
        os.date('%H:%M:%S'), name, raidHP, spawnHP, delta, tostring(now)))
    self.file:flush()
end

function HpBenchService:recordSample(name, raidHP, spawnHP, now)
    local last         = self.last[name]
    local raidChanged  = not last or last.raidHP  ~= raidHP
    local spawnChanged = not last or last.spawnHP ~= spawnHP

    if not raidChanged and not spawnChanged then return end

    local stat = self.stats[name]
    if not stat then
        stat = { maxDelta = 0, deltaSum = 0, deltaCount = 0, staleSum = 0, staleCount = 0 }
        self.stats[name] = stat
    end

    local delta = math.abs(raidHP - spawnHP)
    stat.deltaSum   = stat.deltaSum + delta
    stat.deltaCount = stat.deltaCount + 1
    if delta > stat.maxDelta then stat.maxDelta = delta end

    -- Staleness: when spawnHP moves to a new value, stamp it; when raidHP
    -- later catches up to that same value, the gap is the raid-frame lag.
    if spawnChanged then
        stat.pendingSpawnHP = spawnHP
        stat.pendingSpawnAt = now
    end
    if raidChanged and stat.pendingSpawnHP ~= nil and raidHP == stat.pendingSpawnHP then
        stat.staleSum   = stat.staleSum + (now - stat.pendingSpawnAt)
        stat.staleCount = stat.staleCount + 1
        stat.pendingSpawnHP = nil
    end

    self.last[name] = { raidHP = raidHP, spawnHP = spawnHP }

    self:writeRow(name, raidHP, spawnHP, delta, now)
end

function HpBenchService:debugPrint(fmt, ...)
    print('[SRL] benchhps DEBUG: ' .. string.format(fmt, ...))
end

function HpBenchService:tick(ctx)
    if not self.active then return end

    local now = mq.gettime()
    -- Throttle debug output to once every 2s so it doesn't flood chat
    local verbose = (not self.lastDebugPrint) or (now - self.lastDebugPrint >= 2000)
    if verbose then self.lastDebugPrint = now end

    -- ctx.inCombat (Me.Combat()) is personal to this character — a backline
    -- healer drops out of it between casts even mid-fight. State.assist.targetId
    -- is raid-wide (set by /srl assiston, broadcast to everyone) and stays set
    -- for the whole pull, so it's a much better "is the raid fighting" signal.
    local fighting = ctx.inCombat
        or (ctx.numberOfAggresiveInXTar and ctx.numberOfAggresiveInXTar > 0)
        or (State.assist.targetId ~= nil)

    if not fighting then
        if verbose then self:debugPrint('not fighting (inCombat=false, no aggro xtar, no assist target), skipping') end
        return
    end

    local raidCount = mq.TLO.Raid.Members() or 0
    if raidCount == 0 then
        if verbose then self:debugPrint('inCombat=true but Raid.Members()=0, skipping') end
        return
    end

    if verbose then self:debugPrint('inCombat=true, raidCount=%d, scanning...', raidCount) end

    for i = 1, raidCount do
        local r = mq.TLO.Raid.Member(i)

        if not r() then
            if verbose then self:debugPrint('  [%d] Raid.Member(%d) did not resolve', i, i) end
            goto continue
        end

        if r.Dead() then
            if verbose then self:debugPrint('  [%d] %s is dead, skipping', i, tostring(r.CleanName())) end
            goto continue
        end

        local name = r.CleanName()
        if not name then
            if verbose then self:debugPrint('  [%d] CleanName() returned nil', i) end
            goto continue
        end

        local raidHP = r.PctHPs()
        if not raidHP then
            if verbose then self:debugPrint('  [%d] %s raidHP=nil (r.PctHPs() unresolved)', i, name) end
            goto continue
        end

        local id = self.spawnIdCache[name]
        local spawn = id and mq.TLO.Spawn('id ' .. id)
        if not (spawn and spawn()) then
            spawn = mq.TLO.Spawn('pc =' .. name)
            if spawn() then self.spawnIdCache[name] = spawn.ID() end
        end

        if not (spawn and spawn()) then
            if verbose then self:debugPrint('  [%d] %s spawn did not resolve (raidHP=%d)', i, name, raidHP) end
            goto continue
        end

        if spawn.Dead() then
            if verbose then self:debugPrint('  [%d] %s spawn is dead', i, name) end
            goto continue
        end

        local spawnHP = spawn.PctHPs()
        if verbose then
            self:debugPrint('  [%d] %s raidHP=%s spawnHP=%s', i, name, tostring(raidHP), tostring(spawnHP))
        end

        self:recordSample(name, raidHP, spawnHP, now)

        ::continue::
    end
end

function HpBenchService:stop()
    if not self.active then
        print('[SRL] benchhps: not running')
        return
    end
    self.active = false

    print('[SRL] === benchhps summary ===')
    local any = false
    for name, stat in pairs(self.stats) do
        any = true
        local avgDelta = stat.deltaCount > 0 and (stat.deltaSum / stat.deltaCount) or 0
        if stat.staleCount > 0 then
            local avgStale = stat.staleSum / stat.staleCount / 1000
            print(string.format('[SRL]   %-16s maxDelta=%d%%  avgDelta=%.1f%%  avgStaleness=%.2fs (n=%d)',
                name, stat.maxDelta, avgDelta, avgStale, stat.staleCount))
        else
            print(string.format('[SRL]   %-16s maxDelta=%d%%  avgDelta=%.1f%%  avgStaleness=n/a',
                name, stat.maxDelta, avgDelta))
        end
    end
    if not any then
        print('[SRL]   no samples recorded')
    end

    if self.file then
        self.file:close()
        print('[SRL] benchhps: log saved to ' .. self.path)
        self.file = nil
    end
end

return HpBenchService