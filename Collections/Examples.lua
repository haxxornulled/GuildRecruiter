-- Collections/Examples.lua — Usage examples for the LINQ-style collections
local _, Addon = ...

-- This file demonstrates how to use the new collections
-- Remove or comment out if you don't want examples in production

local function RunExamples()
    local L = Addon.List
    local D = Addon.Dictionary
    local LINQ = Addon.LINQ
    
    print("|cff66ccff[GuildRecruiter][Collections]|r Running LINQ examples...")
    
    -- ===========================
    -- List Examples
    -- ===========================
    
    -- Create some sample prospect data
    local prospects = L.new({
        { name = "Thunderfury", level = 80, class = "WARRIOR", zone = "Stormwind" },
        { name = "Ashbringer", level = 75, class = "PALADIN", zone = "Stormwind" },
        { name = "Sulfuras", level = 85, class = "SHAMAN", zone = "Orgrimmar" },
        { name = "Benediction", level = 70, class = "PRIEST", zone = "Stormwind" },
        { name = "Thunderfury", level = 78, class = "ROGUE", zone = "Stormwind" }, -- Duplicate name
    })
    
    print("Original prospects count:", prospects:Count())
    
    -- Filter high-level prospects in Stormwind
    local stormwindElites = prospects
        :Where(function(p) return p.level >= 75 and p.zone == "Stormwind" end)
        :OrderByDescending(function(p) return p.level end)
    
    print("Stormwind elites (75+):")
    stormwindElites:ForEach(function(p) 
        print(string.format("  %s (%s, %d)", p.name, p.class, p.level))
    end)
    
    -- Group by class
    local byClass = prospects:GroupBy(function(p) return p.class end)
    print("\nProspects by class:")
    byClass:ForEach(function(group)
        print(string.format("  %s: %d prospects", group.Key, group.Count))
        group.Items:ForEach(function(p)
            print(string.format("    - %s (level %d)", p.name, p.level))
        end)
    end)
    
    -- Get unique names
    local uniqueNames = prospects
        :Select(function(p) return p.name end)
        :Distinct()
        :OrderBy()
    
    print("\nUnique prospect names:")
    uniqueNames:ForEach(function(name) print("  " .. name) end)
    
    -- Aggregations
    local avgLevel = prospects:Average(function(p) return p.level end)
    local maxLevel = prospects:Max(function(p) return p.level end)
    local minLevel = prospects:Min(function(p) return p.level end)
    
    print(string.format("\nLevel stats: Avg=%.1f, Min=%d, Max=%d", avgLevel, minLevel, maxLevel))
    
    -- Take/Skip examples
    local topThree = prospects
        :OrderByDescending(function(p) return p.level end)
        :Take(3)
    
    print("\nTop 3 by level:")
    topThree:ForEach(function(p)
        print(string.format("  %s: %d", p.name, p.level))
    end)
    
    -- ===========================
    -- Dictionary Examples  
    -- ===========================
    
    -- Create a lookup by name
    local prospectLookup = D.empty()
    prospects:ForEach(function(p)
        if not prospectLookup:ContainsKey(p.name) then
            prospectLookup:Add(p.name, L.empty())
        end
        prospectLookup:Get(p.name):Add(p)
    end)
    
    print("\nProspect lookup created with", prospectLookup:Count(), "unique names")
    
    -- Find all prospects named "Thunderfury"
    local thunderfuries = prospectLookup:Get("Thunderfury")
    if thunderfuries then
        print("All Thunderfury prospects:")
        thunderfuries:ForEach(function(p)
            print(string.format("  %s (%s)", p.class, p.zone))
        end)
    end
    
    -- Dictionary LINQ operations
    local classStats = D.empty()
    byClass:ForEach(function(group)
        classStats:Add(group.Key, {
            count = group.Count,
            avgLevel = group.Items:Average(function(p) return p.level end),
            maxLevel = group.Items:Max(function(p) return p.level end)
        })
    end)
    
    print("\nClass statistics:")
    classStats:ForEach(function(class, stats)
        print(string.format("  %s: %d prospects, avg level %.1f, max %d", 
            class, stats.count, stats.avgLevel, stats.maxLevel))
    end)
    
    -- ===========================
    -- Extension Examples (for raw tables)
    -- ===========================
    
    -- Convert existing WoW addon data
    local rawProspectData = {
        { name = "Player1", level = 80, class = "MAGE" },
        { name = "Player2", level = 75, class = "WARRIOR" },
        { name = "Player3", level = 85, class = "MAGE" }
    }
    
    -- Use LINQ extensions on raw table
    local mages = LINQ.Where(rawProspectData, function(p) return p.class == "MAGE" end)
    local mageNames = LINQ.Select(mages, function(p) return p.name end)
    
    print("\nMages from raw data:", table.concat(mageNames, ", "))
    
    -- Convert to proper List for more operations
    local properList = LINQ.ToList(rawProspectData)
    local highLevelMages = properList
        :Where(function(p) return p.class == "MAGE" and p.level >= 80 end)
        :Select(function(p) return p.name end)
    
    print("High-level mages:", table.concat(highLevelMages:ToArray(), ", "))
    
    -- ===========================
    -- Real WoW Integration Examples
    -- ===========================
    
    -- Example: Process guild roster
    if IsInGuild and IsInGuild() then
        local guildMembers = L.empty()
        local numMembers = GetNumGuildMembers()
        
        for i = 1, math.min(numMembers, 10) do -- Limit for example
            local name, rank, _, level, class = GetGuildRosterInfo(i)
            if name then
                guildMembers:Add({
                    name = name,
                    rank = rank,
                    level = level or 1,
                    class = class or "UNKNOWN"
                })
            end
        end
        
        if not guildMembers:IsEmpty() then
            print("\nGuild analysis (first 10 members):")
            
            -- Officers and high ranks
            local officers = guildMembers
                :Where(function(m) return m.rank and (m.rank:find("Officer") or m.rank:find("Leader")) end)
            
            print("Officers found:", officers:Count())
            
            -- Level distribution
            local levelGroups = guildMembers
                :GroupBy(function(m) 
                    local level = m.level
                    if level >= 80 then return "80+"
                    elseif level >= 70 then return "70-79"
                    elseif level >= 60 then return "60-69"
                    else return "<60"
                    end
                end)
            
            print("Level distribution:")
            levelGroups:ForEach(function(group)
                print(string.format("  %s: %d members", group.Key, group.Count))
            end)
        end
    end
    
    print("|cff66ccff[GuildRecruiter][Collections]|r Examples completed!")
end

-- Register with the addon to run examples
local function RegisterExamples()
    if Addon.EventBus and Addon.EventBus.Subscribe then
        Addon.EventBus:Subscribe("GuildRecruiter.Ready", function()
            C_Timer.After(1, RunExamples) -- Run after everything is loaded
        end)
    end
end

-- Auto-register if EventBus is available
if Addon.EventBus then
    RegisterExamples()
else
    -- Fallback: register when EventBus becomes available
    local function checkEventBus()
        if Addon.EventBus then
            RegisterExamples()
        else
            C_Timer.After(0.5, checkEventBus)
        end
    end
    checkEventBus()
end

return RunExamples
