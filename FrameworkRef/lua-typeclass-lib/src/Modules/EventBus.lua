-- Modules/EventBus.lua
local ADDON_NAME = "TaintedSin" -- Change this ONCE per project!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

Addon._modules = Addon._modules or {}

if not Addon.provide then
    function Addon.provide(name, mod)
        if not name or not mod then
            error("Usage: Addon.provide(name, mod)")
        end
        Addon._modules[name] = mod
    end
end

if not Addon.require then
    function Addon.require(name)
        local m = Addon._modules[name]
        if not m then
            error("Module '"..tostring(name).."' not found. " ..
                "Did you forget to load the file in your .toc, or forget Addon.provide?")
        end
        return m
    end
end

-- EventBus.lua
-- Enterprise-ready event system for decoupled communication

local EventBus = {}
EventBus._listeners = {}
EventBus._stats = { emitted = 0, errors = 0 }

--------------------------------------------------------
-- Subscribe to an event (returns unsubscribe function)
-- Usage: local off = EventBus.On("MY_EVENT", function(arg) ... end)
--------------------------------------------------------
function EventBus.On(event, callback)
    assert(type(event) == "string", "Event name must be a string")
    assert(type(callback) == "function", "Callback must be a function")
    
    if not EventBus._listeners[event] then
        EventBus._listeners[event] = {}
    end
    
    table.insert(EventBus._listeners[event], callback)
    
    EventBus.SafeLog("DEBUG", "Subscribed to event '%s' (now %d listeners)", 
        event, #EventBus._listeners[event])
    
    -- Return an unsubscribe function
    return function()
        if EventBus._listeners[event] then
            for i, cb in ipairs(EventBus._listeners[event]) do
                if cb == callback then
                    table.remove(EventBus._listeners[event], i)
                    EventBus.SafeLog("DEBUG", "Unsubscribed from event '%s' (now %d listeners)", 
                        event, #EventBus._listeners[event])
                    break
                end
            end
        end
    end
end

--------------------------------------------------------
-- Subscribe once (auto-unsubscribe after first fire)
-- Usage: EventBus.Once("MY_EVENT", function(arg) ... end)
--------------------------------------------------------
function EventBus.Once(event, callback)
    local off
    off = EventBus.On(event, function(...)
        off() -- Unsubscribe immediately
        callback(...)
    end)
    return off
end

--------------------------------------------------------
-- Emit (fire) an event with error handling
-- Usage: EventBus.Emit("MY_EVENT", arg1, arg2, ...)
--------------------------------------------------------
function EventBus.Emit(event, ...)
    local listeners = EventBus._listeners[event]
    if not listeners or #listeners == 0 then
        EventBus.SafeLog("DEBUG", "Event '%s' emitted but no listeners", event)
        return 0
    end
    
    EventBus._stats.emitted = EventBus._stats.emitted + 1
    local successCount = 0
    
    -- Copy array for safe iteration (allows unsubscribe during emit)
    local copy = {}
    for i, cb in ipairs(listeners) do
        copy[i] = cb
    end
    
    for _, cb in ipairs(copy) do
        local ok, err = pcall(cb, ...)
        if ok then
            successCount = successCount + 1
        else
            EventBus._stats.errors = EventBus._stats.errors + 1
            EventBus.SafeLog("ERROR", "Event '%s' handler error: %s", event, tostring(err))
        end
    end
    
    EventBus.SafeLog("DEBUG", "Event '%s' fired to %d/%d listeners successfully", 
        event, successCount, #copy)
    
    return successCount
end

--------------------------------------------------------
-- Remove all listeners for an event
--------------------------------------------------------
function EventBus.Clear(event)
    if event then
        local count = EventBus._listeners[event] and #EventBus._listeners[event] or 0
        EventBus._listeners[event] = nil
        EventBus.SafeLog("DEBUG", "Cleared %d listeners for event '%s'", count, event)
    else
        -- Clear all events
        local totalCount = 0
        for _, listeners in pairs(EventBus._listeners) do
            totalCount = totalCount + #listeners
        end
        EventBus._listeners = {}
        EventBus.SafeLog("DEBUG", "Cleared all events (%d total listeners)", totalCount)
    end
end

--------------------------------------------------------
-- List current listeners for an event (debugging)
--------------------------------------------------------
function EventBus.Listeners(event)
    return EventBus._listeners[event] or {}
end

--------------------------------------------------------
-- Get all registered events
--------------------------------------------------------
function EventBus.Events()
    local events = {}
    for event, listeners in pairs(EventBus._listeners) do
        if #listeners > 0 then
            table.insert(events, event)
        end
    end
    return events
end

--------------------------------------------------------
-- Get EventBus statistics
--------------------------------------------------------
function EventBus.Stats()
    local eventCount = 0
    local listenerCount = 0
    
    for _, listeners in pairs(EventBus._listeners) do
        if #listeners > 0 then
            eventCount = eventCount + 1
            listenerCount = listenerCount + #listeners
        end
    end
    
    return {
        events = eventCount,
        listeners = listenerCount,
        emitted = EventBus._stats.emitted,
        errors = EventBus._stats.errors
    }
end

--------------------------------------------------------
-- Safe logging utility (works even if Logger not ready)
--------------------------------------------------------
function EventBus.SafeLog(level, message, ...)
    -- Try to use Logger if available, otherwise fallback to print
    local hasLogger, Logger = pcall(function() return Addon.require("Logger") end)
    
    if hasLogger and Logger then
        if level == "DEBUG" and Logger.Debug then
            Logger.Debug(message, ...)
        elseif level == "INFO" and Logger.Info then
            Logger.Info(message, ...)
        elseif level == "WARN" and Logger.Warn then
            Logger.Warn(message, ...)
        elseif level == "ERROR" and Logger.Error then
            Logger.Error(message, ...)
        end
    else
        -- Fallback to print (only show non-DEBUG in fallback)
        if level ~= "DEBUG" then
            print("[" .. ADDON_NAME .. "-" .. level .. "] " .. string.format(message, ...))
        end
    end
end

--------------------------------------------------------
-- Namespace pattern: support event namespaces like "ui.button.click"
--------------------------------------------------------
function EventBus.EmitNamespace(namespace, event, ...)
    local fullEvent = namespace .. "." .. event
    return EventBus.Emit(fullEvent, ...)
end

function EventBus.OnNamespace(namespace, event, callback)
    local fullEvent = namespace .. "." .. event
    return EventBus.On(fullEvent, callback)
end

Addon.provide("EventBus", EventBus)
