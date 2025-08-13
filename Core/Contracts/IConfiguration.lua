-- Core/Contracts/IConfiguration.lua
-- Interface for configuration access used across the addon.
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

-- Do NOT call Addon.require here (Phase 1); prefer Addon.Interface or fallback.
local Interface = (Addon and Addon.Interface)
if type(Interface) ~= 'function' then
  -- Fallback minimal Interface helper (keeps analyzer happy if loaded super-early)
  Interface = function(name, methods)
    local map = {}
    for _,m in ipairs(methods or {}) do map[m]=true end
    return { __interface=true, __name=name or 'IConfiguration', __methods=map }
  end
end

local IConfiguration = Interface('IConfiguration', {
  'Get',    -- (key, fallback?) -> any; when key is nil, returns the backing table
  'Set',    -- (key, value) -> boolean changed
  'All',    -- () -> table (read-only contract by convention)
  'IsDev',  -- () -> boolean
  'Reset',  -- () -> unit; resets config to defaults (preserving critical tables as needed)
})

-- Priority registration hook for the framework bootstrap
local function RegisterIConfiguration()
  -- Provide IConfiguration as an alias to the concrete Config implementation.
  -- Using the scope resolver defers to whatever 'Config' factory is registered.
  if not Addon or type(Addon.safeProvide) ~= 'function' then return end
  Addon.safeProvide('IConfiguration', function(scope)
    return scope:Resolve('Config')
  end, { lifetime = 'SingleInstance' })
end

if Addon then
  Addon._RegisterIConfiguration = RegisterIConfiguration
end

-- Ensure the alias exists even if bootstrap hasn't run yet (idempotent)
pcall(RegisterIConfiguration)

return RegisterIConfiguration
