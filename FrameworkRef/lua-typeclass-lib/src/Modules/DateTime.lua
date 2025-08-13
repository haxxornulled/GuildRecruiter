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

-- DateTime.lua
-- WoW-compatible UTC DateTime utilities (safe for restricted environment)

local DateTime = {}

-- Returns a table in UTC (year, month, day, hour, min, sec)
-- Usage: local now = DateTime.UtcNow()
function DateTime.UtcNow()
    return date("!*t") -- WoW's date can do UTC with ! prefix
end

-- Returns a table in local time (server/realm time)
-- Usage: local now = DateTime.LocalNow()
function DateTime.LocalNow()
    return date("*t")
end

-- Returns seconds since epoch in UTC
-- Usage: local epoch = DateTime.UtcEpoch()
function DateTime.UtcEpoch()
    return time(date("!*t"))
end

-- Returns seconds since epoch in local time
-- Usage: local epoch = DateTime.LocalEpoch()
function DateTime.LocalEpoch()
    return time()
end

-- Format a UTC time as ISO 8601 string: "2025-08-01T17:44:03Z"
-- Usage: DateTime.FormatUTC(time_table_or_epoch)
function DateTime.FormatUTC(t)
    local tbl = type(t) == "table" and t or date("!*t", t)
    return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", 
        tbl.year, tbl.month, tbl.day, tbl.hour, tbl.min, tbl.sec)
end

-- Format a local time as readable string: "2025-08-01 17:44:03"
-- Usage: DateTime.FormatLocal(time_table_or_epoch)
function DateTime.FormatLocal(t)
    local tbl = type(t) == "table" and t or date("*t", t)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        tbl.year, tbl.month, tbl.day, tbl.hour, tbl.min, tbl.sec)
end

-- Format time for WoW chat/UI: "17:44:03" or "Aug 1, 17:44"
-- Usage: DateTime.FormatChat(time_table_or_epoch, include_date)
function DateTime.FormatChat(t, includeDate)
    local tbl = type(t) == "table" and t or date("*t", t)
    if includeDate then
        local months = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
        return string.format("%s %d, %02d:%02d", 
            months[tbl.month], tbl.day, tbl.hour, tbl.min)
    else
        return string.format("%02d:%02d:%02d", tbl.hour, tbl.min, tbl.sec)
    end
end

-- Get difference between two times in seconds
-- Usage: DateTime.DiffSeconds(newer_time, older_time)
function DateTime.DiffSeconds(t1, t2)
    local time1 = type(t1) == "table" and time(t1) or t1
    local time2 = type(t2) == "table" and time(t2) or t2
    return time1 - time2
end

-- Get difference in a human readable format
-- Usage: DateTime.DiffHuman(newer_time, older_time) -> "2 hours ago"
function DateTime.DiffHuman(t1, t2)
    local diff = DateTime.DiffSeconds(t1, t2)
    local absDiff = math.abs(diff)
    local suffix = diff >= 0 and "" or " ago"
    
    if absDiff < 60 then
        return math.floor(absDiff) .. " seconds" .. suffix
    elseif absDiff < 3600 then
        return math.floor(absDiff / 60) .. " minutes" .. suffix
    elseif absDiff < 86400 then
        return math.floor(absDiff / 3600) .. " hours" .. suffix
    else
        return math.floor(absDiff / 86400) .. " days" .. suffix
    end
end

-- Add seconds to a time
-- Usage: DateTime.AddSeconds(time_table_or_epoch, seconds_to_add)
function DateTime.AddSeconds(t, seconds)
    local epoch = type(t) == "table" and time(t) or t
    return date("*t", epoch + seconds)
end

-- Parse simple date strings (YYYY-MM-DD format)
-- Usage: DateTime.ParseDate("2025-08-01") -> time table
function DateTime.ParseDate(dateStr)
    local year, month, day = dateStr:match("(%d+)%-(%d+)%-(%d+)")
    if year and month and day then
        return {
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = 0,
            min = 0,
            sec = 0
        }
    end
    return nil
end

-- Check if a year is a leap year
-- Usage: DateTime.IsLeapYear(2024) -> true
function DateTime.IsLeapYear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
end

-- Get days in a month
-- Usage: DateTime.DaysInMonth(2, 2024) -> 29
function DateTime.DaysInMonth(month, year)
    local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if month == 2 and DateTime.IsLeapYear(year) then
        return 29
    end
    return days[month] or 0
end

Addon.provide("DateTime", DateTime)
