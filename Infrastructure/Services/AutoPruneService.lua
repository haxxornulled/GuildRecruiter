-- Infrastructure/Services/AutoPruneService.lua
-- Periodically prunes prospects/blacklist respecting Config maxima.
local ADDON_NAME, Addon = ...
local Class = (Addon and Addon.Class) or function(_,def) return setmetatable(def or {}, { __call=function(c, ...) local o=setmetatable({}, { __index=c }); if o.init then o:init(...) end; return o end }) end

local AutoPruneService = Class('AutoPruneService', {
  __deps = { 'Config', 'ProspectsService', 'Scheduler', 'Logger' },
  __implements = { },
})

function AutoPruneService:init(cfg, prosSvc, scheduler, logger)
  self._cfg = cfg
  self._svc = prosSvc
  self._sch = scheduler
  self._logger = (logger and logger:ForContext('Subsystem','AutoPrune')) or logger or { Info=function() end, Debug=function() end }
  self._tickId = nil
end

function AutoPruneService:Start()
  local interval = tonumber(self._cfg:Get('autoPruneInterval', 0)) or 0
  if interval <= 0 or not self._sch then return end
  self._tickId = self._sch:Every(interval, function()
    self:RunOnce()
  end, { namespace = 'AutoPrune' })
end

function AutoPruneService:RunOnce()
  local maxPros = tonumber(self._cfg:Get('prospectsMax', 0)) or 0
  local maxBL   = tonumber(self._cfg:Get('blacklistMax', 0)) or 0
  local removedP, removedB = 0, 0
  if maxPros > 0 then removedP = self._svc:PruneProspects(maxPros) or 0 end
  if maxBL > 0 then removedB = self._svc:PruneBlacklist(maxBL) or 0 end
  if (removedP + removedB) > 0 then
    local log = self._logger
    if log and log.Info then log:Info('AutoPrune removed {P} prospects, {B} blacklist', { P = removedP, B = removedB }) end
    local bus = Addon.ResolveOptional and Addon.ResolveOptional('EventBus')
    if bus and bus.Publish then
      local E = (Addon.ResolveOptional and Addon.ResolveOptional('Events')) or error('Events constants missing')
      bus:Publish(E.Prospects.Changed, 'pruned', removedP + removedB)
    end
  end
end

function AutoPruneService:Stop()
  if self._tickId and self._sch then self._sch:Cancel(self._tickId) end
  self._tickId = nil
end

local function Register()
  if Addon.ClassProvide and not (Addon.IsProvided and Addon.IsProvided('AutoPruneService')) then
    Addon.ClassProvide('AutoPruneService', AutoPruneService, { lifetime='SingleInstance', meta={ layer='Infrastructure', area='maintenance' } })
  end
end
Register()
Addon._RegisterAutoPruneService = Register
return AutoPruneService
