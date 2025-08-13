local EventBus = {}

local callbacks = {}

function EventBus.On(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end

function EventBus.Emit(event, ...)
    local cbs = callbacks[event]
    if not cbs then return end
    for _, fn in ipairs(cbs) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print("[EventBus] Error in callback for event '"..event.."': "..tostring(err))
        end
    end
end

function EventBus.Off(event, fn)
    if not callbacks[event] then return end
    for i, f in ipairs(callbacks[event]) do
        if f == fn then
            table.remove(callbacks[event], i)
            break
        end
    end
end

_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.EventBus = EventBus
return EventBus
