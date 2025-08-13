print("[GuildRecruiter][UI] ConfigWindow.lua loaded")

-- Ensure global registration for UI/ConfigWindow
_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.UI = _G.GuildRecruiter.UI or {}
local ConfigWindow = {}
_G.GuildRecruiter.UI.ConfigWindow = ConfigWindow
_G.GuildRecruiter.ConfigWindow = ConfigWindow

local EventBus = _G.GuildRecruiter and _G.GuildRecruiter.EventBus
if not EventBus then
    print("[GuildRecruiter][UI] EventBus not found! UI will not function.")
    return
end

-- Class colors for better visual appeal
local CLASS_COLORS = {
    ["WARRIOR"] = {0.78, 0.61, 0.43},
    ["PALADIN"] = {0.96, 0.55, 0.73},
    ["HUNTER"] = {0.67, 0.83, 0.45},
    ["ROGUE"] = {1.0, 0.96, 0.41},
    ["PRIEST"] = {1.0, 1.0, 1.0},
    ["SHAMAN"] = {0.0, 0.44, 0.87},
    ["MAGE"] = {0.25, 0.78, 0.92},
    ["WARLOCK"] = {0.53, 0.53, 0.93},
    ["DRUID"] = {1.0, 0.49, 0.04},
    ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
    ["MONK"] = {0.0, 1.0, 0.59},
    ["DEMONHUNTER"] = {0.64, 0.19, 0.79},
    ["EVOKER"] = {0.2, 0.58, 0.5}
}

-- Current filter state
local currentFilters = {
    onlineOnly = false,
    minLevel = nil,
    maxLevel = nil,
    selectedClasses = {},
    searchText = ""
}

-- Enhanced last online formatting with color coding
local function FormatLastOnline(lastOnlineHours, isOnline, isMobile)
    if isOnline then
        if isMobile then
            return "|cffFFD700Mobile|r"
        else
            return "|cff00FF00Online|r"
        end
    end
    
    if not lastOnlineHours or lastOnlineHours == 0 then
        return "|cff808080Unknown|r"
    end
    
    local hours = tonumber(lastOnlineHours)
    if not hours or hours <= 0 then
        return "|cff808080Unknown|r"
    end
    
    -- Convert hours to more readable format
    local days = math.floor(hours / 24)
    
    if days > 365 then
        local years = math.floor(days / 365)
        return string.format("|cff404040%dy ago|r", years)  -- Dark gray for > 1 year
    elseif days > 30 then
        return string.format("|cff808080%dd ago|r", days)  -- Gray for > 30 days
    elseif days > 7 then
        return string.format("|cffFF6B6B%dd ago|r", days)  -- Red for > 1 week
    elseif days > 0 then
        return string.format("|cffFFD93D%dd ago|r", days)  -- Yellow for days
    elseif hours > 0 then
        return string.format("|cff6BCF7F%dh ago|r", hours) -- Green for hours
    else
        return "|cff808080Unknown|r"
    end
end

-- Helper function to create a better-styled panel
local function CreatePanel(name, parent)
    local frame = CreateFrame("Frame", name, parent, "ButtonFrameTemplate")
    frame:SetSize(900, 650)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(10)
    
    -- Ensure .Inset exists for tab panels with proper styling
    if not frame.Inset then
        frame.Inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
    end
    
    return frame
end

-- Register /grcfg slash command to open config UI
if _G.GuildRecruiter.WoWApiAdapter and _G.GuildRecruiter.WoWApiAdapter.RegisterSlash then
    _G.GuildRecruiter.WoWApiAdapter.RegisterSlash("grcfg", function()
        print("[GuildRecruiter][UI] /grcfg called via WoWApiAdapter")
        if ConfigWindow.OnShow then ConfigWindow.OnShow() end
    end)
else
    SLASH_GRCONFIG1 = "/grcfg"
    SlashCmdList["GRCONFIG"] = function()
        print("[GuildRecruiter][UI] /grcfg called via fallback")
        if ConfigWindow.OnShow then ConfigWindow.OnShow() end
    end
end

-- Helper function to create better-looking tabs
local function CreateTab(parent, id, text)
    local tab = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate")
    tab:SetText(text)
    tab:SetID(id)
    tab:SetScript("OnClick", function(self)
        ConfigWindow.SwitchToTab(self:GetID())
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end)
    parent.tabs[id] = tab
    return tab
end

function ConfigWindow.SwitchToTab(tabId)
    if not ConfigWindow.frame or not ConfigWindow.frame.tabs then
        return
    end
    
    for i, tab in ipairs(ConfigWindow.frame.tabs) do
        if i == tabId then
            tab.panel:Show()
            PanelTemplates_SelectTab(tab)
            
            -- Initialize tab content
            if i == 1 then
                ConfigWindow.UpdateOptionsTab(tab.panel)
            elseif i == 2 then
                ConfigWindow.UpdateMembersTab(tab.panel)
            elseif i == 3 then
                ConfigWindow.UpdateExportTab(tab.panel)
            end
        else
            tab.panel:Hide()
            PanelTemplates_DeselectTab(tab)
        end
    end
end

function ConfigWindow.UpdateOptionsTab(panel)
    if panel.optionsCreated then return end
    
    -- Create some sample options
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("GuildRecruiter Options")
    title:SetTextColor(1, 0.82, 0)
    
    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Configure your guild recruitment settings")
    
    -- Sample checkbox
    local checkbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    checkbox.Text:SetText("Enable Auto-Recruitment")
    checkbox:SetChecked(true)
    
    -- Sample slider
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 0, -32)
    slider:SetMinMaxValues(1, 10)
    slider:SetValue(5)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider.textLow = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.textHigh = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slider.textLow:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3)
    slider.textHigh:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3)
    slider.textLow:SetText("1")
    slider.textHigh:SetText("10")
    
    local sliderTitle = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sliderTitle:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    sliderTitle:SetText("Recruitment Frequency")
    
    panel.optionsCreated = true
end

function ConfigWindow.UpdateExportTab(panel)
    if panel.exportCreated then return end
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Export Guild Data")
    title:SetTextColor(1, 0.82, 0)
    
    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Export your guild roster and statistics")
    
    -- Export button
    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetSize(120, 32)
    exportBtn:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    exportBtn:SetText("Export CSV")
    exportBtn:SetScript("OnClick", function()
        local Core = _G.GuildRecruiterCore
        local collector = Core and Core.Resolve and Core.Resolve("PlayerDataCollectorService")
        
        if collector then
            local members = collector:QueryMembers({source = "guild"})
            collector:ExportMembers(members)
            print(string.format("|cff33ff99[GuildRecruiter]|r Exported %d guild members", #members))
        else
            print("|cffff0000[GuildRecruiter]|r Export service not available")
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    
    panel.exportCreated = true
end

-- Refresh the members list with current filters
function ConfigWindow.RefreshMembersList()
    if not ConfigWindow.frame or not ConfigWindow.frame.tabs[2] or not ConfigWindow.frame.tabs[2].panel then
        return
    end
    
    ConfigWindow.UpdateMembersTab(ConfigWindow.frame.tabs[2].panel, true)
end

function ConfigWindow.UpdateMembersTab(panel, forceRefresh)
    if not panel.membersInitialized then
        -- Create filter controls
        local filterFrame = CreateFrame("Frame", nil, panel)
        filterFrame:SetHeight(40)
        filterFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
        filterFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
        
        -- Filter background
        filterFrame.bg = filterFrame:CreateTexture(nil, "BACKGROUND")
        filterFrame.bg:SetAllPoints()
        filterFrame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
        
        -- Online only checkbox - FIXED SPACING
        local onlineCheck = CreateFrame("CheckButton", nil, filterFrame, "InterfaceOptionsCheckButtonTemplate")
        onlineCheck:SetPoint("LEFT", filterFrame, "LEFT", 8, 0)
        onlineCheck:SetSize(20, 20)
        onlineCheck.Text:SetText("Online Only")
        onlineCheck.Text:SetPoint("LEFT", onlineCheck, "RIGHT", 6, 0)
        onlineCheck:SetScript("OnClick", function(self)
            currentFilters.onlineOnly = self:GetChecked()
            ConfigWindow.RefreshMembersList()
        end)
        
        -- Search label - BETTER POSITIONING
        local searchLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        searchLabel:SetPoint("LEFT", onlineCheck.Text, "RIGHT", 25, 0)  -- Position relative to checkbox text
        searchLabel:SetText("Search:")
        
        -- Search box - POSITIONED AFTER LABEL
        local searchBox = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
        searchBox:SetSize(150, 20)
        searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)  -- 8px after "Search:" label
        searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnEnterPressed", function(self)
            currentFilters.searchText = self:GetText():lower()
            ConfigWindow.RefreshMembersList()
            self:ClearFocus()
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            currentFilters.searchText = ""
            ConfigWindow.RefreshMembersList()
            self:ClearFocus()
        end)
        
        -- Level filter
        local levelLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        levelLabel:SetPoint("LEFT", searchBox, "RIGHT", 20, 0)
        levelLabel:SetText("Level:")
        
        local minLevelBox = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
        minLevelBox:SetSize(40, 20)
        minLevelBox:SetPoint("LEFT", levelLabel, "RIGHT", 5, 0)
        minLevelBox:SetNumeric(true)
        minLevelBox:SetAutoFocus(false)
        minLevelBox:SetScript("OnEnterPressed", function(self)
            local value = tonumber(self:GetText())
            currentFilters.minLevel = (value and value > 0) and value or nil
            ConfigWindow.RefreshMembersList()
            self:ClearFocus()
        end)
        
        local levelSeparator = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        levelSeparator:SetPoint("LEFT", minLevelBox, "RIGHT", 2, 0)
        levelSeparator:SetText("-")
        
        local maxLevelBox = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
        maxLevelBox:SetSize(40, 20)
        maxLevelBox:SetPoint("LEFT", levelSeparator, "RIGHT", 2, 0)
        maxLevelBox:SetNumeric(true)
        maxLevelBox:SetAutoFocus(false)
        maxLevelBox:SetScript("OnEnterPressed", function(self)
            local value = tonumber(self:GetText())
            currentFilters.maxLevel = (value and value > 0) and value or nil
            ConfigWindow.RefreshMembersList()
            self:ClearFocus()
        end)
        
        -- MEMBER COUNT - carefully positioned between level and refresh button
        local memberCountLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        memberCountLabel:SetPoint("CENTER", filterFrame, "CENTER", 120, 0)  -- Shifted right to avoid overlap
        memberCountLabel:SetTextColor(1, 1, 1)
        memberCountLabel:SetText("Showing 0 of 0 members")
        filterFrame.memberCountLabel = memberCountLabel
        
        -- Refresh last online times button
        local refreshLastOnlineBtn = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
        refreshLastOnlineBtn:SetSize(100, 22)
        refreshLastOnlineBtn:SetPoint("RIGHT", filterFrame, "RIGHT", -78, 0)
        refreshLastOnlineBtn:SetText("Refresh Times")
        refreshLastOnlineBtn:SetScript("OnClick", function()
            local Core = _G.GuildRecruiterCore
            local collector = Core and Core.Resolve and Core.Resolve("PlayerDataCollectorService")
            if collector then
                collector:ClearCache()
                ConfigWindow.RefreshMembersList()
                print("|cff33ff99[GuildRecruiter]|r Last online times refreshed")
            end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        -- Clear filters button
        local clearBtn = CreateFrame("Button", nil, filterFrame, "UIPanelButtonTemplate")
        clearBtn:SetSize(60, 22)
        clearBtn:SetPoint("RIGHT", filterFrame, "RIGHT", -8, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            currentFilters.onlineOnly = false
            currentFilters.minLevel = nil
            currentFilters.maxLevel = nil
            currentFilters.searchText = ""
            onlineCheck:SetChecked(false)
            searchBox:SetText("")
            minLevelBox:SetText("")
            maxLevelBox:SetText("")
            ConfigWindow.RefreshMembersList()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
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
        header.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        
        -- FIXED column positions
        local colX = {8, 140, 190, 265, 420, 520, 650}
        local colWidths = {130, 48, 73, 153, 98, 128, 120}
        local colTitles = {"Name", "Level", "Class", "Zone", "Status", "Rank", "Last Online"}
        
        header.columns = {}
        for j, title in ipairs(colTitles) do
            local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetText(title)
            fs:SetPoint("LEFT", header, "LEFT", colX[j], 0)
            fs:SetWidth(colWidths[j])
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(0.9, 0.9, 0.9)
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
    end
    
    local content = panel.rosterContent
    
    -- Clear existing rows
    for _, row in ipairs(content.rows) do 
        row:Hide()
    end
    
    -- Get member data
    local Core = _G.GuildRecruiterCore
    local collector = Core and Core.Resolve and Core.Resolve("PlayerDataCollectorService")
    
    if not collector then
        print("|cffff0000[GuildRecruiter]|r PlayerDataCollectorService not available")
        return
    end
    
    -- Force refresh if needed
    if forceRefresh then
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
        collector:ClearCache()
    end
    
    -- Get filtered members
    local members = collector:QueryMembers({source = "guild", forceRefresh = forceRefresh})
    
    -- Apply filters
    local filteredMembers = {}
    for _, member in ipairs(members) do
        local include = true
        
        if currentFilters.onlineOnly and not member.online then
            include = false
        end
        if currentFilters.minLevel and (not member.level or member.level < currentFilters.minLevel) then
            include = false
        end
        if currentFilters.maxLevel and (not member.level or member.level > currentFilters.maxLevel) then
            include = false
        end
        if currentFilters.searchText and currentFilters.searchText ~= "" then
            local search = currentFilters.searchText
            if not ((member.name and member.name:lower():find(search)) or
                   (member.class and member.class:lower():find(search)) or
                   (member.zone and member.zone:lower():find(search))) then
                include = false
            end
        end
        
        if include then
            table.insert(filteredMembers, member)
        end
    end
    
    -- Update member count
    if panel.filterFrame and panel.filterFrame.memberCountLabel then
        panel.filterFrame.memberCountLabel:SetText(string.format("Showing %d of %d members", #filteredMembers, #members))
    end
    
    -- Display members
    local colX = {8, 140, 190, 265, 420, 520, 650}
    local y = 0
    
    for idx, member in ipairs(filteredMembers) do
        local row = content.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(20)
            
            -- Row background
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            if idx % 2 == 0 then
                row.bg:SetColorTexture(0.05, 0.05, 0.05, 0.3)
            else
                row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
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
        
        -- Set member data
        local function trunc(str, max)
            if not str then return "" end
            if #str > max then return str:sub(1, max-1).."…" else return str end
        end
        
        row.name:SetText(trunc(member.name or "?", 20))
        row.level:SetText(member.level or "")
        
        local classText = trunc(member.classDisplayName or member.class or "", 10)
        row.class:SetText(classText)
        if member.class and CLASS_COLORS[member.class:upper()] then
            local color = CLASS_COLORS[member.class:upper()]
            row.class:SetTextColor(color[1], color[2], color[3])
        else
            row.class:SetTextColor(1, 1, 1)
        end
        
        row.zone:SetText(trunc(member.zone or "", 22))
        
        if member.online then
            if member.isMobile then
                row.status:SetText("|cffFFD700Mobile|r")
            else
                row.status:SetText("|cff00FF00Online|r")
            end
        else
            row.status:SetText("|cff808080Offline|r")
        end
        
        row.rank:SetText(trunc(member.rank or "", 18))
        row.lastOnline:SetText(FormatLastOnline(member.lastOnline, member.online, member.isMobile))
        
        row:Show()
        y = y + 20
    end
    
    content:SetHeight(math.max(y + 10, panel.rosterScroll:GetHeight()))
end

-- FIXED OnShow function
function ConfigWindow.OnShow()
    print("[GuildRecruiter][UI] ConfigWindow.OnShow called")
    
    -- Close any existing purge windows first to prevent overlap
    if _G.GuildRecruiterPurgePanel then
        _G.GuildRecruiterPurgePanel:Hide()
    end
    
    -- Hide any existing purge icons to prevent conflicts
    if _G.GRPurgeIcon then
        _G.GRPurgeIcon:Hide()
    end
    
    if ConfigWindow.frame then
        print("[GuildRecruiter][UI] Showing existing config frame")
        ConfigWindow.frame:Show()
        return
    end
    
    print("[GuildRecruiter][UI] Creating config frame")
    local f = CreatePanel("GuildRecruiterConfigWindow", UIParent)
    ConfigWindow.frame = f
    
    -- Fix the portrait properly
    if f.portrait then
        SetPortraitTexture(f.portrait, "player")
    elseif f.PortraitContainer and f.PortraitContainer.portrait then
        SetPortraitTexture(f.PortraitContainer.portrait, "player")
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
    
    -- Enhanced title
    if f.TitleText or (f.GetTitleText and f:GetTitleText()) then
        local titleRegion = f.TitleText or (f.GetTitleText and f:GetTitleText())
        if titleRegion then
            titleRegion:SetText("GuildRecruiter")
            titleRegion:SetTextColor(1, 0.82, 0)
        end
    end
    
    -- Enhanced tabs
    f.tabs = {}
    local tabNames = {"Options", "Members", "Export"}
    
    -- FIXED: Better positioned purge icon that doesn't overlap
    local purgeIcon = CreateFrame("Button", "GRPurgeIcon", UIParent)
    purgeIcon:SetSize(32, 32)
    purgeIcon:SetPoint("TOPLEFT", f, "TOPRIGHT", 10, -50) -- Better positioning
    purgeIcon:SetFrameStrata("DIALOG")
    purgeIcon:SetFrameLevel(15) -- Higher than main window
    
    purgeIcon:SetNormalTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
    purgeIcon:GetNormalTexture():SetVertexColor(1, 0.2, 0.2)
    purgeIcon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    
    purgeIcon:SetScript("OnClick", function()
        local PurgePanel = _G.GuildRecruiter.UI.PurgePanel
        if PurgePanel and PurgePanel.OnShow then
            PurgePanel.OnShow()
        else
            print("|cffff0000[GuildRecruiter]|r Purge Management Panel not available")
        end
    end)
    
    purgeIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Purge Management")
        GameTooltip:AddLine("Click to manage inactive members", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    
    purgeIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Hide/show with main window
    f:SetScript("OnShow", function() 
        purgeIcon:Show() 
    end)
    f:SetScript("OnHide", function() 
        purgeIcon:Hide()
        -- Also hide any open purge windows when main window closes
        if _G.GuildRecruiterPurgePanel then
            _G.GuildRecruiterPurgePanel:Hide()
        end
    end)
    
    f.purgeIcon = purgeIcon
    
    -- Better action button styling
    f.ActionButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.ActionButton:SetText("Refresh Data")
    f.ActionButton:SetWidth(100)
    f.ActionButton:SetHeight(22)
    f.ActionButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 6)
    f.ActionButton:SetScript("OnClick", function()
        if ConfigWindow.frame.tabs[2].panel:IsShown() then
            print("|cff33ff99[GuildRecruiter]|r Refreshing guild data...")
            ConfigWindow.UpdateMembersTab(ConfigWindow.frame.tabs[2].panel, true)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    
    for i, name in ipairs(tabNames) do
        local tab = CreateTab(f, i, name)
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, -27)
        else
            tab:SetPoint("LEFT", f.tabs[i-1], "RIGHT", 0, 0)
        end
        
        tab.panel = CreateFrame("Frame", nil, f.Inset)
        tab.panel:SetAllPoints(f.Inset)
        tab.panel:Hide()
        
        f.tabs[i] = tab
    end
    
    -- Show the second tab (Members) by default for better user experience
    ConfigWindow.SwitchToTab(2)
    f:Show()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
end

-- Additional slash commands for easier access
SLASH_GRPURGE1 = "/grpurge"
SlashCmdList["GRPURGE"] = function()
    local PurgePanel = _G.GuildRecruiter.UI.PurgePanel
    if PurgePanel and PurgePanel.OnShow then
        PurgePanel.OnShow()
    else
        print("|cffff0000[GuildRecruiter]|r Purge Management Panel not available")
    end
end

-- Add a debug slash command for troubleshooting
SLASH_GRDEBUG1 = "/grdebug"
SlashCmdList["GRDEBUG"] = function()
    print("|cff33ff99[GuildRecruiter Debug]|r")
    print("ConfigWindow.frame exists:", ConfigWindow.frame ~= nil)
    if ConfigWindow.frame then
        print("Frame is shown:", ConfigWindow.frame:IsShown())
        print("Current tab:", ConfigWindow.frame.tabs and "has tabs" or "no tabs")
    end
    
    local Core = _G.GuildRecruiterCore
    print("Core exists:", Core ~= nil)
    
    if Core then
        local collector = Core.Resolve and Core.Resolve("PlayerDataCollectorService")
        print("PlayerDataCollectorService exists:", collector ~= nil)
        
        if collector then
            local members = collector:QueryMembers({source = "guild"})
            print("Guild members found:", #members)
            
            -- Show a few sample members for debugging
            if #members > 0 then
                print("Sample member data:")
                for i = 1, math.min(3, #members) do
                    local m = members[i]
                    print(string.format("  %d. %s (L%s %s) - %s", 
                        i, 
                        m.name or "Unknown", 
                        m.level or "?", 
                        m.class or "?", 
                        m.online and "Online" or "Offline"
                    ))
                end
            end
        end
    end
    
    -- Test guild API availability
    print("Guild API Test:")
    print("  IsInGuild():", IsInGuild())
    if IsInGuild() then
        print("  GetNumGuildMembers():", GetNumGuildMembers and GetNumGuildMembers() or "API not available")
        print("  GetGuildRosterInfo(1):", GetGuildRosterInfo and (GetGuildRosterInfo(1) or "No data") or "API not available")
    end
end

-- Export the ConfigWindow module
return ConfigWindow