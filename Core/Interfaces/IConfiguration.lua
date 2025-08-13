-- Core/Interfaces/IConfiguration.lua
-- Interface for configuration access used across the addon.
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

local Interface = (Addon and Addon.Interface)
if type(Interface) ~= 'function' then
  Interface = function(name, methods)
    local map = {}
    for _,m in ipairs(methods or {}) do map[m]=true end
    return { __interface=true, __name=name or 'IConfiguration', __methods=map }
  end
end

local IConfiguration = Interface('IConfiguration', {
  'Get','Set','All','IsDev','Reset'
})

-- Priority registration hook as before
local function RegisterIConfiguration()
  if not Addon or type(Addon.safeProvide) ~= 'function' then return end
  Addon.safeProvide('IConfiguration', function(scope)
    return scope:Resolve('Config')
  end, { lifetime = 'SingleInstance' })
end

if Addon then Addon._RegisterIConfiguration = RegisterIConfiguration end
pcall(RegisterIConfiguration)
return RegisterIConfiguration
