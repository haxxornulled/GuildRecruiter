-- init.lua - Main initialization file for TaintedSin addon framework
-- Enterprise-grade modular architecture with full logging support
local ADDON_NAME = "TaintedSin" -- Change this if you use a different addon name!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

-- Initialize loading order (critical modules first)
local loadOrder = {
    "PackageLoader",   -- Module system foundation
    "Core",           -- DI container and framework core
    "Logger",         -- Serilog-style logging system
    "LogConsole",     -- WoW UI frame for log viewing
    "SavedVariablesSink", -- Persistent logging to SavedVariables
    "DateTime",       -- DateTime utilities
    "Class",          -- OOP class system
    "Interface",      -- Interface/contract system
    "TypeCheck",      -- Type validation utilities
    "TryCatch"        -- Error handling utilities
}

print("|cff33ff99[" .. ADDON_NAME .. "]:|r Enterprise Framework v2.0.0 - Initializing modules...")

-- Load modules in dependency order
for i, moduleName in ipairs(loadOrder) do
    local success, err = pcall(function()
        -- Modules are loaded via .toc file in proper order
        -- This init.lua ensures proper initialization sequencing
        print("|cffaaaaaa[" .. ADDON_NAME .. "]:|r Loading " .. moduleName .. "...")
    end)
    
    if not success then
        print("|cffff5555[" .. ADDON_NAME .. "]: Failed to load " .. moduleName .. ":|r " .. tostring(err))
    end
end

-- Wait for all modules to be available, then initialize framework
local function CompleteInitialization()
    local Logger = Addon.require and Addon.require("Logger")
    local LogConsole = Addon.require and Addon.require("LogConsole")
    local Core = Addon.require and Addon.require("Core")
    
    if Logger and LogConsole and Core then
        Logger.Info("=== %s Framework Initialized ===", ADDON_NAME)
        Logger.Info("Enterprise logging system active")
        Logger.Info("Modules loaded: %s", table.concat(loadOrder, ", "))
        Logger.Info("Type /tslogs to open log console")
        
        -- Register slash commands for log console
        SLASH_TSLOGS1 = "/tslogs"
        SLASH_TSLOGS2 = "/tslogconsole"
        SlashCmdList["TSLOGS"] = function(msg)
            if msg == "clear" then
                Logger.Info("Clearing log console...")
                LogConsole.Hide()
                if Logger.ClearBuffer then
                    Logger.ClearBuffer()
                end
            elseif msg == "stats" then
                if Logger.PrintStats then
                    Logger.PrintStats()
                end
                local stats = LogConsole.GetStats()
                Logger.Info("Console: %d total, %d filtered, buffer=%d, visible=%s", 
                    stats.totalLines, stats.filteredLines, stats.bufferSize, tostring(stats.isVisible))
            elseif msg == "test" then
                Logger.Debug("Test DEBUG message with timestamp")
                Logger.Info("Test INFO message - framework operational")
                Logger.Warn("Test WARN message - this is a warning")
                Logger.Error("Test ERROR message - simulated error")
                Logger.Info("Log test completed - check console UI")
            else
                LogConsole.Toggle()
            end
        end
        
        -- Register framework global access
        _G[ADDON_NAME .. "_Framework"] = {
            Logger = Logger,
            LogConsole = LogConsole,
            Core = Core,
            Version = "2.0.0",
            Modules = loadOrder
        }
        
        Logger.Info("Framework globals registered as %s_Framework", ADDON_NAME)
        Logger.Info("Use Logger.ForContext({user='player'}).Info('message') for structured logging")
        
        return true
    else
        print("|cffff5555[" .. ADDON_NAME .. "]: Some core modules not available, retrying...|r")
        return false
    end
end

-- Try initialization immediately, then retry if needed
if not CompleteInitialization() then
    -- Retry after short delay to allow module loading
    local retryCount = 0
    local function RetryInit()
        retryCount = retryCount + 1
        if CompleteInitialization() then
            print("|cff33ff99[" .. ADDON_NAME .. "]:|r Framework initialization completed after " .. retryCount .. " retries")
            return
        elseif retryCount < 10 then
            C_Timer.After(0.5, RetryInit)
        else
            print("|cffff5555[" .. ADDON_NAME .. "]: Framework initialization FAILED after " .. retryCount .. " attempts|r")
        end
    end
    C_Timer.After(0.5, RetryInit)
end

-- Provide init module
if Addon.provide then
    Addon.provide("Init", {
        Version = "2.0.0",
        LoadOrder = loadOrder,
        CompleteInitialization = CompleteInitialization
    })
end

print("|cff33ff99[" .. ADDON_NAME .. "]:|r Init.lua completed - Enterprise framework loading...")
