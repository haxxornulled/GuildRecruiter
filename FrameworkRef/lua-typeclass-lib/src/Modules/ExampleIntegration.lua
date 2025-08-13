-- Modules/ExampleIntegration.lua
-- Shows how EventBus integrates with other services
local ADDON_NAME = "TaintedSin"
local Addon = _G[ADDON_NAME]

local Core = Addon.require("Core")
local EventBus = Addon.require("EventBus")
local DateTime = Addon.require("DateTime")

-- Example of a service that both emits and listens to events
local PlayerStatusService = {
    init = function(self)
        self.loginTime = DateTime.UtcEpoch()
        self.eventSubscriptions = {}
        self:SetupEventListeners()
        
        -- Emit that we're ready
        EventBus.Emit("player.status.ready", self.loginTime)
    end,
    
    SetupEventListeners = function(self)
        -- Listen for addon events
        self.eventSubscriptions[1] = EventBus.On("addon.loaded", function(addonName)
            print("|cff00ff00[PlayerStatus]:|r Addon loaded: " .. addonName)
        end)
        
        -- Listen for player events
        self.eventSubscriptions[2] = EventBus.On("player.level.changed", function(newLevel, oldLevel)
            local uptime = DateTime.DiffHuman(DateTime.UtcEpoch(), self.loginTime)
            print("|cff00ff00[PlayerStatus]:|r Level changed from " .. oldLevel .. 
                  " to " .. newLevel .. " (uptime: " .. uptime .. ")")
            
            -- Re-emit as a more specific event
            EventBus.Emit("player.progression.levelup", {
                newLevel = newLevel,
                oldLevel = oldLevel,
                uptime = uptime,
                timestamp = DateTime.UtcEpoch()
            })
        end)
    end,
    
    SimulateEvents = function(self)
        -- Simulate some player events
        EventBus.Emit("player.level.changed", 61, 60)
        EventBus.Emit("player.level.changed", 62, 61)
        
        -- Emit status update
        EventBus.Emit("player.status.update", {
            uptime = DateTime.DiffHuman(DateTime.UtcEpoch(), self.loginTime),
            loginTime = self.loginTime
        })
    end,
    
    Cleanup = function(self)
        for _, unsub in pairs(self.eventSubscriptions) do
            unsub()
        end
        self.eventSubscriptions = {}
        EventBus.Emit("player.status.cleanup")
    end
}

-- A logging service that listens to all events
local EventLoggerService = {
    init = function(self)
        self.eventLog = {}
        self.maxLogSize = 50
        
        -- Listen to all player events with a wildcard-like approach
        EventBus.On("player.status.ready", function(loginTime)
            self:LogEvent("PlayerStatus", "Service ready", { loginTime = loginTime })
        end)
        
        EventBus.On("player.progression.levelup", function(data)
            self:LogEvent("PlayerProgression", "Level up", data)
        end)
        
        EventBus.On("player.status.update", function(data)
            self:LogEvent("PlayerStatus", "Status update", data)
        end)
        
        EventBus.On("player.status.cleanup", function()
            self:LogEvent("PlayerStatus", "Service cleanup", {})
        end)
    end,
    
    LogEvent = function(self, category, action, data)
        local logEntry = {
            timestamp = DateTime.UtcEpoch(),
            category = category,
            action = action,
            data = data or {}
        }
        
        table.insert(self.eventLog, logEntry)
        
        -- Trim log if too large
        if #self.eventLog > self.maxLogSize then
            table.remove(self.eventLog, 1)
        end
        
        print("|cffff6600[EventLogger]:|r " .. category .. " -> " .. action)
    end,
    
    GetRecentEvents = function(self, count)
        count = count or 10
        local recent = {}
        local start = math.max(1, #self.eventLog - count + 1)
        
        for i = start, #self.eventLog do
            table.insert(recent, self.eventLog[i])
        end
        
        return recent
    end,
    
    PrintLog = function(self, count)
        local events = self:GetRecentEvents(count)
        print("|cffff6600[EventLogger]:|r Recent Events:")
        
        for _, event in ipairs(events) do
            local timeStr = DateTime.FormatChat(event.timestamp)
            print("  " .. timeStr .. " | " .. event.category .. " -> " .. event.action)
        end
    end
}

-- Register services with DI
Core.Register("PlayerStatusService", function()
    return PlayerStatusService
end, { singleton = true })

Core.Register("EventLoggerService", function()
    return EventLoggerService  
end, { singleton = true })

-- Integration demo service
Core.Register("IntegrationDemoService", function()
    return {
        RunDemo = function(self)
            print("|cff9900ff[Integration Demo]:|r Starting integrated services demo...")
            
            -- Get services (they auto-initialize and setup event listeners)
            local playerStatus = Core.Resolve("PlayerStatusService")
            local eventLogger = Core.Resolve("EventLoggerService")
            
            -- Simulate some activity
            playerStatus:SimulateEvents()
            
            -- Show the logged events
            eventLogger:PrintLog(5)
            
            print("|cff9900ff[Integration Demo]:|r Demo completed!")
        end
    }
end, { singleton = true })

Addon.provide("PlayerStatusService", PlayerStatusService)
Addon.provide("EventLoggerService", EventLoggerService)
