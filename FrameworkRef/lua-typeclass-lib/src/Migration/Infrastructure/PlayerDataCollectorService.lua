-- Infrastructure/PlayerDataCollectorService.lua
-- FIXED: Proper guild roster data collection with better error handling

local PlayerDataCollectorService = {}

-- Cache for reducing API calls
local cache = {
    guildRoster = {data = nil, lastUpdate = 0, ttl = 30}, -- 30 second cache
    groupRoster = {data = nil, lastUpdate = 0, ttl = 10}, -- 10 second cache
}

-- Debug logging helper
local function DebugLog(msg, ...)
    if msg then
        print("|cff33ff99[PlayerDataCollector]|r " .. string.format(msg, ...))
    else
        print("|cff33ff99[PlayerDataCollector]|r (no message)")
    end
end

-- Standardized player data structure
local function CreatePlayerRecord(data)
    return {
        -- Core identity
        name = data.name or "Unknown",
        fullName = data.fullName or data.name or "Unknown", -- With server name
        guid = data.guid,
        
        -- Character info
        level = tonumber(data.level) or 0,
        class = data.class or "Unknown",
        classDisplayName = data.classDisplayName or data.class or "Unknown",
        race = data.race,
        
        -- Status
        online = data.online or false,
        status = data.status or 0, -- AFK, DND, etc.
        isMobile = data.isMobile or false,
        zone = data.zone or "",
        
        -- Guild specific
        rank = data.rank,
        rankIndex = data.rankIndex,
        note = data.note or "",
        officerNote = data.officerNote or "",
        lastOnline = data.lastOnline,
        
        -- Group specific  
        subgroup = data.subgroup,
        role = data.role, -- tank/healer/dps
        isDead = data.isDead or false,
        isML = data.isML or false,
        
        -- Metadata
        source = data.source or "unknown", -- "guild", "group", "who"
        timestamp = GetTime(),
        
        -- Scoring data (for recruitment)
        ilvl = data.ilvl,
        achievementPoints = data.achievementPoints,
        score = data.score, -- Calculated by RecruitScoring
    }
end

-- Helper function to calculate total hours from GetGuildRosterLastOnline
local function CalculateLastOnlineHours(years, months, days, hours)
    if not years and not months and not days and not hours then
        return nil -- Player is online or no data
    end
    
    years = years or 0
    months = months or 0
    days = days or 0
    hours = hours or 0
    
    -- Convert everything to hours (approximate)
    local totalHours = hours + (days * 24) + (months * 30.5 * 24) + (years * 365.25 * 24)
    return math.floor(totalHours)
end

-- Cache management
local function IsCacheValid(cacheEntry)
    return cacheEntry.data and (GetTime() - cacheEntry.lastUpdate) < cacheEntry.ttl
end

local function UpdateCache(cacheKey, data)
    cache[cacheKey].data = data
    cache[cacheKey].lastUpdate = GetTime()
end

local function ClearCache(cacheKey)
    if cacheKey then
        cache[cacheKey].data = nil
        cache[cacheKey].lastUpdate = 0
    else
        -- Clear all caches
        for key in pairs(cache) do
            cache[key].data = nil
            cache[key].lastUpdate = 0
        end
    end
end

-- FIXED: Direct API access without WoWApiAdapter dependency
function PlayerDataCollectorService:CollectGuildRoster(forceRefresh)
    DebugLog("CollectGuildRoster called (forceRefresh: %s)", tostring(forceRefresh))
    
    if not forceRefresh and IsCacheValid(cache.guildRoster) then
        DebugLog("Using cached guild roster data (%d members)", #cache.guildRoster.data)
        return cache.guildRoster.data
    end
    
    -- Check if player is in a guild using direct API
    if not IsInGuild() then
        DebugLog("Player is not in a guild")
        return {}
    end

    local guildName = GetGuildInfo("player") or "Unknown"
    DebugLog("Player is in guild: %s", guildName)

    -- Force refresh guild roster from server
    if forceRefresh then
        DebugLog("Forcing guild roster refresh...")
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
        -- Small delay to let the roster update
        C_Timer.After(0.5, function()
            -- Recursive call without forceRefresh to get the updated data
            PlayerDataCollectorService:CollectGuildRoster(false)
        end)
        return cache.guildRoster.data or {}
    end

    local numMembers = GetNumGuildMembers()
    DebugLog("GetNumGuildMembers() returned: %s", tostring(numMembers))

    if not numMembers or numMembers == 0 then
        DebugLog("No guild members returned by API - trying roster refresh")
        -- Try to refresh roster data
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
        
        -- Wait a moment and try again
        C_Timer.After(1, function()
            local retryNum = GetNumGuildMembers()
            DebugLog("Retry GetNumGuildMembers() returned: %s", tostring(retryNum))
            if retryNum and retryNum > 0 then
                PlayerDataCollectorService:CollectGuildRoster(false)
            end
        end)
        return {}
    end

    DebugLog("Collecting guild roster data for %d members", numMembers)

    local results = {}

    for i = 1, numMembers do
        -- Get basic roster info using direct API
        local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online, status, class, achievementPoints, achievementRank, isMobile, canSoR, repStanding, guid = GetGuildRosterInfo(i)

        if name then
            -- Debug: Print roster info for first few members
            if i <= 3 then
                DebugLog("Member %d: %s (Level: %s, Class: %s, Online: %s)", 
                    i, name, tostring(level), tostring(class), tostring(online))
            end

            -- Get lastOnline data using separate API call
            local lastOnlineHours = nil
            if not online and GetGuildRosterLastOnline then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                lastOnlineHours = CalculateLastOnlineHours(years, months, days, hours)

                -- Debug lastOnline for first few members
                if i <= 3 then
                    DebugLog("  LastOnline: y=%s, m=%s, d=%s, h=%s -> %s hours", 
                        tostring(years), tostring(months), tostring(days), tostring(hours), tostring(lastOnlineHours))
                end
            end

            -- Clean the name (remove server suffix for display)
            local cleanName = name
            local fullName = name
            
            -- Use Ambiguate if available (retail)
            if Ambiguate then
                cleanName = Ambiguate(name, "short")
                fullName = Ambiguate(name, "all")
            else
                -- Fallback for classic - manually strip server name
                if name:find("-") then
                    cleanName = name:match("^([^-]+)")
                end
            end

            local playerData = CreatePlayerRecord({
                name = cleanName,
                fullName = fullName,
                guid = guid,
                level = level,
                class = class,
                classDisplayName = classDisplayName,
                rank = rank,
                rankIndex = rankIndex,
                zone = zone,
                note = note,
                officerNote = officerNote,
                online = online,
                status = status,
                isMobile = isMobile,
                lastOnline = lastOnlineHours,
                achievementPoints = achievementPoints,
                source = "guild"
            })

            table.insert(results, playerData)
        else
            if i <= 5 then -- Debug first few empty results
                DebugLog("GetGuildRosterInfo(%d) returned nil name", i)
            end
        end
    end
    
    DebugLog("Successfully collected %d guild members", #results)
    
    -- Sort by rank index (officers first), then by name
    table.sort(results, function(a, b)
        if a.rankIndex ~= b.rankIndex then
            return (a.rankIndex or 99) < (b.rankIndex or 99)
        end
        return (a.name or "") < (b.name or "")
    end)
    
    UpdateCache("guildRoster", results)
    DebugLog("Guild roster collection complete: %d members cached", #results)
    
    return results
end

-- Enhanced group roster collection
function PlayerDataCollectorService:CollectGroupRoster(forceRefresh)
    if not forceRefresh and IsCacheValid(cache.groupRoster) then
        return cache.groupRoster.data
    end
    
    if not IsInGroup() and not IsInRaid() then
        DebugLog("Player is not in a group or raid")
        return {}
    end
    
    local results = {}
    
    -- Get group/raid members
    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
            if name then
                local cleanName = name
                local fullName = name
                if Ambiguate then
                    cleanName = Ambiguate(name, "short")
                    fullName = Ambiguate(name, "all")
                end
                
                local playerData = CreatePlayerRecord({
                    name = cleanName,
                    fullName = fullName,
                    level = level,
                    class = class,
                    classDisplayName = class, -- Raid API doesn't provide display name
                    zone = zone,
                    online = online,
                    subgroup = subgroup,
                    role = role,
                    isDead = isDead,
                    isML = isML,
                    rank = rank, -- Raid rank, not guild rank
                    source = "raid"
                })
                table.insert(results, playerData)
            end
        end
    elseif IsInGroup() then
        -- Party members (1-4, excluding player)
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local classLocale, class = UnitClass(unit)
                local level = UnitLevel(unit)
                local zone = GetRealZoneText() -- Same zone as player for party
                local online = UnitIsConnected(unit)
                
                if name then
                    local playerData = CreatePlayerRecord({
                        name = name,
                        fullName = name,
                        level = level,
                        class = class,
                        classDisplayName = classLocale,
                        zone = zone,
                        online = online,
                        isDead = UnitIsDeadOrGhost(unit),
                        role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
                        source = "party"
                    })
                    table.insert(results, playerData)
                end
            end
        end
        
        -- Add self to party data
        local name = UnitName("player")
        local classLocale, class = UnitClass("player")
        local level = UnitLevel("player")
        local zone = GetRealZoneText()
        
        local selfData = CreatePlayerRecord({
            name = name,
            fullName = name,
            level = level,
            class = class,
            classDisplayName = classLocale,
            zone = zone,
            online = true,
            isDead = UnitIsDeadOrGhost("player"),
            role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") or nil,
            source = "party"
        })
        table.insert(results, selfData)
    end
    
    UpdateCache("groupRoster", results)
    DebugLog("Group roster collection complete: %d members", #results)
    
    return results
end

-- Enhanced query system with better filtering
function PlayerDataCollectorService:QueryMembers(params)
    params = params or {}
    local source = params.source or "guild"
    local forceRefresh = params.forceRefresh or false
    
    DebugLog("QueryMembers called (source: %s, forceRefresh: %s)", source, tostring(forceRefresh))
    
    local members
    if source == "guild" then
        members = self:CollectGuildRoster(forceRefresh)
    elseif source == "group" or source == "party" or source == "raid" then
        members = self:CollectGroupRoster(forceRefresh)
    else
        DebugLog("Unknown source: %s", source)
        return {}
    end
    
    DebugLog("QueryMembers got %d members from source %s", #members, source)
    
    -- Apply filters
    if params.filters then
        members = self:ApplyFilters(members, params.filters)
        DebugLog("After filtering: %d members", #members)
    end
    
    -- Apply sorting
    if params.sortBy then
        members = self:SortMembers(members, params.sortBy, params.sortOrder or "asc")
    end
    
    -- Apply limit
    if params.limit and params.limit > 0 then
        local limited = {}
        for i = 1, math.min(params.limit, #members) do
            table.insert(limited, members[i])
        end
        members = limited
        DebugLog("After limit: %d members", #members)
    end
    
    return members
end

-- Flexible filtering system
function PlayerDataCollectorService:ApplyFilters(members, filters)
    local filtered = {}
    
    for _, member in ipairs(members) do
        local include = true
        
        -- Level range filter
        if filters.minLevel and member.level < filters.minLevel then
            include = false
        end
        if filters.maxLevel and member.level > filters.maxLevel then
            include = false
        end
        
        -- Class filter
        if filters.classes and #filters.classes > 0 then
            local hasClass = false
            for _, class in ipairs(filters.classes) do
                if member.class and member.class:upper() == class:upper() then
                    hasClass = true
                    break
                end
            end
            if not hasClass then include = false end
        end
        
        -- Online status filter
        if filters.onlineOnly and not member.online then
            include = false
        end
        if filters.offlineOnly and member.online then
            include = false
        end
        
        -- Rank filter (for guild members)
        if filters.ranks and #filters.ranks > 0 and member.rank then
            local hasRank = false
            for _, rank in ipairs(filters.ranks) do
                if member.rank == rank then
                    hasRank = true
                    break
                end
            end
            if not hasRank then include = false end
        end
        
        -- Custom filter function
        if filters.customFilter and type(filters.customFilter) == "function" then
            if not filters.customFilter(member, filters) then
                include = false
            end
        end
        
        if include then
            table.insert(filtered, member)
        end
    end
    
    return filtered
end

-- Sorting system
function PlayerDataCollectorService:SortMembers(members, sortBy, sortOrder)
    local orderMultiplier = (sortOrder == "desc") and -1 or 1
    
    table.sort(members, function(a, b)
        local valueA, valueB
        
        if sortBy == "name" then
            valueA, valueB = a.name or "", b.name or ""
        elseif sortBy == "level" then
            valueA, valueB = a.level or 0, b.level or 0
        elseif sortBy == "class" then
            valueA, valueB = a.class or "", b.class or ""
        elseif sortBy == "rank" then
            valueA, valueB = a.rankIndex or 99, b.rankIndex or 99
        elseif sortBy == "online" then
            valueA = a.online and 1 or 0
            valueB = b.online and 1 or 0
        elseif sortBy == "lastOnline" then
            -- Sort by last online time (online players first, then by recency)
            valueA = a.online and -1 or (a.lastOnline or 999999)
            valueB = b.online and -1 or (b.lastOnline or 999999)
        else
            return false -- Unknown sort field
        end
        
        if valueA == valueB then
            return (a.name or "") < (b.name or "") -- Secondary sort by name
        end
        
        if orderMultiplier == 1 then
            return valueA < valueB
        else
            return valueA > valueB
        end
    end)
    
    return members
end

-- Get statistics about collected data
function PlayerDataCollectorService:GetStatistics(source)
    local members = self:QueryMembers({source = source or "guild"})
    local stats = {
        total = #members,
        online = 0,
        offline = 0,
        mobile = 0,
        classes = {},
        levels = {min = 999, max = 0, avg = 0},
        ranks = {}
    }
    
    local totalLevel = 0
    
    for _, member in ipairs(members) do
        -- Online status
        if member.online then
            stats.online = stats.online + 1
            if member.isMobile then
                stats.mobile = stats.mobile + 1
            end
        else
            stats.offline = stats.offline + 1
        end
        
        -- Classes
        if member.class then
            stats.classes[member.class] = (stats.classes[member.class] or 0) + 1
        end
        
        -- Levels
        if member.level and member.level > 0 then
            stats.levels.min = math.min(stats.levels.min, member.level)
            stats.levels.max = math.max(stats.levels.max, member.level)
            totalLevel = totalLevel + member.level
        end
        
        -- Ranks (for guild)
        if member.rank then
            stats.ranks[member.rank] = (stats.ranks[member.rank] or 0) + 1
        end
    end
    
    -- Calculate average level
    if stats.total > 0 then
        stats.levels.avg = math.floor(totalLevel / stats.total)
    end
    
    -- Fix min level if no valid levels found
    if stats.levels.min == 999 then
        stats.levels.min = 0
    end
    
    return stats
end

-- Export functionality
function PlayerDataCollectorService:ExportMembers(members, format)
    format = format or "savedvariables"
    
    local Core = _G.GuildRecruiterCore
    local exportService = Core and Core.Resolve and Core.Resolve("ExportService")
    
    if not exportService then
        DebugLog("Export Service not available")
        return false
    end
    
    if format == "csv" then
        DebugLog("CSV export not yet implemented")
        return false
    end
    
    -- Default: export to SavedVariables
    local exported = 0
    for _, member in ipairs(members) do
        exportService:Save(member)
        exported = exported + 1
    end
    
    DebugLog("Exported %d member records", exported)
    return true
end

-- Clear all cached data
function PlayerDataCollectorService:ClearCache()
    ClearCache()
    DebugLog("Player data cache cleared")
end

-- Register the service
_G.GuildRecruiter_PlayerDataCollectorService = PlayerDataCollectorService

return PlayerDataCollectorService