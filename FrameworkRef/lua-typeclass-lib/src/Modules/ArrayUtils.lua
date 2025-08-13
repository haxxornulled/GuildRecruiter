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

-- ArrayUtils.lua
-- High-performance array utilities optimized for Lua tables used as arrays

local ArrayUtils = {}

-- Transform each element: ArrayUtils.map(arr, function(val, idx) return val * 2 end)
function ArrayUtils.map(tbl, fn)
    local out = {}
    for i = 1, #tbl do 
        out[i] = fn(tbl[i], i) 
    end
    return out
end

-- Filter elements: ArrayUtils.filter(arr, function(val, idx) return val > 5 end)
function ArrayUtils.filter(tbl, fn)
    local out, j = {}, 1
    for i = 1, #tbl do
        if fn(tbl[i], i) then 
            out[j] = tbl[i]
            j = j + 1 
        end
    end
    return out
end

-- Find first matching element: val, index = ArrayUtils.find(arr, value_or_function)
function ArrayUtils.find(tbl, valOrFn)
    for i = 1, #tbl do
        if type(valOrFn) == "function" then
            if valOrFn(tbl[i], i) then return tbl[i], i end
        else
            if tbl[i] == valOrFn then return tbl[i], i end
        end
    end
    return nil, nil
end

-- Get index of value: ArrayUtils.indexOf(arr, value)
function ArrayUtils.indexOf(tbl, val)
    for i = 1, #tbl do
        if tbl[i] == val then return i end
    end
    return nil
end

-- Append to end (O(1)): ArrayUtils.push(arr, value)
function ArrayUtils.push(tbl, val)
    tbl[#tbl + 1] = val
    return tbl
end

-- Remove from end (O(1)): value = ArrayUtils.pop(arr)
function ArrayUtils.pop(tbl)
    if #tbl == 0 then return nil end
    local val = tbl[#tbl]
    tbl[#tbl] = nil
    return val
end

-- Remove at index (O(n)): ArrayUtils.remove(arr, index)
function ArrayUtils.remove(tbl, idx)
    table.remove(tbl, idx)
    return tbl
end

-- Concatenate arrays: ArrayUtils.concat(arr1, arr2)
function ArrayUtils.concat(tbl1, tbl2)
    local out, n = {}, 1
    for i = 1, #tbl1 do 
        out[n] = tbl1[i]
        n = n + 1 
    end
    for i = 1, #tbl2 do 
        out[n] = tbl2[i]
        n = n + 1 
    end
    return out
end

-- Extract slice: ArrayUtils.slice(arr, first_index, last_index)
function ArrayUtils.slice(tbl, first, last)
    local out, n = {}, 1
    for i = first or 1, last or #tbl do 
        out[n] = tbl[i]
        n = n + 1 
    end
    return out
end

-- Iterate with side effects: ArrayUtils.foreach(arr, function(val, idx) print(val) end)
function ArrayUtils.foreach(tbl, fn)
    for i = 1, #tbl do 
        fn(tbl[i], i) 
    end
end

-- Shallow copy: ArrayUtils.copy(arr)
function ArrayUtils.copy(tbl)
    local out = {}
    for i = 1, #tbl do 
        out[i] = tbl[i] 
    end
    return out
end

-- Check if array contains value: ArrayUtils.contains(arr, value)
function ArrayUtils.contains(tbl, val)
    return ArrayUtils.indexOf(tbl, val) ~= nil
end

-- Reverse array in place: ArrayUtils.reverse(arr)
function ArrayUtils.reverse(tbl)
    local len = #tbl
    for i = 1, math.floor(len / 2) do
        tbl[i], tbl[len - i + 1] = tbl[len - i + 1], tbl[i]
    end
    return tbl
end

-- Get last element: ArrayUtils.last(arr)
function ArrayUtils.last(tbl)
    return tbl[#tbl]
end

-- Get first element: ArrayUtils.first(arr)
function ArrayUtils.first(tbl)
    return tbl[1]
end

-- Check if array is empty: ArrayUtils.isEmpty(arr)
function ArrayUtils.isEmpty(tbl)
    return #tbl == 0
end

Addon.provide("ArrayUtils", ArrayUtils)
