-- Collections/Dictionary.lua — Key-value collections with LINQ-style methods
local _, Addon = ...

local Dictionary = {}
Dictionary.__index = Dictionary

-- Constructor
function Dictionary.new(items)
    local instance = setmetatable({
        _items = {},
        _keys = {},
        _count = 0
    }, Dictionary)
    
    if items and type(items) == "table" then
        for k, v in pairs(items) do
            instance:Add(k, v)
        end
    end
    
    return instance
end

-- Factory methods
function Dictionary.from(items)
    return Dictionary.new(items)
end

function Dictionary.empty()
    return Dictionary.new()
end

-- Core properties
function Dictionary:Count()
    return self._count
end

function Dictionary:IsEmpty()
    return self._count == 0
end

function Dictionary:Keys()
    local result = {}
    for i = 1, #self._keys do
        result[i] = self._keys[i]
    end
    return Addon.List.new(result)
end

function Dictionary:Values()
    local result = {}
    for i = 1, #self._keys do
        result[i] = self._items[self._keys[i]]
    end
    return Addon.List.new(result)
end

-- Access methods
function Dictionary:Get(key)
    return self._items[key]
end

function Dictionary:Set(key, value)
    if self._items[key] == nil then
        self._keys[#self._keys + 1] = key
        self._count = self._count + 1
    end
    self._items[key] = value
    return self
end

function Dictionary:Add(key, value)
    if self._items[key] ~= nil then
        error("Key already exists: " .. tostring(key))
    end
    return self:Set(key, value)
end

function Dictionary:TryAdd(key, value)
    if self._items[key] ~= nil then
        return false
    end
    self:Set(key, value)
    return true
end

function Dictionary:ContainsKey(key)
    return self._items[key] ~= nil
end

function Dictionary:ContainsValue(value, comparer)
    for _, v in pairs(self._items) do
        if comparer then
            if comparer(v, value) then return true end
        else
            if v == value then return true end
        end
    end
    return false
end

function Dictionary:Remove(key)
    if self._items[key] == nil then
        return false
    end
    
    self._items[key] = nil
    self._count = self._count - 1
    
    -- Remove from keys array
    for i = 1, #self._keys do
        if self._keys[i] == key then
            table.remove(self._keys, i)
            break
        end
    end
    
    return true
end

function Dictionary:Clear()
    self._items = {}
    self._keys = {}
    self._count = 0
    return self
end

-- LINQ-style methods
function Dictionary:Where(predicate)
    local result = Dictionary.empty()
    for key, value in pairs(self._items) do
        if predicate(key, value) then
            result:Add(key, value)
        end
    end
    return result
end

function Dictionary:Select(selector)
    local result = Addon.List.empty()
    for key, value in pairs(self._items) do
        result:Add(selector(key, value))
    end
    return result
end

function Dictionary:SelectKeys(selector)
    local result = Addon.List.empty()
    for key, value in pairs(self._items) do
        result:Add(selector(key))
    end
    return result
end

function Dictionary:SelectValues(selector)
    local result = Addon.List.empty()
    for key, value in pairs(self._items) do
        result:Add(selector(value))
    end
    return result
end

function Dictionary:OrderBy(keySelector)
    local pairs_list = self:Select(function(k, v) 
        local sortKey = keySelector and keySelector(k, v) or k
        return { Key = k, Value = v, SortKey = sortKey }
    end)
    
    local sorted = pairs_list:OrderBy(function(pair) return pair.SortKey end)
    
    local result = Dictionary.empty()
    sorted:ForEach(function(pair)
        result:Add(pair.Key, pair.Value)
    end)
    
    return result
end

function Dictionary:OrderByDescending(keySelector)
    local pairs_list = self:Select(function(k, v) 
        local sortKey = keySelector and keySelector(k, v) or k
        return { Key = k, Value = v, SortKey = sortKey }
    end)
    
    local sorted = pairs_list:OrderByDescending(function(pair) return pair.SortKey end)
    
    local result = Dictionary.empty()
    sorted:ForEach(function(pair)
        result:Add(pair.Key, pair.Value)
    end)
    
    return result
end

function Dictionary:GroupBy(keySelector)
    local groups = Dictionary.empty()
    
    for key, value in pairs(self._items) do
        local groupKey = keySelector(key, value)
        if not groups:ContainsKey(groupKey) then
            groups:Add(groupKey, Addon.List.empty())
        end
        groups:Get(groupKey):Add({ Key = key, Value = value })
    end
    
    return groups:Select(function(groupKey, items)
        return {
            Key = groupKey,
            Items = items,
            Count = items:Count()
        }
    end)
end

-- Aggregation methods
function Dictionary:Any(predicate)
    if not predicate then
        return self._count > 0
    end
    
    for key, value in pairs(self._items) do
        if predicate(key, value) then
            return true
        end
    end
    return false
end

function Dictionary:All(predicate)
    for key, value in pairs(self._items) do
        if not predicate(key, value) then
            return false
        end
    end
    return true
end

function Dictionary:First(predicate)
    for key, value in pairs(self._items) do
        if not predicate or predicate(key, value) then
            return { Key = key, Value = value }
        end
    end
    error("No matching element found")
end

function Dictionary:FirstOrDefault(predicate, defaultValue)
    for key, value in pairs(self._items) do
        if not predicate or predicate(key, value) then
            return { Key = key, Value = value }
        end
    end
    return defaultValue
end

-- Conversion methods
function Dictionary:ToArray()
    local result = {}
    for i = 1, #self._keys do
        local key = self._keys[i]
        result[i] = { Key = key, Value = self._items[key] }
    end
    return result
end

function Dictionary:ToTable()
    local result = {}
    for key, value in pairs(self._items) do
        result[key] = value
    end
    return result
end

-- Iteration support
function Dictionary:ForEach(action)
    for key, value in pairs(self._items) do
        action(key, value)
    end
    return self
end

function Dictionary:__pairs()
    return pairs(self._items)
end

-- Array-style access
function Dictionary:__index(key)
    -- Check if it's a method first
    local method = rawget(Dictionary, key)
    if method then return method end
    
    -- Otherwise treat as dictionary access
    return self._items[key]
end

function Dictionary:__newindex(key, value)
    if value == nil then
        self:Remove(key)
    else
        self:Set(key, value)
    end
end

-- Convert to string for debugging
function Dictionary:__tostring()
    local items = {}
    local count = 0
    for key, value in pairs(self._items) do
        count = count + 1
        if count > 5 then break end -- Limit for readability
        
        local keyStr = type(key) == "string" and '"' .. key .. '"' or tostring(key)
        local valueStr = type(value) == "string" and '"' .. value .. '"' or tostring(value)
        items[count] = keyStr .. ": " .. valueStr
    end
    
    local result = "Dictionary{" .. table.concat(items, ", ")
    if self._count > 5 then
        result = result .. ", ... (" .. (self._count - 5) .. " more)"
    end
    result = result .. "}"
    
    return result
end

-- Export for DI container
Addon.provide("Dictionary", Dictionary, { lifetime = "SingleInstance" })
Addon.Dictionary = Dictionary

return Dictionary
