local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})
-- Ensure we point at the shared addon namespace table (the second var is often nil when loaded via TOC)
Addon = (Addon and next(Addon)) and Addon or _G[ADDON_NAME] or Addon or {}
_G[ADDON_NAME] = _G[ADDON_NAME] or Addon

-- Never resolve DI at file load; use Addon.Class if present, fallback to inline shim
local Class = (Addon and Addon.Class) or function(_,def)
  return setmetatable(def or {}, {
    __call = function(c, ...)
      local o = setmetatable({}, { __index = c })
      if o.init then o:init(...) end
      return o
    end
  })
end

-- Persistence is handled via SavedVarsService; do not touch global DB directly here.

local ProspectsService = Class('ProspectsService', {
  __deps = { 'EventBus', 'Logger', 'SavedVarsService' },
  __implements = { 'IProspectsService' },
})

-- Status constants (lazy resolve for safety in early load / tests)
local Status = (Addon and Addon.ResolveOptional and Addon.ResolveOptional('ProspectStatus')) or { New='New', Invited='Invited', Blacklisted='Blacklisted', Rejected='Rejected' }

function ProspectsService:init(bus, logger, savedVars)
  -- Logger contract may differ; ensure we have safe methods
  self._bus = bus
  self._logger = (logger and logger.ForContext and logger:ForContext('Subsystem','ProspectsService')) or logger or { Info=function() end, Debug=function() end, Warn=function() end, Error=function() end }
  self._sv = savedVars
  -- Ensure namespaces/keys exist
  if self._sv and self._sv.GetNamespace then
    -- Using empty namespace returns the root SavedVariables table
    self._sv:GetNamespace('', { prospects = {}, blacklist = {} })
  end
end

local function publish(self, action, guid)
  local bus = self._bus
  if bus then
    local pub = rawget(bus, 'Publish') or (type(bus) == 'table' and bus.Publish)
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events') or error('Events constants not registered')
  local ev = E.Prospects.Changed
  if type(pub) == 'function' then pcall(pub, bus, ev, action, guid) end
  end
end

local function DB(self)
  -- Access the SavedVariables root via SavedVarsService
  if self._sv and self._sv.GetNamespace then
    return self._sv:GetNamespace('')
  end
  -- Fallback: create minimal structure to avoid runtime errors (should not happen if DI is correct)
  local root = _G['GuildRecruiterDB'] or {}
  root.prospects = root.prospects or {}
  root.blacklist = root.blacklist or {}
  _G['GuildRecruiterDB'] = root
  return root
end

-- Prospect access
function ProspectsService:Get(guid) local db=DB(self); return db.prospects[guid] end
function ProspectsService:GetProspect(guid) local db=DB(self); return db.prospects[guid] end
function ProspectsService:GetAll()
  local t = {}
  local db = DB(self)
  for _,p in pairs(db.prospects) do t[#t+1]=p end
  return t
end
function ProspectsService:GetAllGuids()
  local t = {}
  local db = DB(self)
  for g,_ in pairs(db.prospects) do t[#t+1]=g end
  return t
end

function ProspectsService:Upsert(p)
  if not p or not p.guid then return end
  local db = DB(self)
  local cur = db.prospects[p.guid]
  if cur then
    for k,v in pairs(p) do cur[k]=v end
  -- no paging index maintained here by design
    publish(self,'updated', p.guid)
  else
    db.prospects[p.guid] = p
    
    publish(self,'queued', p.guid)
  end
end

function ProspectsService:RemoveProspect(guid)
  local db = DB(self)
  if db.prospects[guid] then
    db.prospects[guid]=nil
    
    publish(self,'removed', guid)
  end
end
ProspectsService.Remove = ProspectsService.RemoveProspect

-- Blacklist ops
function ProspectsService:Blacklist(guid, reason)
  if not guid then return end
  local db = DB(self)
  local now = (_G.time and _G.time()) or 0
  db.blacklist[guid] = db.blacklist[guid] or { reason = reason or 'manual', timestamp = now }
  
  publish(self,'blacklisted', guid)
end
function ProspectsService:Unblacklist(guid)
  local db = DB(self)
  if db.blacklist[guid] then
    db.blacklist[guid]=nil
    
    publish(self,'unblacklisted', guid)
  end
end
function ProspectsService:IsBlacklisted(guid) local db=DB(self); return db.blacklist[guid] ~= nil end
function ProspectsService:GetBlacklist() local db=DB(self); return db.blacklist end
function ProspectsService:GetBlacklistReason(guid) local db=DB(self); local e=db.blacklist[guid]; return e and e.reason or nil end

-- Lightweight aggregated counts (avoids full provider cost when only high-level numbers needed)
function ProspectsService:GetCounts()
  local db = DB(self)
  local total, blacklisted, new, active = 0,0,0,0
  local bl = db.blacklist or {}
  for guid,p in pairs(db.prospects) do
    total = total + 1
    local isBl = bl[guid] ~= nil
    if isBl then blacklisted = blacklisted + 1 else
      local st = p.status or Status.New
      if st == Status.New then new = new + 1 end
      active = active + 1
    end
  end
  return { total = total, blacklisted = blacklisted, active = active, new = new }
end

-- Prune
function ProspectsService:PruneProspects(max)
  max = tonumber(max); if not max or max <= 0 then return 0 end
  local db = DB(self)
  local items = {}
  for guid,p in pairs(db.prospects) do items[#items+1] = { guid=guid, ls=p.lastSeen or 0 } end
  table.sort(items, function(a,b) return a.ls > b.ls end)
  local keep = {}
  for i=1, math.min(max,#items) do keep[items[i].guid]=true end
  local removed=0
  for guid,_ in pairs(db.prospects) do if not keep[guid] then db.prospects[guid]=nil; removed=removed+1 end end
  return removed
end
function ProspectsService:PruneBlacklist(maxKeep)
  maxKeep = tonumber(maxKeep); if not maxKeep or maxKeep <= 0 then return 0 end
  local db = DB(self)
  local items = {}
  for guid,e in pairs(db.blacklist) do items[#items+1] = { guid=guid, ts=e.timestamp or 0 } end
  table.sort(items, function(a,b) return a.ts > b.ts end)
  local keep = {}
  for i=1, math.min(maxKeep, #items) do keep[items[i].guid] = true end
  local removed = 0
  for guid,_ in pairs(db.blacklist) do if not keep[guid] then db.blacklist[guid] = nil; removed = removed + 1 end end
  return removed
end

-- Register via ClassProvide if not already provided
local function RegisterProspectsService()
  if Addon.ClassProvide and not (Addon.IsProvided and Addon.IsProvided('ProspectsService')) then
    Addon.ClassProvide('ProspectsService', ProspectsService, { lifetime='SingleInstance', meta = { layer = 'Application', area = 'prospects' } })
  end
end
RegisterProspectsService()
Addon._RegisterProspectsService = RegisterProspectsService

-- Back-compat adapters (still provided same as before)
local function adapterProvided(oldKey) return Addon.IsProvided and Addon.IsProvided(oldKey) end
local function provideAdapter(key, build)
  if Addon.provide and not adapterProvided(key) then
    Addon.provide(key, build, { lifetime='SingleInstance', meta = { layer = 'Application', area = 'adapter' } })
  end
end

provideAdapter('ProspectRepository', function(scope)
  local svc = scope:Resolve('ProspectsService')
  return {
    Get = function(_, g) return svc:Get(g) end,
    GetAll = function() return svc:GetAll() end,
    Save = function(_, p) return svc:Upsert(p) end,
    Remove = function(_, g) return svc:RemoveProspect(g) end,
    Blacklist = function(_, g, r) return svc:Blacklist(g,r) end,
    Unblacklist = function(_, g) return svc:Unblacklist(g) end,
    IsBlacklisted = function(_, g) return svc:IsBlacklisted(g) end,
    GetBlacklist = function() return svc:GetBlacklist() end,
    PruneProspects = function(_, m) return svc:PruneProspects(m) end,
    PruneBlacklist = function(_, m) return svc:PruneBlacklist(m) end,
  }
end)

provideAdapter('BlacklistRepository', function(scope)
  local svc = scope:Resolve('ProspectsService')
  return {
    Add = function(_, g, r) return svc:Blacklist(g,r) end,
    Remove = function(_, g) return svc:Unblacklist(g) end,
    Contains = function(_, g) return svc:IsBlacklisted(g) end,
    GetAll = function() return svc:GetBlacklist() end,
    GetReason = function(_, g) return svc:GetBlacklistReason(g) end,
    Prune = function(_, m) return svc:PruneBlacklist(m) end,
  }
end)

provideAdapter('ProspectService', function(scope)
  local svc = scope:Resolve('ProspectsService')
  return svc
end)

return ProspectsService
