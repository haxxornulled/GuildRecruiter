-- Core/Contracts/IProspectsService.lua
-- C#-style interface declaration (pure contract, no implementation logic)
-- Usage: local IProspectsService = Addon.require('IProspectsService')
--        TypeCheck.Require(serviceInstance, IProspectsService)
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}

local Interface = (Addon and Addon.Interface) or function(name, methods) return { __interface=true, __name=name, __methods=(function(t) local m={} for _,v in ipairs(t) do m[v]=true end return m end)(methods) } end

local IProspectsService = Interface('IProspectsService', {
  'Get','GetProspect','GetAll','GetAllGuids','Upsert','RemoveProspect','Blacklist','Unblacklist','IsBlacklisted','GetBlacklist','GetBlacklistReason','PruneProspects','PruneBlacklist','Stats','DumpDebug'
})

if Addon.provide then Addon.provide('IProspectsService', IProspectsService) end
return IProspectsService
