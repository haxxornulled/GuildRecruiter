# WoW Enterprise Logging Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![WoW Version](https://img.shields.io/badge/WoW-10.0.7+-blue.svg)](https://worldofwarcraft.com/)
[![Lua Version](https://img.shields.io/badge/Lua-5.1%2B-blue.svg)](https://www.lua.org/)

> **Enterprise-grade Serilog-style logging framework for World of Warcraft addons**

Transform your WoW addon development with structured, multi-sink logging capabilities that rival enterprise .NET applications. This framework provides the logging infrastructure that large-scale addons need for production debugging, user support, and performance monitoring.

## 🚀 **Why This Framework?**

- **🎯 Serilog-Style Architecture**: Structured events, contextual logging, multiple sinks
- **🖥️ Advanced UI Console**: Real-time log viewing with filtering and export
- **💾 Cross-Session Persistence**: SavedVariables integration with automatic cleanup
- **🏗️ Enterprise Patterns**: DI container, modular architecture, production-ready
- **⚡ Performance Optimized**: Minimal overhead, configurable buffering
- **🔧 Developer Friendly**: Rich API, comprehensive documentation, demos

## 📊 **Feature Comparison**

| Feature | This Framework | Basic print() | Other Logging |
|---------|---------------|---------------|---------------|
| Structured Logging | ✅ Full Support | ❌ No | ⚠️ Limited |
| Multiple Output Targets | ✅ Chat + UI + Disk | ❌ Chat Only | ⚠️ Limited |
| Level-based Filtering | ✅ 5 Levels + Config | ❌ No | ⚠️ Basic |
| Contextual Logging | ✅ .ForContext() Pattern | ❌ No | ❌ No |
| UI Log Viewer | ✅ Advanced Console | ❌ No | ❌ No |
| Persistent Storage | ✅ SavedVariables | ❌ No | ❌ No |
| Export Capabilities | ✅ Copy/Export | ❌ No | ❌ No |
| Production Ready | ✅ Enterprise Grade | ❌ Debug Only | ⚠️ Limited |

## 🎮 **Quick Start**

### 1. **Installation**
```bash
# Clone into your addon directory
git clone https://github.com/yourusername/wow-enterprise-logging YourAddon
cd YourAddon

# Update addon name in files (see Configuration section)
```
- `/tslog clear` - Clear log buffer
- `/tsconsole` - Toggle log console with filtering and search capabilities

## Utility Modulesddon Framework

A **generic, reusable** dependency injection powered WoW addon framework with modular architecture and high-performance utilities.

## Features

- **🔧 Generic & Reusable**: Works with any addon name - just change `ADDON_NAME` once!
- **🏭 Enterprise DI Container**: Full dependency injection with singleton/transient lifetimes
- **📦 Modular Architecture**: Clean file-based module structure with `require/provide`
- **🛡️ Type Safety**: Runtime interface checking and type validation
- **🚫 No Global Pollution**: Only creates `_G[YourAddonName]` - no generic symbols
- **⚡ High-Performance Utilities**: Optimized ArrayUtils and DateTime modules
- **🔍 Diagnostics**: Built-in service diagnostics and error handling
- **🧪 Easy Testing**: All dependencies are injectable for unit testing

## Quick Start

1. **Change the addon name**: Replace `"TaintedSin"` with your addon name in `ADDON_NAME` 
2. Copy all files to your WoW addon directory: `Interface/AddOns/YourAddon/`
3. The addon will auto-initialize when loaded
4. Use `/youraddon demo` in-game to see utility demonstrations

## In-Game Commands

- `/taintedsin` - Show all available commands
- `/taintedsin diag` - Run service diagnostics
- `/taintedsin demo` - Demonstrate all utilities
- `/taintedsin array` - Array utilities demo
- `/taintedsin time` - DateTime utilities demo

## Utility Modules

### ArrayUtils - High-Performance Array Operations
```lua
local ArrayUtils = Addon.require("ArrayUtils")

-- Transform elements
local squares = ArrayUtils.map({1,2,3}, function(x) return x*x end) -- {1,4,9}

-- Filter elements  
local evens = ArrayUtils.filter({1,2,3,4}, function(x) return x%2==0 end) -- {2,4}

-- Find elements
local val, idx = ArrayUtils.find({1,2,3}, 2) -- 2, 2

-- Array manipulation
ArrayUtils.push(arr, value)     -- Append (O(1))
local val = ArrayUtils.pop(arr) -- Remove last (O(1))
ArrayUtils.remove(arr, index)   -- Remove at index (O(n))

-- Utility operations
local copy = ArrayUtils.copy(arr)
local combined = ArrayUtils.concat(arr1, arr2)
local slice = ArrayUtils.slice(arr, 2, 4)
ArrayUtils.reverse(arr) -- In-place
```

### DateTime - WoW-Compatible UTC Support
```lua
local DateTime = Addon.require("DateTime")

-- Current time
local utc = DateTime.UtcNow()      -- UTC time table
local local = DateTime.LocalNow()  -- Server/realm time
local epoch = DateTime.UtcEpoch()  -- UTC seconds since epoch

-- Formatting
DateTime.FormatUTC(time)      -- "2025-08-01T17:44:03Z" 
DateTime.FormatLocal(time)    -- "2025-08-01 17:44:03"
DateTime.FormatChat(time)     -- "17:44:03" or "Aug 1, 17:44"

-- Time calculations
DateTime.DiffSeconds(t1, t2)     -- Difference in seconds
DateTime.DiffHuman(t1, t2)       -- "2 hours ago"
DateTime.AddSeconds(time, 3600)  -- Add 1 hour

-- Utilities
DateTime.IsLeapYear(2024)        -- true
DateTime.DaysInMonth(2, 2024)    -- 29
```

### EventBus - Enterprise Event System
```lua
local EventBus = Addon.require("EventBus")

-- Subscribe to events
local unsubscribe = EventBus.On("my.event", function(data)
    print("Event received:", data)
end)

-- One-time subscription
EventBus.Once("startup", function()
    print("This only fires once!")
end)

-- Emit events
EventBus.Emit("my.event", "Hello World!")

-- Namespaced events
EventBus.OnNamespace("ui", "button.click", handler)
EventBus.EmitNamespace("ui", "button.click", "SaveButton")

-- Management
unsubscribe()                    -- Remove specific listener
EventBus.Clear("my.event")       -- Remove all listeners for event
EventBus.Clear()                 -- Remove all listeners

-- Statistics & debugging
local stats = EventBus.Stats()  -- Get usage statistics
local events = EventBus.Events() -- List active events
```

### Logger - Enterprise Logging System
```lua
local Logger = Addon.require("Logger")

-- Basic logging with levels
Logger.Debug("Debug message: %s", "details")
Logger.Info("Info message: Player level %d", 85)
Logger.Warn("Warning: %s needs attention", "Health")
Logger.Error("Error: %s failed", "CastSpell")
Logger.Fatal("Fatal: Critical system failure")

-- Level management
Logger.SetLevel("DEBUG")         -- DEBUG, INFO, WARN, ERROR, FATAL
local level = Logger.GetLevel()  -- Get current level
Logger.Enable(false)             -- Turn logging on/off

-- Advanced logging
Logger.LogTable(playerData, "PlayerInfo")        -- Log table contents
Logger.LogFunction("CalculateDamage", 100, 50)   -- Log function calls
Logger.LogError(err, "SpellCasting")             -- Log caught errors

-- Buffer and statistics
local buffer = Logger.GetBuffer()    -- Get all log entries
Logger.ClearBuffer()                 -- Clear log history
local stats = Logger.GetStats()      -- Get logging statistics

-- Custom listeners (e.g., for UI display)
Logger.AddListener(function(fullMessage, level, message, timestamp)
    -- Custom handling of log messages
end, "MyListener")
```

### LogConsole - Visual Log Viewer
```lua
local LogConsole = Addon.require("LogConsole")

-- Basic operations
LogConsole.Show()                -- Open console window
LogConsole.Hide()                -- Close console
LogConsole.Toggle()              -- Toggle visibility

-- Filtering and search
LogConsole.SetFilter("ERROR")    -- Show only ERROR and FATAL
LogConsole.SetSearch("player")   -- Search for "player" in messages
LogConsole.SetAutoScroll(true)   -- Auto-scroll to new messages

-- Export and management
LogConsole.Export()              -- Export filtered logs to copy/paste
LogConsole.Clear()               -- Clear console content
local status = LogConsole.GetStatus()  -- Get console configuration
```

## In-Game Commands

- `/taintedsin` - Show all available commands
- `/taintedsin diag` - Run service diagnostics
- `/taintedsin demo` - Demonstrate all utilities
- `/taintedsin array` - Array utilities demo
- `/taintedsin time` - DateTime utilities demo
- `/taintedsin events` - EventBus demonstration
- `/taintedsin eventstats` - Show EventBus statistics
- `/taintedsin integration` - Service integration demo
- `/taintedsin cleanup` - Clean up demo event listeners
- `/taintedsin info` - Show framework information and version

## Customization

**To use with your addon, change ONE line in every file:**

```lua
local ADDON_NAME = "YourAddonName" -- Change this ONCE per project!
```

That's it! The framework automatically uses your addon's namespace (`_G.YourAddonName`) instead of polluting globals.

## Architecture

### Core Libraries (Never modify these!)
- `Core/PackageLoader.lua` - Generic module system (loaded first)
- `Core/Core.lua` - The immutable DI container
- `Core/Class.lua` - Class system with inheritance  
- `Core/Interface.lua` - Interface definitions
- `Core/TypeCheck.lua` - Runtime type checking
- `Core/TryCatch.lua` - Exception handling
- `Core/init.lua` - Framework initialization and health checks

### Your Code Goes Here
- `Modules/` - Add your feature modules here

## Framework Initialization

The `init.lua` file provides:
- **🔍 Health Checks**: Validates all modules are loaded correctly
- **🏗️ Service Registration**: Auto-registers framework utilities as DI services
- **📊 Diagnostics**: Runs comprehensive startup tests
- **📡 Ready Event**: Emits `framework.ready` event when initialization completes
- **ℹ️ Version Info**: Provides framework version and build information
- Use `Modules/_FeatureTemplate.lua` as a starting point

## Adding New Features

1. Create a new file in `Modules/YourFeature.lua`
2. Start with the namespace block:
```lua
_G.MyAddon = _G.MyAddon or {}
local MyAddon = _G.MyAddon
```
3. Import dependencies:
```lua
local Core = MyAddon.require("Core")
local Class = MyAddon.require("Class")
-- etc...
```
4. Define interfaces, classes, and register services
5. Add your file to `MyAddon.toc`

## Module System

The framework uses a clean `require/provide` system:

- **`PackageLoader.lua`** defines `MyAddon.require()` and `MyAddon.provide()`
- Every core file ends with `MyAddon.provide("ModuleName", ModuleObject)`
- Consumer files use `local Module = MyAddon.require("ModuleName")`
- Load order is controlled by `.toc` file

## No Globals Rule

- Never use Lua's built-in `require()` or `module()` 
- Always use `MyAddon.require()` and `MyAddon.provide()`
- Keep everything under the `MyAddon` namespace

## File Structure

```
Core/
├── PackageLoader.lua          # Module system (first in .toc)
├── Core.lua                   # DI container  
├── Class.lua                  # Class system
├── Interface.lua              # Interface definitions
├── TypeCheck.lua              # Type checking
└── TryCatch.lua              # Exception handling
Modules/
├── HelloWorld.lua            # Example module
└── _FeatureTemplate.lua      # Template for new modules
MyAddon.lua                   # Main entry point
MyAddon.toc                   # Load order manifest
```

## Example Service

```lua
-- Define interface
local IMyService = Interface("IMyService", {"DoWork"})

-- Define class
local MyServiceClass = Class("MyServiceClass", {
    init = function(self, config)
        self.config = config
    end,
    DoWork = function(self)
        print("Working!")
    end
})

-- Register with DI
Core.Register("MyService", function(dependencyService)
    local service = MyServiceClass({})
    assert(TypeCheck.Implements(service, IMyService))
    return service
end, { 
    deps = {"DependencyService"},
    singleton = true 
})
```

## Slash Commands

- `/myaddon` - Show help
- `/myaddon diag` - Run service diagnostics
