local Engine = {}

function Engine:evaluate(ctx)

    local best = nil
    local bestScore = 0

    for _, action in ipairs(self.actions) do

        local score = action:score(ctx)

        if score > bestScore then
            bestScore = score
            best = action
        end

    end

    return best

end

return Engine