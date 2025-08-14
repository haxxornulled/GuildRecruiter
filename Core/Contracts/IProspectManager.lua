-- Core/Contracts/IProspectManager.lua
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

-- Avoid Addon.require at file load; use Addon.Interface if present
local Interface = (Addon and Addon.Interface)
if type(Interface) ~= 'function' then
  Interface = function(name, methods)
    local m = {}
    for _,v in ipairs(methods or {}) do m[v] = true end
    return { __interface = true, __name = name or 'IProspectManager', __methods = m }
  end
end

local IProspectManager = Interface('IProspectManager', {
  'GetProspect',      -- (guid) -> prospect|nil
  'GetAll',           -- () -> {prospects}
  'GetAllGuids',      -- () -> {guids}
  'RemoveProspect',   -- (guid) -> unit
  'Clear',            -- () -> removedCount
  'Blacklist',        -- (guid, reason?) -> unit
  'Unblacklist',      -- (guid) -> unit
  'IsBlacklisted',    -- (guid) -> boolean
  'GetBlacklist',     -- () -> table
  'PruneProspects',   -- (max?) -> removedCount
  'PruneBlacklist',   -- (maxKeep?) -> removedCount
  'Upsert',           -- (prospect) -> unit (added for convenience / test helper compatibility)
})

-- Optional: register the contract for early aliasing if desired
if Addon and Addon.provide then
  -- Register as contract-only to avoid colliding with the runtime implementation alias
  if not (Addon.IsProvided and Addon.IsProvided('IProspectManager.Contract')) then
    Addon.provide('IProspectManager.Contract', IProspectManager, { lifetime = 'SingleInstance' })
  end
end

return IProspectManager
