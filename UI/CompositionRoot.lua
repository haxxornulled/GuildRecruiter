-- UI/CompositionRoot.lua
-- Composition Root owned by the UI layer (Clean Architecture style):
-- defines which services are registered and in what order.
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})
-- luacheck: pop
Addon = Addon or _G[ADDON_NAME] or {}

-- Reuse existing registration helpers exposed on Addon (set up by infra files)
local specs = {
  { key = "Core", register = function() if Addon.safeProvide then Addon.safeProvide("Core", function() return Core end, { lifetime = "SingleInstance" }) end end, resolve = false },
  { key = "IConfiguration", register = Addon._RegisterIConfiguration, resolve = false },
  { key = "SavedVarsService", register = Addon._RegisterSavedVarsService, resolve = false },
  { key = "Config", register = Addon._RegisterConfig, resolve = false },
  { key = "Logger", register = Addon._RegisterLogger, resolve = false },
  { key = "EventBus", register = Addon._RegisterEventBus, resolve = false },
  { key = "Clock", register = function() end, resolve = false }, -- self-registers on load
  { key = "Scheduler", register = Addon._RegisterScheduler, resolve = false },
  { key = "RuntimeCaps", register = function() end, resolve = false }, -- self-registers on load
  { key = "ChatRouting", register = function() end, resolve = false }, -- self-registers on load
  { key = "ProspectsService", register = function() end, resolve = false }, -- self-registers on load
  { key = "ProspectsDataProvider", register = Addon._RegisterProspectsDataProvider, resolve = false },
  { key = "Recruiter", register = Addon._RegisterRecruiter, resolve = false },
  { key = "InviteService", register = Addon._RegisterInviteService, resolve = false },
  { key = "Options", register = Addon._RegisterOptions, resolve = false },
}

Addon._ServiceSpecs = specs -- override default registry with UI-owned composition
return specs
