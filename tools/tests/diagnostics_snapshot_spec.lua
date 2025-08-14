-- tools/tests/diagnostics_snapshot_spec.lua
-- Generates a deterministic diagnostics snapshot and compares to stored golden file (if present).
local Harness = require('tools.HeadlessHarness')
local Addon = Harness.GetAddon()

if not Addon.IsProvided('EventBus') then dofile('Infrastructure/Messaging/EventBus.lua'); Addon._RegisterEventBus() end
if not Addon.IsProvided('Scheduler') then dofile('Infrastructure/Scheduling/Scheduler.lua'); Addon._RegisterScheduler() end

local GOLDEN_PATH = 'tools/tests/_golden_diagnostics.txt'

local function encode(v)
  local t = type(v)
  if t=='table' then
    local keys = {}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
    local parts = {}
    for _,k in ipairs(keys) do parts[#parts+1] = tostring(k)..'='..encode(v[k]) end
    return '{'..table.concat(parts,';')..'}'
  elseif t=='string' then return string.format('%q', v)
  else return tostring(v) end
end

local function snapshot()
  local bus = Addon.require('EventBus')
  local sch = Addon.require('Scheduler')
  -- seed some activity
  bus:Publish('Snapshot.Warm')
  sch:After(0.1, function() end, { namespace='Snap' })
  local snap = {
    bus = bus:Diagnostics(),
    scheduler = sch:Diagnostics(),
  }
  return encode(snap)
end

Harness.AddTest('Diagnostics golden snapshot stable', function()
  local s = snapshot()
  local f = io.open(GOLDEN_PATH, 'r')
  if not f then
    -- first run: write golden
    local wf = assert(io.open(GOLDEN_PATH, 'w'))
  assert(type(s)=='string', 'snapshot must be string')
  wf:write(s)
  wf:close()
    return -- accept baseline
  end
  local golden = f:read('*a'); f:close()
  if golden ~= s then
    error('Diagnostics snapshot drift.\nGolden: '..golden..'\nCurrent:'..s)
  end
end)

return true
