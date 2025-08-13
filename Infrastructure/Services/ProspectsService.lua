local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

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

-- Persistent DB reference
local DB_VAR = 'GuildRecruiterDB'
_G[DB_VAR] = _G[DB_VAR] or {}
local DB = _G[DB_VAR]
DB.prospects = DB.prospects or {}
DB.blacklist = DB.blacklist or {}

local ProspectsService = Class('ProspectsService', {
  __deps = { 'EventBus', 'Logger' },
  __implements = { 'IProspectsService' },
})

function ProspectsService:init(bus, logger)
  -- Logger contract may differ; ensure we have safe methods
  self._bus = bus
  self._logger = (logger and logger.ForContext and logger:ForContext('Subsystem','ProspectsService')) or logger or { Info=function() end, Debug=function() end, Warn=function() end, Error=function() end }
end

local function publish(self, action, guid)
  local bus = self._bus
  if bus then
    local pub = rawget(bus, 'Publish') or (type(bus)=='table' and bus.Publish)
    if type(pub)=='function' then pcall(pub, bus, 'Prospects.Changed', action, guid) end
  end
end

-- Prospect access
function ProspectsService:Get(guid) return DB.prospects[guid] end
function ProspectsService:GetProspect(guid) return DB.prospects[guid] end
function ProspectsService:GetAll()
  local t = {}
  for _,p in pairs(DB.prospects) do t[#t+1]=p end
  return t
end
function ProspectsService:GetAllGuids()
  local t = {}
  for g,_ in pairs(DB.prospects) do t[#t+1]=g end
  return t
end

function ProspectsService:Upsert(p)
  if not p or not p.guid then return end
  local cur = DB.prospects[p.guid]
  if cur then
    for k,v in pairs(p) do cur[k]=v end
  -- no paging index maintained here by design
    publish(self,'updated', p.guid)
  else
    DB.prospects[p.guid] = p
    
    publish(self,'queued', p.guid)
  end
end

function ProspectsService:RemoveProspect(guid)
  if DB.prospects[guid] then
    DB.prospects[guid]=nil
    
    publish(self,'removed', guid)
  end
end
ProspectsService.Remove = ProspectsService.RemoveProspect

-- Blacklist ops
function ProspectsService:Blacklist(guid, reason)
  if not guid then return end
  local now = (_G.time and _G.time()) or 0
  DB.blacklist[guid] = DB.blacklist[guid] or { reason = reason or 'manual', timestamp = now }
  
  publish(self,'blacklisted', guid)
end
function ProspectsService:Unblacklist(guid)
  if DB.blacklist[guid] then
    DB.blacklist[guid]=nil
    
    publish(self,'unblacklisted', guid)
  end
end
function ProspectsService:IsBlacklisted(guid) return DB.blacklist[guid] ~= nil end
function ProspectsService:GetBlacklist() return DB.blacklist end
function ProspectsService:GetBlacklistReason(guid) local e=DB.blacklist[guid]; return e and e.reason or nil end

-- Prune
function ProspectsService:PruneProspects(max)
  max = tonumber(max); if not max or max <= 0 then return 0 end
  local items = {}
  for guid,p in pairs(DB.prospects) do items[#items+1] = { guid=guid, ls=p.lastSeen or 0 } end
  table.sort(items, function(a,b) return a.ls > b.ls end)
  local keep = {}
  for i=1, math.min(max,#items) do keep[items[i].guid]=true end
  local removed=0
  for guid,_ in pairs(DB.prospects) do if not keep[guid] then DB.prospects[guid]=nil; removed=removed+1 end end
  return removed
end
function ProspectsService:PruneBlacklist(maxKeep)
  maxKeep = tonumber(maxKeep); if not maxKeep or maxKeep <= 0 then return 0 end
  local items = {}
  for guid,e in pairs(DB.blacklist) do items[#items+1] = { guid=guid, ts=e.timestamp or 0 } end
  table.sort(items, function(a,b) return a.ts > b.ts end)
  local keep = {}
  for i=1, math.min(maxKeep, #items) do keep[items[i].guid] = true end
  local removed = 0
  for guid,_ in pairs(DB.blacklist) do if not keep[guid] then DB.blacklist[guid] = nil; removed = removed + 1 end end
  return removed
end

-- Register via ClassProvide if not already provided
if Addon.ClassProvide and not (Addon.IsProvided and Addon.IsProvided('ProspectsService')) then
  Addon.ClassProvide('ProspectsService', ProspectsService, { lifetime='SingleInstance', meta = { layer = 'Application', area = 'prospects' } })
end

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
