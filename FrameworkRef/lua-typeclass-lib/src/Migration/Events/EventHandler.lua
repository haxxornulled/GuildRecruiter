-- GuildRecruiter/EventHandler.lua
-- Modern, minimal pub/sub event bus for internal addon messaging

-- Ensure namespace exists
_G.GuildRecruiter = _G.GuildRecruiter or {}
local Logger = _G.GuildRecruiter.Logger

local EventHandler = {}
EventHandler._listeners = {}

--------------------------------------------------------
-- Subscribe to a custom event (returns unsubscribe fn)
-- Usage: local off = EventHandler.On("MY_EVENT", function(arg) ... end)
--------------------------------------------------------
function EventHandler.On(event, callback)
    assert(type(event) == "string", "Event name must be a string")
    assert(type(callback) == "function", "Callback must be a function")
    if not EventHandler._listeners[event] then
        EventHandler._listeners[event] = {}
    end
    table.insert(EventHandler._listeners[event], callback)
    -- Return an unsubscribe function for convenience
    return function()
        for i, cb in ipairs(EventHandler._listeners[event]) do
            if cb == callback then
                table.remove(EventHandler._listeners[event], i)
                break
            end
        end
    end
end

--------------------------------------------------------
-- Emit (fire) a custom event
-- Usage: EventHandler.Emit("MY_EVENT", arg1, arg2, ...)
--------------------------------------------------------
function EventHandler.Emit(event, ...)
    if Logger and Logger.Debug then
        Logger.Debug("[EventHandler] Emitting event: %s", tostring(event))
    end
    local listeners = EventHandler._listeners[event]
    if listeners then
        -- Copy so listeners can safely unsubscribe during emit
        local copy = { unpack(listeners) }
        for _, cb in ipairs(copy) do
            local ok, err = pcall(cb, ...)
            if not ok and Logger and Logger.Error then
                Logger.Error("[EventHandler] Event '%s' handler error: %s", tostring(event), tostring(err))
            end
        end
    end
end

--------------------------------------------------------
-- Optionally: remove all listeners for an event
--------------------------------------------------------
function EventHandler.Clear(event)
    EventHandler._listeners[event] = nil
end

--------------------------------------------------------
-- Optionally: list all current listeners (for debugging)
--------------------------------------------------------
function EventHandler.Listeners(event)
    return EventHandler._listeners[event] or {}
end

-- SafeLog utility (for modules that might load before logger)
function EventHandler.SafeLog(level, message, ...)
    if Logger then
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
        print("[GR-" .. level .. "] " .. string.format(message, ...))
    end
end

-- Register the EventHandler globally
_G.GuildRecruiter.EventHandler = EventHandler
return EventHandler
