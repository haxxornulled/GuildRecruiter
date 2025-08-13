-- Core/Contracts/IEventBus.lua
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}
local Interface = (Addon and Addon.Interface) or function(name, methods) local m={} for _,v in ipairs(methods) do m[v]=true end return { __interface=true, __name=name, __methods=m } end
local IEventBus = Interface('IEventBus', {
  'Publish','Subscribe','Unsubscribe','UnsubscribeNamespace','ListEvents','HandlerCount','Diagnostics','RegisterWoWEvent'
})
if Addon.provide then Addon.provide('IEventBus', IEventBus) end
return IEventBus
