stringutil_export = {}

--Assumes splits by | to get the value
function stringutil_export.getValueByName(inputstr, value)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    i, j = string.find(inputstr, value)
    --Need to find if there is another / if not we can assume this is the end
    local stringLength = string.len(value)
    local con = string.sub(inputstr, i + 1, -1)
    k = string.find(con, "/")
    if(k == nil) then
        k = string.len(con)
    else
        k = k - 1
    end
    local ret = string.sub(con, stringLength + 1, k)

    return ret
end

function stringutil_export.split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

function stringutil_export.printGlobalVariables()

end
-- Returns the numeric rank from a spell name (e.g. "Spell Rk. III" → 3), or 0 if unranked.
function stringutil_export.parseRank(name)
    local roman = name and name:match('%s+Rk%.%s*(%a+)$')
    if not roman then return 0 end
    local map = { I=1, II=2, III=3, IV=4, V=5, VI=6, VII=7, VIII=8, IX=9, X=10 }
    return map[roman] or 0
end

return stringutil_export