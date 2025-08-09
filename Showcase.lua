-- Showcase.lua — Demonstrates the power of the Guild Recruiter framework
local _, Addon = ...

-- This file shows how we've essentially built a .NET-style application framework in Lua!

local function ShowcaseFramework()
    print("|cff00ff00=== GUILD RECRUITER FRAMEWORK SHOWCASE ===|r")
    print("")
    
    -- ===========================
    -- 1. Dependency Injection Container (Autofac-style)
    -- ===========================
    print("|cffffff00[1] Dependency Injection Container|r")
    print("✓ Service registration with lifetime management")
    print("✓ Constructor injection via scope resolution")
    print("✓ Lazy facades with boot-time protection")
    print("✓ Circular dependency detection")
    print("✓ Owned<T> pattern for disposable scopes")
    print("")
    
    -- Show some DI in action
    if Addon.require then
        local logger = Addon.require("Logger")
        local eventBus = Addon.require("EventBus") 
        local config = Addon.require("Config")
        
        print("Sample DI resolutions:")
        print("  Logger instance:", type(logger))
        print("  EventBus instance:", type(eventBus))
        print("  Config instance:", type(config))
        print("")
    end
    
    -- ===========================
    -- 2. LINQ-style Collections
    -- ===========================
    print("|cffffff00[2] LINQ-style Collections (C# → Lua)|r")
    print("✓ List<T> with fluent interface")
    print("✓ Dictionary<K,V> with key-value operations")
    print("✓ Extension methods for raw tables")
    print("✓ Method chaining: Where().Select().OrderBy()")
    print("")
    
    -- Demonstrate LINQ power
    local prospects = Addon.List.new({
        { name = "Alice", level = 85, class = "MAGE" },
        { name = "Bob", level = 78, class = "WARRIOR" },
        { name = "Charlie", level = 82, class = "MAGE" },
        { name = "Diana", level = 76, class = "PRIEST" }
    })
    
    local highLevelMages = prospects
        :Where(function(p) return p.class == "MAGE" and p.level >= 80 end)
        :Select(function(p) return p.name .. " (L" .. p.level .. ")" end)
        :OrderBy()
    
    print("LINQ Example - High-level mages:")
    highLevelMages:ForEach(function(name) print("  " .. name) end)
    print("")
    
    -- ===========================
    -- 3. Event-Driven Architecture
    -- ===========================
    print("|cffffff00[3] Event-Driven Architecture|r")
    print("✓ Pub/Sub messaging bus")
    print("✓ WoW event integration")
    print("✓ Namespace support for cleanup")
    print("✓ Error isolation with pcall")
    print("")
    
    if Addon.EventBus then
        print("EventBus available - framework events active")
        print("  Events like: ConfigChanged, ProspectQueued, etc.")
    end
    print("")
    
    -- ===========================
    -- 4. Structured Logging
    -- ===========================
    print("|cffffff00[4] Structured Logging|r")
    print("✓ Multiple sinks (chat, buffer)")
    print("✓ Contextual logging")
    print("✓ Template-based messages")
    print("✓ Level filtering")
    print("")
    
    if Addon.Logger then
        local log = Addon.Logger:ForContext("Demo", "Showcase")
        log:Info("Demo log entry from {Source}", { Source = "Showcase" })
        print("✓ Demo log entry created")
    end
    print("")
    
    -- ===========================
    -- 5. Task Scheduling & Timing
    -- ===========================
    print("|cffffff00[5] Task Scheduling & Timing|r")
    print("✓ Async operations with After/Every")
    print("✓ Debounce/Throttle for rate limiting")
    print("✓ Coalescing for batch operations")
    print("✓ Namespace cleanup")
    print("")
    
    if Addon.Scheduler then
        local scheduler = Addon.Scheduler
        print("Scheduler available:")
        print("  scheduler:After(delay, fn)")
        print("  scheduler:Every(interval, fn)")
        print("  scheduler:Debounce(key, window, fn)")
        print("  scheduler:Throttle(key, window, fn)")
    end
    print("")
    
    -- ===========================
    -- 6. Configuration Management
    -- ===========================
    print("|cffffff00[6] Configuration Management|r")
    print("✓ SavedVariables persistence")
    print("✓ Change notifications via EventBus")
    print("✓ Default value support")
    print("✓ Safe access with fallbacks")
    print("")
    
    if Addon.Config then
        local config = Addon.Config
        print("Config available:")
        print("  Current broadcast enabled:", config:Get("broadcastEnabled", false))
        print("  Current interval:", config:Get("broadcastInterval", 300), "seconds")
    end
    print("")
    
    -- ===========================
    -- 7. Business Logic Services
    -- ===========================
    print("|cffffff00[7] Business Logic Services|r")
    print("✓ Recruiter: Prospect capture & management")
    print("✓ InviteService: Broadcast rotation & invitations")
    print("✓ ProspectsManager: Data persistence")
    print("✓ Clean separation of concerns")
    print("")
    
    if Addon.Recruiter then
        local recruiter = Addon.Recruiter
        if recruiter.GetProspectStats then
            local stats = recruiter:GetProspectStats()
            print("Current prospect stats:")
            print("  Total prospects:", stats.total)
            print("  Average level:", math.floor(stats.avgLevel))
            if stats.topClasses and #stats.topClasses > 0 then
                print("  Top class:", stats.topClasses[1].class, "(" .. stats.topClasses[1].count .. ")")
            end
        end
    end
    print("")
    
    -- ===========================
    -- 8. Modern UI Architecture
    -- ===========================
    print("|cffffff00[8] Modern UI Architecture|r")
    print("✓ Modular page system")
    print("✓ Reactive updates via EventBus")
    print("✓ Theme support with background assets")
    print("✓ Component-based design")
    print("")
    
    if Addon.UI then
        print("UI system available:")
        print("  Main frame with tabbed interface")
        print("  Prospects, Blacklist, Settings pages")
        print("  Real-time status updates")
    end
    print("")
    
    -- ===========================
    -- Framework Summary
    -- ===========================
    print("|cff00ff00=== FRAMEWORK SUMMARY ===|r")
    print("This WoW addon demonstrates that Lua can be used as a")
    print("legitimate application runtime with enterprise patterns:")
    print("")
    print("• |cffff8800Dependency Injection|r - Autofac-style container")
    print("• |cffff8800LINQ Collections|r - C#-style data processing")
    print("• |cffff8800Event Architecture|r - Pub/Sub messaging")
    print("• |cffff8800Structured Logging|r - Multi-sink with contexts")
    print("• |cffff8800Task Scheduling|r - Async operations")
    print("• |cffff8800Configuration|r - Persistent settings")
    print("• |cffff8800Service Lifecycle|r - Start/Stop patterns")
    print("• |cffff8800Modular UI|r - Component architecture")
    print("")
    print("Lua isn't just a scripting language - it's a runtime! 🚀")
    print("")
    print("|cff00ff00=== END SHOWCASE ===|r")
end

-- Register to run after everything is loaded
local function RegisterShowcase()
    if Addon.EventBus and Addon.EventBus.Subscribe then
        Addon.EventBus:Subscribe("GuildRecruiter.Ready", function()
            C_Timer.After(2, ShowcaseFramework) -- Run after examples
        end)
    end
end

-- Auto-register
if Addon.EventBus then
    RegisterShowcase()
else
    -- Fallback
    local function checkEventBus()
        if Addon.EventBus then
            RegisterShowcase()
        else
            C_Timer.After(0.5, checkEventBus)
        end
    end
    checkEventBus()
end

-- Also expose for manual triggering
Addon.ShowcaseFramework = ShowcaseFramework

return ShowcaseFramework
