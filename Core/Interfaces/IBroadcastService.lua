-- Core/Interfaces/IBroadcastService.lua
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}
local Interface = (Addon and Addon.Interface) or function(name, methods) local m={} for _,v in ipairs(methods) do m[v]=true end return { __interface=true, __name=name, __methods=m } end
-- Methods kept minimal; InviteService previously owned this logic.
-- Start/Stop manage rotation; BroadcastOnce triggers immediate send; IsRunning state; NextInterval (optional for UI);
-- Configure message keys uses underlying config.
local IBroadcastService = Interface('IBroadcastService', {
  'IsRunning','StartRotation','StopRotation','BroadcastOnce','GetLastBroadcast','GetLastBroadcastAt','GetLastBroadcastChannel','Start','Stop'
})
return IBroadcastService
