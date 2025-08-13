-- Modules/EventBusDemo.lua
local ADDON_NAME = "TaintedSin"
local Addon = _G[ADDON_NAME]

local EventBus = Addon.require("EventBus")
local Core = Addon.require("Core")

-- Demo service that shows EventBus usage
local EventBusDemoClass = {
    init = function(self)
        self.messageCount = 0
        self.subscriptions = {}
        self:SetupEventListeners()
    end,
    
    SetupEventListeners = function(self)
        -- Example 1: Simple event subscription
        self.subscriptions[1] = EventBus.On("demo.message", function(message, sender)
            self.messageCount = self.messageCount + 1
            print("|cffff9900[EventBus Demo]:|r Message #" .. self.messageCount .. 
                  " from " .. (sender or "unknown") .. ": " .. (message or ""))
        end)
        
        -- Example 2: One-time event subscription
        self.subscriptions[2] = EventBus.Once("demo.startup", function()
            print("|cffff9900[EventBus Demo]:|r Startup event fired once!")
        end)
        
        -- Example 3: Namespaced events
        self.subscriptions[3] = EventBus.OnNamespace("ui", "button.click", function(buttonName)
            print("|cffff9900[EventBus Demo]:|r UI Button clicked: " .. (buttonName or "unknown"))
        end)
        
        -- Example 4: Error handling demonstration
        self.subscriptions[4] = EventBus.On("demo.error", function()
            error("This is a deliberate error to show error handling!")
        end)
    end,
    
    DemoBasicEvents = function(self)
        print("|cffff9900[EventBus Demo]:|r === Basic Events Demo ===")
        
        -- Fire some messages
        EventBus.Emit("demo.message", "Hello World!", "System")
        EventBus.Emit("demo.message", "This is a test", "User")
        EventBus.Emit("demo.message", "EventBus is working!", "EventBus")
        
        -- Fire startup event (will only work once due to Once subscription)
        EventBus.Emit("demo.startup")
        EventBus.Emit("demo.startup") -- This won't trigger the handler
        
        print("Message count: " .. self.messageCount)
    end,
    
    DemoNamespacedEvents = function(self)
        print("|cffff9900[EventBus Demo]:|r === Namespaced Events Demo ===")
        
        -- Fire namespaced events
        EventBus.EmitNamespace("ui", "button.click", "SaveButton")
        EventBus.EmitNamespace("ui", "button.click", "CancelButton")
        EventBus.Emit("ui.button.click", "DirectButton") -- Alternative syntax
    end,
    
    DemoErrorHandling = function(self)
        print("|cffff9900[EventBus Demo]:|r === Error Handling Demo ===")
        
        -- This will trigger an error but not crash the addon
        EventBus.Emit("demo.error")
        
        print("Error handled gracefully - addon continues running!")
    end,
    
    DemoStatistics = function(self)
        print("|cffff9900[EventBus Demo]:|r === EventBus Statistics ===")
        
        local stats = EventBus.Stats()
        print("Active events: " .. stats.events)
        print("Total listeners: " .. stats.listeners)
        print("Events emitted: " .. stats.emitted)
        print("Handler errors: " .. stats.errors)
        
        local events = EventBus.Events()
        print("Registered events: " .. table.concat(events, ", "))
    end,
    
    RunAllDemos = function(self)
        print("|cffff9900[EventBus Demo]:|r Starting EventBus demonstrations...")
        print("")
        
        self:DemoBasicEvents()
        print("")
        
        self:DemoNamespacedEvents()
        print("")
        
        self:DemoErrorHandling()
        print("")
        
        self:DemoStatistics()
        print("")
        
        print("|cffff9900[EventBus Demo]:|r All demos completed!")
    end,
    
    Cleanup = function(self)
        -- Unsubscribe from all events
        for _, unsubscribe in pairs(self.subscriptions) do
            if type(unsubscribe) == "function" then
                unsubscribe()
            end
        end
        self.subscriptions = {}
        print("|cffff9900[EventBus Demo]:|r Cleaned up all event subscriptions")
    end
}

-- Register as a service for DI
Core.Register("EventBusDemoService", function()
    return EventBusDemoClass
end, { singleton = true })

-- Also register EventBus itself as a DI service
Core.Register("EventBus", function() 
    return EventBus 
end, { singleton = true })

Addon.provide("EventBusDemoClass", EventBusDemoClass)
