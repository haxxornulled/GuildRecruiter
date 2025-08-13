-- tools/tests/test_coalesce.lua
-- Coalesce aggregation tests using headless harness.
local Harness = rawget(_G, 'Harness') or rawget(_G, 'HeadlessHarness')
if not Harness then
  error('Harness global not found; load tools/HeadlessHarness.lua first in headless runner')
end
local Addon = Harness.GetAddon()

local bus = Addon.require('EventBus')
local sch = Addon.require('Scheduler')

Harness.AddTest('Coalesce aggregates payload count', function()
  Harness.ResetClock()
  local received
  bus:Subscribe('Ping.Aggregated', function(_, acc) received = acc end)
  sch:Coalesce(bus, 'Ping', 0.5, function(acc, payload)
    acc = acc or { sum=0, count=0 }
    acc.sum = acc.sum + (payload or 0)
    acc.count = acc.count + 1
    return acc
  end, 'Ping.Aggregated')

  -- Fire 3 events inside the window
  bus:Publish('Ping', 2)
  bus:Publish('Ping', 3)
  bus:Publish('Ping', 5)
  -- Advance less than window -> no publish yet
  Harness.Advance(0.49)
  assert(received == nil, 'Should not have published early')
  -- Cross window boundary
  Harness.Advance(0.02)
  assert(received ~= nil, 'Should have received aggregated')
  assert(received.count == 3, 'Expected 3 events coalesced')
  assert(received.sum == 10, 'Sum mismatch')
end)

Harness.AddTest('Coalesce second window separate accumulation', function()
  Harness.ResetClock()
  local results = {}
  bus:Subscribe('Burst.Aggregated', function(_, acc) results[#results+1] = acc end)
  sch:Coalesce(bus, 'Burst', 0.25, function(acc, payload)
    acc = acc or { count=0 }
    acc.count = acc.count + 1
    return acc
  end, 'Burst.Aggregated')
  -- First burst (2 events)
  bus:Publish('Burst', 1)
  bus:Publish('Burst', 1)
  Harness.Advance(0.3) -- triggers first aggregate
  assert(#results == 1 and results[1].count == 2, 'First window expected 2')
  -- Second burst (3 events)
  bus:Publish('Burst', 1)
  bus:Publish('Burst', 1)
  bus:Publish('Burst', 1)
  Harness.Advance(0.26)
  assert(#results == 2 and results[2].count == 3, 'Second window expected 3')
end)

if ... == nil then
  Harness.RunAll()
end
