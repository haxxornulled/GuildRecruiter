-- Core/Collections/LRU.lua — Lightweight LRU cache (no WoW APIs)
-- Usage:
--   local LRU = Addon.require and Addon.require('LRU')
--   local cache = LRU.New(1000)
--   cache:Set(key, value)
--   local v = cache:Get(key)

local __params = { ... }
local _, Addon = __params[1], __params[2]
Addon = Addon or {}

local function assertf(cond, msg) if not cond then error(msg, 2) end end

local Node = {}
Node.__index = Node
function Node.new(k, v) return setmetatable({ k=k, v=v, prev=nil, next=nil }, Node) end

local LRU = {}
LRU.__index = LRU

function LRU.new(capacity)
  capacity = tonumber(capacity) or 128
  if capacity < 16 then capacity = 16 end
  local self = setmetatable({
    _cap = capacity,
    _map = {},
    _head = nil, -- most recent
    _tail = nil, -- least recent
    _count = 0,
  }, LRU)
  return self
end

local function removeNode(self, node)
  local p, n = node.prev, node.next
  if p then p.next = n else self._head = n end
  if n then n.prev = p else self._tail = p end
  node.prev, node.next = nil, nil
end

local function pushFront(self, node)
  node.prev, node.next = nil, self._head
  if self._head then self._head.prev = node else self._tail = node end
  self._head = node
end

function LRU:Get(key)
  local node = self._map[key]
  if not node then return nil end
  removeNode(self, node)
  pushFront(self, node)
  return node.v
end

function LRU:Set(key, value)
  local node = self._map[key]
  if node then
    node.v = value
    removeNode(self, node)
    pushFront(self, node)
    return
  end
  node = Node.new(key, value)
  self._map[key] = node
  pushFront(self, node)
  self._count = self._count + 1
  if self._count > self._cap then
    local evict = self._tail
    if evict ~= nil then
      local k = (type(evict) == 'table') and rawget(evict, 'k') or nil
      removeNode(self, evict)
      if k ~= nil then self._map[k] = nil end
      self._count = self._count - 1
    end
  end
end

function LRU:Has(key) return self._map[key] ~= nil end
function LRU:Size() return self._count end
function LRU:Capacity() return self._cap end
function LRU:Clear()
  self._map = {}
  self._head = nil
  self._tail = nil
  self._count = 0
end

if Addon and Addon.provide then
  Addon.provide('LRU', { New = function(capacity) return LRU.new(capacity) end, _type='LRU' })
end

return LRU
