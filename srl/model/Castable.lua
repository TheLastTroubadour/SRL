--Castable Object Spell/AA/Item

function Castable:name(self, name)
    self.name = name
end

function Castable:id(self, id)
    self.id = id
end

function Castable:new (o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end