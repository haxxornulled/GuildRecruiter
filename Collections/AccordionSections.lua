-- Collections/AccordionSections.lua
-- Narrowly scoped wrapper for accordion section frames (formerly SectionCollection)
-- Provides stable interface regardless of backing container (List vs plain table)
local _, Addon = ...
local List = Addon.require and Addon.require("Collections.List")

local AccordionSections = {}
AccordionSections.__index = AccordionSections

function AccordionSections.new()
  return setmetatable({ _list = (List and List.new() or {} ) }, AccordionSections)
end

function AccordionSections:Add(sec)
  if self._list.Add then self._list:Add(sec) else table.insert(self._list, sec) end
  return self
end

function AccordionSections:ForEach(fn)
  if self._list.Count then
    for i=1,self._list:Count() do fn(self._list:Get(i), i) end
  else
    for i, v in ipairs(self._list) do fn(v, i) end
  end
end

function AccordionSections:Count()
  return (self._list.Count and self._list:Count()) or #self._list
end

function AccordionSections:Get(i)
  return (self._list.Get and self._list:Get(i)) or self._list[i]
end

-- Removal by index (1-based). Returns removed section or nil.
function AccordionSections:RemoveAt(index)
  if self._list.RemoveAt then
    local sec = self:Get(index)
    self._list:RemoveAt(index)
    return sec
  else
    if index < 1 then return nil end
    local t = self._list
    if index > #t then return nil end
    local sec = t[index]
    table.remove(t, index)
    return sec
  end
end

-- Remove by predicate; returns count removed.
function AccordionSections:RemoveWhere(pred)
  local removed = 0
  for i = self:Count(), 1, -1 do
    local sec = self:Get(i)
    if pred(sec, i) then self:RemoveAt(i); removed = removed + 1 end
  end
  return removed
end

Addon.provide("AccordionSections", AccordionSections, { lifetime = "SingleInstance" })
pcall(Addon.provide, "Collections.AccordionSections", AccordionSections, { lifetime = "SingleInstance" })
Addon.AccordionSections = AccordionSections
return AccordionSections
