local ADDON_NAME, Addon = ...

-- ProspectsManager as Class with constructor injection
local Class = (Addon and Addon.Class) or function(_,def)
    return setmetatable(def or {}, { __call = function(c, ...) local o=setmetatable({}, { __index = c }); if o.init then o:init(...) end; return o end })
end

local ProspectsManager = Class('ProspectsManager', {
    __deps = { 'ProspectsService', 'Logger', 'EventBus', 'InviteService', 'IProspectsReadModel' },
    __implements = { 'IProspectManager' },
})

function ProspectsManager:init(svc, logger, bus, invite, provider)
    self._svc = svc
    self._bus = bus
    self._logger = (logger and logger.ForContext and logger:ForContext('Subsystem','ProspectsManager')) or logger or { Info=function() end, Error=function() end }
    self._invite = invite
    self._provider = provider -- read-side collaborator (optional usage)
end

local function publish(self, action, guid)
    local bus = self._bus
    if not bus or not bus.Publish then return end
    local ok, err = pcall(bus.Publish, bus, 'ProspectsManager.Event', action, guid)
    if not ok then local l=self._logger; if l and l.Error then l:Error('Bus publish failed {Err}', { Err = err }) end end
end

function ProspectsManager:GetProspect(guid) return self._svc:GetProspect(guid) end
function ProspectsManager:GetAll() return self._svc:GetAll() end
function ProspectsManager:GetAllGuids() return self._svc:GetAllGuids() end

function ProspectsManager:RemoveProspect(guid)
    self._svc:RemoveProspect(guid); publish(self,'removed', guid)
end

function ProspectsManager:Clear()
    local removed = 0
    for _, g in ipairs(self._svc:GetAllGuids() or {}) do self._svc:RemoveProspect(g); removed = removed + 1 end
    publish(self,'cleared', removed)
    local l=self._logger; if l and l.Info then l:Info('Cleared {Count} prospects', { Count = removed }) end
    return removed
end

function ProspectsManager:Blacklist(guid, reason)
    self._svc:Blacklist(guid, reason); publish(self,'blacklisted', guid)
end

function ProspectsManager:Unblacklist(guid)
    self._svc:Unblacklist(guid); publish(self,'unblacklisted', guid)
end

function ProspectsManager:IsBlacklisted(guid) return self._svc:IsBlacklisted(guid) end
function ProspectsManager:GetBlacklist() return self._svc:GetBlacklist() end

function ProspectsManager:PruneProspects(max)
    local removed = self._svc:PruneProspects(max); publish(self,'pruned-prospects', removed); return removed
end

function ProspectsManager:PruneBlacklist(maxKeep)
    local removed = self._svc:PruneBlacklist(maxKeep); publish(self,'pruned-blacklist', removed); return removed
end

function ProspectsManager:InviteProspect(guid)
    local inv = self._invite
    if inv and inv.InviteProspect and guid then return inv:InviteProspect(guid) end
    return false
end

-- Added passthrough Upsert so tests (and callers) that previously invoked ProspectsManager:Upsert continue to work
-- without needing to reach for the lower-level ProspectsService directly. ProspectsService already emits the
-- appropriate events; we intentionally do NOT duplicate publish() here to avoid double notification.
function ProspectsManager:Upsert(p)
    if not p or not p.guid then return end
    if self._svc and self._svc.Upsert then self._svc:Upsert(p) end
end

-- Registration using ClassProvide (provides alias for IProspectManager automatically)
local function RegisterProspectsManager()
    if not Addon or not Addon.ClassProvide then return end
    if not (Addon.IsProvided and Addon.IsProvided('ProspectsManager')) then
        Addon.ClassProvide('ProspectsManager', ProspectsManager, { lifetime = 'SingleInstance', meta = { layer = 'Infrastructure', role = 'controller', area = 'prospects' } })
    end
end

RegisterProspectsManager()
Addon._RegisterProspectsManager = RegisterProspectsManager

Addon.ProspectsManager = setmetatable({}, { __index = function(_, k) local inst=Addon.require('ProspectsManager'); return inst and inst[k] or nil end })

return ProspectsManager
