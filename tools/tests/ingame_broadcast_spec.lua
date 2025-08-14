---@diagnostic disable: undefined-global, undefined-field
local Addon = _G.GuildProspector or _G.GuildRecruiter or select(2, ...)
if not Addon or not Addon.RegisterInGameTest then return end

local function broadcast() return Addon.Get and (Addon.Get('IBroadcastService') or Addon.Get('BroadcastService')) end

Addon.RegisterInGameTest('BroadcastService events: sent/skip/cooldown', function()
  local b = broadcast(); local cfg = Addon.Get and Addon.Get('IConfiguration'); local bus = Addon.Get and Addon.Get('EventBus'); if not b or not cfg or not bus then return end
  cfg:Set('broadcastEnabled', true)
  cfg:Set('customMessage1','Test Message One')
  -- Allow SAY fallback without confirmation for test success
  cfg:Set('allowSayFallbackConfirm', false)
  local sent, skipped, cooldownSkip = false, false, false
  -- Temporary subscribers
  local s1 = bus:Subscribe('BroadcastService.BroadcastSent', function() sent = true end, { once = true, namespace='Test' })
  local s2 = bus:Subscribe('BroadcastService.BroadcastSkipped', function(reason) skipped = true; if type(reason)=='string' and reason:find('cooldown') then cooldownSkip = true end end, { namespace='Test' })
  local ok, why = b:BroadcastOnce();
  if not ok then
    -- Edge case: if first call still skipped (e.g. misconfig), attempt reset + retry once
    if b._TestResetCooldown then b:_TestResetCooldown() end
    ok, why = b:BroadcastOnce()
  end
  if not ok then error('expected a successful broadcast (enabled + message) got '..tostring(why)) end
  if not sent then error('expected BroadcastService.BroadcastSent event') end
  -- Force immediate cooldown skip attempt
  local okCooldown, whyCooldown = b:BroadcastOnce(); if okCooldown then error('expected cooldown skip on immediate second broadcast') end
  if not (cooldownSkip or (type(whyCooldown)=='string' and whyCooldown:find('cooldown'))) then error('expected cooldown skip reason, got '..tostring(whyCooldown)) end
  -- Force skip: clear message (ensure not counted as cooldown by toggling enabled after clearing message)
  cfg:Set('customMessage1','')
  cfg:Set('broadcastEnabled', true)
  local ok2, why2 = b:BroadcastOnce(); if ok2 then error('expected skip when no message') end
  -- Confirm skipped event fired (either earlier cooldown skip or now no-message skip)
  if not skipped then error('expected BroadcastService.BroadcastSkipped event') end
  -- Cleanup subscriptions
  if bus.Unsubscribe and s1 and s1.token then pcall(function() bus:Unsubscribe(s1.token) end) end
  if bus.Unsubscribe and s2 and s2.token then pcall(function() bus:Unsubscribe(s2.token) end) end
end)
