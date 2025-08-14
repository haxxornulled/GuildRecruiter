-- (Addon defined below; helpers appended after Addon local)
-- tools/HeadlessHarness.lua
-- Minimal headless test harness to exercise pure Core / ports without WoW globals.
-- Usage (outside game): load this file with a Lua 5.1 interpreter after stubbing required WoW APIs.
-- Focus: Demonstrate bootstrapping DI, EventBus mock, Scheduler logic (pure portions), Logger buffer sink.

local Harness = { tests = {} }
Harness.__index = Harness

-- Simple stub Addon table replicating minimal DI surface.
local Addon = { _registry = {}, _singletons = {}, _booting = false }

-- Assertion helpers (now Addon exists)
function Addon.AssertEquals(a,b,msg)
  if a~=b then error(msg or ('AssertEquals failed: '..tostring(a)..' ~= '..tostring(b))) end
end
function Addon.AssertTrue(v,msg) if not v then error(msg or 'AssertTrue failed') end end
function Addon.AssertFalse(v,msg) if v then error(msg or 'AssertFalse failed') end end
function Addon.AssertEventPublished(ev,predicate,msg)
  for _,e in ipairs(Addon.TestEvents) do
    if e.event==ev and (not predicate or predicate(e.args)) then return true end
  end
  error(msg or ('Expected event '..ev..' not published'))
end

function Addon.provide(name, factory, opts) Addon._registry[name] = { factory = factory, opts = opts or {} } end
function Addon.IsProvided(name) return Addon._registry[name] ~= nil end
function Addon.require(name)
  local reg = Addon._registry[name]; if not reg then error('Dependency not provided: '..tostring(name)) end
  if reg.opts.lifetime == 'SingleInstance' then
    if not Addon._singletons[name] then Addon._singletons[name] = reg.factory(Addon) end
    return Addon._singletons[name]
  end
  return reg.factory(Addon)
end

-- Provide Get/Peek compatibility used by production modules
function Addon.Get(name) if Addon.IsProvided(name) then local ok,v=pcall(Addon.require,name); if ok then return v end end end
function Addon.Peek(name) return Addon.Get(name) end

-- Lightweight buffer logger for headless usage if real logger not loaded.
local BufferLogger = {}; BufferLogger.__index = BufferLogger
function BufferLogger:new() return setmetatable({ lines = {} }, self) end
local levels = { TRACE=1, DEBUG=2, INFO=3, WARN=4, ERROR=5, FATAL=6 }
local function log(self, level, msg) self.lines[#self.lines+1] = level..': '..msg end
for lvl,_ in pairs(levels) do BufferLogger[lvl:sub(1,1)..lvl:sub(2):lower()] = function(self,m) log(self,lvl,m) end end
function BufferLogger:Dump() for _,l in ipairs(self.lines) do print(l) end end

-- Provide fake Logger if none.
Addon.provide('Logger', function() local root=BufferLogger:new(); function root:ForContext() return self end; return root end, { lifetime='SingleInstance' })

-- Provide a pure EventBus (no WoW frame):
Addon.TestEvents = {}
Addon.provide('EventBus', function()
  local self = { _subs={}, _next=0 }
  function self:Publish(ev, ...) Addon.TestEvents[#Addon.TestEvents+1]={event=ev,args={...}}; local s=self._subs[ev]; if s then for _,h in pairs(s) do pcall(h.fn, ev, ...) end end end
  function self:Subscribe(ev, fn, opts) self._next=self._next+1; local tok='sub'..self._next; local s=self._subs[ev] or {}; s[tok]={fn=fn,ns=opts and opts.namespace}; self._subs[ev]=s; return tok end
  function self:Unsubscribe(tok) for _,s in pairs(self._subs) do if s[tok] then s[tok]=nil; return true end end return false end
  function self:Diagnostics() local c=0; for _,s in pairs(self._subs) do for _ in pairs(s) do c=c+1 end end; return { Total=c } end
  return self
end, { lifetime='SingleInstance' })

-- Provide a micro scheduler using socket.gettime (if available) or os.clock (coarser).
-- Attempt to access socket.gettime; fall back to a monotonic-ish clock.
-- Deterministic simulated time
local _now = 0
local function now() return _now end

Addon.provide('Scheduler', function()
  local self = { _tasks = {}, _next=0, _deb={}, _thr={} }
  local function schedule(due, fn, interval)
    self._next = self._next + 1
    local t = { due=due, fn=fn, interval=interval, tok=self._next }
    self._tasks[#self._tasks+1] = t
    return t.tok, t
  end
  function self:NextTick(fn) return schedule(now(), fn) end
  function self:After(d, fn) return schedule(now()+d, fn) end
  function self:Every(interval, fn)
    local function runner() pcall(fn); schedule(now()+interval, runner) end
    return select(1, schedule(now()+interval, runner, interval))
  end
  function self:Pump()
    table.sort(self._tasks, function(a,b) return (a.due or 0) < (b.due or 0) end)
    local i=1
    while i <= #self._tasks do
      local t = self._tasks[i]
      if not t or (t.due or 0) > now() then break end
      table.remove(self._tasks, i)
      if t.fn then pcall(t.fn, t.tok) end
    end
  end
  function self:Advance(dt) _now = _now + dt; self:Pump() end
  function self:Debounce(key, window, fn)
    local e = self._deb[key] or {}; e.fn=fn; e.window=window; e.due=now()+window; self._deb[key]=e
    schedule(e.due, function() if now() >= e.due then pcall(e.fn) end end)
  end
  function self:Throttle(key, window, fn)
    local e = self._thr[key]; if not e then e={ lastFire=-math.huge }; self._thr[key]=e end
    local elapsed = now() - e.lastFire
    if elapsed >= window then
      e.lastFire = now(); pcall(fn); return
    end
    if e.trailing then return end
    e.trailing=true
    local fireAt = e.lastFire + window
    schedule(fireAt, function()
      e.trailing=false; e.lastFire=now(); pcall(fn)
    end)
  end
  function self:Coalesce(bus, event, window, reducerFn, publishAs)
    local state = { acc=nil, timer=nil }
    local token = bus:Subscribe(event, function(_, ...)
      state.acc = reducerFn(state.acc, ...)
      if not state.timer then
        state.timer = schedule(now()+window, function() bus:Publish(publishAs or event, state.acc); state.acc=nil; state.timer=nil end)
      end
    end)
    return { unsubscribe=function() if token then bus:Unsubscribe(token); token=nil end end }
  end
  return self
end, { lifetime='SingleInstance' })

function Harness.Run() end -- legacy no-op
function Harness.Advance(dt) Addon.require('Scheduler'):Advance(dt) end

function Harness.AddTest(name, fn) Harness.tests[#Harness.tests+1] = { name=name, fn=fn } end
function Harness.ClearEvents() Addon.TestEvents = {} end

local function result(ok,msg) print((ok and '[PASS] ' or '[FAIL] ')..msg) end

function Harness.RunAll()
  local log = Addon.require('Logger'); log:Info('Running '..#Harness.tests..' tests')
  local pass,fail=0,0
  for _,t in ipairs(Harness.tests) do
    local ok, err = pcall(t.fn)
    if ok then pass=pass+1; result(true, t.name) else fail=fail+1; result(false, t.name..' error: '..tostring(err)) end
  end
  print(string.format('Summary: %d passed, %d failed', pass, fail))
  if log.Dump then log:Dump() end
end

function Harness.ResetClock() _now = 0 end

function Harness.GetTime() return _now end

function Harness.GetAddon() return Addon end

-- Legacy single-run demonstration
-- Legacy demo removed (kept minimal to silence analyzer)

return Harness
