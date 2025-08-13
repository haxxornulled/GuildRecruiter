-- Core/Interfaces/IScheduler.lua
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}
local Interface = (Addon and Addon.Interface) or function(name, methods) local m={} for _,v in ipairs(methods) do m[v]=true end return { __interface=true, __name=name, __methods=m } end
local IScheduler = Interface('IScheduler', {
  'Start','Stop','NextTick','After','Every','Cancel','CancelNamespace','Debounce','Throttle','Coalesce','Count'
})
if Addon.provide then Addon.provide('IScheduler', IScheduler) end
return IScheduler
