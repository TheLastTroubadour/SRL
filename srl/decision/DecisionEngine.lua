local TableUtil = require 'srl.util.TableUtil'
local Engine = {}
Engine.__index = Engine

function Engine:new(modules)
    setmetatable({}, self)

    self.modules = modules
    self.__index = self
    self.debug = {}
    return self
end

function Engine:evaluate(ctx)

    local best = nil
    local bestScore = 0

    for _, module in ipairs(self.modules) do

        local score = module:score(ctx)

        if score > 0 then
            table.insert(self.debug, {
                name = module.name,
                score = score
            })

            if #self.debug > 50 then
                table.remove(self.debug, 1)
            end

        end

        if score > bestScore then
            bestScore = score
            best = module
        end
    end

    if bestScore < .1 then
        return
    end

    return best
end

return Engine