-- Infrastructure/UI/ButtonLib.lua — skinnable button helper
local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})
-- Map the existing Tools.ButtonLib to a UI-scoped DI key for cleanliness.
-- Use a lazy resolver to avoid load-order coupling. Do NOT call Addon.require at file load.
if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('UI.ButtonLib')) then
  Addon.provide('UI.ButtonLib', function()
    return (Addon.Get and Addon.Get('Tools.ButtonLib')) -- lazy/safe
  end, { lifetime='SingleInstance' })
end
-- No immediate return that forces DI resolution at load time.
-- The UI.ButtonLib will be resolved via DI (Addon.require('UI.ButtonLib')) when needed.
