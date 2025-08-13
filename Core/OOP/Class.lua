-- Core/OOP/Class.lua
-- Lightweight class helper: single inheritance, named classes, init ctor.
local firstArg = select(1, ...)
local secondArg = select(2, ...)
local ADDON_NAME = type(firstArg)=='string' and firstArg or 'GuildRecruiter'
local Addon = (type(firstArg)=='table' and firstArg) or secondArg or _G[ADDON_NAME] or _G.GuildRecruiter or {}

local function Class(name, base, def)
  if type(base) == 'table' and def == nil and (base.__name or base.init or base[1] == nil) then
    -- Form Class(name, def)
    def, base = base, nil
  end
  assert(type(name)=='string' and name ~= '', 'Class: name required')
  def = def or {}
  local cls = {}
  cls.__name = name
  cls.__base = base
  cls.__index = cls

  if base then
    setmetatable(cls, { __index = base })
  end

  for k,v in pairs(def) do cls[k]=v end

  local function construct(_, ...)
    local obj = setmetatable({}, cls)
    if obj.init then obj:init(...) end
    return obj
  end
  setmetatable(cls, { __call = construct })
  return cls
end

-- Provide through addon DI style registry if available
Addon.provide = Addon.provide or function(key, value) Addon[key]=value end
Addon.Class = Class
Addon.provide('Class', function() return Class end)

return Class
