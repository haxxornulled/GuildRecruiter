-- Scheduler.lua — OnUpdate micro-scheduler + debounce/throttle/coalesce helpers
-- Factory-based registration, no top-level resolves

local ADDON_NAME, Addon = ...

local function now() return GetTime() end
local function newid() return tostring({}):gsub("table: ", "sch#") end

-- Min-heap by .due
local Heap = {} ; Heap.__index = Heap
function Heap.new() return setmetatable({ a = {} }, Heap) end
local function cmp(a,b) return a.due < b.due end
local function up(h,i) local a=h.a; while i>1 do local p=math.floor(i/2); if not cmp(a[i],a[p]) then break end; a[i],a[p]=a[p],a[i]; i=p end end
local function down(h,i) local a=h.a; local n=#a; while true do local l=i*2; local r=l+1; local s=i; if l<=n and cmp(a[l],a[s]) then s=l end; if r<=n and cmp(a[r],a[s]) then s=r end; if s==i then break end; a[i],a[s]=a[s],a[i]; i=s end end
function Heap:push(x) local a=self.a; a[#a+1]=x; up(self,#a) end
function Heap:peek() return self.a[1] end
function Heap:pop() local a=self.a; local n=#a; if n==0 then return nil end; local t=a[1]; a[1]=a[n]; a[n]=nil; if n>1 then down(self,1) end; return t end
function Heap:size() return #self.a end
function Heap:clear() self.a = {} end

-- Factory function for DI container (proper lazy resolution)
local function CreateScheduler()
    -- Lazy dependency accessor - resolved only when actually used
    local function getLog()
      return Addon.require("Logger"):ForContext("Subsystem","Scheduler")
    end

  local self = {}
  local frame, running = nil, false
  local heap = Heap.new()
  local index, nsIndex = {}, {}
  local deb, thr = {}, {}

  local function schedule(due, fn, interval, ns)
    local t = { token = newid(), due = due, fn = fn, interval = interval, ns = ns }
    heap:push(t); index[t.token]=t
    if ns then nsIndex[ns]=nsIndex[ns] or {}; nsIndex[ns][t.token]=true end
    return t.token
  end

  local function cancelToken(tok)
    local t = index[tok]; if not t then return false end
    t.canceled = true; index[tok]=nil; if t.ns and nsIndex[t.ns] then nsIndex[t.ns][tok]=nil end
    return true
  end
  local function cancelNS(ns)
    local set = nsIndex[ns]; if not set then return 0 end
    local c=0; for tok in pairs(set) do if cancelToken(tok) then c=c+1 end end
    nsIndex[ns]=nil; return c
  end

  local function pump()
    local nowt = now()
    while heap:size()>0 do
      local top = heap:peek()
      if not top or top.due > nowt then break end
      heap:pop()
      if not top.canceled then
        local ok, err = pcall(top.fn, nowt, top.token)
        if not ok then getLog():Error("Scheduled task error: {Err}", { Err = tostring(err) }) end
        if top.interval and not top.canceled then
          repeat top.due = top.due + top.interval until top.due > nowt
          heap:push(top)
        else
          index[top.token] = nil
          if top.ns and nsIndex[top.ns] then nsIndex[top.ns][top.token] = nil end
        end
      else
        index[top.token] = nil
      end
    end
  end

  local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", ADDON_NAME.."SchedulerFrame")
    frame:Hide()
    frame:SetScript("OnUpdate", function() if running then pump() end end)
  end

  -- Public API
  function self:Start() 
    -- Dependency-free startup - just initialize internal state
    ensureFrame()
    running = true
    getLog():Debug("Scheduler started")
  end
  function self:Stop()
    running=false
    if frame then frame:SetScript("OnUpdate", nil); frame:Hide(); frame=nil end
    heap:clear(); index, nsIndex, deb, thr = {}, {}, {}, {}
    getLog():Debug("Scheduler stopped")
  end

  function self:NextTick(fn, opts) opts=opts or {}; return schedule(now(), fn, nil, opts.namespace) end
  function self:After(delay, fn, opts) opts=opts or {}; return schedule(now() + math.max(0, delay or 0), fn, nil, opts.namespace) end
  function self:Every(interval, fn, opts) assert(interval and interval>0, "Every(interval>0)"); opts=opts or {}; return schedule(now()+interval, fn, interval, opts.namespace) end
  function self:Cancel(tok) return cancelToken(tok) end
  function self:CancelNamespace(ns) return cancelNS(ns) end

  -- Debounce(key, window, fn, {namespace, args})
  function self:Debounce(key, window, fn, opts)
    assert(type(key)=="string" and window and window>=0 and type(fn)=="function","Debounce")
    opts=opts or {}
    local e = deb[key] or {}
    if e.token then cancelToken(e.token) end
    e.fn, e.window, e.ns = fn, window, opts.namespace
    e.lastArgs = opts.args or {}
    e.token = schedule(now()+window, function() local f=e.fn; local a=e.lastArgs; deb[key]=nil; pcall(f, unpack(a)) end, nil, e.ns)
    deb[key] = e
    return e.token
  end

  -- Throttle(key, window, fn, {namespace, args, leading=true, trailing=true})
  function self:Throttle(key, window, fn, opts)
    assert(type(key)=="string" and window and window>0 and type(fn)=="function","Throttle")
    opts=opts or {}
    local e = thr[key] or { lastFire = 0, leading = (opts.leading ~= false), trailing = (opts.trailing ~= false), ns = opts.namespace }
    local t = now()
    local remaining = e.lastFire + window - t
    if remaining <= 0 then
      if e.leading then pcall(fn, unpack(opts.args or {})) end
      e.lastFire = t
      if e.trailingToken then cancelToken(e.trailingToken); e.trailingToken=nil end
      e.trailingArgs = nil
    else
      if e.trailing then
        e.trailingArgs = opts.args or e.trailingArgs
        if not e.trailingToken then
          e.trailingToken = schedule(e.lastFire + window, function()
            e.trailingToken=nil; e.lastFire = now()
            if e.trailingArgs then pcall(fn, unpack(e.trailingArgs)); e.trailingArgs=nil end
          end, nil, e.ns)
        end
      end
    end
    thr[key] = e
    return e.trailingToken
  end

  -- Coalesce(bus, event, window, reducerFn, publishAs?, opts={namespace})
  function self:Coalesce(bus, event, window, reducerFn, publishAs, opts)
    assert(bus and type(bus.Subscribe)=="function" and type(bus.Publish)=="function", "Coalesce: need EventBus")
    assert(type(event)=="string" and window and window>0 and type(reducerFn)=="function", "Coalesce args")
    opts = opts or {}; local ns = opts.namespace or ("Coalesce:"..event)
    local acc, have, timer = nil, false, nil
    local tok = bus:Subscribe(event, function(_, ...)
      if not have then acc = reducerFn(nil, ...); have=true else acc = reducerFn(acc, ...) end
      if not timer then
        timer = self:After(window, function()
          local out = acc; acc, have, timer = nil, false, nil
          bus:Publish(publishAs or event, out)
        end, { namespace = ns })
      end
    end, { namespace = ns })
    return {
      unsubscribe = function()
        if tok then bus:Unsubscribe(tok); tok=nil end
        if timer then self:Cancel(timer); timer=nil end
        self:CancelNamespace(ns)
      end
    }
  end

  function self:Count() return heap:size() end

  return self
end

-- Registration function for Init.lua
local function RegisterSchedulerFactory()
  if not Addon.provide then
    error("Scheduler: Addon.provide not available")
  end
  
  Addon.provide("Scheduler", CreateScheduler, { lifetime = "SingleInstance" })
  
  -- Lazy export (safe)
  Addon.Scheduler = setmetatable({}, {
    __index = function(_, k) 
      if Addon._booting then
        error("Cannot access Scheduler during boot phase")
      end
      local inst = Addon.require("Scheduler"); return inst[k] 
    end,
    __call  = function(_, ...) return Addon.require("Scheduler"), ... end
  })
end

-- Export registration function
Addon._RegisterScheduler = RegisterSchedulerFactory

return RegisterSchedulerFactory
