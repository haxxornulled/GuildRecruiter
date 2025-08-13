-- Application/Services/ProspectService.lua
-- Use case orchestration sits here. Depends only on interfaces, not on infrastructure.
local ADDON_NAME, Addon = ...
local ProspectService = {}
ProspectService.__index = ProspectService

local function CreateProspectService(scope)
    local repo = scope:Resolve('ProspectRepository') -- prospects only now
    local blRepo = nil
    if scope.Resolve then
        local ok, dep = pcall(scope.Resolve, scope, 'BlacklistRepository')
        if ok and dep then blRepo = dep end
    end
    local bus = Addon.require and Addon.require('EventBus') or nil
    local logger = (Addon.require and Addon.require('Logger') or { Info=function() end, Debug=function() end, Warn=function() end, Error=function() end }):ForContext('Service','ProspectService')

    local self = {}

    function self:GetAll()
        return repo:GetAll()
    end

    function self:Get(guid)
        return repo:Get(guid)
    end

    function self:Blacklist(guid, reason)
        if blRepo and blRepo.Add then
            blRepo:Add(guid, reason)
        elseif repo.Blacklist then
            repo:Blacklist(guid, reason)
        end
        if bus and bus.Publish then bus:Publish('Prospects.Changed','blacklisted', guid) end
    end

    function self:Unblacklist(guid)
        if blRepo and blRepo.Remove then
            blRepo:Remove(guid)
        elseif repo.Unblacklist then
            repo:Unblacklist(guid)
        end
        if bus and bus.Publish then bus:Publish('Prospects.Changed','unblacklisted', guid) end
    end

    function self:IsBlacklisted(guid)
        if blRepo and blRepo.Contains then return blRepo:Contains(guid) end
        if repo.IsBlacklisted then return repo:IsBlacklisted(guid) end
        return false
    end

    function self:Prune(maxProspects, maxBlacklist)
        local pr = 0; local br = 0
        if maxProspects then pr = repo:PruneProspects(maxProspects) end
        if maxBlacklist then
            if blRepo and blRepo.Prune then
                br = blRepo:Prune(maxBlacklist)
            elseif repo.PruneBlacklist then
                br = repo:PruneBlacklist(maxBlacklist)
            end
        end
        logger:Info('Prune complete Prospects={P} Blacklist={B}', { P=pr, B=br })
        return pr, br
    end

    return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('ProspectService')) then
    Addon.provide('ProspectService', function(scope) return CreateProspectService(scope) end, { lifetime='SingleInstance' })
end

return CreateProspectService
