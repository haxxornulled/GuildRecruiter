local ADDON_NAME, Addon = ...

local function getLogger()
  local ok, log = pcall(function()
    return Addon.Logger and Addon.Logger:ForContext("Subsystem", "CoreDebug") or nil
  end)
  if ok and log then return log end
end

local function println(msg)
  local log = getLogger()
  if log and log.Info then
    log:Info(tostring(msg))
    return
  end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s][Core]|r %s"):format(ADDON_NAME or "GuildRecruiter", tostring(msg)))
  else
    print(("[%s][Core] %s"):format(ADDON_NAME or "GuildRecruiter", tostring(msg)))
  end
end

local function ensureBus()
  -- Register EventBus factory if available but not yet registered
  local reg = Addon and Addon._RegisterEventBus
  if type(reg) == "function" then
    pcall(reg)
  end
  local ok, bus = pcall(Addon.require or function() end, "EventBus")
  if ok and bus then return bus end
end

local function showHelp()
  println("Core debug commands:")
  println("/gr help        - show this help")
  println("/gr boot        - register and init EventBus")
  println("/gr bus         - show EventBus diagnostics")
  println("/gr pub <event> - publish a test event on EventBus")
  println("/gr regs        - show availability of Core services")
  println("/gr version     - show core version")
  println("/gr log level <L> - set log level (TRACE,DEBUG,INFO,WARN,ERROR,FATAL)")
  println("/gr log test      - emit a test log burst at all levels")
  println("/gr log dump [N]  - print last N log lines (buffer)")
  println("/gr tick          - run a scheduler NextTick smoke test")
  println("/gr diag          - diagnostics summary (services, prospects, events, scheduler)")
  println("/gr di            - DI container diagnostics (services, decorators, singletons)")
  println("/gr di extended   - DI + full snapshot (EventBus/Scheduler)")
  println("/gr bench         - micro benchmark (EventBus publish & Scheduler insert)")
  println("/gr every <sec>   - run a scheduler Every timer once and cancel")
  println("/gr sub <event>   - subscribe to an event and echo once")
  println("/gr debounce <ms> - demo debounce bursts (fires once after quiet)")
  println("/gr throttle <ms> - demo throttle bursts (leading+trailing)")
  println("/gr coalesce <event> <ms> - subscribe & coalesce payloads, publish aggregated")
end

local function handleSlash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  if msg == "" or msg == "help" then
    showHelp(); return
  end

  if msg == "version" then
    local core = Addon and Addon.require and Addon.require("Core")
    println("Core loaded, version="..tostring(core and core.__gr_version or "?"))
    return
  end

  if msg == "boot" then
    local bus = ensureBus()
    if bus and bus.Publish then
      println("EventBus registered and available.")
    else
      println("EventBus not available (registration function missing).")
    end
    return
  end

  if msg == "bus" then
    local bus = ensureBus()
    if not bus then println("EventBus not available."); return end
    local ok, diag = pcall(bus.Diagnostics, bus)
    if ok and diag then
      println(string.format("EventBus publishes=%d errors=%d events=%d", diag.publishes or 0, diag.errors or 0, #(diag.events or {})))
      for _, ev in ipairs(diag.events or {}) do
        println(string.format("  %s (%d handlers)", ev.event, ev.handlers))
      end
    else
      println("EventBus diagnostics not available")
    end
    return
  end

  local sub, rest = msg:match("^(%S+)%s*(.*)$")
  if sub == "pub" then
    local ev = (rest or ""):match("^(%S+)")
    if not ev then println("Usage: /gr pub <event>"); return end
    local bus = ensureBus()
    if not bus then println("EventBus not available."); return end
    local ok = pcall(bus.Publish, bus, ev)
    println(ok and ("Published '"..ev.."'.") or ("Failed to publish '"..ev.."'."))
    return
  end

  if sub == "diag" then
    local counts = (Addon.ResolveOptional and Addon.ResolveOptional('ProspectsService')) and Addon.ResolveOptional('ProspectsService'):GetCounts() or {}
    println(string.format("Prospects: total=%s active=%s new=%s blacklisted=%s",
      counts.total or '?', counts.active or '?', counts.new or '?', counts.blacklisted or '?'))
    local bus = Addon.ResolveOptional and Addon.ResolveOptional('EventBus')
    if bus and bus.Diagnostics then
      local d = bus:Diagnostics()
      println(string.format("EventBus: publishes=%d errors=%d events=%d", d.publishes or 0, d.errors or 0, #(d.events or {})))
    end
    local sch = Addon.ResolveOptional and Addon.ResolveOptional('Scheduler')
    if sch and sch.Diagnostics then
      local sd = sch:Diagnostics()
      println(string.format("Scheduler: tasks=%d ran=%d peak=%d", sd.tasks or 0, sd.ran or 0, sd.peak or 0))
    end
    local regList = (Addon.ListRegistered and Addon.ListRegistered()) or {}
    println("Services registered: "..tostring(#regList))
    return
  end

  if sub == "di" then
    local mode = (rest or ""):match("^(%S+)")
    local root = (Addon.RootScope) or (Addon.ResolveOptional and Addon.ResolveOptional('IServiceProvider')) or (Addon.Get and Addon.Get('IServiceProvider'))
    if not root or not root.Diagnostics then println('DI root not available'); return end
    local d = root:Diagnostics()
    println(string.format('DI: tag=%s services=%d decorators=%d singletons=%d scoped=%d chainDepth=%d',
      d.tag or 'root', d.services or 0, d.decorators or 0, d.singletons or 0, d.scopedInstances or 0, d.chainDepth or 0))
    if mode == 'extended' then
      local list = (Addon.ListRegistered and Addon.ListRegistered()) or {}
      println('Registered keys ('..#list..') => '..table.concat(list, ', '))
      local bus = Addon.ResolveOptional and Addon.ResolveOptional('EventBus')
      local sch = Addon.ResolveOptional and Addon.ResolveOptional('Scheduler')
      local snapshot = {
        di = d,
        bus = bus and bus.Diagnostics and bus:Diagnostics() or {},
        scheduler = sch and sch.Diagnostics and sch:Diagnostics() or {},
      }
      local function encode(v)
        local t = type(v)
        if t == 'table' then
          local parts = {}
          for k, val in pairs(v) do parts[#parts+1] = string.format('%s=%s', tostring(k), encode(val)) end
          table.sort(parts)
          return '{'..table.concat(parts, ';')..'}'
        elseif t == 'string' then return string.format('%q', v)
        else return tostring(v) end
      end
      println('Snapshot='..encode(snapshot))
    end
    return
  end

  if sub == "regs" then
    local function status(key)
      local ok, inst = pcall(Addon.require or function() end, key)
      return ok and inst and "ok" or "missing"
    end
    println("Service availability:")
    println(" - Core: "..status("Core"))
    println(" - EventBus: "..status("EventBus"))
    return
  end

  if sub == "tick" then
    local ok, sch = pcall(Addon.require or function() end, "Scheduler")
    if not ok or not sch or not sch.NextTick then println("Scheduler not available."); return end
    sch:NextTick(function() println("Scheduler: NextTick executed") end)
    return
  end

  if sub == "every" then
    local interval = tonumber((rest or ""):match("^(%S+)")) or 1
    local ok, sch = pcall(Addon.require or function() end, "Scheduler")
    if not ok or not sch or not sch.Every then println("Scheduler not available."); return end
    local token
    token = sch:Every(interval, function()
      println("Scheduler: Every fired; canceling")
      sch:Cancel(token)
    end, { namespace = "CoreDebug" })
    return
  end

  if sub == "sub" then
    local ev = (rest or ""):match("^(%S+)")
    if not ev then println("Usage: /gr sub <event>"); return end
    local bus = ensureBus()
    if not bus then println("EventBus not available."); return end
    local token
    token = bus:Subscribe(ev, function(_, ...)
      println("Event received: "..ev)
      bus:Unsubscribe(token)
    end, { namespace = "CoreDebug" })
    println("Subscribed once to '"..ev.."'.")
    return
  end

  if sub == "debounce" then
    local windowMs = tonumber((rest or ""):match("^(%d+)$")) or 500
    local ok, sch = pcall(Addon.require or function() end, "Scheduler")
    if not ok or not sch or not sch.Debounce then println("Scheduler not available."); return end
    println("Debounce demo: window="..windowMs.."ms sending 10 rapid calls")
    for i = 1, 10 do
      sch:Debounce("DemoDeb", windowMs/1000, function()
        println("Debounce fired once after quiet: i="..i)
      end)
    end
    return
  end

  if sub == "throttle" then
    local windowMs = tonumber((rest or ""):match("^(%d+)$")) or 500
    local ok, sch = pcall(Addon.require or function() end, "Scheduler")
    if not ok or not sch or not sch.Throttle then println("Scheduler not available."); return end
    println("Throttle demo: window="..windowMs.."ms sending 10 rapid calls")
    for i = 1, 10 do
      sch:Throttle("DemoThr", windowMs/1000, function()
        println("Throttle fired at i="..i)
      end)
    end
    return
  end

  if sub == "coalesce" then
    local e, ms = (rest or ""):match("^(%S+) (%d+)")
    if not e or not ms then println("Usage: /gr coalesce <event> <ms>"); return end
    local bus = ensureBus(); if not bus then println("EventBus not available."); return end
    local ok, sch = pcall(Addon.require or function() end, "Scheduler")
    if not ok or not sch or not sch.Coalesce then println("Scheduler without Coalesce."); return end
    println("Coalescing event '"..e.."' over "..ms.."ms; aggregated publishes will appear as '..e..'.Aggregated'")
    local handle = sch:Coalesce(bus, e, ms/1000, function(acc, payload)
      acc = acc or { count = 0 }
      acc.count = acc.count + 1
      return acc
    end, e..".Aggregated", { namespace = "CoreDebug" })
    sch:After(5, function() println("Coalesce auto-unsubscribe after 5s"); if handle and handle.unsubscribe then handle:unsubscribe() end end)
    return
  end

  if sub == "log" then
    local log = getLogger()
    if not log then println("Logger not available."); return end
    local sub2, rest2 = rest:match("^(%S+)%s*(.*)$")
    if sub2 == "level" then
      local lvl = (rest2 or ""):match("^(%S+)")
      if not lvl then println("Usage: /gr log level <TRACE|DEBUG|INFO|WARN|ERROR|FATAL>"); return end
      local okLs, ls = pcall(Addon.require or function() end, "LevelSwitch")
      ---@diagnostic disable-next-line
      if okLs and ls and ls.Set then pcall(ls.Set, ls, lvl:upper()) end
      if log.SetMinLevel then pcall(log.SetMinLevel, log, lvl:upper()) end
      println("Log level set to " .. lvl:upper())
      return
    elseif sub2 == "test" then
      log:Trace("Trace test from {Src}", { Src = "CoreDebug" })
      log:Debug("Debug test from {Src}", { Src = "CoreDebug" })
      log:Info("Info  test from {Src}", { Src = "CoreDebug" })
      log:Warn("Warn  test from {Src}", { Src = "CoreDebug" })
      log:Error("Error test from {Src}", { Src = "CoreDebug" })
      log:Fatal("Fatal test from {Src}", { Src = "CoreDebug" })
      println("Emitted test logs at all levels.")
      return
    elseif sub2 == "dump" then
      local n = tonumber((rest2 or ""):match("^(%d+)") ) or 20
      local okS, sink = pcall(Addon.require or function() end, "LogSink.Buffer")
      local buf = (okS and sink and sink.buffer) or (Addon and Addon.LogBuffer) or {}
      local total = #buf
      local start = total - n + 1; if start < 1 then start = 1 end
      println(string.format("Dumping last %d/%d log lines:", math.min(n, total), total))
      for i = start, total do println(buf[i]) end
      return
    else
      println("Log commands: level <L> | test | dump [N]")
      return
    end
  end

  ---@diagnostic disable-next-line
  if sub == "bench" then
    local bus = Addon.ResolveOptional and Addon.ResolveOptional('EventBus')
    local sch = Addon.ResolveOptional and Addon.ResolveOptional('Scheduler')
    if not bus or not sch then println('Bench requires EventBus & Scheduler'); return end
    local publishes = 2000
    local consumed = 0
    local tok = bus:Subscribe('Bench.Evt', function() consumed = consumed + 1 end, { namespace = 'Bench' })
    local t0 = (GetTime and GetTime()) or os.clock()
    for i = 1, publishes do bus:Publish('Bench.Evt', i) end
    local t1 = (GetTime and GetTime()) or os.clock()
    bus:Unsubscribe(tok)
    local tasks = 1000
    local s0 = (GetTime and GetTime()) or os.clock()
    for i = 1, tasks do sch:After(60, function() end, { namespace = 'BenchSch' }) end
    local s1 = (GetTime and GetTime()) or os.clock()
    local pubTime = (t1 - t0)
    local insTime = (s1 - s0)
    println(string.format('Bench: publishes=%d consumed=%d time=%.4fs (%.2fus/publish)', publishes, consumed, pubTime, (pubTime / publishes) * 1e6))
    println(string.format('Bench: scheduler inserts=%d time=%.4fs (%.2us/task)', tasks, insTime, (insTime / tasks) * 1e6))
    sch:CancelNamespace('BenchSch')
    _G.GuildRecruiterBenchDB = _G.GuildRecruiterBenchDB or { history = {} }
    local h = _G.GuildRecruiterBenchDB.history
    h[#h+1] = { ts = time(), publishes = publishes, pubTime = pubTime, tasks = tasks, insTime = insTime }
    if #h > 25 then table.remove(h, 1) end
    return
  end

  println("Unknown command. Try /gr help.")
end

SLASH_GRCORE1 = "/gr"
SLASH_GRCORE2 = "/grcore"
SlashCmdList.GRCORE = handleSlash
