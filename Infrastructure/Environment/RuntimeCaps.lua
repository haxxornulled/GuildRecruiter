-- Infrastructure/Environment/RuntimeCaps.lua
-- Runtime capability probe for WoW. Exposes environment facts and a /grcaps dump.
-- luacheck: push ignore 113 212/DEFAULT_CHAT_FRAME 212/SlashCmdList
local __args = { ... }
local ADDON_NAME, Addon = __args[1], (__args[2] or {})

local function CreateRuntimeCaps()
  local self = {}
  local caps = {}

  local function safeCall(fn)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c, d, e = pcall(fn)
    if ok then return a, b, c, d, e end
  end

  local function has(tbl, key, kind)
    local v = tbl and tbl[key]
    if kind == 'function' then return type(v) == 'function' end
    if kind == 'table' then return type(v) == 'table' end
    return v ~= nil
  end

  -- Basic APIs
  caps.HasCreateFrame = has(_G, 'CreateFrame', 'function')
  do
    local frame = rawget(_G, 'DEFAULT_CHAT_FRAME')
    caps.HasDEFAULT_CHAT_FRAME = (type(frame) == 'table') and (type(frame and frame.AddMessage) == 'function')
  end
  caps.HasC_Timer = has(_G, 'C_Timer', 'table') and has(_G.C_Timer, 'After', 'function')
  caps.HasGetTime = has(_G, 'GetTime', 'function')
  caps.HasTime = has(_G, 'time', 'function')

  -- Chat/addon messaging
  caps.HasC_ChatInfo = has(_G, 'C_ChatInfo', 'table')
  caps.HasSendAddonMessage = (caps.HasC_ChatInfo and has(_G.C_ChatInfo, 'SendAddonMessage', 'function')) or
  has(_G, 'SendAddonMessage', 'function')

  -- Unit/player
  caps.HasUnitName = has(_G, 'UnitName', 'function')
  caps.HasUnitGUID = has(_G, 'UnitGUID', 'function')

  -- Secure/lockdown
  caps.HasInCombatLockdown = has(_G, 'InCombatLockdown', 'function')

  -- Project/build info
  do
    local ver, build, date, toc = safeCall(_G.GetBuildInfo)
    caps.Version = ver
    caps.Build = build
    caps.BuildDate = date
    caps.InterfaceToc = toc
    -- Project flags (retail/classic variants)
    caps.WOW_PROJECT_ID = rawget(_G, 'WOW_PROJECT_ID')
    caps.WOW_PROJECT_MAINLINE = rawget(_G, 'WOW_PROJECT_MAINLINE')
    caps.WOW_PROJECT_CLASSIC = rawget(_G, 'WOW_PROJECT_CLASSIC')
    caps.WOW_PROJECT_WRATH_CLASSIC = rawget(_G, 'WOW_PROJECT_WRATH_CLASSIC')
  end

  -- Frame/event basics (don’t register unknown events; just check types)
  caps.HasFrameRegisterEvent = caps.HasCreateFrame -- if we can create frames, they will have RegisterEvent

  function self:Get(name, default)
    local v = caps[name]
    if v == nil then return default end
    return v
  end

  function self:Info()
    return caps
  end

  local function out(msg)
    local frame = rawget(_G, 'DEFAULT_CHAT_FRAME')
    if frame and frame.AddMessage then frame:AddMessage('|cff00ccff[GR][Caps]|r ' .. tostring(msg)) end
  end

  function self:Dump()
    out('Build ' .. tostring(caps.Version) .. ' (' .. tostring(caps.Build) .. ') TOC=' .. tostring(caps.InterfaceToc))
    out('Timers: C_Timer=' ..
    tostring(caps.HasC_Timer) .. ' GetTime=' .. tostring(caps.HasGetTime) .. ' time()=' .. tostring(caps.HasTime))
    out('Chat: C_ChatInfo=' .. tostring(caps.HasC_ChatInfo) .. ' SendAddonMessage=' .. tostring(caps.HasSendAddonMessage))
    out('Unit: UnitName=' .. tostring(caps.HasUnitName) .. ' UnitGUID=' .. tostring(caps.HasUnitGUID))
    out('Secure: InCombatLockdown=' .. tostring(caps.HasInCombatLockdown))
  end

  return self
end

if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('RuntimeCaps')) then
  Addon.provide('RuntimeCaps', function() return CreateRuntimeCaps() end, { lifetime = 'SingleInstance' })
end

-- Optional: slash command to dump
do
  local scl = _G and rawget(_G, 'SlashCmdList')
  if scl then
    _G.SLASH_GRCAPS1 = _G.SLASH_GRCAPS1 or '/grcaps'
    scl.GRCAPS = function()
      local ok, caps = pcall(function() return Addon.require and Addon.require('RuntimeCaps') end)
      if ok and caps and caps.Dump then caps:Dump() end
    end
  end
end

-- luacheck: pop
return CreateRuntimeCaps
