-- Collections/Queue.lua — FIFO queue with O(1) amortized ops (SOLID-friendly wrapper)
local _, Addon = ...

local List = Addon.require and Addon.require("Collections.List") -- optional for ToList()

local Queue = {}
Queue.__index = Queue

function Queue.new()
  return setmetatable({ _data = {}, _head = 1, _tail = 0, _count = 0 }, Queue)
end

function Queue:Enqueue(item)
  self._tail = self._tail + 1
  self._data[self._tail] = item
  self._count = self._count + 1
  return self
end

function Queue:Dequeue()
  if self._count == 0 then return nil end
  local item = self._data[self._head]
  self._data[self._head] = nil
  self._head = self._head + 1
  self._count = self._count - 1
  -- Compact occasionally to avoid unbounded growth
  if self._count == 0 then
    self._head, self._tail = 1, 0
  elseif self._head > 64 and (self._head > self._tail / 2) then
    local newData = {}
    local j = 1
    for i = self._head, self._tail do newData[j] = self._data[i]; j = j + 1 end
    self._data = newData
    self._head = 1
    self._tail = j - 1
  end
  return item
end

function Queue:Peek()
  if self._count == 0 then return nil end
  return self._data[self._head]
end

function Queue:Count() return self._count end
function Queue:IsEmpty() return self._count == 0 end

function Queue:Clear()
  self._data = {}; self._head = 1; self._tail = 0; self._count = 0; return self
end

function Queue:ToList()
  if not List then return nil end
  local arr = {}
  local j = 1
  for i = self._head, self._tail do arr[j] = self._data[i]; j = j + 1 end
  return List.new(arr)
end

function Queue:Iter()
  local i = self._head - 1
  return function()
    i = i + 1
    if i <= self._tail then return self._data[i] end
  end
end

-- Register both simple and namespaced keys for consistency
Addon.provide("Queue", Queue, { lifetime = "SingleInstance" })
pcall(Addon.provide, "Collections.Queue", Queue, { lifetime = "SingleInstance" })
return Queue
