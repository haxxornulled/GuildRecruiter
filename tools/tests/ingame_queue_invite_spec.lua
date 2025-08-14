---@diagnostic disable: undefined-global, undefined-field
-- In-game tests for QueueService and InviteService basics (non-networked logic only)
local Addon = _G.GuildProspector or _G.GuildRecruiter or select(2, ...)
if not Addon or not Addon.RegisterInGameTest then return end

local function queue() return Addon.Get and Addon.Get('QueueService') end
local function invite() return Addon.Get and Addon.Get('InviteService') end
local function broadcast() return Addon.Get and (Addon.Get('IBroadcastService') or Addon.Get('BroadcastService')) end
local function pm() return Addon.Get and (Addon.Get('IProspectManager') or Addon.Get('ProspectsManager')) end

local function ensureProspect(guid)
  local m = pm(); local created=false
  if m and m.GetProspect and m.Upsert and not m:GetProspect(guid) then
    m:Upsert({ guid = guid, name = 'QTest'..guid:sub(-4), realm = nil, level = 10, lastSeen = 0 }); created=true
  end
  if (not created) then
    local ps = Addon.Get and Addon.Get('ProspectsService') or nil
    if ps and ps.Upsert then
      local existing = nil
      if ps.GetProspect then existing = ps:GetProspect(guid) end
      if not existing then
        ps:Upsert({ guid = guid, name = 'QTest'..guid:sub(-4), realm = nil, level = 10, lastSeen = 0 })
        created = true
  -- Force read model provider to incorporate new prospect if present
  local prov = Addon.Get and Addon.Get('ProspectsDataProvider')
  if prov and prov._fullRebuild then pcall(function() prov:_fullRebuild() end) end
      end
    end
  end
end

Addon.RegisterInGameTest('QueueService Requeue/Stats', function()
  local q = queue(); if not q then return end
  local before = q:QueueStats().total or 0
  ensureProspect('IG-Q-1'); ensureProspect('IG-Q-2'); ensureProspect('IG-Q-3')
  q:Requeue('IG-Q-1'); q:Requeue('IG-Q-2'); q:Requeue('IG-Q-3')
  local afterStats = q:QueueStats(); local delta = (afterStats.total or 0) - before
  if delta < 2 then error('expected at least 2 new items queued (delta='..tostring(delta)..')') end
  local g1, p1 = q:Dequeue(); if not g1 or not p1 then error('expected a dequeued prospect') end
end)

Addon.RegisterInGameTest('QueueService Clear + Repair', function()
  local q = queue(); if not q then return end
  q:ClearQueue()
  local s1 = q:QueueStats(); if (s1.total or 0) ~= 0 then error('queue not cleared total='..tostring(s1.total)) end
  ensureProspect('IG-Q-CLR')
  q:Requeue('IG-Q-CLR'); local s2 = q:QueueStats(); if (s2.total or 0) < 1 then error('requeue failed after clear total='..tostring(s2.total)) end
  local repairedCount = q:RepairQueue(); if repairedCount < 1 then error('repair queue should rebuild runtime structure') end
end)

Addon.RegisterInGameTest('InviteService History Increment', function()
  local inv = invite(); local q = queue(); if not inv or not q then return end
  ensureProspect('IG-INV-1'); q:Requeue('IG-INV-1')
  -- disable guild invite requirement side-effects by faking doGuildInvite success if available
  -- Enable whisper so history increments
  if inv.InviteGUID then inv:InviteGUID('IG-INV-1', { whisper = true }) end
  local c = inv.GetInviteCount and inv:GetInviteCount('IG-INV-1') or 0
  local cnum = tonumber(c) or 0
  if cnum < 1 then error('expected invite count >=1 got '..tostring(cnum)) end
end)

Addon.RegisterInGameTest('Blacklist blocks queue requeue', function()
  local manager = pm(); local q = queue(); if not manager or not q then return end
  manager:Upsert({ guid='IG-BL-Q-1', name='Blk', level=1, lastSeen=0 })
  manager:Blacklist('IG-BL-Q-1','t')
  q:Requeue('IG-BL-Q-1')
  local arr = q:GetQueue() or {}
  for _,g in ipairs(arr) do if g == 'IG-BL-Q-1' then error('blacklisted guid present in queue') end end
end)

-- We simulate broadcast conditions by toggling config values; we can only assert skip reasons (no real chat send in test env)
Addon.RegisterInGameTest('BroadcastService skip reasons', function()
  local b = broadcast(); local cfg = Addon.Get and Addon.Get('IConfiguration'); if not b or not cfg then return end
  -- Ensure disabled state
  cfg:Set('broadcastEnabled', false)
  local ok, why = b:BroadcastOnce(); if ok or why ~= 'disabled' then error('expected disabled skip') end
  -- Enable but no message configured
  cfg:Set('broadcastEnabled', true)
  cfg:Set('customMessage1','') cfg:Set('customMessage2','') cfg:Set('customMessage3','')
  local ok2, why2 = b:BroadcastOnce(); if ok2 or why2 ~= 'no-message' then error('expected no-message skip') end
end)

Addon.RegisterInGameTest('BroadcastService cooldown skip', function()
  local b = broadcast(); local cfg = Addon.Get and Addon.Get('IConfiguration'); if not b or not cfg then return end
  cfg:Set('broadcastEnabled', true)
  cfg:Set('customMessage1','Hello Guild Recruitment!')
  local ok = b:BroadcastOnce(); if not ok then error('expected first broadcast to succeed or at least not be disabled') end
  -- Immediate second call should cooldown skip (reason starts with 'cooldown')
  local ok2, why2 = b:BroadcastOnce(); if ok2 or not (type(why2)=='string' and why2:find('cooldown')) then error('expected cooldown skip got '..tostring(why2)) end
end)

Addon.RegisterInGameTest('BroadcastService SAY confirm skip', function()
  local b = broadcast(); local cfg = Addon.Get and Addon.Get('IConfiguration'); if not b or not cfg then return end
  cfg:Set('broadcastEnabled', true)
  cfg:Set('broadcastChannel','SAY')
  cfg:Set('customMessage1','Need more for guild!')
  cfg:Set('allowSayFallbackConfirm', true)
  local ok, why = b:BroadcastOnce();
  if ok then error('expected skip (say-confirm) but broadcast succeeded') end
  if type(why)=='string' and not (why=='say-confirm' or why:find('cooldown')) then error('expected say-confirm or cooldown skip got '..tostring(why)) end
  cfg:Set('broadcastChannel','AUTO')
end)

-- Decline handling: simulate a recent invite then feed a fake system decline message pattern
Addon.RegisterInGameTest('InviteService Decline handling auto-blacklist', function()
  local inv = invite(); local cfg = Addon.Get and Addon.Get('IConfiguration'); local manager = pm(); if not inv or not cfg or not manager then return end
  cfg:Set('autoBlacklistDeclines', true)
  -- Create and invite a prospect so recentInvites table has entry
  ensureProspect('IG-DEC-1'); manager:Upsert({ guid='IG-DEC-1', name='Declinee', level=10, lastSeen=0 })
  -- Use public API to invite (records recentInvites)
  if inv.InviteGUID then inv:InviteGUID('IG-DEC-1', { whisper = false }) end
  -- Now simulate SYSTEM message (English pattern)
  local handler = inv._handleSystemMessage or inv.handleSystemMessage or nil
  -- Fallback: We can't directly access local closure; expose shim if not present
  if not handler and Addon.EventBus and Addon.EventBus.Publish then
    -- Try publishing system event (depends on wiring)
    Addon.EventBus:Publish('CHAT_MSG_SYSTEM', 'Declinee has declined your guild invitation.')
  elseif handler then
    handler(nil, 'Declinee has declined your guild invitation.')
  end
  -- Prospect should now be blacklisted if auto-blacklist enabled
  local p = manager:GetProspect('IG-DEC-1')
  if not (p and p.blacklisted) then error('expected prospect to be auto-blacklisted on decline') end
end)
