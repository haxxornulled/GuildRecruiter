-- tools/tests/eventbus_once_spec.lua
-- Tests EventBus Once subscription and diagnostics snapshot.
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

-- Load production EventBus file if factory not registered
if not Addon.IsProvided('EventBus') then
  dofile('Infrastructure/Messaging/EventBus.lua')
  Addon._RegisterEventBus()
end

Harness.AddTest('EventBus Once executes only once', function()
  local bus = Addon.require('EventBus')
  local count = 0
  bus:Once('Test.Once', function() count = count + 1 end)
  bus:Publish('Test.Once')
  bus:Publish('Test.Once')
  Addon.AssertEquals(count, 1, 'Once handler should fire exactly once')
end)

Harness.AddTest('EventBus Diagnostics basic shape', function()
  local bus = Addon.require('EventBus')
  bus:Subscribe('Diag.Evt', function() end, { namespace='Diag' })
  local d = bus:Diagnostics()
  Addon.AssertTrue(d.publishes >= 0, 'publishes missing')
  Addon.AssertTrue(type(d.events)=='table', 'events diagnostics missing')
end)

return true
