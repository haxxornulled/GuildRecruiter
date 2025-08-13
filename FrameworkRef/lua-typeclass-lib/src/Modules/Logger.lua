-- Logger.lua - Enterprise-grade Serilog-style logging system for WoW AddOns
local ADDON_NAME = "TaintedSin" -- Change for your project!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

local Logger = {}

-- Log levels with numeric priorities
local LEVELS = {
    DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5
}

local LEVEL_COLORS = {
    DEBUG = "|cffaaaaaa",  -- Gray
    INFO  = "|cff33ff99",  -- Green
    WARN  = "|cffffff00",  -- Yellow
    ERROR = "|cffff5555",  -- Red
    FATAL = "|cffff0000",  -- Dark Red
}

local DEFAULT_LEVEL = LEVELS.INFO
Logger.LEVELS = LEVELS

local sinks = {}
local enrichers = {}
local globalLevel = DEFAULT_LEVEL

-- Logger Instance for .ForContext()
local LoggerInstance = {}
LoggerInstance.__index = LoggerInstance

-- === Event Construction ===
local function createEvent(level, message, args, properties, context)
    local DateTime = Addon.require and Addon.require("DateTime")
    local timeStr = DateTime and DateTime.FormatUTC and DateTime.FormatUTC(DateTime.UtcEpoch()) or date("%Y-%m-%dT%H:%M:%S")
    local timestamp = DateTime and DateTime.UtcNow and DateTime.UtcNow() or date("!*t")
    local formatted = message
    if args and #args > 0 then
        local ok, result = pcall(string.format, message, table.unpack(args))
        formatted = ok and result or ("LOG FORMAT ERROR: "..tostring(message))
    end
    local event = {
        timestamp = timeStr,
        timestampTable = timestamp,
        level = level,
        message = formatted,
        rawMessage = message,
        args = args or {},
        properties = {},
        context = context or {},
        addonName = ADDON_NAME
    }
    if properties then for k, v in pairs(properties) do event.properties[k] = v end end
    if context then for k, v in pairs(context) do event.properties[k] = v end end
    return event
end

-- === Dispatch ===
local function dispatch(level, message, args, properties, context)
    local levelNum = LEVELS[level]
    if not levelNum or levelNum < globalLevel then return end
    local event = createEvent(level, message, args, properties, context)
    for _, enr in ipairs(enrichers) do
        local fn = enr.fn or enr
        local ok, err = pcall(fn, event)
        if not ok then print("|cffff5555["..ADDON_NAME.." Logger]: Enricher error:|r "..tostring(err)) end
    end
    for _, sink in ipairs(sinks) do
        if levelNum >= (sink.level or DEFAULT_LEVEL) then
            local ok, err = pcall(sink.fn, event)
            if not ok then print("|cffff5555["..ADDON_NAME.." Logger]: Sink error:|r "..tostring(err)) end
        end
    end
end

-- === Sink Management ===
function Logger.AddSink(fn, minLevel, name)
    assert(type(fn) == "function", "AddSink: sink must be a function")
    local sink = { fn = fn, level = minLevel or DEFAULT_LEVEL, name = name or ("Sink"..(#sinks+1)), added = time() }
    table.insert(sinks, sink)
    return sink
end

function Logger.RemoveSink(fnOrName)
    for i = #sinks, 1, -1 do
        local s = sinks[i]
        if s.fn == fnOrName or s.name == fnOrName then table.remove(sinks, i); return true end
    end
    return false
end

function Logger.ListSinks()
    local names = {}
    for _, s in ipairs(sinks) do table.insert(names, s.name) end
    return names
end

-- === Level Management ===
function Logger.SetLevel(level)
    local lv = type(level)=="string" and LEVELS[level:upper()] or level
    if lv then globalLevel = lv; return true end
    Logger.Error("Invalid log level: %s. Valid: DEBUG, INFO, WARN, ERROR, FATAL", tostring(level))
    return false
end

function Logger.GetLevel()
    for n, v in pairs(LEVELS) do if v==globalLevel then return n end end
    return "INFO"
end

-- === Enrichers ===
function Logger.AddEnricher(fn, name)
    assert(type(fn) == "function", "AddEnricher: enricher must be a function")
    table.insert(enrichers, { fn = fn, name = name or ("Enricher"..(#enrichers+1)) })
end

-- === ForContext (Serilog style) ===
function Logger.ForContext(properties)
    return setmetatable({ _context = properties or {} }, LoggerInstance)
end

-- === Main Logging Functions ===
for level, _ in pairs(LEVELS) do
    Logger[level:sub(1,1):upper()..level:sub(2):lower()] = function(msg, ...)
        dispatch(level, msg, {...}, nil, nil)
    end
    LoggerInstance[level:sub(1,1):upper()..level:sub(2):lower()] = function(self, msg, ...)
        dispatch(level, msg, {...}, nil, self._context)
    end
end

function Logger.Log(level, message, args, properties)
    dispatch(level, message, args, properties, nil)
end

function LoggerInstance:Log(level, message, args, properties)
    dispatch(level, message, args, properties, self._context)
end

-- === Structured Logging Helpers ===
function Logger.LogTable(tbl, name, maxDepth)
    name = name or "table"; maxDepth = maxDepth or 3
    local function toStr(t, depth)
        if depth > maxDepth then return "..." end
        if type(t)~="table" then return tostring(t) end
        local out = {}
        for k, v in pairs(t) do
            local key = type(k)=="string" and k or "["..tostring(k).."]"
            local value = type(v)=="table" and toStr(v, depth+1) or tostring(v)
            table.insert(out, key.."="..value)
        end
        return "{"..table.concat(out, ", ").."}"
    end
    Logger.Debug("%s: %s", name, toStr(tbl, 0))
end

function Logger.LogError(err, context)
    Logger.Error("Error%s: %s", context and (" in "..context) or "", tostring(err))
end

function Logger.LogFunction(functionName, ...)
    Logger.Debug("Function call: %s(%s)", tostring(functionName), table.concat({...}, ", "))
end

-- === Statistics ===
function Logger.GetStats()
    return {
        sinks = #sinks, enrichers = #enrichers,
        currentLevel = Logger.GetLevel(),
        availableLevels = { "DEBUG", "INFO", "WARN", "ERROR", "FATAL" }
    }
end

-- === Default Chat Sink ===
local function defaultChatSink(event)
    local color = LEVEL_COLORS[event.level] or "|cffaaaaaa"
    local line = string.format("%s[%s][%s] %s|r", color, event.level, event.timestamp, event.message)
    if event.properties and next(event.properties) then
        local props = {}
        for k, v in pairs(event.properties) do
            table.insert(props, ("%s=%s"):format(tostring(k), tostring(v)))
        end
        line = line .. " |cffa0a0a0{" .. table.concat(props, ", ") .. "}|r"
    end
    print(line)
end

Logger.AddSink(defaultChatSink, LEVELS.DEBUG, "ChatSink")

-- === Initialization Log ===
Logger.Info("Logger initialized (Serilog-style, enterprise, v2)")

Addon.provide("Logger", Logger)
