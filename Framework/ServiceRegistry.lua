-- Framework/ServiceRegistry.lua
-- Central list of DI service specs (in registration order) consumed by Init.lua / Bootstrap.
local __params = { ... }
local ADDON_NAME, Addon = __params[1], __params[2]
Addon = Addon or _G[ADDON_NAME] or {}

-- Each spec: key, register=function(), resolve=bool
local specs = {
  { key = "Core", register = function() if Addon.safeProvide then Addon.safeProvide("Core", function() return Core end, { lifetime = "SingleInstance" }) end end, resolve = false },
  -- Provide interface contracts early so implementations can alias against them
  { key = "IServiceProvider", register = Addon._RegisterIServiceProvider, resolve = false },
  { key = "IConfiguration", register = Addon._RegisterIConfiguration, resolve = false },
  { key = "SavedVarsService", register = Addon._RegisterSavedVarsService, resolve = false },
  { key = "Config", register = Addon._RegisterConfig, resolve = false },
  { key = "Logger", register = Addon._RegisterLogger, resolve = false },
  { key = "EventBus", register = Addon._RegisterEventBus, resolve = false },
  { key = "Clock", register = function() end, resolve = false }, -- self-registers on load
  { key = "Scheduler", register = Addon._RegisterScheduler, resolve = false },
  -- Unified prospects + blacklist data service (post-repository refactor)
  { key = "ProspectsService", register = function() end, resolve = false }, -- self-registers on load
  { key = "ProspectsManager", register = Addon._RegisterProspectsManager, resolve = false },
  { key = "ProspectsDataProvider", register = Addon._RegisterProspectsDataProvider, resolve = false },
  { key = "Recruiter", register = Addon._RegisterRecruiter, resolve = false },
  { key = "InviteService", register = Addon._RegisterInviteService, resolve = false },
  { key = "Options", register = Addon._RegisterOptions, resolve = false },
  -- Chat bridge and feed (UI consumption)
  { key = "ChatRouting", register = function() end, resolve = false }, -- self-registers on load
  { key = "ChatFeed", register = function() end, resolve = false },    -- self-registers on load
  { key = "ChatEventBridge", register = function() end, resolve = true }, -- self-registers on load
}

Addon._ServiceSpecs = specs
return specs
