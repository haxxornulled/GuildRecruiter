# API Reference

## 📚 **Complete API Documentation**

This document provides comprehensive API reference for the WoW Enterprise Logging Framework.

## 🎯 **Logger Module**

### **Core Logging Functions**

#### `Logger.Debug(message, ...)`
Log a debug message (level 1 - lowest priority).
```lua
Logger.Debug("Player position: x=%d, y=%d", x, y)
```

#### `Logger.Info(message, ...)`
Log an informational message (level 2 - default minimum).
```lua
Logger.Info("Quest completed: %s", questName)
```

#### `Logger.Warn(message, ...)`
Log a warning message (level 3).
```lua
Logger.Warn("Low health: %d%%", healthPercent)
```

#### `Logger.Error(message, ...)`
Log an error message (level 4).
```lua
Logger.Error("Failed to save data: %s", errorMessage)
```

#### `Logger.Fatal(message, ...)`
Log a fatal error message (level 5 - highest priority).
```lua
Logger.Fatal("Critical system failure: %s", error)
```

### **Structured Logging**

#### `Logger.Log(level, message, args, properties)`
Log with explicit level and structured properties.
```lua
Logger.Log("INFO", "Player action", {playerName}, {
    action = "quest_complete",
    questId = 12345,
    experience = 2500
})
```

### **Contextual Logging (Serilog-style)**

#### `Logger.ForContext(properties)`
Create a contextual logger with attached properties.
```lua
local combatLogger = Logger.ForContext({
    module = "Combat",
    zone = GetZoneText()
})

combatLogger.Info("Entering combat")  -- Includes context automatically
```

### **Utility Functions**

#### `Logger.LogTable(table, name, maxDepth)`
Log a table with formatted output.
```lua
Logger.LogTable(playerData, "PlayerStats", 2)
```

#### `Logger.LogError(error, context)`
Log an error with context information.
```lua
Logger.LogError(err, "DataLoader.LoadPlayerData")
```

#### `Logger.LogFunction(functionName, ...)`
Log a function call with parameters.
```lua
Logger.LogFunction("CastSpell", spellName, targetName)
```

### **Level Management**

#### `Logger.SetLevel(level)`
Set the minimum logging level.
```lua
Logger.SetLevel("WARN")  -- Only WARN, ERROR, FATAL
Logger.SetLevel(3)       -- Same as above (numeric)
```

#### `Logger.GetLevel()`
Get the current logging level.
```lua
local level = Logger.GetLevel()  -- Returns "INFO", "WARN", etc.
```

### **Sink Management**

#### `Logger.AddSink(sinkFunction, minLevel, name)`
Add a custom logging sink.
```lua
local function MyCustomSink(event)
    -- event = { level, message, timestamp, properties, context }
    print("CUSTOM: " .. event.message)
end

Logger.AddSink(MyCustomSink, Logger.LEVELS.INFO, "CustomSink")
```

#### `Logger.RemoveSink(nameOrFunction)`
Remove a logging sink.
```lua
Logger.RemoveSink("CustomSink")
-- or
Logger.RemoveSink(MyCustomSink)
```

#### `Logger.ListSinks()`
Get list of active sink names.
```lua
local sinks = Logger.ListSinks()  -- Returns array of sink names
```

### **Enricher Management**

#### `Logger.AddEnricher(enricherFunction, name)`
Add a function to enrich all log events.
```lua
Logger.AddEnricher(function(event)
    event.properties.playerGuild = GetGuildInfo("player")
    event.properties.timestamp = GetServerTime()
end, "PlayerEnricher")
```

### **Statistics**

#### `Logger.GetStats()`
Get logging system statistics.
```lua
local stats = Logger.GetStats()
-- Returns: { sinks, enrichers, currentLevel, availableLevels }
```

### **Constants**

#### `Logger.LEVELS`
Log level constants.
```lua
Logger.LEVELS.DEBUG  -- 1
Logger.LEVELS.INFO   -- 2
Logger.LEVELS.WARN   -- 3
Logger.LEVELS.ERROR  -- 4
Logger.LEVELS.FATAL  -- 5
```

## 🖥️ **LogConsole Module**

### **Display Management**

#### `LogConsole.Show()`
Show the log console UI.
```lua
LogConsole.Show()
```

#### `LogConsole.Hide()`
Hide the log console UI.
```lua
LogConsole.Hide()
```

#### `LogConsole.Toggle()`
Toggle log console visibility.
```lua
LogConsole.Toggle()
```

#### `LogConsole.IsVisible()`
Check if console is visible.
```lua
local visible = LogConsole.IsVisible()  -- Returns boolean
```

### **Configuration**

#### `LogConsole.SetFilter(level)`
Set the display filter level.
```lua
LogConsole.SetFilter("ERROR")  -- Show only ERROR and FATAL
```

#### `LogConsole.SetBufferSize(size)`
Set the maximum number of log entries to keep.
```lua
LogConsole.SetBufferSize(2000)  -- Keep 2000 entries
```

#### `LogConsole.GetBufferSize()`
Get current buffer size.
```lua
local size = LogConsole.GetBufferSize()
```

### **Data Management**

#### `LogConsole.AddLogEntry(event)`
Manually add a log entry (usually called by Logger).
```lua
LogConsole.AddLogEntry({
    level = "INFO",
    message = "Test message",
    timestamp = "12:34:56",
    properties = {}
})
```

#### `LogConsole.RefreshDisplay()`
Force refresh of the console display.
```lua
LogConsole.RefreshDisplay()
```

### **Statistics**

#### `LogConsole.GetStats()`
Get console statistics.
```lua
local stats = LogConsole.GetStats()
-- Returns: { totalLines, filteredLines, currentFilter, bufferSize, isVisible }
```

## 💾 **SavedVariablesSink Module**

### **Configuration**

#### `SavedVariablesSink.SetMaxEntries(count)`
Set maximum number of persistent log entries.
```lua
SavedVariablesSink.SetMaxEntries(2000)
```

#### `SavedVariablesSink.SetMaxDays(days)`
Set maximum age for persistent logs.
```lua
SavedVariablesSink.SetMaxDays(30)  -- Keep logs for 30 days
```

#### `SavedVariablesSink.SetMinLevel(level)`
Set minimum level for persistent logging.
```lua
SavedVariablesSink.SetMinLevel("WARN")  -- Only persist WARN+
```

#### `SavedVariablesSink.SetEnabled(enabled)`
Enable or disable persistent logging.
```lua
SavedVariablesSink.SetEnabled(true)
```

### **Data Access**

#### `SavedVariablesSink.GetLogs(maxCount, levelFilter, sessionFilter)`
Retrieve persistent logs.
```lua
-- Get last 100 logs
local logs = SavedVariablesSink.GetLogs(100)

-- Get ERROR level logs only
local errorLogs = SavedVariablesSink.GetLogs(50, "ERROR")

-- Get logs from specific session
local sessionLogs = SavedVariablesSink.GetLogs(nil, nil, "20250801_123456_1234")
```

#### `SavedVariablesSink.GetConfig()`
Get current configuration.
```lua
local config = SavedVariablesSink.GetConfig()
-- Returns: { maxEntries, maxDays, minLevel, enabled }
```

#### `SavedVariablesSink.GetStats()`
Get persistence statistics.
```lua
local stats = SavedVariablesSink.GetStats()
-- Returns: { totalLogs, currentEntries, sessionsLogged, lastCleanup, currentSession, databaseName, config }
```

### **Maintenance**

#### `SavedVariablesSink.ForceCleanup()`
Force immediate cleanup of old entries.
```lua
SavedVariablesSink.ForceCleanup()
```

#### `SavedVariablesSink.ClearAllLogs()`
Clear all persistent logs.
```lua
local deletedCount = SavedVariablesSink.ClearAllLogs()
```

### **Export**

#### `SavedVariablesSink.ExportLogs(format)`
Export logs in specified format.
```lua
-- Export as plain text
local textData = SavedVariablesSink.ExportLogs("text")

-- Export as CSV
local csvData = SavedVariablesSink.ExportLogs("csv")
```

#### `SavedVariablesSink.GetSinkFunction()`
Get the sink function for manual registration.
```lua
local sinkFn = SavedVariablesSink.GetSinkFunction()
Logger.AddSink(sinkFn, Logger.LEVELS.INFO, "ManualPersistentSink")
```

## 🏗️ **Core Framework**

### **PackageLoader (Addon.require/provide)**

#### `Addon.provide(name, module)`
Register a module in the framework.
```lua
Addon.provide("MyModule", MyModule)
```

#### `Addon.require(name)`
Get a registered module.
```lua
local Logger = Addon.require("Logger")
```

#### `Addon.listModules()`
Get list of all registered modules.
```lua
local modules = Addon.listModules()
```

### **Core DI Container**

#### `Core.register(name, constructor, options)`
Register a service with the DI container.
```lua
Core.register("MyService", function()
    return { value = 42 }
end, { singleton = true })
```

#### `Core.resolve(name)`
Resolve a service from the container.
```lua
local service = Core.resolve("MyService")
```

## 🎮 **In-Game Commands**

### **Log Console Commands**
- `/tslogs` - Toggle log console
- `/tslogs clear` - Clear all logs
- `/tslogs stats` - Show statistics
- `/tslogs test` - Run test sequence

### **Demo Commands**
- `/tsdemo` - Run full demonstration
- `/tsdemo basic` - Basic logging demo
- `/tsdemo context` - Contextual logging demo
- `/tsdemo ui` - UI integration demo
- `/tsdemo persistence` - Persistence demo
- `/tsdemo stats` - Show system status

## 📊 **Event Structure**

Log events passed to sinks have this structure:
```lua
{
    timestamp = "12:34:56",           -- Formatted time string
    timestampTable = { ... },         -- Lua date table
    level = "INFO",                   -- Log level string
    message = "Formatted message",    -- Final formatted message
    rawMessage = "Template: %s",      -- Original template
    args = {"arg1", "arg2"},         -- Format arguments
    properties = {                    -- Structured properties
        key1 = "value1",
        key2 = "value2"
    },
    context = {                       -- Context from ForContext()
        module = "Combat",
        zone = "Stormwind"
    },
    addonName = "YourAddon"          -- Addon identifier
}
```

## 🔧 **Advanced Configuration**

### **Custom Sink Example**
```lua
local function AdvancedSink(event)
    -- Filter by properties
    if event.properties.module == "Combat" then
        -- Send combat logs to specific handler
        HandleCombatLog(event)
    end
    
    -- Add metadata
    local enhanced = {
        originalEvent = event,
        processedTime = GetTime(),
        serverName = GetRealmName()
    }
    
    -- Store or transmit
    StoreEnhancedLog(enhanced)
end

Logger.AddSink(AdvancedSink, Logger.LEVELS.DEBUG, "AdvancedSink")
```

### **Custom Enricher Example**
```lua
local function PerformanceEnricher(event)
    event.properties.memoryUsage = GetAddOnMemoryUsage("YourAddon")
    event.properties.frameRate = GetFramerate()
    event.properties.latency = select(3, GetNetStats())
end

Logger.AddEnricher(PerformanceEnricher, "Performance")
```

## 🚨 **Error Handling**

All framework functions include error handling:
- Invalid parameters trigger Lua errors with descriptive messages
- Sink/enricher errors are caught and logged without stopping execution
- Failed log formatting falls back to error messages
- Missing dependencies are detected and reported

## 📈 **Performance Considerations**

- **Log Level Filtering**: Set appropriate minimum levels to reduce overhead
- **Buffer Sizes**: Larger buffers use more memory but reduce cleanup frequency
- **Sink Performance**: Custom sinks should be optimized for high throughput
- **Property Serialization**: Large property objects impact performance

## 🔍 **Troubleshooting**

### **Common Error Messages**

**"Module 'Logger' not found"**
- Check .toc file load order
- Ensure `Addon.provide("Logger", Logger)` exists
- Verify ADDON_NAME consistency

**"AddSink: sink must be a function"**
- Ensure sink parameter is a function, not a table
- Check function signature: `function(event)`

**"LOG FORMAT ERROR"**
- String.format failed due to argument mismatch
- Check format string matches argument count/types

---

For more examples and advanced usage patterns, see the [EXAMPLES.md](EXAMPLES.md) file.
