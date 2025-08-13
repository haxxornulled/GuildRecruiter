-- Core/Interfaces/IProspectsService.lua
-- Interface: Prospects data/service access
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}
local Interface = (Addon and Addon.Interface) or function(name, methods) local m={} for _,v in ipairs(methods) do m[v]=true end return { __interface=true, __name=name, __methods=m } end
local IProspectsService = Interface('IProspectsService', {
  'Get','GetProspect','GetAll','GetAllGuids','Upsert','RemoveProspect','Blacklist','Unblacklist','IsBlacklisted','GetBlacklist','GetBlacklistReason','PruneProspects','PruneBlacklist','Stats','DumpDebug'
})
if Addon.provide then Addon.provide('IProspectsService', IProspectsService) end
return IProspectsService
