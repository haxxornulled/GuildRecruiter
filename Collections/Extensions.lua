-- Collections/Extensions.lua — Extension methods for native Lua tables
local _, Addon = ...

-- Global extension functions for tables (like C# extension methods)
local Extensions = {}

-- Convert any table to List
function Extensions.ToList(tbl)
    return Addon.List.new(tbl)
end

-- Convert any table to Dictionary
function Extensions.ToDictionary(tbl, keySelector, valueSelector)
    local dict = Addon.Dictionary.empty()
    
    if keySelector then
        -- Array-style table with key/value selectors
        for i, item in ipairs(tbl) do
            local key = keySelector(item, i)
            local value = valueSelector and valueSelector(item, i) or item
            dict:Add(key, value)
        end
    else
        -- Direct key-value table
        for k, v in pairs(tbl) do
            dict:Add(k, v)
        end
    end
    
    return dict
end

-- LINQ-style Where for raw tables
function Extensions.Where(tbl, predicate)
    local result = {}
    local count = 0
    
    if #tbl > 0 then
        -- Array-style table
        for i = 1, #tbl do
            if predicate(tbl[i], i) then
                count = count + 1
                result[count] = tbl[i]
            end
        end
    else
        -- pairs-style table
        for k, v in pairs(tbl) do
            if predicate(v, k) then
                count = count + 1
                result[count] = v
            end
        end
    end
    
    return result
end

-- LINQ-style Select for raw tables
function Extensions.Select(tbl, selector)
    local result = {}
    
    if #tbl > 0 then
        -- Array-style table
        for i = 1, #tbl do
            result[i] = selector(tbl[i], i)
        end
    else
        -- pairs-style table
        local count = 0
        for k, v in pairs(tbl) do
            count = count + 1
            result[count] = selector(v, k)
        end
    end
    
    return result
end

-- FirstOrDefault for raw tables
function Extensions.FirstOrDefault(tbl, predicate, defaultValue)
    if #tbl > 0 then
        -- Array-style table
        for i = 1, #tbl do
            if not predicate or predicate(tbl[i], i) then
                return tbl[i]
            end
        end
    else
        -- pairs-style table
        for k, v in pairs(tbl) do
            if not predicate or predicate(v, k) then
                return v
            end
        end
    end
    return defaultValue
end

-- Any for raw tables
function Extensions.Any(tbl, predicate)
    if not predicate then
        return next(tbl) ~= nil
    end
    
    if #tbl > 0 then
        -- Array-style table
        for i = 1, #tbl do
            if predicate(tbl[i], i) then
                return true
            end
        end
    else
        -- pairs-style table
        for k, v in pairs(tbl) do
            if predicate(v, k) then
                return true
            end
        end
    end
    return false
end

-- Count for raw tables (with optional predicate)
function Extensions.Count(tbl, predicate)
    if not predicate then
        return #tbl > 0 and #tbl or (function()
            local count = 0
            for _ in pairs(tbl) do count = count + 1 end
            return count
        end)()
    end
    
    local count = 0
    if #tbl > 0 then
        -- Array-style table
        for i = 1, #tbl do
            if predicate(tbl[i], i) then
                count = count + 1
            end
        end
    else
        -- pairs-style table
        for k, v in pairs(tbl) do
            if predicate(v, k) then
                count = count + 1
            end
        end
    end
    return count
end

-- GroupBy for raw tables
function Extensions.GroupBy(tbl, keySelector)
    local groups = {}
    local groupOrder = {}
    
    local items = #tbl > 0 and tbl or (function()
        local arr = {}
        for k, v in pairs(tbl) do arr[#arr + 1] = { key = k, value = v } end
        return arr
    end)()
    
    for i, item in ipairs(items) do
        local groupKey = keySelector(item, i)
        
        if not groups[groupKey] then
            groups[groupKey] = {}
            groupOrder[#groupOrder + 1] = groupKey
        end
        
        groups[groupKey][#groups[groupKey] + 1] = item
    end
    
    local result = {}
    for i, key in ipairs(groupOrder) do
        result[i] = {
            Key = key,
            Items = groups[key],
            Count = #groups[key]
        }
    end
    
    return result
end

-- Monkey-patch metatable support for tables (optional - can be dangerous!)
local function EnableTableExtensions()
    local originalMT = getmetatable({}) or {}
    
    function originalMT.__index(tbl, key)
        -- Check if it's one of our extension methods
        if Extensions[key] then
            return function(self, ...)
                return Extensions[key](self, ...)
            end
        end
        return rawget(tbl, key)
    end
    
    -- Apply to all tables (WARNING: This is global!)
    debug.setmetatable({}, originalMT)
end

-- Safer approach: explicit extension function
function Extensions.Extend(tbl)
    local mt = getmetatable(tbl) or {}
    
    local function createMethod(methodName)
        return function(self, ...)
            return Extensions[methodName](self, ...)
        end
    end
    
    -- Add extension methods to this specific table
    for methodName, _ in pairs(Extensions) do
        if methodName ~= "Extend" and methodName ~= "EnableGlobal" then
            tbl[methodName] = createMethod(methodName)
        end
    end
    
    return tbl
end

-- Global enable function (use with caution!)
Extensions.EnableGlobal = EnableTableExtensions

-- Export for DI container
Addon.provide("TableExtensions", Extensions, { lifetime = "SingleInstance" })
Addon.TableExtensions = Extensions

-- Convenience global access (like C# using statements)
Addon.LINQ = Extensions

return Extensions
