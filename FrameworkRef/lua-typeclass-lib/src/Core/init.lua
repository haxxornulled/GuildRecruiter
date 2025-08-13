-- init.lua - Framework Initialization and Health Check
-- Ensures all core modules are loaded, registered, and working properly
local ADDON_NAME = "TaintedSin" -- Change this if you use a different addon name!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

-- Framework version and build info
local FRAMEWORK_VERSION = "1.0.0"
local BUILD_DATE = "2025-08-01"

print("|cff33ff99[" .. ADDON_NAME .. "]:|r Initializing framework v" .. FRAMEWORK_VERSION .. "...")

-- Require each core module (forces .toc order and module load)
-- This validates that all modules are properly loaded and provided
local Core      = Addon.require("Core")
local Class     = Addon.require("Class")
local Interface = Addon.require("Interface")
local TypeCheck = Addon.require("TypeCheck")
local TryCatch  = Addon.require("TryCatch")

-- Require utility modules
local ArrayUtils = Addon.require("ArrayUtils")
local DateTime   = Addon.require("DateTime")
local EventBus   = Addon.require("EventBus")
local Logger     = Addon.require("Logger")
local LogConsole = Addon.require("LogConsole")
local LoggerDemo = Addon.require("LoggerDemo")

-- Enable framework logging
if Core and Core.EnableLogging then
    Core.EnableLogging(true)
end

-- Framework health check and validation
local function PerformHealthCheck()
    -- Check that all core modules are loaded
    assert(Core and type(Core.Register) == "function", "Core DI container not loaded!")
    assert(Class and type(Class) == "function", "Class system not loaded!")
    assert(Interface and type(Interface) == "function", "Interface system not loaded!")
    assert(TypeCheck and TypeCheck.IsInstanceOf and TypeCheck.Implements, "TypeCheck system not loaded!")
    assert(TryCatch and type(TryCatch) == "function", "TryCatch system not loaded!")
    
    -- Check utility modules
    assert(ArrayUtils and ArrayUtils.map and ArrayUtils.filter, "ArrayUtils not loaded!")
    assert(DateTime and DateTime.UtcNow and DateTime.FormatUTC, "DateTime not loaded!")
    assert(EventBus and EventBus.On and EventBus.Emit, "EventBus not loaded!")
    assert(Logger and Logger.Info and Logger.Error, "Logger not loaded!")
    assert(LogConsole and LogConsole.Show and LogConsole.Hide, "LogConsole not loaded!")
    
    -- Test basic functionality
    local testInterface = Interface("TestInterface", {"TestMethod"})
    assert(testInterface.__interface, "Interface creation failed!")
    
    local TestClass = Class("TestClass", {
        TestMethod = function(self) return "test" end
    })
    local testInstance = TestClass()
    assert(TypeCheck.Implements(testInstance, testInterface), "TypeCheck validation failed!")
    
    -- Test ArrayUtils
    local testArray = {1, 2, 3}
    local mapped = ArrayUtils.map(testArray, function(x) return x * 2 end)
    assert(#mapped == 3 and mapped[1] == 2, "ArrayUtils test failed!")
    
    -- Test DateTime
    local now = DateTime.UtcNow()
    assert(now and now.year and now.month, "DateTime test failed!")
    
    -- Test EventBus
    local eventFired = false
    local unsubscribe = EventBus.On("test.event", function() eventFired = true end)
    EventBus.Emit("test.event")
    unsubscribe()
    assert(eventFired, "EventBus test failed!")
    
    -- Test Logger
    Logger.Info("Framework health check - Logger test successful")
    local stats = Logger.GetStats()
    assert(stats and stats.totalLogs > 0, "Logger stats test failed!")
    
    -- Test LogConsole (basic functionality)
    local consoleStatus = LogConsole.GetStatus()
    assert(consoleStatus, "LogConsole status test failed!")
    
    return true
end

-- Register framework-wide singletons/services for DI
local function RegisterFrameworkServices()
    -- Register utility modules as DI services (if not already registered)
    if not Core.HasService("ArrayUtils") then
        Core.Register("ArrayUtils", function() return ArrayUtils end, { singleton = true })
    end
    
    if not Core.HasService("DateTime") then
        Core.Register("DateTime", function() return DateTime end, { singleton = true })
    end
    
    if not Core.HasService("EventBus") then
        Core.Register("EventBus", function() return EventBus end, { singleton = true })
    end
    
    if not Core.HasService("Logger") then
        Core.Register("Logger", function() return Logger end, { singleton = true })
    end
    
    if not Core.HasService("LogConsole") then
        Core.Register("LogConsole", function() return LogConsole end, { singleton = true })
    end
    
    if not Core.HasService("LoggerDemo") then
        Core.Register("LoggerDemo", function() return LoggerDemo end, { singleton = true })
    end
    
    -- Register framework info service
    Core.Register("FrameworkInfo", function()
        return {
            name = ADDON_NAME,
            version = FRAMEWORK_VERSION,
            buildDate = BUILD_DATE,
            coreModules = {"Core", "Class", "Interface", "TypeCheck", "TryCatch"},
            utilityModules = {"ArrayUtils", "DateTime", "EventBus", "Logger", "LogConsole"},
            GetInfo = function(self)
                return {
                    name = self.name,
                    version = self.version,
                    buildDate = self.buildDate,
                    moduleCount = #self.coreModules + #self.utilityModules
                }
            end
        }
    end, { singleton = true })
end

-- Comprehensive framework initialization
local function InitializeFramework()
    local startTime = DateTime and DateTime.UtcEpoch() or 0
    
    -- Step 1: Health check
    local healthOk, healthErr = pcall(PerformHealthCheck)
    if not healthOk then
        print("|cffff5555[" .. ADDON_NAME .. "]: Framework health check FAILED:|r " .. tostring(healthErr))
        return false
    end
    
    -- Step 2: Register framework services
    local servicesOk, servicesErr = pcall(RegisterFrameworkServices)
    if not servicesOk then
        print("|cffff5555[" .. ADDON_NAME .. "]: Service registration FAILED:|r " .. tostring(servicesErr))
        return false
    end
    
    -- Step 3: Run DI diagnostics
    if Core.DiagnoseServices then
        print("|cff33ff99[" .. ADDON_NAME .. "]:|r Running DI container diagnostics...")
        local diagnostics = Core.DiagnoseServices()
        local failedServices = 0
        for _, success in pairs(diagnostics) do
            if not success then failedServices = failedServices + 1 end
        end
        
        if failedServices > 0 then
            print("|cffff5555[" .. ADDON_NAME .. "]: " .. failedServices .. " services failed diagnostics!|r")
            return false
        end
    end
    
    -- Step 4: Connect Logger to LogConsole
    Logger.AddListener(function(fullMessage, level, message, timestamp)
        LogConsole.AddLine(fullMessage)
    end, "LogConsole")
    
    -- Step 5: Emit framework ready event
    if EventBus then
        EventBus.Emit("framework.ready", {
            name = ADDON_NAME,
            version = FRAMEWORK_VERSION,
            buildDate = BUILD_DATE,
            initTime = DateTime and DateTime.UtcEpoch() - startTime or 0
        })
    end
    
    return true
end

-- Execute initialization
local initSuccess = InitializeFramework()

if initSuccess then
    print("|cff00ff00[" .. ADDON_NAME .. "]:|r Framework v" .. FRAMEWORK_VERSION .. " initialized successfully! ✓")
    
    -- Optional: Show framework stats
    local stats = EventBus and EventBus.Stats() or {}
    local serviceCount = #(Core.ListServices and Core.ListServices() or {})
    print("|cff33ff99[" .. ADDON_NAME .. "]:|r " .. serviceCount .. " services registered, framework ready for use.")
else
    print("|cffff0000[" .. ADDON_NAME .. "]:|r Framework initialization FAILED! ✗")
end

-- Provide for require() pattern
Addon.provide("Init", {
    success = initSuccess,
    version = FRAMEWORK_VERSION,
    buildDate = BUILD_DATE,
    addonName = ADDON_NAME
})
