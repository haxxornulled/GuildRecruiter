-- Logger.lua — Structured logging with DI sinks (Autofac-style Core)
-- Factory-based registration, no top-level resolves

local ADDON_NAME, Addon = ...

-- Factory function for logger system
local function CreateLoggerSystem()
    local Levels = { TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, FATAL=5 }
    local LevelNames = { [0]="TRACE",[1]="DEBUG",[2]="INFO",[3]="WARN",[4]="ERROR",[5]="FATAL" }
    local LevelColors = {
        [0]="a0a0a0",[1]="66ccff",[2]="ffffff",[3]="ffcc00",[4]="ff5555",[5]="ff00ff"
    }

    local function nowISO() return date("%Y-%m-%d %H:%M:%S") end
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
    Addon.provide("LevelSwitch", function()
        local self = { min = Levels.INFO }
        function self:Get() return self.min end
        function self:Set(v)
            if type(v) == "string" then v = Levels[v] end
            if type(v) ~= "number" then v = Levels.INFO end
            self.min = v
        end
        return self
    end, { lifetime = "SingleInstance" })

    -- ===========================
    -- Log Sinks
    -- ===========================
    Addon.provide("LogSink", function()
        local self = { capacity = 500, buffer = {} }
        function self:Write(evt)
            local line = string.format("[%s] %-5s %-18s | %s",
                evt.ts or LoggerSystem.nowISO(), LevelNames[evt.level] or evt.level, 
                tostring(evt.source or ""), evt.text or "")
            local buf = self.buffer
            buf[#buf+1] = line
            if #buf > self.capacity then table.remove(buf, 1) end

            -- Store for debug UI
            Addon.LogBuffer = Addon.LogBuffer or {}
            Addon.LogBuffer[#Addon.LogBuffer+1] = line
            if #Addon.LogBuffer > self.capacity then 
                table.remove(Addon.LogBuffer, 1) 
            end

            -- Try to publish log event (safe)
            if Addon.EventBus and Addon.EventBus.Publish then 
                pcall(Addon.EventBus.Publish, Addon.EventBus, "LogUpdated", line, evt) 
            end
        end
        return self
    end, { lifetime = "SingleInstance" })

    Addon.provide("LogSink", function()
        local self = {}
        function self:Write(evt)
            if not DEFAULT_CHAT_FRAME then return end
            local hex = LevelColors[evt.level] or "ffffff"
            local src = evt.source and ("|cff8888ff"..tostring(evt.source).."|r ") or ""
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff%s[%s]|r %s%s",
                hex, LevelNames[evt.level] or evt.level, src, evt.text or ""))
        end
        return self
    end, { lifetime = "SingleInstance" })

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

    Addon.provide("LoggerFactory", function(scope)
        local self = {
            levelSwitch = scope:Resolve("LevelSwitch"),
            sinks       = scope:ResolveAll("LogSink"),
            decorators  = {},
            addonSource = { Source = ADDON_NAME },
        }
        return self
    end, { lifetime = "SingleInstance" })

    Addon.provide("Logger", function(scope)
        local f = scope:Resolve("LoggerFactory")
        return NewLogger(f, LoggerSystem.shallow(f.addonSource))
    end, { lifetime = "SingleInstance" })

    -- Export levels
    Addon.provide("Levels", Levels, { lifetime = "SingleInstance" })

    -- Lazy export for convenience (safe)
    Addon.Logger = setmetatable({}, {
        __index = function(_, k)
            if Addon._booting then
                error("Cannot access Logger during boot phase")
            end
            local inst = Addon.require("Logger"); return inst[k]
        end,
        __call = function(_, ...) return Addon.require("Logger"), ... end
    })
    Addon._loggerRegistered = true
end

-- Export registration function
Addon._RegisterLogger = RegisterLoggerFactories

-- Auto-register on load for convenience (idempotent)
pcall(RegisterLoggerFactories)
return RegisterLoggerFactories
