-- MyAddon.lua
local ADDON_NAME = "TaintedSin"
local Addon = _G[ADDON_NAME]
local Core = Addon.require("Core")

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == ADDON_NAME then
        Core.InitAll()
        Core.DiagnoseServices()
        
        -- Demonstrate HelloWorld
        local hello = Core.Resolve("HelloWorldService")
        hello:SayHello()
        
        -- Demonstrate utilities
        local utils = Core.Resolve("ExampleUtilitiesService")
        utils:RunAllDemos()
        
        -- Fire a startup event
        local EventBus = Core.Resolve("EventBus")
        EventBus.Emit("addon.loaded", ADDON_NAME)
    end
end)

SLASH_TAINTEDSIN1 = "/taintedsin"
SlashCmdList["TAINTEDSIN"] = function(msg)
    if msg == "diag" then
        Core.DiagnoseServices()
    elseif msg == "demo" then
        local utils = Core.Resolve("ExampleUtilitiesService")
        utils:RunAllDemos()
    elseif msg == "array" then
        local utils = Core.Resolve("ExampleUtilitiesService")
        utils:DemonstrateArrays()
    elseif msg == "time" then
        local utils = Core.Resolve("ExampleUtilitiesService")
        utils:DemonstrateDateTime()
    elseif msg == "events" then
        local eventDemo = Core.Resolve("EventBusDemoService")
        eventDemo:RunAllDemos()
    elseif msg == "eventstats" then
        local EventBus = Core.Resolve("EventBus")
        local stats = EventBus.Stats()
        print("|cff33ff99[TaintedSin]:|r EventBus Statistics:")
        print("  Active events: " .. stats.events)
        print("  Total listeners: " .. stats.listeners)  
        print("  Events emitted: " .. stats.emitted)
        print("  Handler errors: " .. stats.errors)
    elseif msg == "cleanup" then
        local eventDemo = Core.Resolve("EventBusDemoService")
        eventDemo:Cleanup()
    elseif msg == "integration" then
        local integrationDemo = Core.Resolve("IntegrationDemoService")
        integrationDemo:RunDemo()
    elseif msg == "info" then
        local frameworkInfo = Core.Resolve("FrameworkInfo")
        local info = frameworkInfo:GetInfo()
        local EventBus = Core.Resolve("EventBus")
        local Logger = Core.Resolve("Logger")
        print("|cff33ff99[TaintedSin]:|r Framework Information:")
        print("  Name: " .. info.name)
        print("  Version: " .. info.version)
        print("  Build Date: " .. info.buildDate)
        print("  Modules: " .. info.moduleCount)
        
        local stats = EventBus.Stats()
        print("  EventBus: " .. stats.events .. " events, " .. stats.listeners .. " listeners")
        
        local logStats = Logger.GetStats()
        print("  Logger: " .. logStats.totalLogs .. " logs, " .. logStats.listenersCount .. " listeners")
    elseif msg == "logdemo" then
        local loggerDemo = Core.Resolve("LoggerDemo")
        loggerDemo.RunAllDemos()
    elseif msg == "console" then
        local LogConsole = Core.Resolve("LogConsole")
        LogConsole.Toggle()
    else
        print("|cff33ff99[TaintedSin]:|r Commands:")
        print("  /taintedsin diag - Service diagnostics")
        print("  /taintedsin demo - Run all utility demos") 
        print("  /taintedsin array - Array utilities demo")
        print("  /taintedsin time - DateTime utilities demo")
        print("  /taintedsin events - EventBus demonstration")
        print("  /taintedsin eventstats - Show EventBus statistics")
        print("  /taintedsin cleanup - Clean up demo event listeners")
        print("  /taintedsin integration - Service integration demo")
        print("  /taintedsin info - Show framework information")
        print("  /taintedsin logdemo - Run comprehensive Logger demonstration")
        print("  /taintedsin console - Toggle log console window")
        print("  ")
        print("  Advanced logging commands:")
        print("  /tslog on|off - Enable/disable logging")
        print("  /tslog level [LEVEL] - Set log level (DEBUG|INFO|WARN|ERROR|FATAL)")
        print("  /tslog demo [TYPE] - Run specific log demos")
        print("  /tsconsole - Toggle log console with filtering/search")
    end
end
