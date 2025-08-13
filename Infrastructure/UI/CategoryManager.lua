-- Infrastructure/UI/CategoryManager.lua — DI registration shim
local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

-- Reuse tools/CategoryManager implementation, but provide a UI-scoped DI key as well
if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('UI.CategoryManager')) then
  Addon.provide('UI.CategoryManager', function()
    -- Resolve lazily at use time; do NOT call Addon.require here to avoid building the container during registration.
    return Addon.Get and Addon.Get('Tools.CategoryManager')
  end, { lifetime='SingleInstance' })
end
-- No return here; this file is a DI registration shim only.
