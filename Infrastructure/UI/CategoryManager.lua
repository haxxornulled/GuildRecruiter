-- Infrastructure/UI/CategoryManager.lua
-- Thin DI shim mapping UI.CategoryManager to Tools.CategoryManager.
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

if Addon and Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('UI.CategoryManager')) then
  Addon.safeProvide('UI.CategoryManager', function(sc)
    return sc:Resolve('Tools.CategoryManager')
  end, { lifetime = 'SingleInstance', meta = { layer = 'UI', area = 'shim', alias = true } })
end

return true
