-- tools/tests/prospects_datalaer_spec.lua
-- Headless tests for ProspectsService & SavedVarsService integration.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

-- Provide SavedVarsService minimal clone (reuse production file by loadfile if available)
if not Addon.IsProvided('SavedVarsService') then
  dofile('Infrastructure/Services/SavedVarsService.lua')
  Addon._RegisterSavedVarsService()
end

-- Provide ProspectsService (production file rely on ClassProvide) 
if not Addon.IsProvided('ProspectsService') then
  dofile('Infrastructure/Services/ProspectsService.lua')
end

Harness.AddTest('ProspectsService Upsert + GetAll', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-1', name='A', level=10, lastSeen=100 })
  svc:Upsert({ guid='Player-2', name='B', level=20, lastSeen=200 })
  assert(#svc:GetAll() == 2, 'expected 2 prospects')
end)

Harness.AddTest('ProspectsService Update merge', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-1', name='A', level=11 })
  local p = svc:Get('Player-1')
  assert(p.level == 11, 'level merge failed')
end)

Harness.AddTest('Blacklist + Unblacklist', function()
  local svc = Addon.require('ProspectsService')
  svc:Blacklist('Player-2','test')
  assert(svc:IsBlacklisted('Player-2'), 'should be blacklisted')
  svc:Unblacklist('Player-2')
  assert(not svc:IsBlacklisted('Player-2'), 'should be removed from blacklist')
end)

Harness.AddTest('PruneProspects keeps newest', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-3', lastSeen=300 })
  local removed = svc:PruneProspects(2)
  assert(removed >= 1, 'expected at least one removal')
  assert(#svc:GetAll() == 2, 'expected exactly 2 remaining')
end)

Harness.AddTest('RemoveProspect publishes event', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='Player-R', lastSeen=123 })
  Harness.ClearEvents()
  svc:RemoveProspect('Player-R')
  local found=false
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  for _,e in ipairs(Addon.TestEvents) do
    if e.event==EV and e.args[1]=='removed' and e.args[2]=='Player-R' then found=true break end
  end
  assert(found, EV..' removed event not published')
end)

Harness.AddTest('PruneBlacklist retains newest entries', function()
  local svc = Addon.require('ProspectsService')
  svc:Blacklist('PBL-1','r1')
  svc:Blacklist('PBL-2','r2')
  svc:Blacklist('PBL-3','r3')
  local removed = svc:PruneBlacklist(2)
  assert(removed >= 1, 'expected blacklist pruning removal')
  local bl = svc:GetBlacklist(); local count=0; for _ in pairs(bl) do count=count+1 end
  assert(count==2, 'expected 2 blacklist entries after prune')
end)

Harness.AddTest('Event publication on blacklist/unblacklist', function()
  local svc = Addon.require('ProspectsService')
  Harness.ClearEvents()
  svc:Blacklist('EVT-1','test')
  svc:Unblacklist('EVT-1')
  local sawBL,sawUB=false,false
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  for _,e in ipairs(Addon.TestEvents) do
    if e.event==EV and e.args[1]=='blacklisted' then sawBL=true end
    if e.event==EV and e.args[1]=='unblacklisted' then sawUB=true end
  end
  assert(sawBL and sawUB, 'missing expected blacklist events')
end)

return true
