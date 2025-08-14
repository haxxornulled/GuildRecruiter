-- tools/tests/scheduler_diag_spec.lua
-- Tests Scheduler diagnostics, Debounce, Throttle, and Coalesce behavior in headless harness.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

if not Addon.IsProvided('Scheduler') then
  dofile('Infrastructure/Scheduling/Scheduler.lua')
  Addon._RegisterScheduler()
end
if not Addon.IsProvided('EventBus') then
  dofile('Infrastructure/Messaging/EventBus.lua')
  Addon._RegisterEventBus()
end

Harness.AddTest('Scheduler Debounce coalesces rapid calls', function()
  local sch = Addon.require('Scheduler')
  local fired = 0
  sch:Debounce('K', 0.5, function() fired=fired+1 end)
  sch:Debounce('K', 0.5, function() fired=fired+1 end)
  Harness.Advance(0.49); Addon.AssertEquals(fired, 0, 'debounce fired too early')
  Harness.Advance(0.02); Addon.AssertEquals(fired, 1, 'debounce should fire once after window')
end)

Harness.AddTest('Scheduler Throttle leading + trailing', function()
  local sch = Addon.require('Scheduler')
  local total = 0
  for i=1,5 do sch:Throttle('T', 0.5, function() total=total+1 end, { args={} }) end
  -- first call should fire immediately (leading)
  Addon.AssertEquals(total, 1, 'leading throttle call missing')
  Harness.Advance(0.5)
  -- trailing should fire after window
  Addon.AssertEquals(total, 2, 'expected trailing throttle fire')
end)

Harness.AddTest('Scheduler Coalesce aggregates payload', function()
  local sch = Addon.require('Scheduler')
  local bus = Addon.require('EventBus')
  local result
  sch:Coalesce(bus, 'Co.In', 0.25, function(acc, v) return (acc or 0) + v end, 'Co.Out')
  bus:Publish('Co.In', 1)
  bus:Publish('Co.In', 2)
  Harness.Advance(0.24); Addon.AssertTrue(result == nil, 'coalesce published too early')
  bus:Subscribe('Co.Out', function(_, v) result = v end)
  Harness.Advance(0.02)
  Addon.AssertEquals(result, 3, 'coalesce reducer incorrect')
end)

Harness.AddTest('Scheduler Diagnostics shape', function()
  local sch = Addon.require('Scheduler')
  local d = sch:Diagnostics()
  Addon.AssertTrue(type(d)=='table' and d.tasks >= 0 and d.peak >= 0, 'scheduler diagnostics missing fields')
end)

return true
