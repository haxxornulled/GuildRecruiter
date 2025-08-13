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

local function chooseChannel(cfg)
  -- Preferred path: ChatChannelHelper (resolve lazily via Addon)
  local chan = (Addon and Addon.Get and Addon.Get("ChatChannelHelper")) or nil
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

-- Perform a GUILD invite (not a party invite). Tries modern and legacy APIs.
local function doInvite(nameRealm)
  if not nameRealm or nameRealm == "" then return false, "no-name" end
  if not IsInGuild or not IsInGuild() then return false, "not-in-guild" end
  -- nameRealm may be Name-Realm; some APIs prefer name only
  local nameOnly = nameRealm:match("^([^%-]+)") or nameRealm

  -- Preferred: C_GuildInfo.Invite (retail)
  if C_GuildInfo and C_GuildInfo.Invite then
    local ok = pcall(C_GuildInfo.Invite, nameRealm)
    if ok then return true end
    -- Retry with name only if first failed and there was a realm part
    if nameOnly ~= nameRealm then
      ok = pcall(C_GuildInfo.Invite, nameOnly)
      if ok then return true end
    end
  end
  return false, "guild-invite-failed"
end

-- Factory function for DI container (TRUE lazy resolution)
local function CreateInviteService(scope)
  -- Unified lazy accessors via DI container helpers
  -- Prefer resolving through DI scope (guarantees proper lifetime handling); fallback to Addon.Get for safety during early boot
  local function getLog() return (scope and scope.Resolve and scope:Resolve("Logger") or Addon.Get("Logger")):ForContext("Subsystem","InviteService") end
  local function getBus() return (scope and scope.Resolve and scope:Resolve("EventBus") or Addon.Get("EventBus")) end
  local function getScheduler() return (scope and scope.Resolve and scope:Resolve("Scheduler") or Addon.Get("Scheduler")) end
  local function getConfig() return (scope and scope.Resolve and scope:Resolve("IConfiguration") or Addon.Get("IConfiguration")) end
  local function getRecruiter() return (scope and scope.Resolve and scope:Resolve("Recruiter") or Addon.Get("Recruiter")) end -- legacy
  local function getProvider()
    if scope and scope.Resolve then
      local ok, p = pcall(function() return scope:Resolve('IProspectsReadModel') end)
      if ok and p then return p end
    end
    if Addon.Get then return Addon.Get('IProspectsReadModel') end
  end
  local function getPM() return (scope and scope.Resolve and scope:Resolve("IProspectManager")) or (Addon.Get and Addon.Get("IProspectManager")) end

  local self = {}
  local running = false
  local timerTok = nil
  local lastSentAt = 0
  local cooldownMin = 10  -- anti-spam safety for broadcasts

  local cycleIndex = 1
  -- Separate rotation index for direct whisper invites so broadcasts keep their own order
  local inviteCycleIndex = 1
  -- History of sent per-prospect whispers (guid -> { lastMessage=string, count=int, lastAt=epoch })
  local inviteHistory = {}
  local function currentHistoryMax()
    local max = 1000
    local ok, cfg = pcall(getConfig)
    if ok and cfg and cfg.Get then
      local v = tonumber(cfg:Get("inviteHistoryMax", max))
      if v and v > 0 then max = v end
    end
    return max
  end
  local function pruneInviteHistory()
    local cap = currentHistoryMax()
    local n=0; for _ in pairs(inviteHistory) do n=n+1 end
    if n <= cap then return end
    local items = {}
    for guid,h in pairs(inviteHistory) do items[#items+1] = { guid=guid, at=h.lastAt or 0 } end
    table.sort(items, function(a,b) return a.at < b.at end)
    local toRemove = n - cap
    for i=1,toRemove do inviteHistory[items[i].guid] = nil end
  end
  -- Track recent guild invites to correlate decline messages
  local recentInvites = {} -- key: lower(name) -> { guid=guid, at=epoch }
  local declinePatterns = nil

  local function sanitize(msg)
    if not msg then return "" end
    -- Remove color codes and hyperlinks for reliable pattern matching
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    msg = msg:gsub("|H.-|h", ""):gsub("|h", "")
    return msg
  end

  local function buildDeclinePatterns()
    if declinePatterns then return declinePatterns end
    -- Localization table (can be extended via other files prior to Init)
    _G.GuildRecruiterLocales = _G.GuildRecruiterLocales or {}
    local L = _G.GuildRecruiterLocales
    -- English fallback patterns (player capture in group 1)
    L.declinePatterns = L.declinePatterns or {
      enUS = {
        "^([%a%d%-]+) has declined your guild invitation%.$",
        "^([%a%d%-]+) declines your guild invitation%.$",
        "^([%a%d%-]+) declines your invitation to join the guild%.$",
      }
    }
    local locale = GetLocale and GetLocale() or "enUS"
    local arr = (L.declinePatterns[locale]) or L.declinePatterns.enUS
    local List = Addon.Get("Collections.List") or Addon.List
    declinePatterns = List and List.new(arr) or arr
    return declinePatterns
  end

  local function noteInvite(guid, target)
    local nameOnly = target:match("^([^%-]+)") or target
    recentInvites[nameOnly:lower()] = { guid=guid, at=now_s() }
  end

  local function cleanupInvites()
    local cutoff = now_s() - 900 -- 15 min
    for k,info in pairs(recentInvites) do if (info.at or 0) < cutoff then recentInvites[k]=nil end end
  end

  local function handleSystemMessage(msg)
    if type(msg) ~= "string" or msg == "" then return end
    if not msg:lower():find("declin") then return end -- quick filter
    local raw = msg
    msg = sanitize(msg)
    local pats = buildDeclinePatterns()
    local who
    if pats.ForEach then
      pats:ForEach(function(pat)
        if not who then who = msg:match(pat) end
      end)
    else
      for _,pat in ipairs(pats) do if not who then who = msg:match(pat) end end
    end
    -- Fallback heuristic: first token before space if message contains 'declined your guild invitation'
    if not who and msg:lower():find("declin") and msg:lower():find("guild invitation") then
      who = msg:match("^([^%s]+)")
    end
  if not who then return end
    local nameOnly = who:match("^([^%-]+)") or who
    local rec = recentInvites[nameOnly:lower()]
    local guid = rec and rec.guid
    -- Fallback: attempt to find prospect by name if guid missing (invite by name)
    if not guid then
      local prov = getProvider()
      if prov and prov.GetAll then
        local all = prov:GetAll() or {}
        for i=1,#all do local p = all[i]; if p and p.name and p.name:lower() == nameOnly:lower() then guid = p.guid; break end end
      end
    end
    if guid then
      cleanupInvites()
      local cfg = getConfig()
      local autoBL = true
      pcall(function() autoBL = cfg:Get("autoBlacklistDeclines", true) end)
      if autoBL then
        local pm = getPM()
        if pm and pm.Blacklist then pcall(function() pm:Blacklist(guid, "declined") end) end
        getBus():Publish("InviteService.InviteDeclined", guid, who)
        getLog():Info("Guild invite declined by {Player}; auto-blacklisted guid={GUID}", { Player = who, GUID = guid })
      else
        getBus():Publish("InviteService.InviteDeclined", guid, who)
        getLog():Info("Guild invite declined by {Player}; noted (auto-blacklist disabled)", { Player = who, GUID = guid })
      end
      recentInvites[nameOnly:lower()] = nil
    else
      getLog():Debug("Decline detected but no guid match for {Player} [Msg={Msg}]", { Player = who, Msg = raw })
    end
  end

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

  local function nextInviteMessage()
    local keys = { "customMessage1", "customMessage2", "customMessage3" }
    for n = 0, #keys-1 do
      local idx = ((inviteCycleIndex - 1 + n) % #keys) + 1
      local txt = getConfig():Get(keys[idx], "")
      if type(txt) == "string" and txt ~= "" then
        inviteCycleIndex = (idx % #keys) + 1
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
    local info = chooseChannel(getConfig())
    if info and info.kind == "SAY" then
      local cfg = getConfig()
      local needConfirm = true
      pcall(function() needConfirm = cfg:Get("allowSayFallbackConfirm", false) end)
      if needConfirm then
        -- Require user to explicitly re-enable or confirm; publish skipped event.
        getBus():Publish("InviteService.BroadcastSkipped", "say-confirm")
        getLog():Warn("Broadcast blocked: SAY fallback requires confirmation (set allowSayFallbackConfirm=false to allow)")
        if DEFAULT_CHAT_FRAME then
          DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00[GR]|r Broadcast skipped: SAY fallback blocked. Toggle 'Require confirm for SAY fallback' in settings or change channel.")
        end
        return false, "say-confirm"
      end
    end
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
  local prov = getProvider(); local p = prov and prov.GetByGuid and prov:GetByGuid(guid) or nil
    if not p then return false, "no-prospect" end
    local target = fmtNameRealm(p.name, p.realm)
    if not target then return false, "bad-name" end

    getBus():Publish("InviteService.InviteAttempt", { guid = guid, target = target })

    if opts.whisper ~= false then
      local tpl
      if getConfig():Get("inviteCycleEnabled", true) then
        tpl = nextInviteMessage()
      end
      tpl = tpl or getConfig():Get("whisperTemplate", getConfig():Get("customMessage1", "Hey {Player}, {Guild} is recruiting!"))
  local text = renderTemplate(tpl, pickBag(p))
  pcall(SendChatMessage, text, "WHISPER", nil, target)
  inviteHistory[guid] = inviteHistory[guid] or { count = 0 }
  local h = inviteHistory[guid]; h.lastMessage = text; h.count = h.count + 1; h.lastAt = now_s()
  pruneInviteHistory()
  getBus():Publish("InviteService.WhisperSent", { guid = guid, target = target, message = text })
    end

    local ok, err = doInvite(target)
    if ok then
      p.status = "Invited"
      getBus():Publish("InviteService.Invited", guid, target)
  getBus():Publish("Prospects.Changed", "updated", guid)
      getLog():Info("Invited {Target}", { Target = target })
      noteInvite(guid, target)
      return true
    else
      getBus():Publish("InviteService.InviteFailed", guid, target, err or "invite-error")
      getLog():Warn("Invite failed {Target}: {Err}", { Target = target, Err = tostring(err) })
      return false, err
    end
  end

  -- Back-compat wrapper used by UI/Prospects and data provider
  function self:InviteProspect(guid)
    return self:InviteGUID(guid, { whisper = true })
  end

  -- === History accessors ===
  function self:GetInviteHistory(guid) return inviteHistory[guid] end
  function self:GetLastInviteMessage(guid) local h = inviteHistory[guid]; return h and h.lastMessage or nil end
  function self:GetInviteCount(guid) local h = inviteHistory[guid]; return h and h.count or 0 end

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

  pruneInviteHistory()

    local ok, err = doInvite(target)
    if ok then
      getBus():Publish("InviteService.Invited", nil, target)
      getLog():Info("Invited {Target}", { Target = target })
      noteInvite(nil, target)
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
  -- Register system chat listener for decline detection
  local bus = getBus()
  self._tokens = self._tokens or {}
  self._tokens[#self._tokens+1] = bus:RegisterWoWEvent("CHAT_MSG_SYSTEM").token
  self._tokens[#self._tokens+1] = bus:Subscribe("CHAT_MSG_SYSTEM", function(_, msg) handleSystemMessage(msg) end, { namespace="InviteService" })
  end

  function self:Stop()
    if timerTok then getScheduler():Cancel(timerTok); timerTok = nil end
    getScheduler():CancelNamespace("InviteService")
    setRunning(false)
    getLog():Debug("InviteService stopped")
    if self._tokens then
      for _,tok in ipairs(self._tokens) do getBus():Unsubscribe(tok) end
      getBus():UnsubscribeNamespace("InviteService")
      self._tokens = nil
    end
  end

  return self
end

-- Registration function for Init.lua
local function RegisterInviteServiceFactory()
  if not Addon.provide then
    error("InviteService: Addon.provide not available")
  end
  
  if not (Addon.IsProvided and Addon.IsProvided("InviteService")) then
    Addon.provide("InviteService", function(scope) return CreateInviteService(scope) end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'chat/invite' } })
  end
  -- Also provide a scoped factory for InviteService (captures current scope)
  if Addon.provideFactory and not (Addon.IsProvided and Addon.IsProvided("InviteService.Factory")) then
    Addon.provideFactory("InviteService.Factory", "InviteService", { lifetime = "InstancePerLifetimeScope", meta = { role = "factory" } })
  end
  
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
