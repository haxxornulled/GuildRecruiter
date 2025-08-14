-- tools/perf_bench.lua
-- Simple micro-bench harness for EventBus publish throughput & Scheduler insertion cost.
-- Usage: lua tools/perf_bench.lua

package.path = package.path .. ';./?.lua;./tools/?.lua;./Infrastructure/Messaging/?.lua;./Infrastructure/Scheduling/?.lua'

local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

-- Ensure production implementations are loaded
if not Addon.IsProvided('EventBus') then dofile('Infrastructure/Messaging/EventBus.lua'); Addon._RegisterEventBus() end
if not Addon.IsProvided('Scheduler') then dofile('Infrastructure/Scheduling/Scheduler.lua'); Addon._RegisterScheduler() end

local function hrtime()
  return os.clock()
end

local function bench_eventbus_publishes(n)
  local bus = Addon.require('EventBus')
  local consumed = 0
  bus:Subscribe('Bench.Evt', function() consumed = consumed + 1 end, { namespace='Bench' })
  local t0 = hrtime()
  for i=1,n do bus:Publish('Bench.Evt', i) end
  local t1 = hrtime()
  return { publishes=n, consumed=consumed, seconds = (t1 - t0) }
end

local function bench_scheduler_insertions(n)
  local sch = Addon.require('Scheduler')
  local t0 = hrtime()
  for i=1,n do sch:After(60, function() end, { namespace='Bench' }) end
  local t1 = hrtime()
  return { tasks=n, seconds=(t1 - t0) }
end

local function fmt(num) return string.format('%.6f', num) end

local function run()
  local sizes = { 1e3, 5e3, 1e4 }
  print('[PerfBench] EventBus publish throughput')
  for _,n in ipairs(sizes) do
    local r = bench_eventbus_publishes(n)
    print(string.format('  publishes=%d time=%ss avg=%s us/publish', r.publishes, fmt(r.seconds), fmt((r.seconds / r.publishes) * 1e6)))
  end
  print('[PerfBench] Scheduler insertion cost')
  for _,n in ipairs(sizes) do
    local r = bench_scheduler_insertions(n)
    print(string.format('  tasks=%d time=%ss avg=%s us/task', r.tasks, fmt(r.seconds), fmt((r.seconds / r.tasks) * 1e6)))
  end
end

run()

return true
