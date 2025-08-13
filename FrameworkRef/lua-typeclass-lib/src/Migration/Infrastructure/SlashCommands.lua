-- Infrastructure/SlashCommands.lua
-- Enterprise-grade slash command service with comprehensive testing commands

local SlashCommandService = {}

-- Command registry for better organization
local CommandRegistry = {
    core = {},      -- Core functionality commands
    recruit = {},   -- Recruitment-related commands  
    test = {},      -- Testing and debugging commands
    ui = {},        -- UI-related commands
    debug = {}      -- Debug and diagnostic commands
}

-- Command validation and help system
local function ValidateCommand(commandName, handler, category)
    assert(type(commandName) == "string" and commandName ~= "", "Command name must be a non-empty string")
    assert(type(handler) == "function", "Command handler must be a function")
    
    category = category or "core"
    CommandRegistry[category] = CommandRegistry[category] or {}
    CommandRegistry[category][commandName] = handler
end

-- Enhanced error handling for commands
local function SafeExecuteCommand(commandName, handler, msg, logger)
    local success, error = pcall(handler, msg)
    if not success then
        local errorMsg = string.format("Command '%s' failed: %s", commandName, tostring(error))
        if logger and logger.Error then
            logger:Error(errorMsg)
        else
            print("|cffff0000[GuildRecruiter]|r " .. errorMsg)
        end
    end
end

-- Help system
local function ShowCommandHelp(category, logger)
    if category and CommandRegistry[category] then
        local helpText = string.format("|cff33ff99[GuildRecruiter]|r %s Commands:", category:upper())
        print(helpText)
        
        local commands = {
            core = {
                ["/gr"] = "Show general debug info",
                ["/gr_diag"] = "Diagnose all service registrations"
            },
            recruit = {
                ["/recruit <class> <level|range> [ilvl] [role]"] = "Start recruitment process",
                ["/recruitprocess"] = "Process current /who results"
            },
            test = {
                ["/gr_test_guild [refresh]"] = "Test guild roster collection",
                ["/gr_test_filter"] = "Test filtering system",
                ["/gr_test_stats"] = "Show guild statistics", 
                ["/gr_test_sort [field]"] = "Test sorting (level, name, class)",
                ["/gr_debug_member <name>"] = "Debug specific member data",
                ["/gr_clear_cache"] = "Clear cached data"
            },
            ui = {
                ["/grui"] = "Open configuration UI",
                ["/grcfg"] = "Open configuration UI (alias)"
            },
            debug = {
                ["/grguilddebug"] = "Test guild roster APIs directly",
                ["/grrefresh"] = "Force guild roster refresh",
                ["/grpurge"] = "Open purge management panel"
            }
        }
        
        local categoryCommands = commands[category]
        if categoryCommands then
            for cmd, desc in pairs(categoryCommands) do
                print(string.format("  %s - %s", cmd, desc))
            end
        end
    else
        print("|cff33ff99[GuildRecruiter]|r Available command categories:")
        print("  /gr help core - Core functionality commands")
        print("  /gr help recruit - Recruitment commands")
        print("  /gr help test - Testing and debugging commands")
        print("  /gr help ui - User interface commands")
        print("  /gr help debug - Debug and diagnostic commands")
    end
end

function SlashCommandService.Init(core)
    local WoWApi = core.Resolve("WoWApiAdapter")
    local Logger = core.Resolve("Logger")
    local RecruitmentService = core.Resolve("RecruitmentService")

    if not WoWApi or not Logger then
        error("SlashCommandService requires WoWApiAdapter and Logger services")
    end

    -- ================================
    -- CORE COMMANDS
    -- ================================
    
    -- /gr - Enhanced debug and help system
    ValidateCommand("gr", function(msg)
        local args = {}
        for arg in string.gmatch(msg or "", "%S+") do 
            table.insert(args, arg) 
        end
        
        if #args == 0 then
            Logger:Info("GuildRecruiter v0.2 - Guild recruitment automation")
            Logger:Info("Use '/gr help' for available commands")
            Logger:Info("Try '/recruit <class> <level> <ilvl>' to test scoring")
        elseif args[1] == "help" then
            ShowCommandHelp(args[2], Logger)
        else
            Logger:Info("Unknown subcommand: %s. Use '/gr help' for available commands", args[1])
        end
    end, "core")

    -- /gr_diag - Service diagnostics
    ValidateCommand("gr_diag", function(msg)
        Logger:Info("Running system diagnostics...")
        if core and core.DiagnoseServices then
            core.DiagnoseServices()
        else
            Logger:Error("Core.DiagnoseServices not available!")
        end
    end, "core")

    -- ================================
    -- DEBUG COMMANDS (NEW SECTION)
    -- ================================
    
    -- /grguilddebug - Test guild roster APIs directly
    ValidateCommand("grguilddebug", function(msg)
        print("|cff33ff99[Guild Debug]|r Starting guild roster API test...")
        
        -- Test basic guild status
        print("=== Basic Guild Status ===")
        print("IsInGuild():", IsInGuild())
        
        if not IsInGuild() then
            print("|cffff0000Player is not in a guild!|r")
            return
        end
        
        local guildName = GetGuildInfo("player")
        print("Guild Name:", guildName or "Unknown")
        
        -- Test guild roster functions
        print("\n=== Guild Roster API Test ===")
        print("GetNumGuildMembers():", GetNumGuildMembers())
        
        local numMembers = GetNumGuildMembers()
        if not numMembers or numMembers == 0 then
            print("|cffff5555No members returned - trying roster refresh...|r")
            
            -- Try refreshing roster
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                print("Using C_GuildInfo.GuildRoster()")
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                print("Using legacy GuildRoster()")
                GuildRoster()
            else
                print("|cffff0000No roster refresh API available!|r")
            end
            
            -- Wait and try again
            C_Timer.After(2, function()
                local retryNum = GetNumGuildMembers()
                print("After refresh - GetNumGuildMembers():", retryNum)
                
                if retryNum and retryNum > 0 then
                    print("\n=== Sample Member Data ===")
                    for i = 1, math.min(5, retryNum) do
                        local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online, status, class = GetGuildRosterInfo(i)
                        if name then
                            print(string.format("Member %d: %s (L%s %s) - %s - Online: %s", 
                                i, name, tostring(level), tostring(class), tostring(rank), tostring(online)))
                            
                            -- Test last online for offline members
                            if not online and GetGuildRosterLastOnline then
                                local years, months, days, hours = GetGuildRosterLastOnline(i)
                                if years or months or days or hours then
                                    print(string.format("  Last Online: %sy %sm %sd %sh", 
                                        tostring(years or 0), tostring(months or 0), 
                                        tostring(days or 0), tostring(hours or 0)))
                                end
                            end
                        else
                            print(string.format("Member %d: No data returned", i))
                        end
                    end
                else
                    print("|cffff0000Still no member data after refresh!|r")
                    print("This might indicate:")
                    print("- Guild roster hasn't loaded from server yet")
                    print("- API access restrictions")
                    print("- Player permissions issue")
                end
            end)
        else
            print("\n=== Sample Member Data ===")
            for i = 1, math.min(5, numMembers) do
                local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online, status, class = GetGuildRosterInfo(i)
                if name then
                    print(string.format("Member %d: %s (L%s %s) - %s - Online: %s", 
                        i, name, tostring(level), tostring(class), tostring(rank), tostring(online)))
                    
                    -- Test last online for offline members
                    if not online and GetGuildRosterLastOnline then
                        local years, months, days, hours = GetGuildRosterLastOnline(i)
                        if years or months or days or hours then
                            print(string.format("  Last Online: %sy %sm %sd %sh", 
                                tostring(years or 0), tostring(months or 0), 
                                tostring(days or 0), tostring(hours or 0)))
                        end
                    end
                else
                    print(string.format("Member %d: No data returned", i))
                end
            end
        end
        
        -- Test PlayerDataCollectorService if available
        print("\n=== Testing PlayerDataCollectorService ===")
        local collector = _G.GuildRecruiter_PlayerDataCollectorService
        if collector then
            print("PlayerDataCollectorService found")
            local members = collector:CollectGuildRoster(true) -- Force refresh
            print("CollectGuildRoster returned:", #members, "members")
            
            if #members > 0 then
                print("First member:", members[1].name, members[1].level, members[1].class)
            end
        else
            print("|cffff0000PlayerDataCollectorService not found!|r")
        end
    end, "debug")

    -- /grrefresh - Force roster refresh command
    ValidateCommand("grrefresh", function(msg)
        print("|cff33ff99[Guild Refresh]|r Forcing guild roster refresh...")
        
        if not IsInGuild() then
            print("|cffff0000Not in a guild!|r")
            return
        end
        
        -- Try both refresh methods
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
            print("Used C_GuildInfo.GuildRoster()")
        end
        
        if GuildRoster then
            GuildRoster()
            print("Used GuildRoster()")
        end
        
        -- Clear any cached data
        local collector = _G.GuildRecruiter_PlayerDataCollectorService
        if collector and collector.ClearCache then
            collector:ClearCache()
            print("Cleared PlayerDataCollectorService cache")
        end
        
        print("Roster refresh initiated. Wait 2-3 seconds then try your UI again.")
    end, "debug")

    -- /grpurge - Open purge management panel
    ValidateCommand("grpurge", function(msg)
        local PurgePanel = _G.GuildRecruiter.UI.PurgePanel
        if PurgePanel and PurgePanel.OnShow then
            PurgePanel.OnShow()
        else
            print("|cffff0000[GuildRecruiter]|r Purge Management Panel not available")
        end
    end, "debug")

    -- ================================
    -- UI COMMANDS
    -- ================================
    
    -- /grui - Open configuration UI
    ValidateCommand("grui", function(msg)
        local ConfigWindow = _G.GuildRecruiter and _G.GuildRecruiter.UI and _G.GuildRecruiter.UI.ConfigWindow
        if ConfigWindow and ConfigWindow.OnShow then
            Logger:Info("Opening configuration UI...")
            ConfigWindow.OnShow()
        else
            Logger:Error("Configuration UI not available")
            print("|cffff5555[GuildRecruiter]|r Config UI not loaded. Check your addon installation.")
        end
    end, "ui")

    -- ================================
    -- RECRUITMENT COMMANDS
    -- ================================
    
    -- /recruit - Enhanced recruitment command with better parsing
    ValidateCommand("recruit", function(msg)
        if not RecruitmentService then
            Logger:Error("RecruitmentService not available")
            return
        end
        
        local tokens = {}
        for token in string.gmatch(msg or "", "%S+") do 
            table.insert(tokens, token) 
        end

        if #tokens < 2 then
            Logger:Info("Usage: /recruit <class> <level|range> [ilvl] [role]")
            print("|cffff5555Examples:|r")
            print("  /recruit Mage 70 450 dps")
            print("  /recruit Paladin 70-80 500 tank") 
            print("  /recruit Priest 75-80 healer")
            return
        end

        local playerClass = table.remove(tokens, 1)
        local levelArg = table.remove(tokens, 1)
        local ilvl, role
        
        -- Parse remaining arguments
        for _, token in ipairs(tokens) do
            if tonumber(token) then
                ilvl = tonumber(token)
            elseif token:lower():match("^(tank|healer|dps)$") then
                role = token:lower()
            end
        end

        -- Detect level range vs single level
        local minLevel, maxLevel = string.match(levelArg, "^(%d+)%-(%d+)$")
        if minLevel and maxLevel then
            -- Range recruitment
            minLevel, maxLevel = tonumber(minLevel), tonumber(maxLevel)
            Logger:Info("Starting mass recruitment: %s levels %d-%d", playerClass, minLevel, maxLevel)
            
            local success = WoWApi.QueryWho(playerClass, minLevel, maxLevel, function(players)
                if not players or #players == 0 then
                    Logger:Info("No players found for %s %d-%d", playerClass, minLevel, maxLevel)
                    print("|cffff5555[Recruiter]|r No matching players found.")
                    return
                end
                
                local myName = UnitName("player")
                local processed = 0
                
                for _, player in ipairs(players) do
                    if player.name ~= myName then
                        RecruitmentService.StartRecruitmentForPlayer(player.name, player.class, player.level, ilvl, role)
                        processed = processed + 1
                    end
                end
                
                Logger:Info("Mass recruitment complete: processed %d players", processed)
                print(string.format("|cff33ff99[Recruiter]|r Processed %d players from /who results", processed))
            end)
            
            if not success then
                Logger:Warn("Who API not available. Open Who panel, run /who, then use /recruitprocess")
                print("|cffff5555[Recruiter]|r Who API unavailable. Use /who in-game, then /recruitprocess")
            end
        else
            -- Single player test mode
            local level = tonumber(levelArg)
            if not level then
                Logger:Error("Invalid level/range format")
                print("|cffff5555Usage:|r /recruit <class> <level|min-max> [ilvl] [role]")
                return
            end
            
            Logger:Info("Test mode: %s level %d, ilvl %s, role %s", playerClass, level, tostring(ilvl or "N/A"), tostring(role or "auto"))
            local myName = UnitName("player")
            RecruitmentService.StartRecruitmentForPlayer(myName, playerClass, level, ilvl, role) 
        end
    end, "recruit")

    -- /recruitprocess - Manual /who processing with enhanced error handling
    ValidateCommand("recruitprocess", function(msg)
        if not RecruitmentService then
            Logger:Error("RecruitmentService not available")
            return
        end
        
        -- Enhanced Who UI loading
        local function EnsureWhoUIAvailable()
            local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WhoUI")) or
                           (IsAddOnLoaded and IsAddOnLoaded("Blizzard_WhoUI"))
            
            if not isLoaded then
                local loaded = (C_AddOns and C_AddOns.LoadAddOn and C_AddOns.LoadAddOn("Blizzard_WhoUI")) or
                              (LoadAddOn and LoadAddOn("Blizzard_WhoUI"))
                if not loaded then
                    return false
                end
            end
            
            return GetNumWhoResults and GetWhoInfo
        end

        if not EnsureWhoUIAvailable() then
            Logger:Error("Who UI not available")
            print("|cffff5555[Recruiter]|r Cannot load Who panel. Open Who panel manually and try again.")
            return
        end

        local numResults = GetNumWhoResults()
        if numResults == 0 then
            Logger:Warn("No /who results available")
            print("|cffff5555[Recruiter]|r No /who results. Open Who panel, search, then try again.")
            return
        end

        Logger:Info("Processing %d /who results...", numResults)
        local myName = UnitName("player")
        local processed = 0
        
        for i = 1, numResults do
            local name, guild, level, race, className = GetWhoInfo(i)
            if name and name ~= myName then
                RecruitmentService.StartRecruitmentForPlayer(name, className, level)
                processed = processed + 1
            end
        end
        
        Logger:Info("Manual /who processing complete: %d players processed", processed)
        print(string.format("|cff33ff99[Recruiter]|r Processed %d players from /who results", processed))
    end, "recruit")

    -- ================================
    -- TEST COMMANDS
    -- ================================
    
    -- /gr_test_guild - Guild roster testing
    ValidateCommand("gr_test_guild", function(msg)
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        local forceRefresh = msg and msg:find("refresh") ~= nil
        Logger:Info("Testing guild roster collection (refresh: %s)...", tostring(forceRefresh))
        
        local startTime = GetTime()
        local members = collector:CollectGuildRoster(forceRefresh)
        local endTime = GetTime()
        
        Logger:Info("Guild roster test complete: %d members in %.2fs", #members, endTime - startTime)
        
        -- Show sample data
        local sampleSize = math.min(5, #members)
        if sampleSize > 0 then
            print("|cff33ff99[Test Results]|r First " .. sampleSize .. " members:")
            for i = 1, sampleSize do
                local m = members[i]
                local status = m.online and "|cff00ff00Online|r" or "|cff808080Offline|r"
                if m.isMobile then status = "|cffFFD700Mobile|r" end
                
                print(string.format("  %s (%d %s) - %s - %s - LastOnline: %s", 
                    m.name, m.level or 0, m.class or "Unknown", m.rank or "No Rank", status, tostring(m.lastOnline)))
            end
            
            if #members > sampleSize then
                print(string.format("  ... and %d more members", #members - sampleSize))
            end
        else
            print("|cffff5555[Test Results]|r No guild members found")
        end
    end, "test")

    -- /gr_test_filter - Filter system testing
    ValidateCommand("gr_test_filter", function(msg)
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        Logger:Info("Testing filtering system...")
        
        local filterTests = {
            {name = "Online Only", filters = {onlineOnly = true}},
            {name = "Level 70+", filters = {minLevel = 70}},
            {name = "Level 60-79", filters = {minLevel = 60, maxLevel = 79}},
            {name = "Paladins", filters = {classes = {"PALADIN"}}},
            {name = "Tanks & Healers", filters = {classes = {"PALADIN", "PRIEST", "DRUID", "WARRIOR"}}},
            {name = "Officers", filters = {ranks = {"Guild Master", "Officer", "Senior Officer"}}},
        }
        
        print("|cff33ff99[Filter Test Results]|r")
        for _, test in ipairs(filterTests) do
            local startTime = GetTime()
            local members = collector:QueryMembers({
                source = "guild",
                filters = test.filters
            })
            local endTime = GetTime()
            
            print(string.format("  %-20s: %3d members (%.2fms)", 
                test.name, #members, (endTime - startTime) * 1000))
        end
    end, "test")

    -- /gr_test_stats - Statistics testing
    ValidateCommand("gr_test_stats", function(msg)
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        Logger:Info("Generating guild statistics...")
        
        local startTime = GetTime()
        local stats = collector:GetStatistics("guild")
        local endTime = GetTime()
        
        print(string.format("|cff33ff99[Guild Statistics]|r (generated in %.2fms)", (endTime - startTime) * 1000))
        print(string.format("  Total Members: %d", stats.total))
        print(string.format("  Online: %d | Offline: %d | Mobile: %d", stats.online, stats.offline, stats.mobile))
        
        if stats.total > 0 then
            local onlinePercent = math.floor((stats.online / stats.total) * 100)
            print(string.format("  Online Rate: %d%%", onlinePercent))
        end
        
        print(string.format("  Level Range: %d-%d (avg: %d)", stats.levels.min, stats.levels.max, stats.levels.avg))
        
        if next(stats.classes) then
            print("  Class Distribution:")
            local sortedClasses = {}
            for class, count in pairs(stats.classes) do
                table.insert(sortedClasses, {class = class, count = count})
            end
            table.sort(sortedClasses, function(a, b) return a.count > b.count end)
            
            for _, data in ipairs(sortedClasses) do
                local percent = math.floor((data.count / stats.total) * 100)
                print(string.format("    %-12s: %3d (%2d%%)", data.class, data.count, percent))
            end
        end
        
        if next(stats.ranks) then
            print("  Rank Distribution:")
            local sortedRanks = {}
            for rank, count in pairs(stats.ranks) do
                table.insert(sortedRanks, {rank = rank, count = count})
            end
            table.sort(sortedRanks, function(a, b) return a.count > b.count end)
            
            for _, data in ipairs(sortedRanks) do
                local percent = math.floor((data.count / stats.total) * 100)
                print(string.format("    %-15s: %3d (%2d%%)", data.rank, data.count, percent))
            end
        end
    end, "test")

    -- /gr_test_sort - Sorting system testing
    ValidateCommand("gr_test_sort", function(msg)
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        local sortBy = msg and msg:match("(%w+)") or "level"
        local validFields = {level = true, name = true, class = true, rank = true, online = true}
        
        if not validFields[sortBy] then
            Logger:Warn("Invalid sort field: %s", sortBy)
            print("|cffff5555Valid fields:|r level, name, class, rank, online")
            return
        end
        
        Logger:Info("Testing sort by %s...", sortBy)
        
        local startTime = GetTime()
        local members = collector:QueryMembers({
            source = "guild",
            sortBy = sortBy,
            sortOrder = "desc",
            limit = 10
        })
        local endTime = GetTime()
        
        print(string.format("|cff33ff99[Sort Test Results]|r Top 10 by %s (%.2fms):", 
            sortBy, (endTime - startTime) * 1000))
            
        for i, m in ipairs(members) do
            local value = m[sortBy]
            if sortBy == "online" then
                value = m.online and "Online" or "Offline"
            elseif not value then
                value = "N/A"
            end
            
            print(string.format("  %2d. %-20s - %s", i, m.name or "Unknown", tostring(value)))
        end
    end, "test")

    -- /gr_debug_member - Debug specific member data
    ValidateCommand("gr_debug_member", function(msg)
        local memberName = msg and msg:match("%S+")
        if not memberName or memberName == "" then
            print("|cffff5555Usage:|r /gr_debug_member <playername>")
            return
        end
        
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        local members = collector:QueryMembers({
            source = "guild",
            filters = {
                customFilter = function(member, filters)
                    return member.name and member.name:lower():find(memberName:lower())
                end
            }
        })
        
        if #members == 0 then
            print(string.format("|cffff5555[Debug]|r No member found matching '%s'", memberName))
            return
        end
        
        for _, member in ipairs(members) do
            print(string.format("|cff33ff99[Debug Member: %s]|r", member.name))
            print(string.format("  Level: %s", tostring(member.level)))
            print(string.format("  Class: %s (%s)", tostring(member.class), tostring(member.classDisplayName)))
            print(string.format("  Rank: %s (index: %s)", tostring(member.rank), tostring(member.rankIndex)))
            print(string.format("  Online: %s", tostring(member.online)))
            print(string.format("  Mobile: %s", tostring(member.isMobile)))
            print(string.format("  Status: %s", tostring(member.status)))
            print(string.format("  Zone: %s", tostring(member.zone)))
            print(string.format("  LastOnline: %s", tostring(member.lastOnline)))
            print(string.format("  Note: %s", tostring(member.note)))
            print(string.format("  Source: %s", tostring(member.source)))
            print(string.format("  Timestamp: %s", tostring(member.timestamp)))
        end
    end, "test")

    -- /gr_clear_cache - Cache management
    ValidateCommand("gr_clear_cache", function(msg)
        local collector = core.Resolve("PlayerDataCollectorService")
        if not collector then
            Logger:Error("PlayerDataCollectorService not available")
            return
        end
        
        collector:ClearCache()
        Logger:Info("All player data caches cleared")
        print("|cff33ff99[Cache]|r Player data cache cleared successfully")
    end, "test")

    -- ================================
    -- REGISTER ALL COMMANDS
    -- ================================
    
    local function RegisterAllCommands()
        local registered = 0
        for category, commands in pairs(CommandRegistry) do
            for commandName, handler in pairs(commands) do
                WoWApi.RegisterSlash(commandName, function(msg)
                    SafeExecuteCommand(commandName, handler, msg, Logger)
                end)
                registered = registered + 1
            end
        end
        
        Logger:Info("Registered %d slash commands across %d categories", registered, 5)
        return registered
    end

    -- Register all commands
    local commandCount = RegisterAllCommands()
    
    -- Show startup summary
    print("|cff33ff99[GuildRecruiter]|r SlashCommands initialized")
    print(string.format("  %d commands registered - use '/gr help' for assistance", commandCount))

    return SlashCommandService
end

-- Global registration
_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.SlashCommands = SlashCommandService

return SlashCommandService