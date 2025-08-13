-- Modules/ExampleUtilities.lua
local ADDON_NAME = "TaintedSin"
local Addon = _G[ADDON_NAME]

local ArrayUtils = Addon.require("ArrayUtils")
local DateTime = Addon.require("DateTime")
local Core = Addon.require("Core")

-- Example service that demonstrates utility usage
local ExampleUtilitiesClass = {
    init = function(self)
        self.data = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
        self.startTime = DateTime.UtcEpoch()
    end,
    
    DemonstrateArrays = function(self)
        print("|cff33ff99[ExampleUtilities]:|r Array Operations Demo")
        
        -- Map: square all numbers
        local squares = ArrayUtils.map(self.data, function(x) return x * x end)
        print("Squares: " .. table.concat(squares, ", "))
        
        -- Filter: only even numbers
        local evens = ArrayUtils.filter(self.data, function(x) return x % 2 == 0 end)
        print("Evens: " .. table.concat(evens, ", "))
        
        -- Find: first number > 5
        local found, index = ArrayUtils.find(self.data, function(x) return x > 5 end)
        print("First > 5: " .. tostring(found) .. " at index " .. tostring(index))
        
        -- Array manipulation
        local arr = ArrayUtils.copy(self.data)
        ArrayUtils.push(arr, 99)
        local popped = ArrayUtils.pop(arr)
        print("Pushed 99, then popped: " .. tostring(popped))
        
        -- Slice and concat
        local slice1 = ArrayUtils.slice(self.data, 1, 3)  -- {1,2,3}
        local slice2 = ArrayUtils.slice(self.data, 8, 10) -- {8,9,10}
        local combined = ArrayUtils.concat(slice1, slice2)
        print("Combined slices: " .. table.concat(combined, ", "))
    end,
    
    DemonstrateDateTime = function(self)
        print("|cff33ff99[ExampleUtilities]:|r DateTime Operations Demo")
        
        -- Current times
        local utcNow = DateTime.UtcNow()
        local localNow = DateTime.LocalNow()
        
        print("UTC Now: " .. DateTime.FormatUTC(utcNow))
        print("Local Now: " .. DateTime.FormatLocal(localNow))
        print("Chat Format: " .. DateTime.FormatChat(localNow, true))
        
        -- Time since service started
        local currentTime = DateTime.UtcEpoch()
        local uptime = DateTime.DiffHuman(currentTime, self.startTime)
        print("Service uptime: " .. uptime)
        
        -- Date calculations
        local futureTime = DateTime.AddSeconds(utcNow, 3600) -- +1 hour
        print("One hour from now: " .. DateTime.FormatUTC(futureTime))
        
        -- Leap year check
        local currentYear = utcNow.year
        print("Is " .. currentYear .. " a leap year? " .. tostring(DateTime.IsLeapYear(currentYear)))
    end,
    
    RunAllDemos = function(self)
        self:DemonstrateArrays()
        print("") -- blank line
        self:DemonstrateDateTime()
    end
}

-- Register the demo service
Core.Register("ExampleUtilitiesService", function() 
    return ExampleUtilitiesClass
end, { singleton = true })

Addon.provide("ExampleUtilitiesClass", ExampleUtilitiesClass)
