-- Infrastructure/Providers/ProspectsDataProvider.lua
-- Read-only Prospects read model with indices and LINQ-style query helpers
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

-- Class shim (fallback if Addon.Class not present at load)
local Class = (Addon and Addon.Class) or function(_,def)
  return setmetatable(def or {}, {
    __call = function(c, ...)
      local o = setmetatable({}, { __index = c })
      if o.init then o:init(...) end
      return o
    end
  })
end

local ProspectsDataProvider = Class('ProspectsDataProvider', {
  __deps = { 'SavedVarsService', 'Logger', 'EventBus', 'Collections.List' },
  __implements = { 'IProspectsReadModel' },
})

local Status = (Addon and Addon.ResolveOptional and Addon.ResolveOptional('ProspectStatus')) or { New='New', Invited='Invited', Blacklisted='Blacklisted', Rejected='Rejected' }

local function _escapePattern(str)
  return (tostring(str or ''):gsub('([^%w])', '%%%1'))
end

function ProspectsDataProvider:init(SavedVars, logger, EventBus, List)
  self._sv = SavedVars
  self._logger = (logger and logger.ForContext and logger:ForContext('Subsystem','ProspectsDataProvider')) or logger or { Info=function() end, Error=function() end, Debug=function() end }
  self._bus = EventBus
  self._List = List
  self._byGuid = {}
  self._byName = {}  -- key: lower(name)|realm -> set of guids
  self._version = 0

  -- build initial indices and subscribe to changes
  self:_fullRebuild()
  if self._bus and self._bus.Subscribe then
  local E = (Addon.ResolveOptional and Addon.ResolveOptional('Events')) or error('Events constants missing')
  self._bus:Subscribe(E.Prospects.Changed, function(ev, action, guid)
      self:_onChanged(action, guid)
    end, { namespace = 'ProspectsDataProvider' })
  end
end

function ProspectsDataProvider:_touch() self._version = self._version + 1 end

function ProspectsDataProvider:DB()
  if self._sv and self._sv.GetNamespace then
    return self._sv:GetNamespace('', { prospects = {}, blacklist = {} })
  end
  local root = _G['GuildRecruiterDB'] or {}
  root.prospects = root.prospects or {}
  root.blacklist = root.blacklist or {}
  _G['GuildRecruiterDB'] = root
  return root
end

local function _sanitize(self, p, guid)
  if not p then return nil end
  local db = self:DB()
  local realmFn = rawget(_G, 'GetRealmName')
  local realm = p.realm or (realmFn and realmFn()) or 'Unknown'
  local isBlacklisted = db and db.blacklist and db.blacklist[guid] ~= nil
  return {
    guid = p.guid or guid,
    name = p.name or 'Unknown',
    realm = realm,
    level = p.level or 0,
    classToken = p.classToken,
    className = p.className or p.classToken or 'Unknown',
    raceName = p.raceName,
    raceToken = p.raceToken,
  status = isBlacklisted and Status.Blacklisted or (p.status or Status.New),
    firstSeen = p.firstSeen or 0,
    lastSeen = p.lastSeen or 0,
    seenCount = p.seenCount or 0,
    sources = p.sources or {},
    faction = p.faction,
    sex = p.sex,
    mapID = p.mapID,
    declinedAt = p.declinedAt,
    declinedBy = p.declinedBy,
    blacklistReason = (db and db.blacklist and db.blacklist[guid] and db.blacklist[guid].reason) or p.blacklistReason,
  }
end

function ProspectsDataProvider:_fullRebuild()
  self._byGuid, self._byName = {}, {}
  local db = self:DB()
  for guid, raw in pairs((db and db.prospects) or {}) do
    local c = _sanitize(self, raw, guid)
    if c and c.guid then
      self._byGuid[c.guid] = c
      local key = (c.name and c.name:lower() or '') .. '|' .. (c.realm or '')
      self._byName[key] = self._byName[key] or {}
      self._byName[key][c.guid] = true
    end
  end
  self:_touch()
  local l=self._logger; if l and l.Debug then l:Debug('ProspectsDataProvider full rebuild') end
end

function ProspectsDataProvider:_upsert(guid)
  if not guid then return end
  local db = self:DB(); local raw = db and db.prospects and db.prospects[guid]
  if not raw then return end
  local ex = self._byGuid[guid]
  if ex then
    local oldKey = (ex.name and ex.name:lower() or '') .. '|' .. (ex.realm or '')
    -- update fields
    local n = _sanitize(self, raw, guid)
    for k,v in pairs(n) do ex[k]=v end
    local newKey = (ex.name and ex.name:lower() or '') .. '|' .. (ex.realm or '')
    if newKey ~= oldKey then
      local set = self._byName[oldKey]; if set then set[guid] = nil; if not next(set) then self._byName[oldKey] = nil end end
      self._byName[newKey] = self._byName[newKey] or {}; self._byName[newKey][guid] = true
    end
  else
    local c = _sanitize(self, raw, guid)
    if c then
      self._byGuid[guid] = c
      local key = (c.name and c.name:lower() or '') .. '|' .. (c.realm or '')
      self._byName[key] = self._byName[key] or {}; self._byName[key][guid] = true
    end
  end
  self:_touch()
end

function ProspectsDataProvider:_remove(guid)
  local ex = guid and self._byGuid[guid]
  if not ex then return end
  self._byGuid[guid] = nil
  local key = (ex.name and ex.name:lower() or '') .. '|' .. (ex.realm or '')
  local set = self._byName[key]; if set then set[guid] = nil; if not next(set) then self._byName[key] = nil end end
  self:_touch()
end

function ProspectsDataProvider:_onChanged(action, guid)
  local a = tostring(action or '')
  if a == 'queued' or a == 'updated' or a == 'declined' or a == 'blacklisted' or a == 'unblacklisted' then
    self:_upsert(guid)
  elseif a == 'removed' then
    self:_remove(guid)
  else
    self:_fullRebuild()
  end
end

-- Interface methods -------------------------------------------------------
function ProspectsDataProvider:GetVersion() return self._version end

function ProspectsDataProvider:GetStats()
  local total, active, blacklisted, new, byClass, totalLevels = 0,0,0,0,{},0
  for _,p in pairs(self._byGuid) do
    total = total + 1
  if p.status == Status.Blacklisted then blacklisted = blacklisted + 1
  elseif p.status == Status.New then new = new + 1; active = active + 1
    else active = active + 1 end
    local cls = p.className or p.classToken or 'Unknown'
    byClass[cls] = (byClass[cls] or 0) + 1
    if p.level and p.level > 0 then totalLevels = totalLevels + p.level end
  end
  local avg = total > 0 and (math.floor((totalLevels/total)*10+0.5)/10) or 0
  return { total = total, active = active, blacklisted = blacklisted, new = new, byClass = byClass, avgLevel = avg }
end

-- Cheap snapshot for UI diffing (version + counts only)
function ProspectsDataProvider:GetSnapshot()
  local s = self:GetStats()
  return { version = self._version, total = s.total, active = s.active, blacklisted = s.blacklisted, new = s.new }
end

function ProspectsDataProvider:GetAll()
  local arr, i = {}, 0
  for _, p in pairs(self._byGuid) do i = i + 1; arr[i] = p end
  return arr
end

function ProspectsDataProvider:GetAllGuids()
  local arr, i = {}, 0
  for g,_ in pairs(self._byGuid) do i = i + 1; arr[i] = g end
  return arr
end

function ProspectsDataProvider:Exists(guid) return self._byGuid[guid] ~= nil end
function ProspectsDataProvider:GetByGuid(guid) return self._byGuid[guid] end

function ProspectsDataProvider:GetByName(name, realm)
  if not name or name == '' then return nil end
  local r = tostring(realm or '')
  local key = name:lower() .. '|' .. r
  local set = self._byName[key]
  if set then
    local firstGuid = next(set)
    return firstGuid and self._byGuid[firstGuid] or nil
  end
  if r ~= '' then
    -- cross-realm match using a safe pattern
    local pat = '^' .. _escapePattern(name) .. '%-' .. _escapePattern(r) .. '$'
    for _, p in pairs(self._byGuid) do
      local n = p.name or ''
      local rr = p.realm or ''
      local full = (n ~= '' and rr ~= '') and (n..'-'..rr) or n
      if full:match(pat) then return p end
    end
  end
  return nil
end

function ProspectsDataProvider:GetFiltered(filters, sortColumn, sortDescending)
  local arr = self:GetAll()
  local List = self._List
  if not (List and List.from) then
    -- Fallback simple filter/sort
    if type(filters) == 'function' then
      local res = {}; for _,p in ipairs(arr) do if filters(p) then res[#res+1]=p end end; arr = res
    elseif type(filters) == 'table' then
      local status = filters.status or 'all'
      local search = tostring(filters.search or ''):lower()
      local out = {}
      for _,p in ipairs(arr) do
        local ps = tostring(p.status or '')
  local okStatus = (status=='all') or (status=='active' and ps~=Status.Blacklisted) or (status=='blacklisted' and ps==Status.Blacklisted) or (status=='new' and ps==Status.New)
        if okStatus then
          if search == '' then out[#out+1]=p else
            local name=(p.name or ''):lower(); local cls=(p.className or p.classToken or ''):lower()
            if name:find(search,1,true) or cls:find(search,1,true) then out[#out+1]=p end
          end
        end
      end
      arr = out
    end
    if sortColumn then
      table.sort(arr, function(a,b)
        local av, bv = a[sortColumn], b[sortColumn]
        if av == bv then return false end
        return sortDescending and av > bv or av < bv
      end)
    end
    return arr
  end
  local list = List.from(arr)
  local predicate
  if type(filters) == 'function' then
    predicate = filters
  elseif type(filters) == 'table' then
    local status = filters.status or 'all'
    local search = tostring(filters.search or ''):lower()
    local hasSearch = search ~= ''
    predicate = function(p)
      local ps = tostring(p.status or '')
  local okStatus = (status=='all') or (status=='active' and ps~=Status.Blacklisted) or (status=='blacklisted' and ps==Status.Blacklisted) or (status=='new' and ps==Status.New)
      if not okStatus then return false end
      if hasSearch then
        local name=(p.name or ''):lower(); local cls=(p.className or p.classToken or ''):lower()
        if not (name:find(search,1,true) or cls:find(search,1,true)) then return false end
      end
      return true
    end
  end
  if predicate then list = list:Where(predicate) end
  if sortColumn then
    local key = tostring(sortColumn)
    if sortDescending and list.OrderByDescending then
      list = list:OrderByDescending(function(p) return p[key] end)
    else
      list = list:OrderBy(function(p) return p[key] end)
    end
  end
  return list:ToArray()
end

function ProspectsDataProvider:GetPage(opts)
  opts = opts or {}
  local page = opts.page or 1
  local size = opts.pageSize or 50
  local arr = self:GetAll()
  local List = self._List
  if not (List and List.from) then return arr end
  local list = List.from(arr)
  if type(opts.sort) == 'function' then
    list = list:OrderBy(opts.sort)
  elseif type(opts.sort) == 'table' and opts.sort.key then
    local key = opts.sort.key; local dir = (opts.sort.dir or 'asc'):lower()
    if dir == 'desc' and list.OrderByDescending then
      list = list:OrderByDescending(function(a) return a[key] end)
    else
      list = list:OrderBy(function(a) return a[key] end)
    end
  end
  local skip = (page-1)*size
  return list:Skip(skip):Take(size):ToArray()
end

function ProspectsDataProvider:Query(opts)
  opts = opts or {}
  local arr = self:GetAll()
  local List = self._List
  if not (List and List.from) then return arr end
  local list = List.from(arr)
  if opts.where then list = list:Where(opts.where) end
  if opts.orderBy then list = list:OrderBy(opts.orderBy) end
  if opts.orderByDesc and list.OrderByDescending then list = list:OrderByDescending(opts.orderByDesc) end
  if opts.skip then list = list:Skip(opts.skip) end
  if opts.take then list = list:Take(opts.take) end
  return list:ToArray()
end

-- Registration via ClassProvide; interface alias provided automatically
local function RegisterProspectsDataProvider()
  if not Addon or not Addon.ClassProvide then return end
  if not (Addon.IsProvided and Addon.IsProvided('ProspectsDataProvider')) then
    Addon.ClassProvide('ProspectsDataProvider', ProspectsDataProvider, { lifetime = 'SingleInstance', meta = { layer='Infrastructure', role='read-model' } })
  end
end

RegisterProspectsDataProvider()
Addon._RegisterProspectsDataProvider = RegisterProspectsDataProvider
return ProspectsDataProvider
