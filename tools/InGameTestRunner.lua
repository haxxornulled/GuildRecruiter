-- InGameTestRunner.lua
-- Lightweight in-game execution of headless-style tests (no file system globbing).
-- Usage: /gr test   or /gr tests
local name, Addon = ...

if not Addon or not Addon.IsProvided then return end

local function println(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[Tests]|r "..tostring(msg)) end
end

local Harness = { tests = {} }
local registered = false

function Harness.Add(name, fn)
  Harness.tests[#Harness.tests+1] = { name=name, fn=fn }
end

-- Public registration API for external spec files included via TOC
function Addon.RegisterInGameTest(name, fn)
  Harness.Add(name, fn)
end

local function runAll()
  local pass, fail = 0, 0
  println("Running "..#Harness.tests.." tests...")
  for _,t in ipairs(Harness.tests) do
  if Addon.TestContext and Addon.TestContext.BeforeEach then pcall(Addon.TestContext.BeforeEach) end
    local ok, err = pcall(t.fn)
  if Addon.TestContext and Addon.TestContext.AfterEach then pcall(Addon.TestContext.AfterEach) end
    if ok then pass=pass+1; println("|cff00ff00PASS|r "..t.name) else fail=fail+1; println("|cffff3333FAIL|r "..t.name.." - "..tostring(err)) end
  end
  println(string.format("Summary: %d passed, %d failed", pass, fail))
end

-- Minimal assertions
local function Assert(cond, msg) if not cond then error(msg or 'assert failed') end end

-- Wire Prospects service + its deps (reuse production registrations)
local function ensureServices()
  if not (Addon.IsProvided and Addon.IsProvided('ProspectsService')) then
    error('Missing ProspectsService registration (should be loaded via TOC before tests).')
  end
  return true
end

local function defineProspectTests()
  if registered then return end
  ensureServices()
  registered = true
  local svc = Addon.Get('ProspectsService')
  Harness.Add('Upsert basic', function()
  local nowVal = 0 -- avoid referencing unavailable time APIs in static analysis
  svc:Upsert({ guid='IG-1', name='Test', level=10, lastSeen=nowVal })
    local all = svc:GetAll(); Assert(#all >= 1, 'no prospects after upsert')
  end)
  Harness.Add('Blacklist cycle', function()
    svc:Blacklist('IG-1','r')
    Assert(svc:IsBlacklisted('IG-1'), 'expected blacklisted')
    svc:Unblacklist('IG-1')
    Assert(not svc:IsBlacklisted('IG-1'), 'expected unblacklisted')
  end)
end

local function run()
  defineProspectTests()
  if #Harness.tests == 0 then println('No tests registered'); return end
  runAll()
end

-- Expose through Addon table for slash command module to call.
Addon.RunInGameTests = run
