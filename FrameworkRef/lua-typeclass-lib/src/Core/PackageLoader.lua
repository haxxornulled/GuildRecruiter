-- PackageLoader.lua
-- Enterprise-grade "require/provide" system for WoW AddOns
-- Supports any addon name - just change ADDON_NAME!
local ADDON_NAME = "TaintedSin" -- Change this if you use a different addon name!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

-- Only define the loader once (idempotent)
if not Addon._modules then
    Addon._modules = {}

    function Addon.provide(name, mod)
        if not name or not mod then
            error("Usage: Addon.provide(name, mod)")
        end
        Addon._modules[name] = mod
    end

    function Addon.require(name)
        local m = Addon._modules[name]
        if not m then
            error("Module '"..tostring(name).."' not found. " ..
                "Did you forget to load the file in your .toc, or forget Addon.provide?")
        end
        return m
    end
    
    -- Debug function to list all available modules
    function Addon.listModules()
        local modules = {}
        for name, _ in pairs(Addon._modules) do
            table.insert(modules, name)
        end
        return modules
    end
end

-- Provide the loader itself
Addon.provide("PackageLoader", Addon)
