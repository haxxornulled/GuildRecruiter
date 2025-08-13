local ADDON_NAME, Addon = ...

-- Proper controller that wraps ProspectsService and exposes IProspectManager
local function CreateProspectsManager(scope)
    local svc = scope:Resolve("ProspectsService")
    local logger = scope:Resolve("Logger"):ForContext("Subsystem","ProspectsManager")
    local bus = scope:Resolve("EventBus")

    local self = {}

    local function publish(action, guid)
        local ok, err = pcall(bus.Publish, bus, "ProspectsManager.Event", action, guid)
        if not ok then logger:Error("Bus publish failed {Err}", { Err = err }) end
    end

    -- Interface methods
    function self:GetProspect(guid) return svc:GetProspect(guid) end
    function self:GetAll() return svc:GetAll() end
    function self:GetAllGuids() return svc:GetAllGuids() end

    function self:RemoveProspect(guid)
        svc:RemoveProspect(guid); publish('removed', guid)
    end

    function self:Clear()
        local removed = 0
        for _, g in ipairs(svc:GetAllGuids() or {}) do svc:RemoveProspect(g); removed = removed + 1 end
        publish('cleared', removed)
        logger:Info("Cleared {Count} prospects", { Count = removed })
        return removed
    end

    function self:Blacklist(guid, reason)
        svc:Blacklist(guid, reason); publish('blacklisted', guid)
    end

    function self:Unblacklist(guid)
        svc:Unblacklist(guid); publish('unblacklisted', guid)
    end

    function self:IsBlacklisted(guid) return svc:IsBlacklisted(guid) end
    function self:GetBlacklist() return svc:GetBlacklist() end

    function self:PruneProspects(max)
        local removed = svc:PruneProspects(max); publish('pruned-prospects', removed); return removed
    end

    function self:PruneBlacklist(maxKeep)
        local removed = svc:PruneBlacklist(maxKeep); publish('pruned-blacklist', removed); return removed
    end

    -- Mark interface implementation for validation
    self.__implements = self.__implements or {}
    self.__implements['IProspectManager'] = true

    return self
end

-- Register controller
if Addon.provide then
    if not (Addon.IsProvided and Addon.IsProvided("ProspectsManager")) then
    Addon.provide("ProspectsManager", function(scope) return CreateProspectsManager(scope) end, { lifetime = "SingleInstance", meta = { layer = 'Application', role = "controller", area = "prospects" } })
    end
    -- Provide interface alias
    if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('IProspectManager')) then
        Addon.safeProvide('IProspectManager', function(sc) return sc:Resolve('ProspectsManager') end, { lifetime = 'SingleInstance' })
    end
end

-- Optional legacy export
Addon.ProspectsManager = setmetatable({}, { __index = function(_, k) local inst=Addon.require("ProspectsManager"); return inst and inst[k] or nil end })

return CreateProspectsManager
