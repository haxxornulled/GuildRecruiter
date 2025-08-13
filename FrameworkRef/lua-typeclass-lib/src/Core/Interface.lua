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

-- Interface.lua
-- Define an interface (protocol) for runtime checks

local function Interface(name, methods)
    assert(type(name) == "string", "Interface name required")
    assert(type(methods) == "table", "Interface requires method list")
    local iface = {
        __interface = true,
        __name = name,
        __methods = {}
    }
    for _, method in ipairs(methods) do
        assert(type(method) == "string", "Interface methods must be strings")
        iface.__methods[method] = true
    end
    return iface
end

Addon.provide("Interface", Interface)

return Interface
