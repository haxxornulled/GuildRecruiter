-- Infrastructure/WoWApiAdapter.lua
-- Complete WoW API adapter with all required methods

local WoWApiAdapter = {}
local slashCount = 0
local registeredCommands = {}

function WoWApiAdapter.Init(core)
    local self = {}
    local EventBus = (_G.GuildRecruiter and _G.GuildRecruiter.EventBus) or nil
    local logger = core and core.Resolve and core.Resolve("Logger") or nil

    -- === GUILD API WRAPPERS ===
    function self.IsInGuild()
        return IsInGuild()
    end

    function self.GetNumGuildMembers()
        return GetNumGuildMembers()
    end

    function self.GetGuildRosterInfo(index)
        return GetGuildRosterInfo(index)
    end

    function self.GetGuildRosterLastOnline(index)
        return GetGuildRosterLastOnline(index)
    end

    function self.GetGuildInfo(unit)
        return GetGuildInfo(unit)
    end

    function self.GuildRoster()
        if GuildRoster then return GuildRoster() end
    end

    function self.GuildPromote(memberName)
        if GuildPromote then return GuildPromote(memberName) end
    end

    function self.GuildDemote(memberName)
        if GuildDemote then return GuildDemote(memberName) end
    end

    function self.SetGuildMemberRank(memberName, rankIndex)
        if SetGuildMemberRank then return SetGuildMemberRank(memberName, rankIndex) end
    end

    function self.GetGuildMemberIndexByName(memberName)
        if GetGuildRosterInfo and IsInGuild() then
            local num = self.GetNumGuildMembers()
            for i = 1, num do
                local name = GetGuildRosterInfo(i)
                if name and name:find("-") then name = name:match("^[^-]+") end
                if name == memberName then return i end
            end
        end
        return nil
    end

    function self.GuildUninviteByName(memberName)
        if C_GuildInfo and C_GuildInfo.RemoveGuildMember then
            C_GuildInfo.RemoveGuildMember(memberName)
            if logger then logger:Info("[WoWApiAdapter] Removed guild member: %s (C_GuildInfo.RemoveGuildMember)", memberName) end
        else
            if GuildUninviteByName then
                GuildUninviteByName(memberName)
                if logger then logger:Info("[WoWApiAdapter] Removed guild member: %s (GuildUninviteByName)", memberName) end
            elseif GuildUninvite then
                GuildUninvite(memberName)
                if logger then logger:Info("[WoWApiAdapter] Removed guild member: %s (GuildUninvite)", memberName) end
            else
                if logger then logger:Error("[WoWApiAdapter] No available API to remove guild member: %s", memberName) end
            end
        end
        if EventBus then EventBus.Emit("GuildMemberRemoved", memberName) end
    end

    -- === WHISPER AND MESSAGING ===
    function self.SendWhisper(playerName, message)
        if not playerName or not message then return false end
        SendChatMessage(message, "WHISPER", nil, playerName)
        if logger then logger:Info("[WoWApiAdapter] Sent whisper to %s: %s", playerName, message) end
        return true
    end

    function self.SendGuildInvite(playerName)
        if not playerName then return false end
        GuildInviteByName(playerName)
        if logger then logger:Info("[WoWApiAdapter] Sent guild invite to %s", playerName) end
        return true
    end

    function self.OnWhisperReceived(callback)
        if not callback or type(callback) ~= "function" then return end
        
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("CHAT_MSG_WHISPER")
        frame:SetScript("OnEvent", function(self, event, message, sender)
            callback(message, sender)
        end)
        
        if logger then logger:Info("[WoWApiAdapter] Registered whisper listener") end
        return frame
    end

    -- === WHO SYSTEM ===
    function self.QueryWho(class, minLevel, maxLevel, callback)
        if not callback or type(callback) ~= "function" then
            if logger then logger:Error("[WoWApiAdapter] QueryWho requires a callback function") end
            return false
        end

        -- Modern WHO API (Retail)
        if C_FriendList and C_FriendList.SendWho then
            local whoRequest = {
                minLevel = minLevel,
                maxLevel = maxLevel,
                classFilter = class,
            }
            
            C_FriendList.SendWho(whoRequest)
            
            -- Listen for WHO results
            local frame = CreateFrame("Frame")
            frame:RegisterEvent("WHO_LIST_UPDATE")
            frame:SetScript("OnEvent", function(self, event)
                local numResults = C_FriendList.GetNumWhoResults()
                local players = {}
                
                for i = 1, numResults do
                    local info = C_FriendList.GetWhoInfo(i)
                    if info then
                        table.insert(players, {
                            name = info.fullName or info.name,
                            level = info.level,
                            class = info.filename, -- This is the class token
                            zone = info.area
                        })
                    end
                end
                
                callback(players)
                frame:UnregisterEvent("WHO_LIST_UPDATE")
                if logger then logger:Info("[WoWApiAdapter] WHO query completed: %d results", #players) end
            end)
            
            return true
        end

        -- Legacy WHO API
        if SendWho then
            local whoString = ""
            if class then whoString = whoString .. "c-" .. class .. " " end
            if minLevel and maxLevel then
                whoString = whoString .. minLevel .. "-" .. maxLevel
            elseif minLevel then
                whoString = whoString .. minLevel .. "-80"
            end
            
            SendWho(whoString)
            
            -- Use a timer to check results since legacy API doesn't have reliable events
            C_Timer.After(2, function()
                local numResults = GetNumWhoResults()
                local players = {}
                
                for i = 1, numResults do
                    local name, guildName, level, race, class, zone = GetWhoInfo(i)
                    if name then
                        table.insert(players, {
                            name = name,
                            level = level,
                            class = class,
                            zone = zone,
                            guild = guildName,
                            race = race
                        })
                    end
                end
                
                callback(players)
                if logger then logger:Info("[WoWApiAdapter] Legacy WHO query completed: %d results", #players) end
            end)
            
            return true
        end

        if logger then logger:Error("[WoWApiAdapter] No WHO API available") end
        return false
    end

    -- === SLASH COMMANDS ===
    function self.RegisterSlash(command, handler)
        if not command or not handler then return false end
        
        slashCount = slashCount + 1
        local slashCmd = "GUILDRECRUITER_SLASH_" .. slashCount
        
        -- Register the slash command
        _G["SLASH_" .. slashCmd .. "1"] = "/" .. command
        SlashCmdList[slashCmd] = handler
        
        registeredCommands[command] = slashCmd
        
        if logger then logger:Info("[WoWApiAdapter] Registered slash command: /%s", command) end
        return true
    end

    function self.UnregisterSlash(command)
        local slashCmd = registeredCommands[command]
        if slashCmd then
            SlashCmdList[slashCmd] = nil
            registeredCommands[command] = nil
            if logger then logger:Info("[WoWApiAdapter] Unregistered slash command: /%s", command) end
            return true
        end
        return false
    end

    -- === EVENT HANDLING ===
    function self.RegisterEvent(event, callback)
        if not event or not callback then return nil end
        
        local frame = CreateFrame("Frame")
        frame:RegisterEvent(event)
        frame:SetScript("OnEvent", callback)
        
        if logger then logger:Info("[WoWApiAdapter] Registered event: %s", event) end
        return frame
    end

    -- === UTILITY FUNCTIONS ===
    function self.GetPlayerName()
        return UnitName("player")
    end

    function self.GetPlayerGuild()
        return GetGuildInfo("player")
    end

    function self.IsPlayerInGuild()
        return IsInGuild()
    end

    function self.PlaySound(soundKit)
        if PlaySound then
            PlaySound(soundKit)
        end
    end

    -- Initialize any startup procedures
    if logger then logger:Info("[WoWApiAdapter] Initialized successfully") end
    
    return self
end

-- Static method for creating instance
function WoWApiAdapter.Create(core)
    return WoWApiAdapter.Init(core)
end

-- Global registration
_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.WoWApiAdapter = WoWApiAdapter

return WoWApiAdapter