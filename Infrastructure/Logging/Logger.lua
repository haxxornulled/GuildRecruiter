-- Logger.lua — Structured logging with DI sinks (Autofac-style Core)
-- Factory-based registration, no top-level resolves

local _G = _G or {}
local ADDON_NAME = (select(1, ...) or "GuildRecruiter")
local Addon = select(2, ...) or _G[ADDON_NAME] or {}

-- Factory function for logger system
local function CreateLoggerSystem()
    local Levels = { TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, FATAL=5 }
    local LevelNames = { [0]="TRACE",[1]="DEBUG",[2]="INFO",[3]="WARN",[4]="ERROR",[5]="FATAL" }
    local LevelColors = {
        [0]="a0a0a0",[1]="66ccff",[2]="ffffff",[3]="ffcc00",[4]="ff5555",[5]="ff00ff"
    }

    local _date = rawget(_G, "date") or function(...) return "0000-00-00 00:00:00" end
    local function nowISO() return _date("%Y-%m-%d %H:%M:%S") end
    local function safe_tostring(v)
        local t = type(v)
        if t == "table" or t == "function" or t == "userdata" then return "<"..t..">" end
        return tostring(v)
    end
    local function get_prop(props, key)
        if not props then return nil end
        local v = props
        for part in string.gmatch(key, "([%w_]+)%.?") do
            if type(v) ~= "table" then return nil end
            v = v[part]
        end
        return v
    end
    local function render(template, props)
        if type(template) ~= "string" then return safe_tostring(template) end
        return (template:gsub("{([%w_%.]+)}", function(k)
            local val = get_prop(props, k)
            if val == nil then return "{"..k.."}" end
            return safe_tostring(val)
        end))
    end
    local function shallow(t) local r={}; if t then for k,v in pairs(t) do r[k]=v end end; return r end
    local function merge(a,b) local r=shallow(a); if b then for k,v in pairs(b) do r[k]=v end end; return r end

    return {
        Levels = Levels,
        LevelNames = LevelNames,
        LevelColors = LevelColors,
        nowISO = nowISO,
        safe_tostring = safe_tostring,
        get_prop = get_prop,
        render = render,
        shallow = shallow,
        merge = merge
    }
end

-- Registration function for Init.lua
local function RegisterLoggerFactories()
    if Addon._loggerRegistered then return end
    if not Addon.provide then
        error("Logger: Addon.provide not available")
    end

    local LoggerSystem = CreateLoggerSystem()
    local Levels = LoggerSystem.Levels
    local LevelNames = LoggerSystem.LevelNames  
    local LevelColors = LoggerSystem.LevelColors

    -- ===========================
    -- LevelSwitch (singleton)
    -- ===========================
        local function safeProvide(key, factory, opts)
            if Addon.IsProvided and Addon.IsProvided(key) then return end
            Addon.provide(key, factory, opts)
        end
    safeProvide("LevelSwitch", function(scope)
                local initial = Levels.INFO
                local okCfg, cfg = pcall(function() return (Addon.Get and Addon.Get("IConfiguration")) or (Addon.Peek and Addon.Peek("IConfiguration")) end)
                if okCfg and type(cfg) == "table" and type(cfg.Get) == "function" then
                    local lvlName = tostring(cfg:Get("logLevel", "INFO")):upper()
                    initial = Levels[lvlName] or Levels.INFO
                end
                local self = { min = initial }
        function self:Get() return self.min end
        function self:Set(v)
            if type(v) == "string" then v = Levels[v] end
            if type(v) == "number" then
                local map = { [0]=Levels.TRACE,[1]=Levels.DEBUG,[2]=Levels.INFO,[3]=Levels.WARN,[4]=Levels.ERROR,[5]=Levels.FATAL }
                v = map[v] or Levels.INFO
            end
            if v == nil then v = Levels.INFO end
            self.min = v
        end
        return self
    end, { lifetime = "SingleInstance" })

    -- ===========================
    -- Log Sinks (buffer + chat). Use distinct keys then aggregate.
    -- ===========================
    safeProvide("LogSink.Buffer", function()
        local defaultCap = 500
        local numericCap = tonumber(defaultCap) or 500
        pcall(function()
            local okC, cfg = pcall(function() return (Addon.Get and Addon.Get("IConfiguration")) or (Addon.Peek and Addon.Peek("IConfiguration")) end)
            if okC and type(cfg) == 'table' and type(cfg.Get) == 'function' then
                local v = tonumber(cfg:Get("logBufferCapacity", defaultCap))
                if v ~= nil then numericCap = v end
            end
        end)
        -- Clamp to prevent unbounded memory usage
        local capVal = math.floor(tonumber(numericCap) or defaultCap)
        if capVal < 50 then capVal = 50 elseif capVal > 5000 then capVal = 5000 end
        local self = { capacity = capVal, buffer = {} }
        function self:Write(evt)
            local line = string.format("[%s] %-5s %-18s | %s",
                evt.ts or LoggerSystem.nowISO(), LevelNames[evt.level] or evt.level,
                tostring(evt.source or ""), evt.text or "")
            local buf = self.buffer
            buf[#buf+1] = line
            if #buf > self.capacity then table.remove(buf, 1) end
            -- Store for debug UI (shared ring)
            Addon.LogBuffer = Addon.LogBuffer or {}
            Addon.LogBuffer[#Addon.LogBuffer+1] = line
            if #Addon.LogBuffer > self.capacity then table.remove(Addon.LogBuffer, 1) end
            if Addon.EventBus and Addon.EventBus.Publish then
                pcall(Addon.EventBus.Publish, Addon.EventBus, "LogUpdated", line, evt)
            end
        end
        return self
    end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'logging', sink = 'buffer' } })

    safeProvide("LogSink.Chat", function()
        local self = {}
        local function resolveMin()
            local lvl = "INFO"
            pcall(function()
                local cfg = (Addon.Get and Addon.Get("IConfiguration")) or (Addon.Peek and Addon.Peek("IConfiguration"))
                if cfg and cfg.Get then lvl = tostring(cfg:Get("chatLogMinLevel", "INFO")) end
            end)
            lvl = lvl:upper()
            return Levels[lvl] or Levels.INFO
        end
        local minLevel = resolveMin()
        function self:Write(evt)
            if not DEFAULT_CHAT_FRAME then return end
            if evt.level < minLevel then return end
            local hex = LevelColors[evt.level] or "ffffff"
            local src = evt.source and ("|cff8888ff"..tostring(evt.source).."|r ") or ""
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff%s[%s]|r %s%s",
                hex, LevelNames[evt.level] or evt.level, src, evt.text or ""))
        end
        -- React to config changes to adjust threshold on the fly
        C_Timer.After(0.2, function()
            local ok, bus = pcall(Addon.require, "EventBus")
            if ok and type(bus) == 'table' and type(bus.Subscribe) == 'function' then
                bus:Subscribe("ConfigChanged", function(_, key)
                    if key == "chatLogMinLevel" then minLevel = resolveMin() end
                end, { namespace = "Logger.ChatSink" })
            end
        end)
        return self
    end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'logging', sink = 'chat' } })

    -- ===========================
    -- Logger Factory
    -- ===========================
    local function NewLogger(factory, baseProps)
        local self = {}
        self._f = factory
        self._props = baseProps or {}

        local function write(level, template, props, ex)
            if level < self._f.levelSwitch:Get() then return end
            local merged = LoggerSystem.merge(self._props, props)
            local evt = {
                ts = LoggerSystem.nowISO(),
                level = level,
                source = merged.Source or merged.source or merged.Context or merged.context or ADDON_NAME,
                text = LoggerSystem.render(template, merged),
                props = merged,
                ex = ex,
            }
            for i=1,#self._f.decorators do
                local dec = self._f.decorators[i]
                local ok, handled = pcall(dec, evt, self)
                if not ok then evt.text = evt.text .. " [decorator-error]" end
                if handled == true then return end
            end
            for i=1,#self._f.sinks do
                local s = self._f.sinks[i]
                pcall(s.Write, s, evt)
            end
        end

        function self:SetMinLevel(x) self._f.levelSwitch:Set(x); return self end
        function self:ForContext(k,v) 
            local ctx=LoggerSystem.shallow(self._props); ctx[k]=v; 
            return NewLogger(self._f, ctx) 
        end
        function self:With(props) 
            return NewLogger(self._f, LoggerSystem.merge(self._props, props)) 
        end

        function self:Trace(t,p)   write(Levels.TRACE,t,p) end
        function self:Debug(t,p)   write(Levels.DEBUG,t,p) end
        function self:Info (t,p)   write(Levels.INFO ,t,p) end
        function self:Warn (t,p)   write(Levels.WARN ,t,p) end
        function self:Error(t,p,e) write(Levels.ERROR,t,p,e) end
        function self:Fatal(t,p,e) write(Levels.FATAL,t,p,e) end

        self.Levels = Levels; self.LevelNames = LevelNames
        return self
    end

    safeProvide("LoggerFactory", function(scope)
        local self = {
            levelSwitch = scope:Resolve("LevelSwitch"),
            -- Aggregate known sink keys; tolerate missing ones.
            sinks       = (function()
                local list = {}
                local function try(key)
                    local ok, inst = pcall(scope.Resolve, scope, key)
                    if ok and inst then list[#list+1] = inst end
                end
                try("LogSink.Buffer"); try("LogSink.Chat")
                return list
            end)(),
            decorators  = {},
            addonSource = { Source = ADDON_NAME },
        }
        return self
    end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'logging' } })

    safeProvide("Logger", function(scope)
        local f = scope:Resolve("LoggerFactory")
        return NewLogger(f, LoggerSystem.shallow(f.addonSource))
    end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'logging' } })

        -- React to config changes for dynamic log level & capacity
    local function TryHookConfig()
            local ok, bus = pcall(Addon.require, "EventBus")
            if not ok or not bus or not bus.Subscribe then return end
            bus:Subscribe("ConfigChanged", function(_, key, value)
                if key == "logLevel" then
                    local logger = Addon.require and Addon.require("Logger")
                    local ls = Addon.require and Addon.require("LevelSwitch")
                    if ls then ls:Set(tostring(value):upper()) end
                    if logger and logger.Info then
                        logger:Info("Log level changed to {Level}", { Level = tostring(value) })
                    end
                elseif key == "logBufferCapacity" then
                    -- Resize buffer sink capacity on the fly.
                    local okS, sink = pcall(Addon.require, "LogSink.Buffer")
                    if okS and type(sink) == 'table' and (sink.capacity ~= nil) then
                        local newCap = tonumber(value) or sink.capacity
                        if newCap < 50 then newCap = 50 elseif newCap > 5000 then newCap = 5000 end
                        sink.capacity = newCap
                        local buf = sink.buffer; if type(buf) ~= 'table' then buf = {} ; sink.buffer = buf end
                        while #buf > newCap do table.remove(buf, 1) end
                    end
                end
            end, { namespace = "Logger" })
        end
    C_Timer.After(0.3, TryHookConfig)

    -- Export levels
    safeProvide("Levels", Levels, { lifetime = "SingleInstance" })

    -- No-op logger for early/boot phases or if resolution fails
    local function MakeNoopLogger()
        local n = {}
        local function noop(...) end
        n.Trace = noop; n.Debug = noop; n.Info = noop; n.Warn = noop; n.Error = noop; n.Fatal = noop
        function n:ForContext(k, v) return self end
        function n:With(props) return self end
        function n:SetMinLevel(x) return self end
        n.Levels = LoggerSystem.Levels; n.LevelNames = LoggerSystem.LevelNames
        return n
    end

    local NOOP = MakeNoopLogger()

    -- Lazy export for convenience (resilient during boot)
    Addon.Logger = setmetatable({}, {
        __index = function(_, k)
            -- During boot or if resolution fails, return noop members to avoid crashes in guards like `if Addon.Logger and Addon.Logger.Error then ... end`.
            if Addon._booting then
                local v = NOOP[k]
                if type(v) == "function" then
                    return function() end
                end
                return v
            end
            local ok, inst = pcall(Addon.require, "Logger")
            if not ok or not inst then
                local v = NOOP[k]
                if type(v) == "function" then
                    return function() end
                end
                return v
            end
            local v = inst[k]
            if type(v) == "function" then
                -- Return a wrapper bound to the real instance so calls like pcall(Addon.Logger.Error, Addon.Logger, ...) work
                return function(_, ...)
                    return v(inst, ...)
                end
            end
            return v
        end,
        __call = function(_, ...)
            if Addon._booting then return NOOP, ... end
            local ok, inst = pcall(Addon.require, "Logger")
            if ok and inst then return inst, ... end
            return NOOP, ...
        end
    })
    Addon._loggerRegistered = true
end

-- Export registration function
Addon._RegisterLogger = RegisterLoggerFactories

-- Auto-register on load for convenience (idempotent)
pcall(RegisterLoggerFactories)
return RegisterLoggerFactories
