-- tools/tests/namespace_unsubscribe_spec.lua
-- Tests EventBus:UnsubscribeNamespace and Scheduler:CancelNamespace behavior.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

if not Addon.IsProvided('EventBus') then
  dofile('Infrastructure/Messaging/EventBus.lua')
  Addon._RegisterEventBus()
end
if not Addon.IsProvided('Scheduler') then
  dofile('Infrastructure/Scheduling/Scheduler.lua')
  Addon._RegisterScheduler()
end

Harness.AddTest('EventBus UnsubscribeNamespace removes handlers', function()
  local bus = Addon.require('EventBus')
  local ns = 'NS-EB'
  bus:Subscribe('NS.Evt', function() end, { namespace = ns })
  bus:Subscribe('NS.Evt', function() end, { namespace = ns })
  local before = bus:Diagnostics().events[1] and bus:Diagnostics().events[1].handlers or 0
  local removed = bus:UnsubscribeNamespace(ns)
  local afterDiag = bus:Diagnostics()
  local remaining = 0
  for _,e in ipairs(afterDiag.events) do if e.event=='NS.Evt' then remaining = e.handlers end end
  Addon.AssertTrue(removed >= 2, 'expected >=2 removed by namespace')
  Addon.AssertEquals(remaining, 0, 'namespace handlers not cleared')
end)

Harness.AddTest('Scheduler CancelNamespace stops tasks', function()
  local sch = Addon.require('Scheduler')
  local ns = 'NS-Sch'
  local count = 0
  sch:After(0.1, function() count = count + 1 end, { namespace = ns })
  sch:After(0.2, function() count = count + 1 end, { namespace = ns })
  local canceled = sch:CancelNamespace(ns)
  Harness.Advance(0.3)
  Addon.AssertEquals(count, 0, 'tasks in namespace executed after cancel')
  Addon.AssertTrue(canceled >= 2, 'expected >=2 tasks canceled')
end)

return true
