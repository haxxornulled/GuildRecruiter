-- Core/DebugCommands.lua — minimal debug slash commands for Core-only smoke tests
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
    for i=1,10 do
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
    for i=1,10 do
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
      acc = acc or { count=0 }
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
      if okLs and ls and ls.Set then
        ls:Set(lvl:upper())
        println("Log level set to "..lvl:upper())
      else
        -- Fallback via logger instance
        log:SetMinLevel(lvl:upper())
        println("Log level set (via logger) to "..lvl:upper())
      end
      return
    elseif sub2 == "test" then
      log:Trace("Trace test from {Src}", { Src = "CoreDebug" })
      log:Debug("Debug test from {Src}", { Src = "CoreDebug" })
      log:Info ("Info  test from {Src}", { Src = "CoreDebug" })
      log:Warn ("Warn  test from {Src}", { Src = "CoreDebug" })
      log:Error("Error test from {Src}", { Src = "CoreDebug" })
      log:Fatal("Fatal test from {Src}", { Src = "CoreDebug" })
      println("Emitted test logs at all levels.")
      return
    elseif sub2 == "dump" then
      local n = tonumber((rest2 or ""):match("^(%d+)")) or 20
  local okS, sink = pcall(Addon.require or function() end, "LogSink.Buffer")
  local buf = (okS and sink and sink.buffer) or (Addon and Addon.LogBuffer) or {}
      local total = #buf
      local start = math.max(1, total - n + 1)
      println(string.format("Dumping last %d/%d log lines:", math.min(n, total), total))
      for i = start, total do println(buf[i]) end
      return
    else
      println("Log commands: level <L> | test | dump [N]")
      return
    end
  end

  println("Unknown command. Try /gr help.")
end

-- Register slash commands (kept simple for core-only; full addon overrides later)
SLASH_GRCORE1 = "/gr"
SLASH_GRCORE2 = "/grcore"
SlashCmdList.GRCORE = handleSlash
