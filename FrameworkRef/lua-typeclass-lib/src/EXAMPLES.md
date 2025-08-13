# 📚 **Usage Examples & Patterns**

This document provides practical examples and usage patterns for the WoW Enterprise Logging Framework.

## 🎯 **Basic Usage Examples**

### **Simple Logging**
```lua
local Logger = Addon.require("Logger")

-- Basic log levels
Logger.Debug("Debug information: player level %d", UnitLevel("player"))
Logger.Info("Loading configuration file")
Logger.Warn("Player health is low: %d%%", healthPercent)
Logger.Error("Failed to connect to server: %s", errorMessage)
Logger.Fatal("Critical addon failure")
```

### **Structured Logging**
```lua
-- Log with structured properties
Logger.Log("INFO", "Quest completed", {questName}, {
    questId = 12345,
    experience = 2500,
    gold = 15,
    zone = GetZoneText(),
    completion_time = 300  -- seconds
})

-- Using table logging
local playerStats = {
    name = UnitName("player"),
    level = UnitLevel("player"),
    health = UnitHealth("player"),
    mana = UnitPower("player")
}
Logger.LogTable(playerStats, "PlayerStats")
```

## 🎭 **Contextual Logging (Serilog-style)**

### **Module-based Context**
```lua
-- Create context loggers for different modules
local combatLogger = Logger.ForContext({
    module = "Combat",
    zone = GetZoneText()
})

local questLogger = Logger.ForContext({
    module = "Quest",
    character = UnitName("player")
})

-- All logs from these loggers will include the context
combatLogger.Info("Entering combat with %s", targetName)
questLogger.Info("Quest accepted: %s", questName)
```

### **Nested Context**
```lua
local guildLogger = Logger.ForContext({
    module = "Guild",
    guild = GetGuildInfo("player")
})

-- Create sub-context for specific events
local raidLogger = guildLogger.ForContext({
    activity = "Raid",
    difficulty = "Heroic"
})

raidLogger.Info("Raid started: %s", instanceName)
raidLogger.Warn("Player died: %s", playerName)
```

## 🏗️ **Custom Sinks**

### **Chat Channel Sink**
```lua
local function ChatSink(event)
    if event.level == "ERROR" or event.level == "FATAL" then
        SendChatMessage("[LOG] " .. event.message, "GUILD")
    end
end

Logger.AddSink(ChatSink, Logger.LEVELS.ERROR, "GuildChatSink")
```

### **File Export Sink**
```lua
local exportBuffer = {}

local function ExportSink(event)
    table.insert(exportBuffer, {
        timestamp = event.timestamp,
        level = event.level,
        message = event.message,
        properties = event.properties
    })
    
    -- Export every 100 entries
    if #exportBuffer >= 100 then
        ExportToFile(exportBuffer)
        exportBuffer = {}
    end
end

Logger.AddSink(ExportSink, Logger.LEVELS.INFO, "ExportSink")
```

### **Discord Webhook Sink (if supported)**
```lua
local function DiscordSink(event)
    if event.level == "FATAL" then
        local payload = {
            content = string.format("🚨 **FATAL ERROR** in %s", ADDON_NAME),
            embeds = {{
                title = "Addon Error",
                description = event.message,
                color = 15158332, -- Red
                fields = {
                    {
                        name = "Level",
                        value = event.level,
                        inline = true
                    },
                    {
                        name = "Time",
                        value = event.timestamp,
                        inline = true
                    }
                }
            }}
        }
        SendToDiscord(payload)
    end
end

Logger.AddSink(DiscordSink, Logger.LEVELS.FATAL, "DiscordSink")
```

## 🔍 **Custom Enrichers**

### **Performance Enricher**
```lua
local function PerformanceEnricher(event)
    event.properties.fps = math.floor(GetFramerate())
    event.properties.memory = math.floor(GetAddOnMemoryUsage(ADDON_NAME))
    event.properties.latency = select(3, GetNetStats())
end

Logger.AddEnricher(PerformanceEnricher, "Performance")
```

### **Player State Enricher**
```lua
local function PlayerStateEnricher(event)
    event.properties.playerLevel = UnitLevel("player")
    event.properties.playerZone = GetZoneText()
    event.properties.playerGuild = GetGuildInfo("player") or "None"
    event.properties.isInCombat = InCombatLockdown()
    event.properties.isInInstance = IsInInstance()
end

Logger.AddEnricher(PlayerStateEnricher, "PlayerState")
```

### **Session Enricher**
```lua
local sessionStart = GetServerTime()
local sessionId = string.format("session_%d_%s", sessionStart, math.random(1000, 9999))

local function SessionEnricher(event)
    event.properties.sessionId = sessionId
    event.properties.sessionUptime = GetServerTime() - sessionStart
end

Logger.AddEnricher(SessionEnricher, "Session")
```

## 🎮 **Game Event Integration**

### **Combat Logging**
```lua
local combatLogger = Logger.ForContext({ module = "Combat" })

local function OnCombatLogEvent()
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, 
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    
    if eventType == "UNIT_DIED" then
        combatLogger.Info("Unit died: %s", destName, {
            sourceUnit = sourceName,
            unitGUID = destGUID,
            eventType = eventType
        })
    elseif eventType == "SPELL_CAST_SUCCESS" then
        local spellId, spellName = select(12, CombatLogGetCurrentEventInfo())
        combatLogger.Debug("Spell cast: %s by %s", spellName, sourceName, {
            spellId = spellId,
            caster = sourceName,
            target = destName
        })
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", OnCombatLogEvent)
```

### **Quest Logging**
```lua
local questLogger = Logger.ForContext({ module = "Quest" })

local function OnQuestLog()
    questLogger.Info("Quest log updated")
end

local function OnQuestComplete()
    local questTitle = GetTitleText()
    questLogger.Info("Quest completed: %s", questTitle, {
        questTitle = questTitle,
        experience = GetQuestLogRewardXP(),
        money = GetQuestLogRewardMoney()
    })
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_COMPLETE")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "QUEST_LOG_UPDATE" then
        OnQuestLog()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    end
end)
```

## 🖥️ **Log Console Usage**

### **Basic Console Operations**
```lua
local LogConsole = Addon.require("LogConsole")

-- Show/hide console
LogConsole.Show()
LogConsole.Hide()
LogConsole.Toggle()

-- Configure filtering
LogConsole.SetFilter("WARN")  -- Show only WARN, ERROR, FATAL
LogConsole.SetBufferSize(5000)  -- Keep 5000 log entries

-- Check status
if LogConsole.IsVisible() then
    Logger.Info("Console is currently visible")
end
```

### **Console Integration Example**
```lua
-- Create button to toggle console
local button = CreateFrame("Button", "LogConsoleButton", UIParent, "UIPanelButtonTemplate")
button:SetSize(100, 30)
button:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
button:SetText("Logs")
button:SetScript("OnClick", function()
    LogConsole.Toggle()
end)

-- Add console command
SLASH_TOGGLELOGS1 = "/logs"
SlashCmdList["TOGGLELOGS"] = function()
    LogConsole.Toggle()
end
```

## 💾 **Persistence Configuration**

### **Configure SavedVariables Sink**
```lua
local SavedVariablesSink = Addon.require("SavedVariablesSink")

-- Configure persistence
SavedVariablesSink.SetMaxEntries(5000)  -- Keep 5000 entries
SavedVariablesSink.SetMaxDays(30)       -- Keep for 30 days
SavedVariablesSink.SetMinLevel("WARN")  -- Persist WARN and above
SavedVariablesSink.SetEnabled(true)

-- Check configuration
local config = SavedVariablesSink.GetConfig()
Logger.Info("Persistence config: entries=%d, days=%d, level=%s", 
    config.maxEntries, config.maxDays, config.minLevel)
```

### **Export Logs**
```lua
-- Export as text
local textData = SavedVariablesSink.ExportLogs("text")
print(textData)

-- Export as CSV
local csvData = SavedVariablesSink.ExportLogs("csv")
-- Save to file or display in UI
```

## 🔧 **Advanced Patterns**

### **Conditional Logging**
```lua
-- Only log in debug mode
if MyAddon.IsDebugMode() then
    Logger.Debug("Debug information: %s", debugData)
end

-- Log based on player level
if UnitLevel("player") >= 60 then
    Logger.Info("Max level player action: %s", action)
end

-- Log errors with stack trace
local function SafeFunction()
    local success, result = pcall(RiskyFunction)
    if not success then
        Logger.Error("Function failed: %s\nStack: %s", result, debugstack())
    end
    return success, result
end
```

### **Rate-Limited Logging**
```lua
local lastLogTime = {}

local function RateLimitedLog(key, message, interval)
    local now = GetTime()
    if not lastLogTime[key] or (now - lastLogTime[key]) >= interval then
        Logger.Info(message)
        lastLogTime[key] = now
    end
end

-- Usage: log at most once per 5 seconds
RateLimitedLog("combat_warning", "Player health critical!", 5)
```

### **Batch Logging**
```lua
local logBatch = {}

local function BatchLog(message, level)
    table.insert(logBatch, { message = message, level = level or "INFO" })
    
    -- Flush batch every 10 entries
    if #logBatch >= 10 then
        FlushBatch()
    end
end

local function FlushBatch()
    for _, entry in ipairs(logBatch) do
        Logger.Log(entry.level, entry.message)
    end
    logBatch = {}
end

-- Flush remaining logs on logout
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", FlushBatch)
```

## 🎪 **Demo Implementation**

### **Complete Demo Function**
```lua
local function RunLoggingDemo()
    Logger.Info("=== Logging Framework Demo ===")
    
    -- Basic logging
    Logger.Debug("Debug message with parameter: %s", "test")
    Logger.Info("Information message")
    Logger.Warn("Warning message")
    Logger.Error("Error message")
    
    -- Structured logging
    Logger.Log("INFO", "Structured log", {}, {
        demo = true,
        timestamp = GetServerTime(),
        player = UnitName("player")
    })
    
    -- Contextual logging
    local demoLogger = Logger.ForContext({
        module = "Demo",
        version = "1.0"
    })
    demoLogger.Info("Contextual log message")
    
    -- Table logging
    Logger.LogTable({
        name = "Test Table",
        values = {1, 2, 3},
        nested = { a = 1, b = 2 }
    }, "DemoTable")
    
    -- Show statistics
    local stats = Logger.GetStats()
    Logger.Info("Logger stats: %d sinks, %d enrichers", 
        stats.sinks, stats.enrichers)
    
    -- Console operations
    local LogConsole = Addon.require("LogConsole")
    LogConsole.Show()
    Logger.Info("Demo completed - check log console!")
end

-- Register demo command
SLASH_DEMO1 = "/tsdemo"
SlashCmdList["DEMO"] = RunLoggingDemo
```

## 📊 **Monitoring & Diagnostics**

### **System Health Check**
```lua
local function HealthCheck()
    local Logger = Addon.require("Logger")
    local LogConsole = Addon.require("LogConsole")
    local SavedVariablesSink = Addon.require("SavedVariablesSink")
    
    -- Logger health
    local loggerStats = Logger.GetStats()
    Logger.Info("Logger Health: %d sinks active, level=%s", 
        loggerStats.sinks, loggerStats.currentLevel)
    
    -- Console health
    local consoleStats = LogConsole.GetStats()
    Logger.Info("Console Health: %d/%d lines, visible=%s", 
        consoleStats.filteredLines, consoleStats.totalLines, 
        tostring(consoleStats.isVisible))
    
    -- Persistence health
    local persistStats = SavedVariablesSink.GetStats()
    Logger.Info("Persistence Health: %d entries, session=%s", 
        persistStats.currentEntries, persistStats.currentSession)
    
    -- Memory usage
    local memory = GetAddOnMemoryUsage(ADDON_NAME)
    Logger.Info("Memory Usage: %.2f KB", memory)
end

-- Run health check every 5 minutes
C_Timer.NewTicker(300, HealthCheck)
```

### **Error Tracking**
```lua
local errorCounts = {}

local function TrackError(errorType)
    errorCounts[errorType] = (errorCounts[errorType] or 0) + 1
    
    if errorCounts[errorType] % 10 == 0 then
        Logger.Warn("Error type '%s' occurred %d times", 
            errorType, errorCounts[errorType])
    end
end

-- Usage in error handlers
local function SafeCall(func, errorType, ...)
    local success, result = pcall(func, ...)
    if not success then
        TrackError(errorType)
        Logger.Error("Function failed (%s): %s", errorType, result)
    end
    return success, result
end
```

## 🚀 **Integration Examples**

### **WeakAuras Integration**
```lua
-- Log WeakAura triggers
local function LogWeakAuraEvent(auraName, event, ...)
    local waLogger = Logger.ForContext({
        module = "WeakAuras",
        aura = auraName
    })
    
    waLogger.Debug("WeakAura event: %s", event, {
        auraName = auraName,
        eventData = {...}
    })
end
```

### **BigWigs/DBM Integration**
```lua
-- Log boss encounter events
local function LogBossEvent(boss, event, phase)
    local bossLogger = Logger.ForContext({
        module = "BossEncounter",
        boss = boss
    })
    
    bossLogger.Info("Boss event: %s (Phase %d)", event, phase or 0, {
        encounterName = boss,
        eventType = event,
        phase = phase,
        difficulty = GetInstanceInfo()
    })
end
```

### **Guild Integration**
```lua
-- Log guild events
local function OnGuildEvent(event, ...)
    local guildLogger = Logger.ForContext({
        module = "Guild",
        guild = GetGuildInfo("player")
    })
    
    if event == "GUILD_ROSTER_UPDATE" then
        guildLogger.Info("Guild roster updated")
    elseif event == "CHAT_MSG_GUILD" then
        local message, sender = ...
        guildLogger.Debug("Guild chat: <%s> %s", sender, message)
    end
end
```

---

For more technical details, see [API.md](API.md) for complete API reference.
