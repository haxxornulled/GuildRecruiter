-- Core/Collections/DataStore.lua — Efficient in-memory keyed store with paging
-- Layer: Core (no WoW APIs). Use for large datasets, snapshot pagers, and caching sources.
-- Usage:
--   local DS = Addon.require and Addon.require('DataStore')
--   local store = DS.New({ keyOf = 'guid', order = 'insertion' })
--   store:Upsert({ guid = 'x', name = 'Alice' })
--   local page, next = store:Page(100)  -- first 100 in insertion order
--   local pager = store:NewPager({ order = 'key' }) ; local p1, done = pager:Next(200)

local __params = { ... }
local _, Addon = __params[1], __params[2]
Addon = Addon or {}

local function assertf(cond, msg)
  if not cond then error(msg, 2) end
end

local function KeySelectorFrom(cfg)
  local t = type(cfg)
  if t == 'string' then
    local field = cfg
    return function(item) return item and item[field] end
  elseif t == 'function' then
    return cfg
  else
    return nil
  end
end

local DataStore = {}
DataStore.__index = DataStore

-- cfg: { keyOf = string|function(item)->key, order='insertion'|'key', comparator=function(aKey,bKey)->bool }
function DataStore.new(cfg)
  cfg = cfg or {}
  local keyOf = KeySelectorFrom(cfg.keyOf)
  assertf(keyOf, 'DataStore.new: cfg.keyOf (string field or function) is required')
  local self = setmetatable({
    _keyOf = keyOf,
    _order = cfg.order == 'key' and 'key' or 'insertion',
    _cmp   = (type(cfg.comparator)=='function') and cfg.comparator or nil,
    _map   = {},     -- key -> item
    _pos   = {},     -- key -> position in _keys (for fast remove)
    _keys  = {},     -- insertion order of keys, may contain holes (false)
    _holes = 0,
    _count = 0,
    _ver   = 0,
    _sorted = nil,   -- cached array of keys sorted by key/comparator
    _sortedDirty = true,
  }, DataStore)
  return self
end

function DataStore:Count() return self._count end
function DataStore:Version() return self._ver end

function DataStore:Get(key) return self._map[key] end

function DataStore:Upsert(item)
  local key = self._keyOf(item)
  assertf(key ~= nil, 'DataStore.Upsert: keyOf(item) returned nil')
  local exists = (self._map[key] ~= nil)
  self._map[key] = item
  if not exists then
    local idx = #self._keys + 1
    self._keys[idx] = key
    self._pos[key] = idx
    self._count = self._count + 1
  end
  self._ver = self._ver + 1
  self._sortedDirty = true
  return not exists
end

function DataStore:RemoveByKey(key)
  local item = self._map[key]
  if not item then return false end
  self._map[key] = nil
  self._count = self._count - 1
  local p = self._pos[key]
  if p ~= nil then
    local idx = tonumber(p)
    if idx and self._keys[idx] == key then self._keys[idx] = false; self._holes = self._holes + 1 end
    self._pos[key] = nil
  end
  self._ver = self._ver + 1
  self._sortedDirty = true
  return true
end

function DataStore:Clear()
  self._map, self._pos, self._keys = {}, {}, {}
  self._holes, self._count = 0, 0
  self._ver = self._ver + 1
  self._sorted, self._sortedDirty = nil, true
end

-- Remove holes if they exceed 25% of the keys array
function DataStore:Compact()
  if self._holes == 0 then return 0 end
  local holesBefore = self._holes
  local newKeys, newPos = {}, {}
  local n = 0
  for i=1,#self._keys do
    local k = self._keys[i]
    if k then n = n + 1; newKeys[n] = k; newPos[k] = n end
  end
  self._keys, self._pos = newKeys, newPos
  self._holes = 0
  self._sortedDirty = true
  return holesBefore
end

local function copyKeysSkippingHoles(keys)
  local out, n = {}, 0
  for i=1,#keys do local k = keys[i]; if k then n=n+1; out[n]=k end end
  return out
end

local function ensureSorted(self)
  if not self._sortedDirty and self._sorted then return self._sorted end
  local list = copyKeysSkippingHoles(self._keys)
  local cmp
  if self._cmp then
    local userCmp = self._cmp
    cmp = function(a,b) return userCmp(a,b) end
  else
    cmp = function(a,b)
      if a == b then return false end
      return tostring(a) < tostring(b)
    end
  end
  table.sort(list, cmp)
  self._sorted = list
  self._sortedDirty = false
  return list
end

-- Internal: get ordered key-list view
local function getOrderKeys(self, order)
  order = order or self._order
  if order == 'key' or self._cmp then
    return ensureSorted(self)
  else
    return self._keys -- may contain holes; callers skip falsy entries
  end
end

-- Page through items in the chosen order.
-- cursor: 1-based index into the ordered key-view; nil/0 => start at 1
-- returns: items[], nextCursor or nil if done
function DataStore:Page(pageSize, cursor, opts)
  assertf(pageSize and pageSize > 0, 'DataStore.Page: pageSize>0 required')
  local order = opts and opts.order or nil
  local keys = getOrderKeys(self, order)
  local i = (cursor and cursor > 0) and cursor or 1
  local out, n = {}, 0
  local taken = 0
  local total = #keys
  if keys == self._keys then
    -- skipping holes
    while i <= total and taken < pageSize do
      local k = keys[i]
      if k then
        local v = self._map[k]
        if v ~= nil then n=n+1; out[n]=v; taken=taken+1 end
      end
      i = i + 1
    end
  else
    while i <= total and taken < pageSize do
      local k = keys[i]
      local v = self._map[k]
      if v ~= nil then n=n+1; out[n]=v; taken=taken+1 end
      i = i + 1
    end
  end
  local nextCursor = (i <= total) and i or nil
  -- Compact if too many holes (lazy heuristic)
  if self._holes > 0 and (#self._keys >= 32) and (self._holes * 4 >= #self._keys) then self:Compact() end
  return out, nextCursor
end

-- Snapshot pager that is immune to concurrent modifications.
function DataStore:NewPager(opts)
  local order = opts and opts.order or nil
  local keys = getOrderKeys(self, order)
  -- Freeze a snapshot of existing keys at creation time
  local snapshot = {}
  local n = 0
  for i=1,#keys do local k = keys[i]; if k and self._map[k] ~= nil then n=n+1; snapshot[n]=k end end
  local idx = 1
  local function Next(pageSize)
    assertf(pageSize and pageSize>0, 'pager.Next: pageSize>0 required')
    local out, c = {}, 0
    local total = #snapshot
    while idx <= total and c < pageSize do
      local k = snapshot[idx]; idx = idx + 1
      local v = self._map[k]
      if v ~= nil then c = c + 1; out[c] = v end
    end
    return out, (idx > total)
  end
  return { Next = Next, Count = function() return #snapshot end }
end

function DataStore:Stats()
  return { count = self._count, holes = self._holes, keysLen = #self._keys, version = self._ver }
end

-- Export via DI
if Addon and Addon.provide then
  Addon.provide('DataStore', { New = function(cfg) return DataStore.new(cfg) end, _type = 'DataStore' })
end

return DataStore
