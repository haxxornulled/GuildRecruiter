-- SavedVariablesSink.lua - Persistent logging sink using WoW's SavedVariables system
-- Stores logs to disk across WoW sessions with configurable retention
local ADDON_NAME = "TaintedSin" -- Change this if you use a different addon name!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

local SavedVariablesSink = {}

-- Saved Variables Configuration
local DEFAULT_MAX_ENTRIES = 1000
local DEFAULT_MAX_DAYS = 7
local DEFAULT_LEVEL = 2 -- INFO and above

-- Database structure (will be persisted)
-- TaintedSinLogDB = {
--     logs = {
--         { timestamp = "2025-01-01 12:00:00", level = "INFO", message = "...", session = "...", addon = "..." },
--         ...
--     },
--     config = {
--         maxEntries = 1000,
--         maxDays = 7,
--         minLevel = 2,
--         enabled = true
--     },
--     stats = {
--         totalLogs = 0,
--         sessionsLogged = 0,
--         lastCleanup = "2025-01-01 00:00:00"
--     }
-- }

local dbName = ADDON_NAME .. "LogDB"

-- Session tracking
local sessionId = nil
local isInitialized = false

-- Generate unique session ID
local function GenerateSessionId()
    local DateTime = Addon.require and Addon.require("DateTime")
    if DateTime then
        local utc = DateTime.UtcNow()
        return string.format("%04d%02d%02d_%02d%02d%02d_%d", 
            utc.year, utc.month, utc.day, utc.hour, utc.min, utc.sec, math.random(1000, 9999))
    else
        return "session_" .. os.time() .. "_" .. math.random(1000, 9999)
    end
end

-- Initialize database structure
local function InitializeDatabase()
    if not _G[dbName] then
        _G[dbName] = {
            logs = {},
            config = {
                maxEntries = DEFAULT_MAX_ENTRIES,
                maxDays = DEFAULT_MAX_DAYS,
                minLevel = DEFAULT_LEVEL,
                enabled = true
            },
            stats = {
                totalLogs = 0,
                sessionsLogged = 0,
                lastCleanup = os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    end
    
    -- Ensure all required fields exist (for version upgrades)
    local db = _G[dbName]
    if not db.logs then db.logs = {} end
    if not db.config then db.config = {} end
    if not db.stats then db.stats = {} end
    
    -- Set default config values
    if db.config.maxEntries == nil then db.config.maxEntries = DEFAULT_MAX_ENTRIES end
    if db.config.maxDays == nil then db.config.maxDays = DEFAULT_MAX_DAYS end
    if db.config.minLevel == nil then db.config.minLevel = DEFAULT_LEVEL end
    if db.config.enabled == nil then db.config.enabled = true end
    
    -- Set default stats
    if db.stats.totalLogs == nil then db.stats.totalLogs = 0 end
    if db.stats.sessionsLogged == nil then db.stats.sessionsLogged = 0 end
    if db.stats.lastCleanup == nil then db.stats.lastCleanup = os.date("%Y-%m-%d %H:%M:%S") end
    
    sessionId = GenerateSessionId()
    db.stats.sessionsLogged = db.stats.sessionsLogged + 1
    
    isInitialized = true
end

-- Clean up old entries based on config
local function CleanupOldEntries()
    local db = _G[dbName]
    if not db or not db.logs then return end
    
    local now = os.time()
    local maxAge = db.config.maxDays * 24 * 60 * 60 -- Convert days to seconds
    local removed = 0
    
    -- Remove entries older than maxDays
    for i = #db.logs, 1, -1 do
        local entry = db.logs[i]
        local entryTime = entry.timestampSeconds or 0
        
        if (now - entryTime) > maxAge then
            table.remove(db.logs, i)
            removed = removed + 1
        end
    end
    
    -- Remove oldest entries if we exceed maxEntries
    while #db.logs > db.config.maxEntries do
        table.remove(db.logs, 1)
        removed = removed + 1
    end
    
    if removed > 0 then
        db.stats.lastCleanup = os.date("%Y-%m-%d %H:%M:%S")
        
        local Logger = Addon.require and Addon.require("Logger")
        if Logger then
            Logger.Debug("SavedVariablesSink cleaned up %d old log entries", removed)
        end
    end
end

-- The sink function that receives log events
local function SavedVariablesSinkFunction(event)
    if not isInitialized then
        InitializeDatabase()
    end
    
    local db = _G[dbName]
    if not db or not db.config or not db.config.enabled then
        return
    end
    
    -- Check level filtering
    local levelNums = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }
    local eventLevel = levelNums[event.level] or 2
    if eventLevel < db.config.minLevel then
        return
    end
    
    -- Create persistent log entry
    local logEntry = {
        timestamp = event.timestamp or os.date("%H:%M:%S"),
        timestampFull = os.date("%Y-%m-%d %H:%M:%S"),
        timestampSeconds = os.time(),
        level = event.level,
        message = event.message,
        rawMessage = event.rawMessage,
        session = sessionId,
        addon = ADDON_NAME,
        properties = {}
    }
    
    -- Copy properties if they exist
    if event.properties then
        for k, v in pairs(event.properties) do
            logEntry.properties[k] = tostring(v) -- Ensure serializable
        end
    end
    
    -- Add context information
    if event.context then
        for k, v in pairs(event.context) do
            logEntry.properties[k] = tostring(v)
        end
    end
    
    -- Store the entry
    table.insert(db.logs, logEntry)
    db.stats.totalLogs = db.stats.totalLogs + 1
    
    -- Periodic cleanup (every 100 entries)
    if db.stats.totalLogs % 100 == 0 then
        CleanupOldEntries()
    end
end

-- Public API: Configuration
function SavedVariablesSink.SetMaxEntries(count)
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if db and db.config then
        db.config.maxEntries = math.max(10, math.min(10000, tonumber(count) or DEFAULT_MAX_ENTRIES))
        CleanupOldEntries()
        return true
    end
    return false
end

function SavedVariablesSink.SetMaxDays(days)
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if db and db.config then
        db.config.maxDays = math.max(1, math.min(365, tonumber(days) or DEFAULT_MAX_DAYS))
        CleanupOldEntries()
        return true
    end
    return false
end

function SavedVariablesSink.SetMinLevel(level)
    if not isInitialized then InitializeDatabase() end
    
    local levelNums = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }
    local levelNum = levelNums[string.upper(tostring(level))] or levelNums[level]
    
    if levelNum then
        local db = _G[dbName]
        if db and db.config then
            db.config.minLevel = levelNum
            return true
        end
    end
    return false
end

function SavedVariablesSink.SetEnabled(enabled)
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if db and db.config then
        db.config.enabled = (enabled ~= false)
        return true
    end
    return false
end

-- Public API: Data Access
function SavedVariablesSink.GetLogs(maxCount, levelFilter, sessionFilter)
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if not db or not db.logs then return {} end
    
    local results = {}
    local levelNums = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }
    local minLevel = levelFilter and levelNums[string.upper(levelFilter)] or 1
    
    -- Filter and collect entries
    for i = #db.logs, 1, -1 do -- Newest first
        local entry = db.logs[i]
        
        -- Level filter
        local entryLevel = levelNums[entry.level] or 2
        if entryLevel < minLevel then
            goto continue
        end
        
        -- Session filter
        if sessionFilter and entry.session ~= sessionFilter then
            goto continue
        end
        
        table.insert(results, entry)
        
        -- Limit results
        if maxCount and #results >= maxCount then
            break
        end
        
        ::continue::
    end
    
    return results
end

function SavedVariablesSink.GetConfig()
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    return db and db.config or {}
end

function SavedVariablesSink.GetStats()
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if not db then return {} end
    
    return {
        totalLogs = db.stats.totalLogs or 0,
        currentEntries = #(db.logs or {}),
        sessionsLogged = db.stats.sessionsLogged or 0,
        lastCleanup = db.stats.lastCleanup or "Never",
        currentSession = sessionId,
        databaseName = dbName,
        config = db.config or {}
    }
end

-- Public API: Maintenance
function SavedVariablesSink.ForceCleanup()
    CleanupOldEntries()
    return true
end

function SavedVariablesSink.ClearAllLogs()
    if not isInitialized then InitializeDatabase() end
    
    local db = _G[dbName]
    if db then
        local count = #(db.logs or {})
        db.logs = {}
        db.stats.totalLogs = 0
        db.stats.lastCleanup = os.date("%Y-%m-%d %H:%M:%S")
        
        local Logger = Addon.require and Addon.require("Logger")
        if Logger then
            Logger.Info("SavedVariablesSink cleared all %d log entries", count)
        end
        
        return count
    end
    return 0
end

function SavedVariablesSink.ExportLogs(format)
    local logs = SavedVariablesSink.GetLogs()
    if #logs == 0 then return "" end
    
    format = format or "text"
    local lines = {}
    
    if format == "csv" then
        table.insert(lines, "Timestamp,Level,Message,Session,Properties")
        for _, entry in ipairs(logs) do
            local props = ""
            if entry.properties and next(entry.properties) then
                local propParts = {}
                for k, v in pairs(entry.properties) do
                    table.insert(propParts, k .. "=" .. v)
                end
                props = table.concat(propParts, "; ")
            end
            local csvLine = string.format('"%s","%s","%s","%s","%s"',
                entry.timestampFull or entry.timestamp,
                entry.level,
                (entry.message or ""):gsub('"', '""'),
                entry.session or "",
                props:gsub('"', '""'))
            table.insert(lines, csvLine)
        end
    else -- text format
        for _, entry in ipairs(logs) do
            local line = string.format("[%s][%s] %s",
                entry.level,
                entry.timestampFull or entry.timestamp,
                entry.message or "")
            
            if entry.properties and next(entry.properties) then
                local props = {}
                for k, v in pairs(entry.properties) do
                    table.insert(props, k .. "=" .. v)
                end
                line = line .. " {" .. table.concat(props, ", ") .. "}"
            end
            
            table.insert(lines, line)
        end
    end
    
    return table.concat(lines, "\n")
end

-- Public API: Get the sink function for Logger registration
function SavedVariablesSink.GetSinkFunction()
    return SavedVariablesSinkFunction
end

-- Initialize and register with Logger when available
local function Initialize()
    InitializeDatabase()
    
    local Logger = Addon.require and Addon.require("Logger")
    if Logger and Logger.AddSink then
        local config = SavedVariablesSink.GetConfig()
        Logger.AddSink(SavedVariablesSinkFunction, config.minLevel, "SavedVariablesSink")
        
        Logger.Info("SavedVariablesSink v1.0.0 initialized - Session: %s", sessionId)
        Logger.Debug("Persistent logging configured: MaxEntries=%d, MaxDays=%d, MinLevel=%d", 
            config.maxEntries, config.maxDays, config.minLevel)
    else
        print("|cffff5555[" .. ADDON_NAME .. "]: SavedVariablesSink could not register with Logger|r")
    end
end

-- Initialize when Logger is available
if Addon.require then
    local Logger = Addon.require("Logger")
    if Logger then
        Initialize()
    else
        -- Wait for Logger to be available
        C_Timer.After(1, Initialize)
    end
end

-- Provide for the module system
Addon.provide("SavedVariablesSink", SavedVariablesSink)
