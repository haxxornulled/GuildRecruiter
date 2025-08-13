local Logger = {}

local function PrintFormatted(level, fmt, ...)
    local prefix = "|cff33ff99[Logger]|r "
    if not fmt or type(fmt) ~= "string" then
        print(prefix .. "[" .. level .. "] (no message)")
        return
    end

    local args = {...}
    local ok, msg = pcall(string.format, fmt, unpack(args))
    if not ok then
        print(prefix .. "[" .. level .. "] FORMAT ERROR: [" .. tostring(fmt) .. "] ARGS: " .. table.concat(args, ", "))
        msg = "(invalid format string or arguments)"
    end

    print(prefix .. "[" .. level .. "] " .. msg)
end

function Logger:Info(fmt, ...)
    PrintFormatted("INFO", fmt, ...)
end

function Logger:Warn(fmt, ...)
    PrintFormatted("WARN", fmt, ...)
end

function Logger:Error(fmt, ...)
    PrintFormatted("ERROR", fmt, ...)
end

function Logger.Init(core)
    return Logger
end

_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.Logger = Logger

return Logger
