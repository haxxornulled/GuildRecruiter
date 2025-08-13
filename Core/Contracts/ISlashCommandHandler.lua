-- Core/Contracts/ISlashCommandHandler.lua
-- C#-style interface contract for slash command handlers

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local Interface = (Addon and Addon.Interface) or function(name, methods)
	local m = {} ; for _,v in ipairs(methods) do m[v]=true end
	return { __interface=true, __name=name, __methods=m }
end

local ISlashCommandHandler = Interface("ISlashCommandHandler", {
	"Handle",
	"Help",
})

if Addon.provide then Addon.provide("Core.Contracts.ISlashCommandHandler", ISlashCommandHandler) end
return ISlashCommandHandler
