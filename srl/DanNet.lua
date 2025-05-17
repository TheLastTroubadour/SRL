local dannet_export = {}

function dannet_export.query(peer, query, timeout)
    mq.cmdf('/dquery %s -q "%s"', peer, query)
    if timeout > 0 then
        mq.delay(25)
        mq.delay(timeout or 1000, function() return (mq.TLO.DanNet(peer).Q(query).Received() or 0) > 0 end)
    end
    local value = mq.TLO.DanNet(peer).Q(query)()
    --Logger.log_verbose('\ayQuerying - mq.TLO.DanNet(%s).Q(%s) = %s', peer, query, value)
    return value
end

return dannet_export