-- DevHarness.lua — lightweight manual diagnostics (loaded only if added to .toc)
local ADDON_NAME, Addon = ...

local function println(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage('|cff99ddff['..ADDON_NAME..'][Harness]|r '..tostring(msg))
  end
end

local function safeRequire(key)
  local ok, inst = pcall(Addon.require, key)
  return ok and inst or nil
end

function GuildRecruiter_RunDiag()
  println('Running quick diagnostics...')
  local rec = safeRequire('Recruiter')
  if rec and rec.QueueStats then
    local qs = rec:QueueStats()
    println(string.format('Queue: total=%d duplicates=%d runtime=%d', qs.total, qs.duplicates, qs.runtime))
  end
  local sched = safeRequire('Scheduler')
  if sched and sched.Count then println('Scheduler tasks: '..sched:Count()) end
  local bus = safeRequire('EventBus')
  if bus and bus.Diagnostics then
    local d = bus:Diagnostics(); println('EventBus publishes='..d.publishes..' events='..#d.events)
  end
  println('Done.')
end

SLASH_GUILDRECRUITERHARNESS1 = '/grh'
SlashCmdList.GUILDRECRUITERHARNESS = function(msg)
  if msg == 'diag' or msg == '' then GuildRecruiter_RunDiag() else println('Usage: /grh diag') end
end
