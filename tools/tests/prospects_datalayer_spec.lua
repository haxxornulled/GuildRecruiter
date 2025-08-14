-- tools/tests/prospects_datalayer_spec.lua
-- Headless tests for ProspectsService & SavedVarsService integration (corrected filename).
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

if not Addon.IsProvided('SavedVarsService') then
  dofile('Infrastructure/Services/SavedVarsService.lua')
  Addon._RegisterSavedVarsService()
end
if not Addon.IsProvided('ProspectsService') then
  dofile('Infrastructure/Services/ProspectsService.lua')
end

Harness.AddTest('ProspectsService Upsert + GetAll', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-1', name='A', level=10, lastSeen=100 })
  svc:Upsert({ guid='Player-2', name='B', level=20, lastSeen=200 })
  Addon.AssertEquals(#svc:GetAll(), 2, 'expected 2 prospects')
end)

Harness.AddTest('ProspectsService Update merge', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-1', name='A', level=11, someField='keepme' })
  local p = svc:Get('Player-1')
  Addon.AssertEquals(p.level, 11, 'level merge failed')
  Addon.AssertEquals(p.someField, 'keepme', 'existing field lost on merge')
end)

Harness.AddTest('Blacklist + Unblacklist', function()
  local svc = Addon.require('ProspectsService')
  svc:Blacklist('Player-2','test')
  Addon.AssertTrue(svc:IsBlacklisted('Player-2'), 'should be blacklisted')
  svc:Unblacklist('Player-2')
  Addon.AssertFalse(svc:IsBlacklisted('Player-2'), 'should be removed from blacklist')
end)

Harness.AddTest('Duplicate blacklist is idempotent', function()
  local svc = Addon.require('ProspectsService')
  svc:Blacklist('Dup-1','r1')
  local before = 0 for _ in pairs(svc:GetBlacklist()) do before=before+1 end
  svc:Blacklist('Dup-1','r2')
  local after = 0 for _ in pairs(svc:GetBlacklist()) do after=after+1 end
  Addon.AssertEquals(after, before, 'duplicate blacklist should not increase size')
end)

Harness.AddTest('PruneProspects keeps newest', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-3', lastSeen=300 })
  local removed = svc:PruneProspects(2)
  Addon.AssertTrue(removed >= 1, 'expected at least one removal')
  Addon.AssertEquals(#svc:GetAll(), 2, 'expected exactly 2 remaining')
end)

Harness.AddTest('RemoveProspect publishes event', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-R', lastSeen=123 })
  Harness.ClearEvents()
  svc:RemoveProspect('Player-R')
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  Addon.AssertEventPublished(E and E.Prospects.Changed or 'Prospects.Changed', function(a) return a[1]=='removed' and a[2]=='Player-R' end, 'Prospects.Changed removed event not published')
end)

Harness.AddTest('PruneBlacklist retains newest entries', function()
  local svc = Addon.require('ProspectsService')
  svc:Blacklist('PBL-1','r1')
  svc:Blacklist('PBL-2','r2')
  svc:Blacklist('PBL-3','r3')
  local removed = svc:PruneBlacklist(2)
  Addon.AssertTrue(removed >= 1, 'expected blacklist pruning removal')
  local bl = svc:GetBlacklist(); local count=0; for _ in pairs(bl) do count=count+1 end
  Addon.AssertEquals(count, 2, 'expected 2 blacklist entries after prune')
end)

Harness.AddTest('Event publication on blacklist/unblacklist', function()
  local svc = Addon.require('ProspectsService')
  Harness.ClearEvents()
  svc:Blacklist('EVT-1','test')
  svc:Unblacklist('EVT-1')
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local ev = E and E.Prospects.Changed or 'Prospects.Changed'
  Addon.AssertEventPublished(ev, function(a) return a[1]=='blacklisted' end, 'missing blacklisted event')
  Addon.AssertEventPublished(ev, function(a) return a[1]=='unblacklisted' end, 'missing unblacklisted event')
end)

return true
