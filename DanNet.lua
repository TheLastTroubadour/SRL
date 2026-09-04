local mq = require 'mq'
local dannet_export = {}

-- Escapes '${' to '$\{' before it goes into a /dquery or /dobserve command
-- string -- otherwise MQ's own command-line parser evaluates ${Me.PctHPs}
-- locally (to whatever it means for the character issuing the command)
-- before the plugin ever sees it, registering the observer/query under a
-- garbage literal-value key instead of the template. The plugin's own
-- trim_query() undoes this exact escaping server-side (regex '\$\{' -> '${'),
-- confirming this is the expected wire format. Reading an already-registered
-- observer (read_observer, via the TLO directly, not a command string) isn't
-- subject to this and stays unescaped.
local function escape_query(query)
    return (query:gsub('%$%{', '$\\{'))
end

function dannet_export.query(peer, query, timeout)
    mq.cmdf('/dquery %s -q "%s"', peer, escape_query(query))
    if timeout > 0 then
        mq.delay(25)
        mq.delay(timeout or 1000, function() return (mq.TLO.DanNet(peer).Q(query).Received() or 0) > 0 end)
    end
    local value = mq.TLO.DanNet(peer).Q(query)()
    --Logger.log_verbose('\ayQuerying - mq.TLO.DanNet(%s).Q(%s) = %s', peer, query, value)
    return value
end

function dannet_export.read_observer(peer, query, timeout)
    local value = mq.TLO.DanNet(peer).O(query)()
    return value
end

function dannet_export.create_observer(peer, query, timeout)
    -- can_read() (plugin-side) only checks whether a subscription entry
    -- exists at all, not whether it's still receiving fresh pushes -- so a
    -- plain /dobserve on top of an already-registered (even dead/stale) entry
    -- is a silent no-op, the plugin never re-sends the whisper. -d explicitly
    -- drops any existing entry first so the follow-up /dobserve actually
    -- registers a fresh subscription instead of doing nothing.
    mq.cmdf('/dobserve %s -q %s -d', peer, escape_query(query))
    mq.cmdf('/dobserve %s -q %s', peer, escape_query(query))
    if timeout > 0 then
        mq.delay(25)
        mq.delay(timeout or 1000, function() return (mq.TLO.DanNet(peer).Q(query).Received() or 0) > 0 end)
    end
    local value = mq.TLO.DanNet(peer).O(query)()
    return value
end

return dannet_export