-- .luacheckrc
-- WoW addon environment globals & lint preferences
std = "lua51"

-- Globals provided by the WoW client or this addon at runtime.
globals = {
  -- Addon namespace & saved variables
  "GuildRecruiter", "GuildRecruiterDB",
  -- Frames / UI
  "CreateFrame", "DEFAULT_CHAT_FRAME", "SlashCmdList", "SLASH_RELOADUI1", "UIParent",
  -- UI Fonts/Textures/Helpers
  "ChatFontNormal", "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall",
  "UIDropDownMenu_SetWidth", "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
  "UIDropDownMenu_SetSelectedID", "UIDropDownMenu_AddButton",
  -- UI popups / reload
  "StaticPopup_Show", "StaticPopupDialogs", "ReloadUI",
  -- Timers
  "C_Timer",
  -- Utility / API
  "EnumerateServerChannels", "IsInGuild", "UnitName", "UnitGUID", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster", "SendChatMessage", "time",
  "strsplit", "CreateColor", "SetPortraitTexture", "UnitClass", "CLASS_ICON_TCOORDS",
  -- Addon message variants
  "C_ChatInfo", "SendAddonMessage", "RegisterAddonMessagePrefix",
  -- Misc constants / tables
  "INVITE", "RAID_CLASS_COLORS", "LE_PARTY_CATEGORY_HOME",
  -- Core exported table (provided in Core.lua)
  "Core"
}

-- Mark additional read-only globals (provided earlier in load order)
read_globals = {
  "Core"
}

-- Allow defining globals at top level (addon pattern) without warnings.
allow_defined_top = true

-- Treat arguments starting with '_' as intentionally unused.
unused_args = false

-- You can selectively ignore warning codes here if desired.
-- Reference: https://github.com/lunarmodules/luacheck#warning-codes
-- ignore = { "111" } -- example: unused argument

-- Per-folder rules to enforce layer boundaries
files = {
  -- UI: allow UI globals, but warn on system/platform APIs if they appear
  ["UI/**/*.lua"] = {
    globals = {
      "CreateFrame", "UIParent",
      "ChatFontNormal", "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall",
      "UIDropDownMenu_SetWidth", "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
      "UIDropDownMenu_SetSelectedID", "UIDropDownMenu_AddButton",
      "SetPortraitTexture", "UnitClass", "CLASS_ICON_TCOORDS",
      "StaticPopup_Show", "StaticPopupDialogs", "ReloadUI",
    },
    -- Flag platform/system APIs if used in UI
    read_globals = { "Core" },
    ignore = {},
    -- Disallow common system APIs (diagnostic-only: luacheck cannot fully block, but we can warn by not whitelisting them here)
  },
  -- Application: no WoW globals should be directly used
  ["Application/**/*.lua"] = {
    globals = { "Core" },
  },
  -- Core: pure Lua only
  ["Core/**/*.lua"] = {
    globals = { "Core" },
  },
  -- Infrastructure: allow platform APIs
  ["Infrastructure/**/*.lua"] = {
    globals = globals, -- inherit top-level globals, which include WoW APIs
  },
}

-- End of .luacheckrc
