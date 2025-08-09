-- InviteService.lua — Broadcast rotation + targeted invites (+rich bus events)
-- Factory-based registration for DI container

local ADDON_NAME, Addon = ...

local CTL = _G.ChatThrottleLib -- optional

local function now() return GetTime() end
local function now_s() return time() end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

local function fmtNameRealm(name, realm)
  if not name or name == "" then return nil end
  if realm and realm ~= "" then return name.."-"..realm end
  return name
end

local function guildName() return GetGuildInfo("player") or (GetRealmName() .. " Guild") end

local function renderTemplate(tpl, bag)
  if type(tpl) ~= "string" then return "" end
  return (tpl:gsub("{([%w_%.]+)}", function(k)
    local v = bag and bag[k]; return v ~= nil and tostring(v) or "{"..k.."}"
  end))
end

-- Map Config channel choice to a concrete target using ChatChannelHelper if present.
-- Returns an "info" table: { kind="CHANNEL"/"SAY"/..., id=<number|nil>, display=<string> }
local function chooseChannel(core, cfg)
  -- Preferred path: ChatChannelHelper
  local chan = core.TryResolve and core.TryResolve("ChatChannelHelper")
  if chan and chan.Resolve then
    local spec = cfg:Get("broadcastChannel", "AUTO")
    local info = chan:Resolve(spec)
    if info and info.kind then return info end
  end

  -- Fallback heuristic (old behavior)
  local ch = cfg:Get("broadcastChannel", "AUTO")
  if ch ~= "AUTO" then
    -- Standard types
    local u = tostring(ch):upper()
    if u == "SAY" or u == "YELL" or u == "GUILD" or u == "OFFICER" or u == "PARTY" or u == "RAID" or u == "INSTANCE_CHAT" then
      return { kind = u, id = nil, display = u }
    end
    -- CHANNEL:<name>
    local name = ch:match("^CHANNEL:(.+)$")
    if name and name ~= "" then
      local id = GetChannelName and GetChannelName(name) or 0
      if id and id > 0 then
        return { kind = "CHANNEL", id = id, display = string.format("%s (%d)", name, id) }
      else
        return { kind = "CHANNEL", id = nil, display = name }
      end
    end
  end

  -- AUTO: try Trade, General, else SAY
  local inInstance = IsInInstance and select(1, IsInInstance()) and true or false
  if inInstance then return { kind = "INSTANCE_CHAT", id = nil, display = "Instance Chat" } end

  local idTrade = GetChannelName and GetChannelName("Trade") or 0
  if idTrade and idTrade > 0 then return { kind = "CHANNEL", id = idTrade, display = "Trade ("..tostring(idTrade)..")" } end

  local idGeneral = GetChannelName and GetChannelName("General") or 0
  if idGeneral and idGeneral > 0 then return { kind = "CHANNEL", id = idGeneral, display = "General ("..tostring(idGeneral)..")" } end

  return { kind = "SAY", id = nil, display = "Say" }
end

-- Send a message using either ChatThrottleLib (if present) or SendChatMessage.
-- Expects "info" from chooseChannel().
local function sendToChannel(msg, info)
  if not msg or msg == "" then return false, "empty" end
  if not info or not info.kind then return false, "no-channel" end

  local which, arg = info.kind, nil
  if which == "CHANNEL" then
    arg = info.id
    if (not arg or arg == 0) and info.display then
      -- Try to resolve an id from display/name when helper didn't provide one
      local nameOnly = tostring(info.display):gsub(" %(%d+%)%s*%[?off%]?","") -- strip " (id) [off]" if present
      local try = GetChannelName and GetChannelName(nameOnly) or 0
      if try and try > 0 then arg = try end
    end
    if not arg or arg == 0 then return false, "channel-missing" end
  end

  if CTL and CTL.SendChatMessage then
    local ok, err = pcall(function()
      if which == "CHANNEL" then
        CTL:SendChatMessage("NORMAL", "GR", msg, which, nil, arg)
      else
        CTL:SendChatMessage("NORMAL", "GR", msg, which)
      end
    end)
    return ok and true or false, (ok and nil or tostring(err))
  else
    local ok, err = pcall(SendChatMessage, msg, which, nil, arg)
    return ok and true or false, (ok and nil or tostring(err))
  end
end

local function doInvite(nameRealm)
  if C_PartyInfo and C_PartyInfo.InviteUnit then
    local ok, err = pcall(C_PartyInfo.InviteUnit, nameRealm)
    return ok and true or false, (ok and nil or tostring(err))
  end
  return false, "no-invite-api"
end

-- Factory function for DI container (TRUE lazy resolution)
local function CreateInviteService()
    -- Lazy dependency accessors - resolved only when actually used
    local function getLog()
      return Addon.require("Logger"):ForContext("Subsystem","InviteService")
    end
    
    local function getBus()
      return Addon.require("EventBus")
    end
    
    local function getScheduler()
      return Addon.require("Scheduler")
    end
    
    local function getConfig()
      return Addon.require("Config")
    end
    
    local function getRecruiter()
      return Addon.require("Recruiter")
    end

  local self = {}
  local running = false
  local timerTok = nil
  local lastSentAt = 0
  local cooldownMin = 10  -- anti-spam safety for broadcasts

  local cycleIndex = 1

  local function randInterval()
    local base = tonumber(getConfig():Get("broadcastInterval", 300)) or 300
    local jitterPct = clamp(tonumber(getConfig():Get("jitterPercent", 0.15)) or 0, 0, 0.50)
    local jitter = base * jitterPct
    local delta = (math.random() * 2 - 1) * jitter
    return clamp(base + delta, math.max(30, cooldownMin), 1800)
  end

  local function pickBag(p)
    local bag = { Guild = guildName(), Date = date("%Y-%m-%d"), Time = date("%H:%M") }
    if p then
      bag.Player = p.name
      bag.Realm  = p.realm or GetRealmName()
      bag.Class  = p.classToken or p.className
      bag.Level  = p.level
    end
    return bag
  end

  local function nextMessage()
    local keys = { "customMessage1", "customMessage2", "customMessage3" }
    for n = 0, #keys-1 do
      local idx = ((cycleIndex - 1 + n) % #keys) + 1
      local txt = getConfig():Get(keys[idx], "")
      if type(txt) == "string" and txt ~= "" then
        cycleIndex = (idx % #keys) + 1
        return txt
      end
    end
    return nil
  end

  local function scheduleNext()
    if not running then return end
    local delay = randInterval()
    timerTok = getScheduler():After(delay, function()
      timerTok = nil
      self:BroadcastOnce()
      scheduleNext()
    end, { namespace = "InviteService" })
  end

  local function setRunning(v)
    if running == v then return end
    running = v
    getBus():Publish("InviteService.StateChanged", running)
  end

  -- ===== Public API =====

  function self:IsRunning() return running end

  function self:StartRotation()
    if running then return end
    setRunning(true)
    scheduleNext()
    getLog():Info("Broadcast rotation started")
  end

  function self:StopRotation()
    if not running then return end
    setRunning(false)
    if timerTok then getScheduler():Cancel(timerTok); timerTok = nil end
    getScheduler():CancelNamespace("InviteService")
    getLog():Info("Broadcast rotation stopped")
  end

  function self:BroadcastOnce()
    if not getConfig():Get("broadcastEnabled", false) then
      getBus():Publish("InviteService.BroadcastSkipped", "disabled"); return false, "disabled"
    end
    local since = now() - lastSentAt
    if since < cooldownMin then
      local why = ("cooldown (%ds left)"):format(math.ceil(cooldownMin - since))
      getBus():Publish("InviteService.BroadcastSkipped", why); return false, why
    end

    local tpl = nextMessage()
    if not tpl then
      getBus():Publish("InviteService.BroadcastSkipped", "no-message")
      getLog():Warn("Broadcast skipped: no configured message")
      return false, "no-message"
    end

    local msg = renderTemplate(tpl, pickBag(nil))
    local info = chooseChannel(nil, getConfig())
    local ok, err = sendToChannel(msg, info)
    if ok then
      lastSentAt = now()
      getBus():Publish("InviteService.BroadcastSent", { channel = info, message = msg, at = now_s() })
      getLog():Info("Broadcast via {Channel}: {Msg}", { Channel = info.display or info.kind, Msg = msg })
      return true
    else
      getBus():Publish("InviteService.BroadcastSkipped", err or "send-failed")
      getLog():Warn("Broadcast failed {Err}", { Err = tostring(err) })
      return false, err
    end
  end

  -- Invite a prospect by GUID (emits rich events)
  function self:InviteGUID(guid, opts)
    opts = opts or {}
    local p = getRecruiter():GetProspect(guid)
    if not p then return false, "no-prospect" end
    local target = fmtNameRealm(p.name, p.realm)
    if not target then return false, "bad-name" end

    getBus():Publish("InviteService.InviteAttempt", { guid = guid, target = target })

    if opts.whisper ~= false then
      local tpl = getConfig():Get("whisperTemplate", getConfig():Get("customMessage1", "Hey {Player}, {Guild} is recruiting!"))
      local text = renderTemplate(tpl, pickBag(p))
      pcall(SendChatMessage, text, "WHISPER", nil, target)
      getBus():Publish("InviteService.WhisperSent", { guid = guid, target = target, message = text })
    end

    local ok, err = doInvite(target)
    if ok then
      p.status = "Invited"
      getBus():Publish("InviteService.Invited", guid, target)
      getBus():Publish("Recruiter.ProspectUpdated", guid, p)
      getLog():Info("Invited {Target}", { Target = target })
      return true
    else
      getBus():Publish("InviteService.InviteFailed", guid, target, err or "invite-error")
      getLog():Warn("Invite failed {Target}: {Err}", { Target = target, Err = tostring(err) })
      return false, err
    end
  end

  -- Invite arbitrary player (name, realm?)
  function self:InviteName(name, realm, opts)
    local target = fmtNameRealm(name, realm)
    if not target then return false, "bad-name" end

    getBus():Publish("InviteService.InviteAttempt", { guid = nil, target = target })

    if opts and opts.whisper then
      local tpl = getConfig():Get("whisperTemplate", getConfig():Get("customMessage1", "Hey {Player}, {Guild} is recruiting!"))
      local text = renderTemplate(tpl, { Player = name, Realm = realm or GetRealmName(), Guild = guildName() })
      pcall(SendChatMessage, text, "WHISPER", nil, target)
      getBus():Publish("InviteService.WhisperSent", { guid = nil, target = target, message = text })
    end

    local ok, err = doInvite(target)
    if ok then
      getBus():Publish("InviteService.Invited", nil, target)
      getLog():Info("Invited {Target}", { Target = target })
      return true
    else
      getBus():Publish("InviteService.InviteFailed", nil, target, err or "invite-error")
      getLog():Warn("Invite failed {Target}: {Err}", { Target = target, Err = tostring(err) })
      return false, err
    end
  end

  -- Lifecycle
  local function refresh()
    local enabled = getConfig():Get("broadcastEnabled", false) and true or false
    if enabled and not running then self:StartRotation()
    elseif (not enabled) and running then self:StopRotation() end
  end

  function self:Start()
    -- Dependency-free startup - just initialize state
    self._started = true
    getLog():Debug("InviteService ready")
  end

  function self:Stop()
    if timerTok then getScheduler():Cancel(timerTok); timerTok = nil end
    getScheduler():CancelNamespace("InviteService")
    setRunning(false)
    getLog():Debug("InviteService stopped")
  end

  return self
end

-- Registration function for Init.lua
local function RegisterInviteServiceFactory()
  if not Addon.provide then
    error("InviteService: Addon.provide not available")
  end
  
  Addon.provide("InviteService", CreateInviteService, { lifetime = "SingleInstance" })
  
  -- Lazy export (safe)
  Addon.InviteService = setmetatable({}, {
    __index = function(_, k) 
      if Addon._booting then
        error("Cannot access InviteService during boot phase")
      end
      local inst = Addon.require("InviteService"); return inst[k] 
    end,
    __call  = function(_, ...) return Addon.require("InviteService"), ... end
  })
end

-- Export registration function
Addon._RegisterInviteService = RegisterInviteServiceFactory

return RegisterInviteServiceFactory
