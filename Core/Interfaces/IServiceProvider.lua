-- Core/Interfaces/IServiceProvider.lua
-- Formalizes a minimal service provider contract for DI-friendly injection.
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

local Interface = (Addon and Addon.Interface)
if type(Interface) ~= 'function' then
  Interface = function(name, methods)
    local map = {}
    for _,m in ipairs(methods or {}) do map[m]=true end
    return { __interface=true, __name=name or 'IServiceProvider', __methods=map }
  end
end

local IServiceProvider = Interface('IServiceProvider', {
  'Resolve','TryResolve','ResolveAll','ResolveOwned','BeginLifetimeScope',
})

-- Keep registration hook for diagnostics
local function RegisterIServiceProvider()
  if Addon and Addon.provide then
    if not (Addon.IsProvided and Addon.IsProvided('IServiceProvider.Contract')) then
      Addon.provide('IServiceProvider.Contract', IServiceProvider, { lifetime = 'SingleInstance' })
    end
  end
end

if Addon then Addon._RegisterIServiceProvider = RegisterIServiceProvider end
return RegisterIServiceProvider
