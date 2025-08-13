-- LoggerDemo.lua - Enterprise Logging Demo (Serilog-Style, WoW AddOn Ready)
local ADDON_NAME = "TaintedSin"
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

local LoggerDemo = {}

local demoRunning = false
local demoStep = 1

-- Demos
local function RunBasicLoggingDemo()
    local Logger = Addon.require("Logger")
    if not Logger then return end
    Logger.Info("=== Basic Logging Demo Started ===")
    Logger.Debug("This is a DEBUG message")
    Logger.Info("This is an INFO message")
    Logger.Warn("This is a WARN message")
    Logger.Error("This is an ERROR message")
    Logger.Fatal("This is a FATAL message")
    Logger.Info("Player has %d gold and %d silver", 1250, 75)
    Logger.Warn("Health is low: %d/%d (%.1f%%)", 150, 1000, 15.0)
    Logger.Log("INFO", "Player action completed", {}, { action="quest_complete", questId=12345, experience=2500, reputation=150 })
    Logger.Info("Basic logging demo completed")
end

local function RunContextualLoggingDemo()
    local Logger = Addon.require("Logger")
    if not Logger then return end
    Logger.Info("=== Contextual Logging Demo Started ===")
    local playerLogger = Logger.ForContext({module="Player", character="TestChar"})
    local combatLogger = Logger.ForContext({module="Combat", zone="Stormwind"})
    local questLogger = Logger.ForContext({module="Quest", category="Main"})
    playerLogger.Info("Player logged in successfully")
    playerLogger.Debug("Loading player data from server")
    combatLogger.Warn("Entering hostile territory")
    combatLogger.Error("Player took critical damage: %d", 850)
    questLogger.Info("New quest accepted: %s", "The Hero's Call")
    questLogger.Debug("Quest objective updated: Kill %d/%d wolves", 5, 10)
    local detailedCombatLogger = combatLogger.ForContext({target="Lich King", difficulty="Heroic"})
    detailedCombatLogger.Fatal("Player defeated by raid boss!")
    Logger.Info("Contextual logging demo completed")
end

local function RunAdvancedFeaturesDemo()
    local Logger = Addon.require("Logger")
    if not Logger then return end
    Logger.Info("=== Advanced Features Demo Started ===")
    -- Table logging (stub or implement in Logger for pretty print)
    if Logger.LogTable then
        local playerData = {
            name = "TestPlayer",
            level = 80,
            class = "Paladin",
            guild = {name = "TestGuild", rank = "Member"},
            stats = {health = 25000, mana = 15000}
        }
        Logger.LogTable(playerData, "PlayerData", 2)
    end
    -- Function call logging (stub or implement in Logger)
    if Logger.LogFunction then
        Logger.LogFunction("CastSpell", "Holy Light", "target")
    end
    -- Error context logging
    if Logger.LogError then
        local function SimulateError()
            error("Simulated addon error for demo")
        end
        local success, err = pcall(SimulateError)
        if not success then
            Logger.LogError(err, "SimulateError function")
        end
    end
    -- Performance context
    local startTime = GetTime and GetTime() or 0
    for i = 1, 1000 do local dummy = math.sqrt(i) end
    local endTime = GetTime and GetTime() or 0
    Logger.ForContext({
        operation = "DataProcessing",
        duration = string.format("%.3f", (endTime - startTime) * 1000),
        records = 1000
    }).Info("Bulk operation completed")
    Logger.Info("Advanced features demo completed")
end

local function RunSinkManagementDemo()
    local Logger = Addon.require("Logger")
    if not Logger then return end
    Logger.Info("=== Sink Management Demo Started ===")
    local sinks = Logger.ListSinks and Logger.ListSinks() or {}
    Logger.Info("Current sinks: %s", type(sinks)=="table" and table.concat(sinks, ", ") or tostring(sinks))
    local demoMessages = {}
    local customSink = function(event)
        table.insert(demoMessages, string.format("[CUSTOM][%s] %s", event.level, event.message))
        if #demoMessages > 5 then table.remove(demoMessages, 1) end
    end
    if Logger.AddSink then Logger.AddSink(customSink, 2, "DemoSink") end
    Logger.Info("Added custom demo sink")
    Logger.Info("Message 1 - should appear in custom sink")
    Logger.Warn("Message 2 - should appear in custom sink")
    Logger.Debug("Message 3 - should NOT appear in custom sink (level too low)")
    Logger.Error("Message 4 - should appear in custom sink")
    Logger.Info("Custom sink captured %d messages:", #demoMessages)
    for i, msg in ipairs(demoMessages) do print("  " .. msg) end
    if Logger.RemoveSink then Logger.RemoveSink("DemoSink") end
    Logger.Info("Removed custom demo sink")
    Logger.Info("Sink management demo completed")
end

local function RunUIIntegrationDemo()
    local Logger = Addon.require("Logger")
    local LogConsole = Addon.require("LogConsole")
    if not Logger or not LogConsole then return end
    Logger.Info("=== UI Integration Demo Started ===")
    LogConsole.Show()
    Logger.Info("Log console opened - you should see a UI window")
    Logger.Debug("Debug message for filtering test")
    Logger.Info("Info message for filtering test")
    Logger.Warn("Warning message for filtering test")
    Logger.Error("Error message for filtering test")
    if LogConsole.GetStats then
        local stats = LogConsole.GetStats()
        Logger.Info("Console stats: %d total lines, %d filtered, buffer size: %d",
            stats.totalLines, stats.filteredLines, stats.bufferSize)
    end
    Logger.Info("Try changing the filter dropdown in the console to see different log levels")
    Logger.Info("Right-click the console for context menu options")
    Logger.Info("Use the Clear button to clear logs, Copy button to copy them")
    Logger.Info("UI integration demo completed - console remains open")
end

local function RunPersistenceDemo()
    local Logger = Addon.require("Logger")
    local SavedVariablesSink = Addon.require and Addon.require("SavedVariablesSink") or nil
    if not Logger or not SavedVariablesSink then
        Logger.Warn("SavedVariablesSink not available - persistence demo skipped")
        return
    end
    Logger.Info("=== Persistence Demo Started ===")
    if SavedVariablesSink.GetStats then
        local stats = SavedVariablesSink.GetStats()
        Logger.Info("Persistent logging stats: total logs: %s, entries: %s, session: %s",
            stats.totalLogs or 0, stats.currentEntries or 0, stats.currentSession or "N/A")
    end
    Logger.Info("Generating persistent log entries...")
    for i = 1, 5 do
        Logger.ForContext({
            demoSequence = i,
            timestamp = date("%Y-%m-%d %H:%M:%S"),
            persistent = true
        }).Info("Persistent demo message #%d", i)
    end
    if SavedVariablesSink.GetLogs then
        local recentLogs = SavedVariablesSink.GetLogs(3)
        Logger.Info("Recent persistent logs (%d entries):", #recentLogs)
        for i, entry in ipairs(recentLogs) do
            Logger.Info("  [%s] %s", entry.level, entry.message)
        end
    end
    Logger.Info("Persistence demo completed - logs saved to SavedVariables")
end

function LoggerDemo.RunFullDemo()
    if demoRunning then print("|cffff5555[" .. ADDON_NAME .. "]: Demo already running!|r") return end
    demoRunning = true
    demoStep = 1
    local Logger = Addon.require("Logger")
    if not Logger then print("|cffff5555[" .. ADDON_NAME .. "]: Logger not available for demo!|r") demoRunning = false return end
    Logger.Info("🚀 ENTERPRISE LOGGING SYSTEM DEMONSTRATION 🚀")
    Logger.Info("This demo showcases all logging features in sequence")
    Logger.Info("Watch the chat and log console for output")
    local demos = {
        RunBasicLoggingDemo,
        RunContextualLoggingDemo,
        RunAdvancedFeaturesDemo,
        RunSinkManagementDemo,
        RunUIIntegrationDemo,
        RunPersistenceDemo
    }
    local function RunNextDemo()
        if demoStep <= #demos then
            demos[demoStep]()
            demoStep = demoStep + 1
            if demoStep <= #demos then
                local timer, frame = 0, CreateFrame("Frame")
                frame:SetScript("OnUpdate", function(self, elapsed)
                    timer = timer + elapsed
                    if timer >= 3 then
                        frame:SetScript("OnUpdate", nil)
                        RunNextDemo()
                    end
                end)
            else
                local timer, frame = 0, CreateFrame("Frame")
                frame:SetScript("OnUpdate", function(self, elapsed)
                    timer = timer + elapsed
                    if timer >= 2 then
                        frame:SetScript("OnUpdate", nil)
                        Logger.Info("🎉 DEMONSTRATION COMPLETED 🎉")
                        Logger.Info("All enterprise logging features demonstrated")
                        Logger.Info("Use /tslogs to open console, /tslogdemo for demo")
                        demoRunning = false
                    end
                end)
            end
        end
    end
    RunNextDemo()
end

function LoggerDemo.TestBasic() RunBasicLoggingDemo() end
function LoggerDemo.TestContextual() RunContextualLoggingDemo() end
function LoggerDemo.TestAdvanced() RunAdvancedFeaturesDemo() end
function LoggerDemo.TestSinks() RunSinkManagementDemo() end
function LoggerDemo.TestUI() RunUIIntegrationDemo() end
function LoggerDemo.TestPersistence() RunPersistenceDemo() end

function LoggerDemo.ShowStats()
    local Logger = Addon.require("Logger")
    local LogConsole = Addon.require("LogConsole")
    local SavedVariablesSink = Addon.require and Addon.require("SavedVariablesSink") or nil
    if not Logger then print("|cffff5555[" .. ADDON_NAME .. "]: Logger not available!|r") return end
    Logger.Info("=== ENTERPRISE LOGGING SYSTEM STATUS ===")
    if Logger.GetStats then
        local stats = Logger.GetStats()
        Logger.Info("Logger: %d sinks, %d enrichers, level: %s",
            stats.sinks or 0, stats.enrichers or 0, stats.currentLevel or "N/A")
    end
    if LogConsole and LogConsole.GetStats then
        local stats = LogConsole.GetStats()
        Logger.Info("Console: %d lines, filter: %s, buffer: %d, visible: %s",
            stats.totalLines, stats.currentFilter, stats.bufferSize, tostring(stats.isVisible))
    end
    if SavedVariablesSink and SavedVariablesSink.GetStats then
        local stats = SavedVariablesSink.GetStats()
        Logger.Info("Persistence: %d total logs, %d current, session: %s",
            stats.totalLogs or 0, stats.currentEntries or 0, stats.currentSession or "N/A")
    end
    Logger.Info("=== STATUS REPORT COMPLETE ===")
end

-- Slash commands
SLASH_TSLOGDEMO1 = "/tslogdemo"
SLASH_TSLOGDEMO2 = "/tsdemo"
SlashCmdList["TSLOGDEMO"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s*", ""):gsub("%s*$", "")
    if msg == "full" or msg == "" then LoggerDemo.RunFullDemo()
    elseif msg == "basic" then LoggerDemo.TestBasic()
    elseif msg == "context" then LoggerDemo.TestContextual()
    elseif msg == "advanced" then LoggerDemo.TestAdvanced()
    elseif msg == "sinks" then LoggerDemo.TestSinks()
    elseif msg == "ui" then LoggerDemo.TestUI()
    elseif msg == "persistence" then LoggerDemo.TestPersistence()
    elseif msg == "stats" then LoggerDemo.ShowStats()
    else
        print("|cff33ff99[" .. ADDON_NAME .. " Demo]:|r Available commands:")
        print("  /tslogdemo or /tsdemo - Run full demonstration")
        print("  /tsdemo basic - Basic logging features")
        print("  /tsdemo context - Contextual logging")
        print("  /tsdemo advanced - Advanced features")
        print("  /tsdemo sinks - Sink management")
        print("  /tsdemo ui - UI integration")
        print("  /tsdemo persistence - SavedVariables persistence")
        print("  /tsdemo stats - Show system status")
    end
end

-- Provide module
Addon.provide("LoggerDemo", LoggerDemo)
