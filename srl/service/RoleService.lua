local mq = require 'mq'
local RoleService = {}
local TableUtil = require 'srl.util.TableUtil'

local MELEE_CLASSES = {
    WAR = "WAR",
    PAL = "PAL",
    SHD = "SHD",
    BRD = "BRD",
    BST = "BST",
    BER = "BER",
    MNK = "MNK",
    RNG = "RNG",
    ROG = "ROG",
}

local CASTER_CLASSES = {
    BST = "BST",
    DRU = "DRU",
    ENC = "ENC",
    MAG = "MAG",
    NEC = "NEC",
    SHM = "SHM",
    WIZ = "WIZ"
}

local HEALER_CLASSES = {
    CLR = "CLR",
    SHM = "SHM",
    DRU = "DRU",
}

local DEBUFF_CLASSES = {
    BST = "BST",
    CLR = "CLR",
    DRU = "DRU",
    ENC = "ENC",
    MAG = "MAG",
    SHM = "SHM",
    WIZ = "WIZ",
}
 local DOT_CLASSES = {
     BST = "BST",
     DRU = "DRU",
     ENC = "ENC",
     MAG = "MAG",
     NEC = "NEC",
     SHM = "SHM",
     SHD = "SHD"
 }


function RoleService:getRoles()
    local roles = {}
    local classShortName = mq.TLO.Me.Class.ShortName()

    if MELEE_CLASSES[classShortName] then
        roles.melee = 'melee'
    end

    if CASTER_CLASSES[classShortName] then
        roles.caster = 'caster'
    end

    if HEALER_CLASSES[classShortName] then
        roles.healer = 'healer'
    end

    if DEBUFF_CLASSES[classShortName] then
        roles.debuff = 'debuff'
    end

    if DOT_CLASSES[classShortName] then
        roles.doter = 'doter'
    end

    return roles
end

return RoleService