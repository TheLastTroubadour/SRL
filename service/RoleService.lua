local mq = require 'mq'
local RoleService = {}
local TableUtil = require 'util.TableUtil'

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

local HYBRID_CLASSES = {
    BRD = "BRD",
    BST = "BST",
    PAL = "PAL",
    SHD = "SHD",
    RNG = "RNG",
}

local CASTER_CLASSES = {
    ENC = "ENC",
    MAG = "MAG",
    NEC = "NEC",
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
local CC_CLASSES = {
    BRD = "BRD",
    ENC = "ENC",
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

    if HYBRID_CLASSES[classShortName] then
        roles.hybrid = 'hybrid'
    end

    if CC_CLASSES[classShortName] then
        roles.cc = 'cc'
    end

    if classShortName == 'BRD' then
        roles.bard = 'bard'
    end

    return roles
end

return RoleService