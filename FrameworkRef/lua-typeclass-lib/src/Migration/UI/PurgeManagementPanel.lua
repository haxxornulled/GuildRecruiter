-- UI/PurgeManagementPanel.lua
-- Purge panel with days filtering for inactive guild members

print("[GuildRecruiter][UI] PurgeManagementPanel.lua loaded")

-- Ensure global registration
_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.UI = _G.GuildRecruiter.UI or {}
local PurgePanel = {}
_G.GuildRecruiter.UI.PurgePanel = PurgePanel

-- Settings
local purgeSettings = {
    daysThreshold = 30
}

-- Helper function to create panel
local function CreatePanel(name, parent)
    local frame = CreateFrame("Frame", name, parent, "ButtonFrameTemplate")
    frame:SetSize(900, 650)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(10)
    
    if not frame.Inset then
        frame.Inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
    end
    
    return frame
end

function PurgePanel.RefreshMembersList()
    if not PurgePanel.frame or not PurgePanel.frame.rosterContent then
        return
    end
    PurgePanel.UpdateMembersTab(PurgePanel.frame.Inset, true)
end

function PurgePanel.UpdateMembersTab(panel, forceRefresh)
    if not panel.membersInitialized then
        -- Create filter controls with proper height for all controls
        local filterFrame = CreateFrame("Frame", nil, panel)
        filterFrame:SetHeight(80)
        filterFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
        filterFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        
        -- Filter background
        filterFrame.bg = filterFrame:CreateTexture(nil, "BACKGROUND")
        filterFrame.bg:SetAllPoints()
        filterFrame.bg:SetColorTexture(0.1, 0.05, 0.05, 0.8)
        
        -- Purge-specific controls
        local title = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("LEFT", filterFrame, "LEFT", 12, -5)
        title:SetText("Purge Inactive Members")
        title:SetTextColor(1, 0.2, 0.2)
        
        -- Days threshold controls
        local daysLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        daysLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        daysLabel:SetText("Show members inactive for:")
        daysLabel:SetTextColor(1, 0.8, 0.8)
        
        local daysSlider = CreateFrame("Slider", nil, filterFrame, "OptionsSliderTemplate")
        daysSlider:SetPoint("LEFT", daysLabel, "RIGHT", 20, 0)
        daysSlider:SetSize(200, 20)
        daysSlider:SetMinMaxValues(1, 365)
        daysSlider:SetValue(purgeSettings.daysThreshold)
        daysSlider:SetValueStep(1)
        daysSlider:SetObeyStepOnDrag(true)
        
        -- Value display with better formatting
        local daysValue = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        daysValue:SetPoint("LEFT", daysSlider, "RIGHT", 10, 0)
        daysValue:SetTextColor(1, 1, 0)
        
        local function updateDaysText(days)
            if days == 1 then
                daysValue:SetText("1 day or more")
            elseif days < 30 then
                daysValue:SetText(days .. " days or more")
            elseif days < 365 then
                local months = math.floor(days / 30)
                daysValue:SetText(string.format("%d+ days (%d+ months)", days, months))
            else
                daysValue:SetText("1+ year")
            end
        end
        
        updateDaysText(purgeSettings.daysThreshold)
        
        daysSlider:SetScript("OnValueChanged", function(self, value)
            purgeSettings.daysThreshold = math.floor(value)
            updateDaysText(purgeSettings.daysThreshold)
            PurgePanel.RefreshMembersList()
        end)
        
        -- Quick preset buttons
        local presets = {
            {text = "1 Week", days = 7},
            {text = "1 Month", days = 30}, 
            {text = "3 Months", days = 90},
            {text = "6 Months", days = 180},
            {text = "1 Year", days = 365}
        }
        
        for i, preset in ipairs(presets) do
            local btn = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
            btn:SetSize(60, 18)
            btn:SetPoint("TOPLEFT", daysLabel, "BOTTOMLEFT", (i-1) * 65, -5)
            btn:SetText(preset.text)
            btn:SetScript("OnClick", function()
                daysSlider:SetValue(preset.days)
                purgeSettings.daysThreshold = preset.days
                updateDaysText(preset.days)
                PurgePanel.RefreshMembersList()
            end)
        end
        
        -- Member count and action buttons
        local memberCountLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        memberCountLabel:SetPoint("RIGHT", filterFrame, "RIGHT", -180, 10)
        memberCountLabel:SetTextColor(1, 1, 0)
        memberCountLabel:SetText("0 members found")
        filterFrame.memberCountLabel = memberCountLabel
        
        -- Refresh button
        local refreshBtn = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
        refreshBtn:SetSize(80, 24)
        refreshBtn:SetPoint("RIGHT", filterFrame, "RIGHT", -90, 10)
        refreshBtn:SetText("Refresh")
        refreshBtn:SetScript("OnClick", function()
            print("|cff33ff99[PurgePanel]|r Refreshing inactive member list...")
            PurgePanel.RefreshMembersList()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        -- Purge selected button (dangerous styling)
        local purgeBtn = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
        purgeBtn:SetSize(80, 24)
        purgeBtn:SetPoint("RIGHT", filterFrame, "RIGHT", -8, 10)
        purgeBtn:SetText("Kick All")
        purgeBtn:SetScript("OnClick", function()
            PurgePanel.ConfirmPurgeAll()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        end)
        
        -- Make purge button look dangerous
        C_Timer.After(0.1, function()
            if purgeBtn:GetNormalTexture() then
                purgeBtn:GetNormalTexture():SetVertexColor(0.8, 0.2, 0.2)
            end
        end)
        
        panel.filterFrame = filterFrame
        
        -- Create header
        local header = CreateFrame("Frame", nil, panel)
        header:SetHeight(24)
        header:SetPoint("TOPLEFT", filterFrame, "BOTTOMLEFT", 0, -8)
        header:SetPoint("TOPRIGHT", filterFrame, "BOTTOMRIGHT", 0, -8)
        
        -- Header background
        header.bg = header:CreateTexture(nil, "BACKGROUND")
        header.bg:SetAllPoints()
        header.bg:SetColorTexture(0.2, 0.1, 0.1, 0.8)
        
        -- Column headers
        local colX = {8, 140, 190, 265, 420, 520, 650}
        local colTitles = {"Name", "Level", "Class", "Zone", "Status", "Rank", "Last Online"}
        
        header.columns = {}
        for j, title in ipairs(colTitles) do
            local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetText(title)
            fs:SetPoint("LEFT", header, "LEFT", colX[j], 0)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(1, 0.8, 0.8)
            header.columns[j] = fs
        end
        
        panel.header = header
        
        -- Create scroll area
        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -25, 8)
        panel.rosterScroll = scroll
        
        local content = CreateFrame("Frame", nil, scroll)
        content:SetPoint("TOPLEFT")
        content:SetPoint("TOPRIGHT")
        content:SetWidth(scroll:GetWidth())
        scroll:SetScrollChild(content)
        panel.rosterContent = content
        content.rows = {}
        
        panel.membersInitialized = true
        print("[GuildRecruiter][UI] Purge panel UI created successfully")
    end
    
    local content = panel.rosterContent
    
    -- Clear existing rows
    for _, row in ipairs(content.rows) do 
        row:Hide()
    end
    
    -- Get guild data using DIRECT WoW API
    print("[GuildRecruiter][UI] Collecting guild data...")
    
    if not IsInGuild() then
        print("|cffff0000[GuildRecruiter]|r Player is not in a guild")
        return
    end
    
    -- Force refresh if needed
    if forceRefresh then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
    end
    
    local numMembers = GetNumGuildMembers()
    print("[GuildRecruiter][UI] Found", numMembers, "guild members")
    
    if not numMembers or numMembers == 0 then
        print("|cffff5555[GuildRecruiter]|r No guild members found")
        return
    end
    
    -- Collect inactive members
    local inactiveMembers = {}
    local hoursThreshold = purgeSettings.daysThreshold * 24
    
    for i = 1, numMembers do
        local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online, status, class = GetGuildRosterInfo(i)
        
        if name and not online then
            -- Get last online time
            local lastOnlineHours = nil
            if GetGuildRosterLastOnline then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                if years or months or days or hours then
                    lastOnlineHours = (hours or 0) + ((days or 0) * 24) + ((months or 0) * 30.5 * 24) + ((years or 0) * 365.25 * 24)
                    lastOnlineHours = math.floor(lastOnlineHours)
                end
            end
            
            -- Check if member meets inactivity threshold
            if lastOnlineHours and lastOnlineHours >= hoursThreshold then
                local memberData = {
                    name = name:match("^([^-]+)") or name, -- Clean name
                    level = level or 0,
                    class = class or "Unknown",
                    classDisplayName = classDisplayName or class or "Unknown",
                    rank = rank or "Unknown",
                    zone = zone or "",
                    lastOnline = lastOnlineHours,
                    online = false
                }
                
                table.insert(inactiveMembers, memberData)
            end
        end
    end
    
    print("[GuildRecruiter][UI] Found", #inactiveMembers, "inactive members")
    
    -- Sort by last online time (most inactive first)
    table.sort(inactiveMembers, function(a, b)
        return (a.lastOnline or 0) > (b.lastOnline or 0)
    end)
    
    -- Update member count with better messaging
    if panel.filterFrame and panel.filterFrame.memberCountLabel then
        local countText
        if #inactiveMembers == 0 then
            countText = string.format("No members inactive %d+ days", purgeSettings.daysThreshold)
        elseif #inactiveMembers == 1 then
            countText = "1 member to review"
        else
            countText = string.format("%d members to review", #inactiveMembers)
        end
        panel.filterFrame.memberCountLabel:SetText(countText)
    end
    
    -- Display members
    local colX = {8, 140, 190, 265, 420, 520, 650}
    local y = 0
    
    for idx, member in ipairs(inactiveMembers) do
        local row = content.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(20)
            
            -- Row background
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            if idx % 2 == 0 then
                row.bg:SetColorTexture(0.1, 0.05, 0.05, 0.3)
            else
                row.bg:SetColorTexture(0.15, 0.08, 0.08, 0.3)
            end
            
            -- Create text elements
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row, "LEFT", colX[1], 0)
            row.name:SetJustifyH("LEFT")
            
            row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.level:SetPoint("LEFT", row, "LEFT", colX[2], 0)
            row.level:SetJustifyH("CENTER")
            
            row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.class:SetPoint("LEFT", row, "LEFT", colX[3], 0)
            row.class:SetJustifyH("LEFT")
            
            row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.zone:SetPoint("LEFT", row, "LEFT", colX[4], 0)
            row.zone:SetJustifyH("LEFT")
            
            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.status:SetPoint("LEFT", row, "LEFT", colX[5], 0)
            row.status:SetJustifyH("CENTER")
            
            row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.rank:SetPoint("LEFT", row, "LEFT", colX[6], 0)
            row.rank:SetJustifyH("LEFT")
            
            row.lastOnline = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.lastOnline:SetPoint("LEFT", row, "LEFT", colX[7], 0)
            row.lastOnline:SetJustifyH("LEFT")
            
            content.rows[idx] = row
        end
        
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", content, "RIGHT", 0, -y)
        
        -- Store member data for kicking
        row.memberData = member
        
        -- Set member data
        local function trunc(str, max)
            if not str then return "" end
            if #str > max then return str:sub(1, max-1).."…" else return str end
        end
        
        row.name:SetText(trunc(member.name, 20))
        row.level:SetText(tostring(member.level))
        row.class:SetText(trunc(member.classDisplayName, 10))
        row.zone:SetText(trunc(member.zone, 22))
        row.status:SetText("|cff808080Offline|r")
        row.rank:SetText(trunc(member.rank, 18))
        
        -- Format last online
        local daysAgo = math.floor(member.lastOnline / 24)
        if daysAgo > 365 then
            local years = math.floor(daysAgo / 365)
            row.lastOnline:SetText(string.format("|cff404040%dy ago|r", years))
        elseif daysAgo > 30 then
            row.lastOnline:SetText(string.format("|cff808080%dd ago|r", daysAgo))
        else
            row.lastOnline:SetText(string.format("|cffFF6B6B%dd ago|r", daysAgo))
        end
        
        row:Show()
        y = y + 20
    end
    
    content:SetHeight(math.max(y + 10, panel.rosterScroll:GetHeight()))
    print("[GuildRecruiter][UI] Display complete -", #inactiveMembers, "members shown")
end

function PurgePanel.ConfirmPurgeAll()
    if not PurgePanel.frame or not PurgePanel.frame.rosterContent then
        return
    end
    
    -- Count how many members would be affected
    local content = PurgePanel.frame.rosterContent
    local memberCount = 0
    for _, row in ipairs(content.rows) do
        if row:IsShown() then
            memberCount = memberCount + 1
        end
    end
    
    if memberCount == 0 then
        print("|cffff5555[PurgePanel]|r No members to purge")
        return
    end
    
    -- Show confirmation dialog
    StaticPopup_Show("GUILDRECRUITER_CONFIRM_PURGE_ALL", memberCount, purgeSettings.daysThreshold)
end

-- Confirmation dialog
StaticPopupDialogs["GUILDRECRUITER_CONFIRM_PURGE_ALL"] = {
    text = "Are you sure you want to KICK ALL %d members who have been inactive for %d+ days?\n\n|cffff0000This action cannot be undone!|r",
    button1 = "Kick All",
    button2 = "Cancel",
    OnAccept = function(self, memberCount, daysThreshold)
        print("|cff33ff99[PurgePanel]|r Starting mass purge...")
        
        -- Get the member list and kick them
        local content = PurgePanel.frame.rosterContent
        local kicked = 0
        
        for _, row in ipairs(content.rows) do
            if row:IsShown() and row.memberData then
                local memberName = row.memberData.name
                
                -- Try different kick APIs
                if GuildUninviteByName then
                    GuildUninviteByName(memberName)
                    kicked = kicked + 1
                elseif C_GuildInfo and C_GuildInfo.RemoveGuildMember then
                    C_GuildInfo.RemoveGuildMember(memberName)
                    kicked = kicked + 1
                else
                    print("|cffff0000[PurgePanel]|r No guild kick API available!")
                    break
                end
                
                print("|cff808080[PurgePanel]|r Kicked:", memberName)
            end
        end
        
        print("|cff33ff99[PurgePanel]|r Mass purge complete:", kicked, "members removed")
        
        -- Refresh the list after a delay
        C_Timer.After(2, function()
            if PurgePanel.frame and PurgePanel.frame:IsShown() then
                PurgePanel.RefreshMembersList()
            end
        end)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Main show function
function PurgePanel.OnShow()
    print("[GuildRecruiter][UI] PurgePanel.OnShow called")
    
    if PurgePanel.frame then
        print("[GuildRecruiter][UI] Showing existing purge frame")
        PurgePanel.frame:Show()
        PurgePanel.RefreshMembersList()
        return
    end
    
    print("[GuildRecruiter][UI] Creating purge frame")
    local f = CreatePanel("GuildRecruiterPurgePanel", UIParent)
    PurgePanel.frame = f
    
    -- Set title
    if f.TitleText then
        f.TitleText:SetText("Purge Management")
        f.TitleText:SetTextColor(1, 0.2, 0.2)
    end
    
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() 
            f:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end)
    end
    
    -- Initialize the members tab
    PurgePanel.UpdateMembersTab(f.Inset, true)
    
    f:Show()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    print("[GuildRecruiter][UI] Purge panel created and shown")
end

return PurgePanel