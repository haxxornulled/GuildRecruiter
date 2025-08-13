-- Core/Interfaces/IProspectManager.lua
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

local Interface = (Addon and Addon.Interface)
if type(Interface) ~= 'function' then
  Interface = function(name, methods)
    local m = {}
    for _,v in ipairs(methods or {}) do m[v] = true end
    return { __interface = true, __name = name or 'IProspectManager', __methods = m }
  end
end

local IProspectManager = Interface('IProspectManager', {
  'GetProspect','GetAll','GetAllGuids','RemoveProspect','Clear','Blacklist','Unblacklist','IsBlacklisted','GetBlacklist','PruneProspects','PruneBlacklist','InviteProspect',
})

if Addon and Addon.provide then
  if not (Addon.IsProvided and Addon.IsProvided('IProspectManager.Contract')) then
    Addon.provide('IProspectManager.Contract', IProspectManager, { lifetime = 'SingleInstance' })
  end
end

return IProspectManager
