-- Infrastructure/Persistence/DataPager.lua — Central paging service for large datasets
-- Provides cursor-based paging over prospects and blacklist. Keeps ProspectsService clean.
local __p = { ... }
local ADDON_NAME, Addon = __p[1], __p[2]

local function slice(list, startIndex, count)
  local out, n = {}, 0
  local i = (startIndex and startIndex > 0) and startIndex or 1
  while list[i] and n < count do n = n + 1; out[n] = list[i]; i = i + 1 end
  local nextCursor = list[i] and i or nil
  return out, nextCursor
end

local function CreateDataPager(scope)
  local self = {}

  local function getBus() return (scope and scope.Resolve and scope:Resolve('EventBus')) or (Addon.Get and Addon.Get('EventBus')) end
  local function getLogger()
    local base = Addon.Get and Addon.Get('Logger') or nil
    return base and base:ForContext('Persistence.DataPager') or nil
  end
  local function logDebug(msg, bag) local l=getLogger(); local fn=l and l.Debug; if type(fn)=='function' then if bag then fn(l,msg,bag) else fn(l,msg) end end end

  local function getProspectsProvider()
    if scope and scope.Resolve then
      local ok, p = pcall(function() return scope:Resolve('ProspectsDataProvider') end)
      if ok and p then return p end
    end
    return Addon.Get and Addon.Get('ProspectsDataProvider') or nil
  end

  local function getProspectsService()
    if scope and scope.Resolve then
      local ok, s = pcall(function() return scope:Resolve('ProspectsService') end)
      if ok and s then return s end
    end
    return Addon.Get and Addon.Get('ProspectsService') or nil
  end

  local function getBlacklistArray()
    local svc = getProspectsService(); if not svc or not svc.GetBlacklist then return {} end
    local map = svc:GetBlacklist() or {}
    local list = {}
    for guid,e in pairs(map) do list[#list+1] = { guid = guid, reason = e.reason, timestamp = e.timestamp } end
    table.sort(list, function(a,b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    return list
  end

  -- Public API
  -- kind: 'prospects' | 'blacklist'
  function self:GetPage(kind, pageSize, cursor, opts)
    pageSize = tonumber(pageSize) or 50
    local k = tostring(kind)
    if k == 'blacklist' then
      local list = getBlacklistArray()
      return slice(list, cursor, pageSize)
    else
      local provider = getProspectsProvider()
      local list = (provider and provider.GetAll and provider:GetAll()) or {}
      -- Optional sorting based on opts
      if opts and opts.sort == 'lastSeen' then table.sort(list, function(a,b) return (a.lastSeen or 0) > (b.lastSeen or 0) end) end
      return slice(list, cursor, pageSize)
    end
  end

  -- Shortcuts
  function self:PageProspects(pageSize, cursor, opts) return self:GetPage('prospects', pageSize, cursor, opts) end
  function self:PageBlacklist(pageSize, cursor, opts) return self:GetPage('blacklist', pageSize, cursor, opts) end

  -- Subscribe to events if we later keep indexes; placeholder for future
  local function subscribe() local bus=getBus(); if not bus or not bus.Subscribe then return end bus:Subscribe('Prospects.Changed', function() logDebug('dataset changed') end, { namespace='DataPager' }) end
  subscribe()

  return self
end

local function Register()
  if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('DataPager')) then
    Addon.provide('DataPager', function(scope) return CreateDataPager(scope) end, { lifetime = 'SingleInstance' })
  end
end

Addon._RegisterDataPager = Register
Register()
return Register
