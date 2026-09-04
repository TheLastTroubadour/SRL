local State = require 'core.State'

local BroadcastUtil = {}

-- Automode.BroadcastScope controls how far automode's own broadcasts travel
-- (assist calls, med break, camp). DanNet's bare scope commands (/dgg, /dgr)
-- loop the message back to the sender's own client; the +e variants (/dgge,
-- /dgze, /dgre, /dgae) exclude the sender. Every call site that uses these
-- already fires a second, explicit local /srlevent for the sender's own copy
-- (see AssistUtil.broadcastAssist's comment), so this always resolves to the
-- exclude-sender variant to match that existing pattern -- group just wasn't
-- configurable before, it was hardcoded to zone everywhere.
-- "all" (/dgae) is every DanNet-connected peer regardless of raid membership
-- or zone -- broader than raid, for automode actions that need to reach bots
-- outside the raid entirely.
local SCOPE_PREFIX = {
    group = '/dgge',
    zone  = '/dgze',
    raid  = '/dgre',
    all   = '/dgae',
}
BroadcastUtil.SCOPE_PREFIX = SCOPE_PREFIX

-- In-memory override (set via /srl broadcastscope <value>) always wins over
-- config -- same precedence as automode itself, a per-bot runtime setting.
function BroadcastUtil.prefix(config)
    local scope = State.flags.broadcastScope
        or (config and config:get('Automode.BroadcastScope'))
        or 'zone'
    scope = tostring(scope):lower()
    return SCOPE_PREFIX[scope] or SCOPE_PREFIX.zone
end

return BroadcastUtil
