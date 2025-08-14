---@diagnostic disable: undefined-global, undefined-field, assign-type-mismatch, param-type-mismatch, need-check-nil, inject-field, missing-fields, lowercase-global
local ADDON_NAME, Addon = ...
local G = _G or {}
local CTL = G.ChatThrottleLib

local function w_Time() return (G.time and G.time()) or os.time() end
local function w_Date(fmt) return (G.date and G.date(fmt)) or os.date(fmt) end
local function w_GetGuildInfo(unit) return (G.GetGuildInfo and G.GetGuildInfo(unit)) or nil end
local function w_GetRealmName() return (G.GetRealmName and G.GetRealmName()) or '?' end
local function w_IsInInstance() return (G.IsInInstance and G.IsInInstance()) or nil end
local function w_SendChatMessage(msg, chatType, lang, target) local f = G.SendChatMessage if not f then return false,'no-api' end return pcall(f,msg,chatType,lang,target) end

local function renderTemplate(tpl, bag) if type(tpl)~='string' then return '' end return (tpl:gsub('{([%w_%.]+)}', function(k) local v=bag and bag[k]; return v~=nil and tostring(v) or '{'..k..'}' end)) end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

local function chooseChannel(cfg)
  local helper = Addon.Get and Addon.Get('ChatChannelHelper')
  if helper and helper.Resolve then
    local info = helper:Resolve(cfg:Get('broadcastChannel','AUTO'))
    if info and info.kind then return info end
  end
  local ch = cfg:Get('broadcastChannel','AUTO')
  if ch ~= 'AUTO' then
    local u = tostring(ch):upper()
    if u=='SAY' or u=='YELL' or u=='GUILD' or u=='OFFICER' or u=='PARTY' or u=='RAID' or u=='INSTANCE_CHAT' then
      return { kind = u, id = nil, display = u }
    end
  end
  if w_IsInInstance() then return { kind = 'INSTANCE_CHAT', id=nil, display='Instance Chat' } end
  return { kind = 'SAY', id=nil, display='Say' }
end

local function sendToChannel(msg, info)
  if not msg or msg=='' then return false,'empty' end
  if not info or not info.kind then return false,'no-channel' end
  local which,arg = info.kind,nil
  if which=='CHANNEL' then arg=info.id; if not arg then return false,'channel-missing' end end
  if CTL and CTL.SendChatMessage then
    local ok, err = pcall(function()
      if which=='CHANNEL' then CTL:SendChatMessage('NORMAL','GR',msg,which,nil,arg) else CTL:SendChatMessage('NORMAL','GR',msg,which) end
    end)
    return ok and true or false, (ok and nil or tostring(err))
  end
  local ok, err = w_SendChatMessage(msg, which, nil, arg)
  return ok and true or false, (ok and nil or tostring(err))
end

local function BroadcastServiceFactory(scope)
  local function resolve(k)
    if scope and scope.Resolve then local ok,v=pcall(function() return scope:Resolve(k) end); if ok and v then return v end end
    return Addon.Get and Addon.Get(k)
  end
  local function getLog() local lg=resolve('Logger'); return lg and lg:ForContext('Subsystem','BroadcastService') or Addon end
  local function getBus() return resolve('EventBus') end
  local function getScheduler() return resolve('Scheduler') end
  local function getConfig() return resolve('IConfiguration') end

  local self = {}
  local running=false
  local lastBroadcastAt=0
  local lastBroadcast=nil
  local lastChannel=nil
  local cooldownMin=10
  local cycleIndex=1
  local timerTok=nil

  local function bag()
    return { Guild=(w_GetGuildInfo('player')) or (w_GetRealmName()..' Guild'), Date=w_Date('%Y-%m-%d'), Time=w_Date('%H:%M') }
  end
  local function nextMessage()
    local cfg=getConfig()
    local keys={'customMessage1','customMessage2','customMessage3'}
    for n=0,#keys-1 do
      local idx=((cycleIndex-1+n)%#keys)+1
      local txt=cfg and cfg.Get and cfg:Get(keys[idx],'') or ''
      if type(txt)=='string' and txt~='' then cycleIndex=(idx%#keys)+1 return txt end
    end
    return nil
  end
  local function randInterval()
    local cfg=getConfig()
    local base=tonumber(cfg and cfg.Get and cfg:Get('broadcastInterval',300)) or 300
    local jitterPct=clamp(tonumber(cfg and cfg.Get and cfg:Get('jitterPercent',0.15)) or 0,0,0.50)
    local jitter=base*jitterPct
    local delta=(math.random()*2-1)*jitter
    return clamp(base+delta, math.max(30,cooldownMin), 1800)
  end
  local function scheduleNext()
    if not running then return end
    local sched=getScheduler(); if not sched then return end
    local delay=randInterval()
    timerTok=sched:After(delay,function()
      timerTok=nil
      self:BroadcastOnce()
      scheduleNext()
    end,{ namespace='BroadcastService' })
  end
  local function setRunning(v)
    if running==v then return end
    running=v
    local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.StateChanged', running) end
  end

  function self:IsRunning() return running end
  function self:StartRotation()
    if running then return end
    setRunning(true); scheduleNext(); local log=getLog(); if log and log.Info then log:Info('Broadcast rotation started') end
  end
  function self:StopRotation()
    if not running then return end
    setRunning(false)
    local sched=getScheduler(); if timerTok and sched then sched:Cancel(timerTok); timerTok=nil end
    if sched then sched:CancelNamespace('BroadcastService') end
    local log=getLog(); if log and log.Info then log:Info('Broadcast rotation stopped') end
  end
  function self:BroadcastOnce()
    local cfg=getConfig()
    if not (cfg and cfg.Get and cfg:Get('broadcastEnabled', false)) then
      local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSkipped','disabled') end
      return false,'disabled'
    end
    local since = w_Time() - lastBroadcastAt
    if since < cooldownMin then
      local why=('cooldown (%ds left)'):format(math.ceil(cooldownMin - since))
      local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSkipped', why) end
      return false, why
    end
    local tpl=nextMessage()
    if not tpl then
      local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSkipped','no-message') end
      local log=getLog(); if log and log.Warn then log:Warn('Broadcast skipped: no configured message') end
      return false,'no-message'
    end
    local msg=renderTemplate(tpl, bag())
    local info=chooseChannel(cfg)
    if info and info.kind=='SAY' then
      local needConfirm=true; pcall(function() needConfirm = cfg:Get('allowSayFallbackConfirm', false) end)
      if needConfirm then
        local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSkipped','say-confirm') end
        local log=getLog(); if log and log.Warn then log:Warn('Broadcast blocked: SAY fallback requires confirmation') end
        local cf=G.DEFAULT_CHAT_FRAME; if cf and cf.AddMessage then cf:AddMessage('|cffffaa00[GR]|r Broadcast skipped: SAY fallback blocked.') end
        return false,'say-confirm'
      end
    end
    local ok, err = sendToChannel(msg, info)
    if ok then
      lastBroadcastAt=w_Time(); lastBroadcast=msg; lastChannel=info
      local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSent',{ channel=info, message=msg, at=w_Time() }) end
      local log=getLog(); if log and log.Info then log:Info('Broadcast via {Channel}: {Msg}', { Channel=info.display or info.kind, Msg=msg }) end
      return true
    else
      local bus=getBus(); if bus and bus.Publish then bus:Publish('BroadcastService.BroadcastSkipped', err or 'send-failed') end
      local log=getLog(); if log and log.Warn then log:Warn('Broadcast failed {Err}', { Err=tostring(err) }) end
      return false, err
    end
  end
  -- Test support: allow resetting cooldown in controlled scenarios (not used in production paths)
  function self:ResetState()
    if not _G.GR_TEST_MODE then return end
    lastBroadcastAt = 0; lastBroadcast=nil; lastChannel=nil
  end
  function self:GetLastBroadcast() return lastBroadcast end
  function self:GetLastBroadcastAt() return lastBroadcastAt end
  function self:GetLastBroadcastChannel() return lastChannel end
  function self:Start() end
  function self:Stop() self:StopRotation() end
  return self
end

local function factory(scope) return BroadcastServiceFactory(scope) end
if Addon.provide then Addon.provide('BroadcastService', factory); Addon.provide('IBroadcastService', factory) end
return factory
