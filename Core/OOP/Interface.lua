-- Core/OOP/Interface.lua
-- Simple interface descriptor for optional runtime conformance checks.
local firstArg = select(1, ...)
local secondArg = select(2, ...)
local ADDON_NAME = type(firstArg)=='string' and firstArg or 'GuildRecruiter'
local Addon = (type(firstArg)=='table' and firstArg) or secondArg or _G[ADDON_NAME] or _G.GuildRecruiter or {}

local _iface_seq = 0

local function Interface(name, methods)
  assert(type(name)=='string' and name~='', 'Interface: name required')
  assert(type(methods)=='table', 'Interface: methods table required')
  local map = {}
  for _,m in ipairs(methods) do
    assert(type(m)=='string' and m~='', 'Interface: method names must be strings')
    map[m]=true
  end
  _iface_seq = _iface_seq + 1
  local id = ("IF:%s:%d"):format(name, _iface_seq)
  return { __interface = true, __name = name, __methods = map, __id = id }
end

local function Implements(obj, iface)
  if not iface or not iface.__interface then return false end
  for m,_ in pairs(iface.__methods) do
    if type(obj[m]) ~= 'function' then return false end
  end
  return true
end

local function Require(obj, iface)
  assert(Implements(obj, iface), ('Object does not implement interface %s'):format(iface and iface.__name or '?'))
  return obj
end

local api = { Interface = Interface, Implements = Implements, Require = Require }

Addon.provide = Addon.provide or function(key, value) Addon[key]=value end
-- Also export on the Addon namespace for non-DI consumers (pre-DI, contracts phase)
Addon.Interface = Interface
Addon.TypeCheck = { Implements = Implements, Require = Require }
-- Provide the Interface constructor as a constant function (do not invoke during resolve)
Addon.provide('Interface', function() return Interface end)
Addon.provide('TypeCheck', { Implements = Implements, Require = Require })

return api
