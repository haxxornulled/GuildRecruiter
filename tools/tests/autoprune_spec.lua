-- tools/tests/autoprune_spec.lua
-- Tests AutoPruneService RunOnce publishes Prospects.Changed when removals occur.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

-- Load constants & dependencies
if not Addon.IsProvided('Events') then dofile('Core/Events.lua') end
if not Addon.IsProvided('ProspectStatus') then dofile('Core/ProspectStatus.lua') end
if not Addon.IsProvided('ProspectsService') then dofile('Infrastructure/Services/ProspectsService.lua') end
if not Addon.IsProvided('AutoPruneService') then dofile('Infrastructure/Services/AutoPruneService.lua') end

-- Provide a Config stub with required getters
if not Addon.IsProvided('Config') then
  Addon.provide('Config', function()
    local cfg = { _vals = { prospectsMax = 1, blacklistMax = 1, autoPruneInterval = 0 } }
    function cfg:Get(k, def) local v=self._vals[k]; if v==nil then return def end return v end
    function cfg:Set(k,v) self._vals[k]=v end
    return cfg
  end, { lifetime='SingleInstance' })
end

Harness.AddTest('AutoPruneService RunOnce publishes pruned event', function()
  local svc = Addon.require('ProspectsService')
  svc:Upsert({ guid='AP-1', lastSeen=1 })
  svc:Upsert({ guid='AP-2', lastSeen=2 }) -- exceed max=1 to force prune
  Harness.ClearEvents()
  local ap = Addon.require('AutoPruneService')
  ap:RunOnce()
  local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
  local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
  local saw=false
  for _,e in ipairs(Addon.TestEvents) do
    if e.event==EV and e.args[1]=='pruned' and (e.args[2] or 0) >= 1 then saw=true break end
  end
  Addon.AssertTrue(saw, 'expected pruned publish on '..EV)
end)

return true
