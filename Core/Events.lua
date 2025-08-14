-- Core/Events.lua
-- Central enumeration of event name constants used across the addon to reduce magic strings.
-- Keep Core pure (no WoW API). Provided via DI key 'Events'.

local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})
Addon = Addon or _G[ADDON_NAME] or {}

---@class GR_EventConstants
local Events = {
  Prospects = {
    Changed = 'Prospects.Changed',            -- (action, guid)
    Manager = 'ProspectsManager.Event',       -- (action, guid)
  },
  Config = {
    Changed = 'ConfigChanged',                -- (key, value)
    Ready   = 'ConfigReady',
  },
  BootstrapStatic = {
    ServicesReady = ADDON_NAME .. '.ServicesReady',
    Ready = ADDON_NAME .. '.Ready',
  },
}

-- Backwards compatibility function form (return existing static table)
function Events.Bootstrap() return Events.BootstrapStatic end

function Events.Diagnostics()
  return {
    prospectEvents = Events.Prospects,
    bootstrap = Events.BootstrapStatic,
  }
end

-- Removed dynamic flattening/back-compat aliasing; reference hierarchical keys directly.
Events.Flat = nil

-- DI registration (idempotent)
if Addon and Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('Events')) then
  Addon.safeProvide('Events', function() return Events end, { lifetime = 'SingleInstance', meta = { layer='Core', role='constants' } })
end

return Events
