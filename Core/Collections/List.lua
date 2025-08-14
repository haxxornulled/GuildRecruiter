-- Collections/List.lua — LINQ-style collections for Lua (because we miss C#)
local _, Addon = ...

local List = {}
List.__index = List

-- Constructor
function List.new(items)
    local instance = setmetatable({
        _items = {},
        _count = 0
    }, List)
    
    if items then
        if type(items) == "table" then
            -- Handle both array-style and pairs iteration
            if #items > 0 then
                -- Array-style table
                for i = 1, #items do
                    instance._items[i] = items[i]
                end
                instance._count = #items
            else
                -- pairs-style table, convert to array
                local idx = 1
                for _, v in pairs(items) do
                    instance._items[idx] = v
                    idx = idx + 1
                end
                instance._count = idx - 1
            end
        end
    end
    
    return instance
end

-- Factory methods
function List.from(items)
    return List.new(items)
end

function List.range(start, count)
    local items = {}
    for i = 1, count do
        items[i] = start + i - 1
    end
    return List.new(items)
end

function List.empty()
    return List.new()
end

-- Core properties
function List:Count()
    return self._count
end

function List:IsEmpty()
    return self._count == 0
end

-- Access methods
function List:Get(index)
    if index < 1 or index > self._count then return nil end
    return self._items[index]
end

function List:ToArray()
    local result = {}
    for i = 1, self._count do
        result[i] = self._items[i]
    end
    return result
end

-- LINQ-style methods (fluent interface)
function List:Where(predicate)
    local result = {}
    local count = 0
    for i = 1, self._count do
        local item = self._items[i]
        if predicate(item, i) then
            count = count + 1
            result[count] = item
        end
    end
    return List.new(result)
end

function List:Select(selector)
    local result = {}
    for i = 1, self._count do
        result[i] = selector(self._items[i], i)
    end
    return List.new(result)
end

function List:SelectMany(selector)
    local result = {}
    local count = 0
    for i = 1, self._count do
        local subItems = selector(self._items[i], i)
        if type(subItems) == "table" then
            for j = 1, #subItems do
                count = count + 1
                result[count] = subItems[j]
            end
        end
    end
    return List.new(result)
end

function List:OrderBy(keySelector)
    local items = self:ToArray()
    table.sort(items, function(a, b) 
        local keyA = keySelector and keySelector(a) or a
        local keyB = keySelector and keySelector(b) or b
        return keyA < keyB 
    end)
    return List.new(items)
end

function List:OrderByDescending(keySelector)
    local items = self:ToArray()
    table.sort(items, function(a, b)
        local keyA = keySelector and keySelector(a) or a
        local keyB = keySelector and keySelector(b) or b
        return keyA > keyB
    end)
    return List.new(items)
end

function List:GroupBy(keySelector)
    local groups = {}
    local groupOrder = {}
    
    for i = 1, self._count do
        local item = self._items[i]
        local key = keySelector(item, i)
        
        if not groups[key] then
            groups[key] = List.empty()
            groupOrder[#groupOrder + 1] = key
        end
        
        groups[key]:Add(item)
    end
    
    -- Return array of { Key, Items } objects
    local result = {}
    for i, key in ipairs(groupOrder) do
        result[i] = {
            Key = key,
            Items = groups[key],
            Count = groups[key]:Count()
        }
    end
    
    return List.new(result)
end

function List:Distinct(keySelector)
    local seen = {}
    local result = {}
    local count = 0
    
    for i = 1, self._count do
        local item = self._items[i]
        local key = keySelector and keySelector(item) or item
        
        if not seen[key] then
            seen[key] = true
            count = count + 1
            result[count] = item
        end
    end
    
    return List.new(result)
end

function List:Take(count)
    count = math.min(count, self._count)
    local result = {}
    for i = 1, count do
        result[i] = self._items[i]
    end
    return List.new(result)
end

function List:Skip(count)
    local result = {}
    local resultCount = 0
    for i = count + 1, self._count do
        resultCount = resultCount + 1
        result[resultCount] = self._items[i]
    end
    return List.new(result)
end

function List:TakeWhile(predicate)
    local result = {}
    local count = 0
    for i = 1, self._count do
        local item = self._items[i]
        if predicate(item, i) then
            count = count + 1
            result[count] = item
        else
            break
        end
    end
    return List.new(result)
end

function List:SkipWhile(predicate)
    local result = {}
    local resultCount = 0
    local skipping = true
    
    for i = 1, self._count do
        local item = self._items[i]
        if skipping and predicate(item, i) then
            -- Keep skipping
        else
            skipping = false
            resultCount = resultCount + 1
            result[resultCount] = item
        end
    end
    
    return List.new(result)
end

-- Aggregation methods
function List:First(predicate)
    for i = 1, self._count do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            return item
        end
    end
    error("No matching element found")
end

function List:FirstOrDefault(predicate, defaultValue)
    for i = 1, self._count do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            return item
        end
    end
    return defaultValue
end

function List:Last(predicate)
    for i = self._count, 1, -1 do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            return item
        end
    end
    error("No matching element found")
end

-- New convenience aggregation helpers -------------------------------------------------
function List:Any(predicate)
    if not predicate then return self._count > 0 end
    for i=1,self._count do if predicate(self._items[i], i) then return true end end
    return false
end

function List:All(predicate)
    if not predicate then return true end
    for i=1,self._count do if not predicate(self._items[i], i) then return false end end
    return true
end

function List:Sum(selector)
    local total = 0
    if selector then
        for i=1,self._count do total = total + (tonumber(selector(self._items[i], i)) or 0) end
    else
        for i=1,self._count do total = total + (tonumber(self._items[i]) or 0) end
    end
    return total
end

function List:Average(selector)
    if self._count == 0 then return 0 end
    return self:Sum(selector) / self._count
end

function List:LastOrDefault(predicate, defaultValue)
    for i = self._count, 1, -1 do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            return item
        end
    end
    return defaultValue
end

function List:Single(predicate)
    local found = false
    local result = nil
    
    for i = 1, self._count do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            if found then
                error("More than one matching element found")
            end
            found = true
            result = item
        end
    end
    
    if not found then
        error("No matching element found")
    end
    
    return result
end

function List:SingleOrDefault(predicate, defaultValue)
    local found = false
    local result = defaultValue
    
    for i = 1, self._count do
        local item = self._items[i]
        if not predicate or predicate(item, i) then
            if found then
                error("More than one matching element found")
            end
            found = true
            result = item
        end
    end
    
    return result
end

function List:Any(predicate)
    if not predicate then
        return self._count > 0
    end
    
    for i = 1, self._count do
        if predicate(self._items[i], i) then
            return true
        end
    end
    return false
end

function List:All(predicate)
    for i = 1, self._count do
        if not predicate(self._items[i], i) then
            return false
        end
    end
    return true
end

function List:Contains(item, comparer)
    for i = 1, self._count do
        local current = self._items[i]
        if comparer then
            if comparer(current, item) then return true end
        else
            if current == item then return true end
        end
    end
    return false
end

function List:IndexOf(item, comparer)
    for i = 1, self._count do
        local current = self._items[i]
        if comparer then
            if comparer(current, item) then return i end
        else
            if current == item then return i end
        end
    end
    return -1
end

-- Numeric aggregations
function List:Sum(selector)
    local total = 0
    for i = 1, self._count do
        local value = selector and selector(self._items[i]) or self._items[i]
        total = total + (tonumber(value) or 0)
    end
    return total
end

function List:Average(selector)
    if self._count == 0 then return 0 end
    return self:Sum(selector) / self._count
end

function List:Min(selector)
    if self._count == 0 then return nil end
    
    local min = selector and selector(self._items[1]) or self._items[1]
    for i = 2, self._count do
        local value = selector and selector(self._items[i]) or self._items[i]
        if value < min then min = value end
    end
    return min
end

function List:Max(selector)
    if self._count == 0 then return nil end
    
    local max = selector and selector(self._items[1]) or self._items[1]
    for i = 2, self._count do
        local value = selector and selector(self._items[i]) or self._items[i]
        if value > max then max = value end
    end
    return max
end

-- Mutation methods (modify original list)
function List:Add(item)
    self._count = self._count + 1
    self._items[self._count] = item
    return self -- For chaining
end

function List:AddRange(items)
    if items and type(items) == "table" then
        for i = 1, #items do
            self:Add(items[i])
        end
    end
    return self
end

function List:Insert(index, item)
    if index < 1 or index > self._count + 1 then
        error("Index out of range")
    end
    
    -- Shift items right
    for i = self._count, index, -1 do
        self._items[i + 1] = self._items[i]
    end
    
    self._items[index] = item
    self._count = self._count + 1
    return self
end

function List:Remove(item, comparer)
    local index = self:IndexOf(item, comparer)
    if index > 0 then
        return self:RemoveAt(index)
    end
    return false
end

function List:RemoveAt(index)
    if index < 1 or index > self._count then
        return false
    end
    
    -- Shift items left
    for i = index, self._count - 1 do
        self._items[i] = self._items[i + 1]
    end
    
    self._items[self._count] = nil
    self._count = self._count - 1
    return true
end

function List:Clear()
    self._items = {}
    self._count = 0
    return self
end

-- Iteration support
function List:ForEach(action)
    for i = 1, self._count do
        action(self._items[i], i)
    end
    return self
end

-- Make it work with Lua's for loop
function List:__pairs()
    local i = 0
    return function()
        i = i + 1
        if i <= self._count then
            return i, self._items[i]
        end
    end
end

-- Make it work with ipairs
function List:__ipairs()
    return self:__pairs()
end

-- Convert to string for debugging
function List:__tostring()
    local items = {}
    for i = 1, math.min(self._count, 10) do -- Limit to first 10 for readability
        local item = self._items[i]
        if type(item) == "string" then
            items[i] = '"' .. item .. '"'
        else
            items[i] = tostring(item)
        end
    end
    
    local result = "List[" .. table.concat(items, ", ")
    if self._count > 10 then
        result = result .. ", ... (" .. (self._count - 10) .. " more)"
    end
    result = result .. "]"
    
    return result
end

-- Export for DI container
-- Primary registration (simple key)
if Addon.safeProvide then
    Addon.safeProvide("List", List, { lifetime = "SingleInstance" })
    Addon.safeProvide("Collections.List", List, { lifetime = "SingleInstance" })
elseif Addon.provide then
    if not (Addon.IsProvided and Addon.IsProvided("List")) then Addon.provide("List", List, { lifetime = "SingleInstance" }) end
    if not (Addon.IsProvided and Addon.IsProvided("Collections.List")) then Addon.provide("Collections.List", List, { lifetime = "SingleInstance" }) end
end
Addon.List = List

return List
