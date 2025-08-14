-- Factory-based registration for DI container

-- InviteService.lua (re-coded clean version)
-- See new implementation below (full rewrite)
---@diagnostic disable: undefined-global, undefined-field, assign-type-mismatch, param-type-mismatch, need-check-nil, inject-field, missing-fields, lowercase-global, invisible
local ADDON_NAME, Addon = ...
local G = _G or {}
local _volatile = (math.random and math.random()) or (os.time() % 1000) -- defeat constant folding heuristics

local function w_GetTime()
  return (G.GetTime and G.GetTime()) or (G.time and G.time()) or os.time()
end
local function w_Time()
  return (G.time and G.time()) or os.time()
end
local function w_Date(fmt)
  return (G.date and G.date(fmt)) or os.date(fmt)
end
local function w_GetGuildInfo(unit)
  return (G.GetGuildInfo and G.GetGuildInfo(unit)) or nil
end
local function w_GetRealmName()
  return (G.GetRealmName and G.GetRealmName()) or "?"
end
local function w_GetChannelName(name)
  return (G.GetChannelName and G.GetChannelName(name)) or nil
end
local function w_IsInGuild()
  return (G.IsInGuild and G.IsInGuild()) or false
end
local function w_IsInInstance()
  return (G.IsInInstance and G.IsInInstance()) or nil
end
local function w_SendChatMessage(msg, chatType, lang, target)
  local f = G.SendChatMessage
  if not f then return false, "no-api" end
  return pcall(f, msg, chatType, lang, target)
end
local function w_GetLocale()
  return (G.GetLocale and G.GetLocale()) or "enUS"
end
local function w_GuildInvite(name)
  local info = G.C_GuildInfo
  if info and info.Invite then return pcall(info.Invite, name) end
  return false, "no-invite-api"
end
local CTL = G.ChatThrottleLib
local function now_s() return w_Time() end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function fmtNameRealm(name, realm) if not name or name=="" then return nil end if realm and realm~="" then return name.."-"..realm end return name end
local function renderTemplate(tpl, bag) if type(tpl)~="string" then return "" end return (tpl:gsub("{([%w_%.]+)}", function(k) local v = bag and bag[k]; return v~=nil and tostring(v) or "{"..k.."}" end)) end
local function doGuildInvite(nameRealm)
  if not nameRealm or nameRealm == "" then return false, "no-name" end
  -- Suppress analyzer complaining about guild membership check
  ---@diagnostic disable-next-line
  if not w_IsInGuild() then return false, "not-in-guild" end
  local nameOnly = nameRealm:match("^([^%-]+)") or nameRealm
  local ok = w_GuildInvite(nameRealm)
  if ok == true then return true end
  if nameOnly ~= nameRealm then
    local ok2 = w_GuildInvite(nameOnly)
    if ok2 == true then return true end
  end
  return false, "guild-invite-failed"
end
local function CreateInviteService(scope)
  local function resolve(k)
    if scope and scope.Resolve then
      local ok, v = pcall(function() return scope:Resolve(k) end)
      if ok and v then return v end
    end
    return Addon.Get and Addon.Get(k)
  end
  local function getLog() local lg = resolve("Logger"); return lg and lg:ForContext("Subsystem","InviteService") or Addon end
  local function getBus() return resolve("EventBus") end
  local function getScheduler() return resolve("Scheduler") end
  local function getConfig() return resolve("IConfiguration") end
  local function getProvider() return resolve("IProspectsReadModel") end
  local function getPM() return resolve("IProspectManager") end

  local self = {}
  -- Broadcast state removed (now handled by BroadcastService)
  local inviteCycleIndex = 1
  local inviteHistory = {}
  local recentInvites = {}
  local declinePatterns = nil
  local volatileTick = _volatile

  local function historyCap()
    local cfg = getConfig()
    local max = 1000
    if cfg and cfg.Get then
      local v = tonumber(cfg:Get("inviteHistoryMax", max))
      if v and v > 0 then max = v end
    end
    return max
  end
  local function pruneHistory()
    local cap = historyCap()
    local n = 0; for _ in pairs(inviteHistory) do n = n + 1 end
    if n <= cap then return end
    local items = {}
    for g, h in pairs(inviteHistory) do items[#items+1] = { guid = g, at = h.lastAt or 0 } end
    table.sort(items, function(a,b) return a.at < b.at end)
    for i = 1, (n - cap) do inviteHistory[items[i].guid] = nil end
  end
  local function sanitize(msg)
    if type(msg) ~= 'string' or msg == '' then return '' end
    msg = msg:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
    msg = msg:gsub('|H.-|h',''):gsub('|h','')
    return msg
  end
  local function buildDeclinePatterns()
  ---@diagnostic disable-next-line
  if declinePatterns then return declinePatterns end -- runtime cache
    G.GuildRecruiterLocales = G.GuildRecruiterLocales or {}
    local L = G.GuildRecruiterLocales
    L.declinePatterns = L.declinePatterns or {
      enUS = {
        '^([%a%d%-]+) has declined your guild invitation%.$',
        '^([%a%d%-]+) declines your guild invitation%.$',
        '^([%a%d%-]+) declines your invitation to join the guild%.$',
      }
    }
    local locale = w_GetLocale()
    local arr = (L.declinePatterns[locale]) or L.declinePatterns.enUS
    local List = resolve('Collections.List') or Addon.List
    declinePatterns = (List and List.new and List.new(arr)) or arr
    return declinePatterns
  end
  local function noteInvite(guid, target)
    local nameOnly = target:match('^([^%-]+)') or target
    recentInvites[nameOnly:lower()] = { guid = guid, at = now_s() }
  end
  local function cleanupInvites()
    local cutoff = now_s() - 900
    for k, info in pairs(recentInvites) do if (info.at or 0) < cutoff then recentInvites[k] = nil end end
  end
  local function handleSystemMessage(_, msg)
    if type(msg) ~= 'string' or msg == '' then return end
    if not msg:lower():find('declin') then return end
    local raw = msg
    msg = sanitize(msg)
    local pats = buildDeclinePatterns()
    local who
    if pats.ForEach then
      pats:ForEach(function(p) if not who then who = msg:match(p) end end)
    else
      for _, p in ipairs(pats) do if not who then who = msg:match(p) end end
    end
    if not who and msg:lower():find('declin') and msg:lower():find('guild invitation') then who = msg:match('^([^%s]+)') end
    if not who then return end
    local nameOnly = who:match('^([^%-]+)') or who
    local rec = recentInvites[nameOnly:lower()]
    local guid = rec and rec.guid
    if not guid then
      local prov = getProvider()
      if prov and prov.GetAll then
        local all = prov:GetAll() or {}
        for i = 1, #all do local p = all[i]; if p and p.name and p.name:lower() == nameOnly:lower() then guid = p.guid; break end end
      end
    end
    if guid then
      cleanupInvites()
      local cfg = getConfig()
      local autoBL = true
      pcall(function() autoBL = cfg:Get('autoBlacklistDeclines', true) end)
      local pm = getPM()
      if autoBL and pm and pm.Blacklist then pcall(function() pm:Blacklist(guid, 'declined') end) end
      local bus = getBus(); if bus and bus.Publish then bus:Publish('InviteService.InviteDeclined', guid, who) end
      local log = getLog(); if log and log.Info then if autoBL then log:Info('Guild invite declined by {Player}; auto-blacklisted guid={GUID}', { Player = who, GUID = guid }) else log:Info('Guild invite declined by {Player}; noted (auto-blacklist disabled)', { Player = who, GUID = guid }) end end
      recentInvites[nameOnly:lower()] = nil
    else
      local log = getLog(); if log and log.Debug then log:Debug('Decline detected but no guid match for {Player} [Msg={Msg}]', { Player = who, Msg = raw }) end
    end
  end
  local function bagForProspect(p)
    local bag = { Guild = (w_GetGuildInfo('player')) or (w_GetRealmName()..' Guild'), Date = w_Date('%Y-%m-%d'), Time = w_Date('%H:%M') }
    if p then
      bag.Player = p.name
      bag.Realm  = p.realm or w_GetRealmName()
      bag.Class  = p.classToken or p.className
      bag.Level  = p.level
    end
    return bag
  end
  local function nextInviteMessage()
    local cfg = getConfig()
    local keys = { 'customMessage1','customMessage2','customMessage3' }
    for n = 0, #keys - 1 do
      local idx = ((inviteCycleIndex - 1 + n) % #keys) + 1
      local txt = cfg and cfg.Get and cfg:Get(keys[idx], '') or ''
      if type(txt) == 'string' and txt ~= '' then
        inviteCycleIndex = (idx % #keys) + 1
        return txt
      end
    end
    return nil
  end
  -- (rotation scheduling removed; delegated to BroadcastService)
  -- Broadcast responsibilities have been extracted to BroadcastService.
  -- These methods now delegate for backward compatibility with existing callers/tests.
  local function getBroadcastSvc()
    return resolve('IBroadcastService') or resolve('BroadcastService') or (Addon.Get and (Addon.Get('IBroadcastService') or Addon.Get('BroadcastService')))
  end
  function self:IsRunning()
    local b = getBroadcastSvc(); if b and b.IsRunning then return b:IsRunning() end
    return false
  end
  function self:StartRotation()
    local b = getBroadcastSvc(); if b and b.StartRotation then b:StartRotation() end
  end
  function self:StopRotation()
    local b = getBroadcastSvc(); if b and b.StopRotation then b:StopRotation() end
  end
  function self:BroadcastOnce()
    local b = getBroadcastSvc(); if not b or not b.BroadcastOnce then return false, 'no-broadcast-service' end
  return b:BroadcastOnce()
  end
  function self:InviteGUID(guid, opts)
    opts = opts or {}
    local prov = getProvider(); local p = prov and prov.GetByGuid and prov:GetByGuid(guid) or nil
    if not p then
      -- Fallback: direct resolve from ProspectsService (test environments may not have provider registered yet)
      local ps = resolve('ProspectsService') or (Addon.Get and Addon.Get('ProspectsService'))
      if ps and ps.GetProspect then p = ps:GetProspect(guid) end
    end
    if not p then return false, 'no-prospect' end
    local target = fmtNameRealm(p.name, p.realm)
    if not target then return false, 'bad-name' end
    local bus = getBus(); if bus and bus.Publish then bus:Publish('InviteService.InviteAttempt', { guid = guid, target = target }) end
    if opts.whisper ~= false then
      local cfg = getConfig(); local tpl
      if cfg and cfg.Get and cfg:Get('inviteCycleEnabled', true) then tpl = nextInviteMessage() end
      tpl = tpl or (cfg and cfg.Get and cfg:Get('whisperTemplate', cfg:Get('customMessage1','Hey {Player}, {Guild} is recruiting!'))) or ''
      local text = renderTemplate(tpl, bagForProspect(p))
      w_SendChatMessage(text, 'WHISPER', nil, target)
      inviteHistory[guid] = inviteHistory[guid] or { count = 0 }
      local h = inviteHistory[guid]; h.lastMessage = text; h.count = h.count + 1; h.lastAt = now_s()
      pruneHistory()
      if bus and bus.Publish then bus:Publish('InviteService.WhisperSent', { guid = guid, target = target, message = text }) end
    end
    local ok, err = doGuildInvite(target)
    if ok then
  local Status = (Addon.ResolveOptional and Addon.ResolveOptional('ProspectStatus')) or { Invited='Invited' }
  p.status = Status.Invited
      local bus = getBus(); if bus and bus.Publish then
  local E = (Addon.ResolveOptional and Addon.ResolveOptional('Events')) or error('Events constants missing')
        bus:Publish('InviteService.Invited', guid, target)
  bus:Publish(E.Prospects.Changed,'updated', guid)
      end
      local log = getLog(); if log and log.Info then log:Info('Invited {Target}', { Target = target }) end
      noteInvite(guid, target)
      return true
    else
      local bus = getBus(); if bus and bus.Publish then bus:Publish('InviteService.InviteFailed', guid, target, err or 'invite-error') end
      local log = getLog(); if log and log.Warn then log:Warn('Invite failed {Target}: {Err}', { Target = target, Err = tostring(err) }) end
      return false, err
    end
  end
  function self:InviteProspect(g) return self:InviteGUID(g, { whisper = true }) end
  function self:GetInviteHistory(g) return inviteHistory[g] end
  function self:GetLastInviteMessage(g) local h = inviteHistory[g]; return h and h.lastMessage or nil end
  function self:GetInviteCount(g) local h = inviteHistory[g]; return h and h.count or 0 end
  function self:ResetState()
    if not _G.GR_TEST_MODE then return end
    for k in pairs(inviteHistory) do inviteHistory[k]=nil end
  end
  function self:InviteName(name, realm, opts)
    local target = fmtNameRealm(name, realm)
    if not target then return false, 'bad-name' end
    local bus = getBus(); if bus and bus.Publish then bus:Publish('InviteService.InviteAttempt', { guid = nil, target = target }) end
    if opts and opts.whisper then
      local cfg = getConfig();
      local tpl = cfg and cfg.Get and cfg:Get('whisperTemplate', cfg:Get('customMessage1','Hey {Player}, {Guild} is recruiting!')) or ''
      local text = renderTemplate(tpl, { Player = name, Realm = realm or w_GetRealmName(), Guild = (w_GetGuildInfo('player')) or (w_GetRealmName()..' Guild') })
      w_SendChatMessage(text, 'WHISPER', nil, target)
      if bus and bus.Publish then bus:Publish('InviteService.WhisperSent', { guid = nil, target = target, message = text }) end
    end
    pruneHistory()
    local ok, err = doGuildInvite(target)
    if ok then
      if bus and bus.Publish then bus:Publish('InviteService.Invited', nil, target) end
      local log = getLog(); if log and log.Info then log:Info('Invited {Target}', { Target = target }) end
      noteInvite(nil, target)
      return true
    else
      if bus and bus.Publish then bus:Publish('InviteService.InviteFailed', nil, target, err or 'invite-error') end
      local log = getLog(); if log and log.Warn then log:Warn('Invite failed {Target}: {Err}', { Target = target, Err = tostring(err) }) end
      return false, err
    end
  end
  function self:Start()
    self._started = true
    volatileTick = volatileTick + 1
    local log = getLog(); if log and log.Debug then log:Debug('InviteService ready') end
    local bus = getBus(); if not bus then return end
    self._tokens = self._tokens or {}
    local evt = bus.RegisterWoWEvent and bus:RegisterWoWEvent('CHAT_MSG_SYSTEM')
    if evt and evt.token then self._tokens[#self._tokens+1] = evt.token end
    local tok = bus:Subscribe('CHAT_MSG_SYSTEM', handleSystemMessage, { namespace = 'InviteService' })
    if tok and tok.token then self._tokens[#self._tokens+1] = tok.token end
  end
  function self:Stop()
    local bus = getBus()
  ---@diagnostic disable-next-line
  if bus and self._tokens then
      for _, t in ipairs(self._tokens) do pcall(function() bus:Unsubscribe(t) end) end
      bus:UnsubscribeNamespace('InviteService')
    end
    self._tokens = nil
    local log = getLog(); if log and log.Debug then log:Debug('InviteService stopped') end
  end
  return self
end
local function RegisterInviteServiceFactory()
  if not Addon.provide then error('InviteService: Addon.provide not available') end
  if not (Addon.IsProvided and Addon.IsProvided('InviteService')) then Addon.provide('InviteService', function(scope) return CreateInviteService(scope) end, { lifetime='SingleInstance', meta={ layer='Infrastructure', area='chat/invite' } }) end
  if Addon.provideFactory and not (Addon.IsProvided and Addon.IsProvided('InviteService.Factory')) then Addon.provideFactory('InviteService.Factory','InviteService',{ lifetime='InstancePerLifetimeScope', meta={ role='factory' } }) end
  Addon.InviteService=setmetatable({}, { __index=function(_,k) if Addon._booting then error('Cannot access InviteService during boot phase') end local inst=Addon.require('InviteService'); return inst[k] end, __call=function(_, ...) return Addon.require('InviteService'), ... end })
end
Addon._RegisterInviteService = RegisterInviteServiceFactory
return RegisterInviteServiceFactory
