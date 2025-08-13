local ADDON_NAME = "TaintedSin" -- Change this ONCE per project!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

Addon._modules = Addon._modules or {}

if not Addon.provide then
    function Addon.provide(name, mod)
        if not name or not mod then
            error("Usage: Addon.provide(name, mod)")
        end
        Addon._modules[name] = mod
    end
end

if not Addon.require then
    function Addon.require(name)
        local m = Addon._modules[name]
        if not m then
            error("Module '"..tostring(name).."' not found. " ..
                "Did you forget to load the file in your .toc, or forget Addon.provide?")
        end
        return m
    end
end

-- Class.lua
-- Minimal class system with single inheritance and constructor support

local function Class(name, base, def)
    -- Usage:
    -- local MyClass = Class("MyClass", BaseClass, { ... })
    -- local obj = MyClass(...)

    -- Only two args: treat base as nil, def as second
    if def == nil and type(base) == "table" then
        def, base = base, nil
    end

    assert(type(name) == "string", "Class name required")
    def = def or {}

    local cls = {}
    cls.__name = name
    cls.__index = cls
    cls.__base = base

    -- Inheritance
    if base then
        setmetatable(cls, { __index = base })
    else
        setmetatable(cls, { __index = function(_, k)
            error("No such member: " .. tostring(k))
        end})
    end

    -- Copy methods/fields from def
    for k, v in pairs(def) do
        cls[k] = v
    end

    -- Instantiation: obj = MyClass(...)
    local function new(_, ...)
        local obj = setmetatable({}, cls)
        if obj.init then obj:init(...) end
        return obj
    end

    -- Allow calling the class table: MyClass(...)
    setmetatable(cls, {
        __call = new
    })

    return cls
end

Addon.provide("Class", Class)

return Class
