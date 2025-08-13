-- Core/Interfaces/IPanelFactory.lua
-- Contract for panel creation/resolution.
local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local Interface = (Addon and Addon.Interface) or function(name, methods)
  local m = {}; for _,v in ipairs(methods) do m[v]=true end
  return { __interface=true, __name=name, __methods=m }
end

local IPanelFactory = Interface('IPanelFactory', { 'GetPanel' })

if Addon and Addon.provide then Addon.provide('IPanelFactory', IPanelFactory, { lifetime='SingleInstance', meta={ layer='Core', role='contract' } }) end
return IPanelFactory
