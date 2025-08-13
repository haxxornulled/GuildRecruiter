-- tools/HeadlessHarness.lua
-- Minimal headless test harness to exercise pure Core / ports without WoW globals.
-- Usage (outside game): load this file with a Lua 5.1 interpreter after stubbing required WoW APIs.
-- Focus: Demonstrate bootstrapping DI, EventBus mock, Scheduler logic (pure portions), Logger buffer sink.

local Harness = { tests = {} }
Harness.__index = Harness

-- Simple stub Addon table replicating minimal DI surface.
local Addon = { _registry = {}, _singletons = {}, _booting = false }

function Addon.provide(name, factory, opts)
  Addon._registry[name] = { factory = factory, opts = opts or {} }
end
function Addon.IsProvided(name) return Addon._registry[name] ~= nil end
function Addon.require(name)
  local reg = Addon._registry[name]
  if not reg then error("Dependency not provided: "..tostring(name)) end
  if reg.opts.lifetime == 'SingleInstance' then
    if not Addon._singletons[name] then
      Addon._singletons[name] = reg.factory(Addon)
    end
    return Addon._singletons[name]
  end
  return reg.factory(Addon)
end

-- Lightweight buffer logger for headless usage if real logger not loaded.
local BufferLogger = {}
BufferLogger.__index = BufferLogger
function BufferLogger:new()
  return setmetatable({ lines = {} }, self)
end
local levels = { TRACE=1, DEBUG=2, INFO=3, WARN=4, ERROR=5, FATAL=6 }
local function log(self, level, msg)
  table.insert(self.lines, level..": "..msg)
end
for lvl,_ in pairs(levels) do
  BufferLogger[lvl:sub(1,1)..lvl:sub(2):lower()] = function(self, m) log(self,lvl,m) end
end
function BufferLogger:Dump() for i,l in ipairs(self.lines) do print(l) end end

-- Provide fake Logger if none.
Addon.provide('Logger', function()
  local root = BufferLogger:new()
  function root:ForContext(k,v) return self end
  return root
end, { lifetime='SingleInstance' })

-- Provide a pure EventBus (no WoW frame):
Addon.provide('EventBus', function()
  local self = { _subs = {}, _next=0 }
  function self:Publish(ev, ...) local s=self._subs[ev]; if s then for _,h in pairs(s) do h.fn(ev, ...) end end end
  function self:Subscribe(ev, fn, opts) self._next=self._next+1; local tok='sub'..self._next; local s=self._subs[ev] or {}; s[tok]={ fn=fn, ns=opts and opts.namespace }; self._subs[ev]=s; return tok end
  function self:Unsubscribe(tok)
    for ev,s in pairs(self._subs) do if s[tok] then s[tok]=nil; return true end end
    return false
  end
  function self:Diagnostics() local c=0; for ev,s in pairs(self._subs) do for _ in pairs(s) do c=c+1 end end; return { Total=c } end
  return self
end, { lifetime='SingleInstance' })

-- Provide a micro scheduler using socket.gettime (if available) or os.clock (coarser).
-- Attempt to access socket.gettime; fall back to a monotonic-ish clock.
-- Deterministic simulated time
local _now = 0
local function now() return _now end

Addon.provide('Scheduler', function()
  local self = { _tasks = {}, _next=0, _deb={}, _thr={}, _busCoalesce={} }
  local function schedule(due, fn, interval)
    self._next = self._next + 1
    local t = { due = due, fn = fn, interval = interval, tok = self._next }
    table.insert(self._tasks, t)
    return t.tok, t
  end
  function self:NextTick(fn) return schedule(now(), fn) end
  function self:After(d, fn) return schedule(now()+d, fn) end
  function self:Every(interval, fn)
    local tok; tok = select(1, schedule(now()+interval, function()
      fn(); if tok then -- reschedule
        for _,t in ipairs(self._tasks) do if t.tok==tok then return end end
        tok = select(1, schedule(now()+interval, function() fn() end))
      end
    end, interval))
    return tok
  end
  function self:Pump()
    table.sort(self._tasks, function(a,b) return a.due < b.due end)
    local i=1
    while i <= #self._tasks do
      local t = self._tasks[i]
      if t.due > now() then break end
      table.remove(self._tasks, i)
      pcall(t.fn, t.tok)
    end
  end
  function self:Advance(dt)
    _now = _now + dt
    self:Pump()
  end
  -- Debounce(key, window, fn)
  function self:Debounce(key, window, fn)
    local e = self._deb[key] or {}
    e.fn = fn; e.window = window; e.lastDue = now()+window
    e.due = e.lastDue
    self._deb[key] = e
    schedule(e.due, function()
      if now() >= e.lastDue then pcall(e.fn) end
    end)
  end
  -- Throttle(key, window, fn, opts)
  function self:Throttle(key, window, fn, opts)
    opts = opts or { leading=true, trailing=true }
    local e = self._thr[key]
    if not e then e = { lastFire = -math.huge } self._thr[key]=e end
    local remaining = (e.lastFire + window) - now()
    if remaining <= 0 then
      e.lastFire = now(); if opts.leading ~= false then pcall(fn) end
    else
      if opts.trailing ~= false and not e.trailing then
        e.trailing = true
        schedule(e.lastFire + window, function()
          e.trailing = false; e.lastFire = now(); pcall(fn)
        end)
      end
    end
  end
  -- Coalesce(bus, event, window, reducerFn, publishAs)
  function self:Coalesce(bus, event, window, reducerFn, publishAs)
    local state = { acc=nil, have=false, timer=nil }
    local token
    token = bus:Subscribe(event, function(_, ...)
      state.acc = reducerFn(state.acc, ...)
      state.have = true
      if not state.timer then
        state.timer = schedule(now()+window, function()
          if state.have then
            bus:Publish(publishAs or event, state.acc)
          end
          state.acc=nil; state.have=false; state.timer=nil
        end)
      end
    end)
    return { unsubscribe = function() if token then bus:Unsubscribe(token); token=nil end end }
  end
  return self
end, { lifetime='SingleInstance' })

function Harness.Run()
function Harness.Advance(dt)
  Addon.require('Scheduler'):Advance(dt)
end

function Harness.AddTest(name, fn)
  Harness.tests[#Harness.tests+1] = { name=name, fn=fn }
end

local function result(ok,msg)
  if ok then print('[PASS] '..msg) else print('[FAIL] '..msg) end
end

function Harness.RunAll()
  local log = Addon.require('Logger')
  log:Info('Running '..#Harness.tests..' tests')
  for _,t in ipairs(Harness.tests) do
    local ok, err = pcall(t.fn)
    if not ok then result(false, t.name..' error: '..tostring(err)) else result(true, t.name) end
  end
  log:Info('All tests complete')
  if log.Dump then log:Dump() end
end

function Harness.ResetClock()
  _now = 0
end

function Harness.GetTime() return _now end

function Harness.GetAddon() return Addon end

-- Legacy single-run demonstration
function Harness.Run()
  Harness.ResetClock()
  local bus = Addon.require('EventBus')
  local sch = Addon.require('Scheduler')
  bus:Subscribe('Ping', function(_, payload) print('Got Ping '..tostring(payload)) end)
  bus:Publish('Ping','A')
  sch:After(0.1, function() bus:Publish('Ping','Delayed') end)
  while Harness.GetTime() < 0.2 do Harness.Advance(0.01) end
end
end

return Harness
