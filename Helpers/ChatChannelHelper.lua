-- ChatChannelHelper.lua — channel utilities (no Core require, DI-friendly)
local _, Addon = ...

local Channels = {}
Addon.ChatChannelHelper = Channels
if Addon.provide then Addon.provide("ChatChannelHelper", Channels) end

-- Standard chat types we expose
local STANDARD = { "SAY","YELL","GUILD","OFFICER","PARTY","RAID","INSTANCE_CHAT" }

-- Canonical names we care about for AUTO/aliases
local CANON = {
  TRADE_SERVICES = "Trade (Services)",
  TRADE          = "Trade",
  LFG            = "LookingForGroup",
  GENERAL        = "General",
  LOCALDEFENSE   = "LocalDefense",
  WORLDDEFENSE   = "WorldDefense",
}

local function trim(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$","%1")) end
local function Pretty(ct) return (ct:gsub("_"," "):lower():gsub("^%l", string.upper)) end

-- Build joined numbered channels: { {id, name, disabled}, ... }
local function JoinedChannelsRaw()
  local out, list, i = {}, { GetChannelList() }, 1
  while list[i] do
    local id, name, disabled = list[i], list[i+1], list[i+2]
    if type(id) == "number" and type(name) == "string" then
      out[#out+1] = { id = id, name = name, disabled = disabled and true or false }
    end
    i = i + 3
  end
  return out
end

local function JoinedChannels()
  local out = {}
  for _, ch in ipairs(JoinedChannelsRaw()) do
    if not ch.disabled then out[#out+1] = ch end
  end
  return out
end

local function FindJoinedByNames(candidates, includeDisabled)
  local pool = includeDisabled and JoinedChannelsRaw() or JoinedChannels()
  for _, want in ipairs(candidates or {}) do
    for _, ch in ipairs(pool) do
      if ch.name == want then return ch end
    end
  end
  return nil
end

-- ===== AUTO priority: Trade (Services) > Trade > LFG > Guild > Say =====
function Channels:GetAutoSpec()
  local t = FindJoinedByNames({ CANON.TRADE_SERVICES, CANON.TRADE })
  if t then return "CHANNEL:" .. t.name end
  local lfg = FindJoinedByNames({ CANON.LFG })
  if lfg then return "CHANNEL:" .. lfg.name end
  if IsInGuild and IsInGuild() then return "GUILD" end
  return "SAY"
end

function Channels:PickAuto() return self:Resolve(self:GetAutoSpec()) end

function Channels:Enumerate()
  local t = { { display = "AUTO (Trade > LFG > Guild > Say)", spec = "AUTO" }, }
  for _, ct in ipairs(STANDARD) do t[#t+1] = { display = Pretty(ct), spec = ct } end
  for _, ch in ipairs(JoinedChannels()) do
    t[#t+1] = { display = string.format("%s (%d)", ch.name, ch.id), spec = "CHANNEL:"..ch.name }
  end
  return t
end

function Channels:ParseUserInput(s)
  s = trim(s):upper()
  if s == "" then return nil end
  if s == "AUTO" then return "AUTO" end
  for _, ct in ipairs(STANDARD) do if s == ct then return s end end
  local ch = s:match("^CHANNEL:(.+)$"); if ch and #ch > 0 then return "CHANNEL:" .. trim(ch) end
  local alias = {
    TRADE = CANON.TRADE_SERVICES, GENERAL = CANON.GENERAL,
    LOCALDEFENSE = CANON.LOCALDEFENSE, WORLDDEFENSE = CANON.WORLDDEFENSE,
    LOOKINGFORGROUP = CANON.LFG, LFG = CANON.LFG,
  }
  if alias[s] then return "CHANNEL:" .. alias[s] end
  return nil
end

function Channels:Resolve(spec)
  local sp = trim(spec or "")
  if sp == "" or sp == "AUTO" then return self:PickAuto() end
  local u = sp:upper()
  for _, ct in ipairs(STANDARD) do
    if u == ct then return { kind = ct, id = nil, display = Pretty(ct) } end
  end
  local m = sp:match("^CHANNEL:(.+)$")
  if m then
    local token = trim(m); local asnum = tonumber(token)
    if asnum then
      for _, ch in ipairs(JoinedChannelsRaw()) do
        if ch.id == asnum then
          return { kind = "CHANNEL", id = ch.id, display = string.format("%s (%d)%s", ch.name, ch.id, ch.disabled and " [off]" or "") }
        end
      end
      return { kind = "CHANNEL", id = asnum, display = "Channel "..asnum }
    end
    local ch = FindJoinedByNames({ token }, true)
    if ch then
      return { kind = "CHANNEL", id = ch.id, display = string.format("%s (%d)%s", ch.name, ch.id, ch.disabled and " [off]" or "") }
    end
    return { kind = "CHANNEL", id = nil, display = token }
  end
  return { kind = "SAY", id = nil, display = "Say" }
end

-- EventBus notifications
local Bus = Addon.EventBus
if Bus and Bus.RegisterWoWEvent and Bus.Publish then
  Bus:RegisterWoWEvent("CHANNEL_UI_UPDATE",     function() Bus:Publish("ChannelsChanged") end)
  Bus:RegisterWoWEvent("PLAYER_GUILD_UPDATE",   function() Bus:Publish("ChannelsChanged") end)
  Bus:RegisterWoWEvent("PLAYER_ENTERING_WORLD", function() Bus:Publish("ChannelsChanged") end)
  Bus:RegisterWoWEvent("ZONE_CHANGED_NEW_AREA", function() Bus:Publish("ChannelsChanged") end)
end

return Channels
