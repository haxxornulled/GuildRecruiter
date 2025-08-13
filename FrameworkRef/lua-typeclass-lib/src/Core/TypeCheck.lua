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

-- TypeCheck.lua
-- Runtime type and interface checks

local function IsInstanceOf(obj, class)
    -- Follows inheritance (__base chain)
    local mt = getmetatable(obj)
    while mt do
        if mt == class then return true end
        mt = mt.__base
    end
    return false
end

local function Implements(obj, iface)
    if not iface or not iface.__interface then return false end
    for method in pairs(iface.__methods) do
        if type(obj[method]) ~= "function" then
            return false
        end
    end
    return true
end

local TypeCheck = {
    IsInstanceOf = IsInstanceOf,
    Implements = Implements
}

Addon.provide("TypeCheck", TypeCheck)

return TypeCheck
