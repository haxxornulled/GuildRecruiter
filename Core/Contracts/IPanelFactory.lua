-- Core/Contracts/IPanelFactory.lua
-- Interface contract for panel creation/resolution.
-- Intent: injectable factory to obtain or build UI panels by key.

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local Interface = (Addon and Addon.Interface) or function(name, methods)
  local m = {}; for _,v in ipairs(methods) do m[v]=true end
  return { __interface=true, __name=name, __methods=m }
end

-- Contract
-- GetPanel(key[, opts]) -> frame (existing or built)
-- Known error modes: unknown key; build failure
local IPanelFactory = Interface("IPanelFactory", {
  "GetPanel",
})

if Addon and Addon.provide then Addon.provide("IPanelFactory", IPanelFactory, { lifetime = "SingleInstance", meta = { layer = 'Core', role = 'contract' } }) end
return IPanelFactory
