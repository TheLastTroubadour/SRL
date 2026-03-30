local mq = require 'mq'

local WeaponSwapService = {}
WeaponSwapService.__index = WeaponSwapService

function WeaponSwapService:new(config)
    local self = setmetatable({}, WeaponSwapService)
    self.config = config
    return self
end

local SLOT_NUMBER = { main = 13, off = 14 }

local function equipItem(itemName, slotNum, slotLabel)
    local item = mq.TLO.FindItem('=' .. itemName)
    if not item() then
        print(string.format('[SRL] WeaponSwap: "%s" not found in inventory', itemName))
        return
    end

    -- Already equipped in the correct slot
    if mq.TLO.InvSlot(slotNum).Item.Name() == itemName then return end

    -- MQ2Exchange: /exchange "Item Name" slotname
    mq.cmdf('/exchange "%s" %s', itemName, slotLabel)
    -- Wait until the slot reflects the new item (up to 2s)
    mq.delay(2000, function()
        return mq.TLO.InvSlot(slotNum).Item.Name() == itemName
    end)
end

-- setName maps to SwapItems.<setName>.Main / .Offhand in YAML.
-- Silently does nothing if the set is not configured for this bot.
-- Set name lookup is case-insensitive.
function WeaponSwapService:swap(setName)
    local swapItems = self.config:get('SwapItems')
    if not swapItems or type(swapItems) ~= 'table' then return end

    local setNameLower = setName:lower()
    local setData
    for k, v in pairs(swapItems) do
        if type(k) == 'string' and k:lower() == setNameLower then
            setData = v
            break
        end
    end
    if not setData then return end

    local main = setData.Main
    local off  = setData.Offhand

    if type(main) ~= 'string' or main == '' then main = nil end
    if type(off)  ~= 'string' or off  == '' then off  = nil end

    if not main and not off then return end

    if main then equipItem(main, SLOT_NUMBER.main, 'mainhand') end
    if off  then equipItem(off,  SLOT_NUMBER.off,  'offhand')  end

    print(string.format('[SRL] WeaponSwap: %s', setName))
end

return WeaponSwapService
