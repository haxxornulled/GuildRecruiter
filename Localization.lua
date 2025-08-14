-- Localization.lua - placeholder scaffold for future translations
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local L = {}
-- Group labels
L.GROUP_UI = 'UI'
L.GROUP_ADMIN = 'Admin'
L.GROUP_DATA = 'Data'
L.GROUP_DEBUG = 'Debug'
L.GROUP_MISC = 'Misc'

-- Command description override examples (uncomment & translate as needed)
-- L.CMD_UI_DESC = 'Open the primary interface'
-- L.CMD_STATS_DESC = 'Show recruitment statistics'
-- L.CMD_EXPORT_DESC = 'Export command metadata'

Addon.L = Addon.L or L -- only set if not already provided by a locale pack
return L
