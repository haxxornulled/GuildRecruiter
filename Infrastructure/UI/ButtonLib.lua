-- Infrastructure/UI/ButtonLib.lua
-- Thin DI shim that exposes Tools.ButtonLib under UI.ButtonLib for UI code.
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

if Addon and Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('UI.ButtonLib')) then
  Addon.safeProvide('UI.ButtonLib', function(sc)
    return sc:Resolve('Tools.ButtonLib')
  end, { lifetime = 'SingleInstance', meta = { layer = 'UI', area = 'shim', alias = true } })
end

return true
