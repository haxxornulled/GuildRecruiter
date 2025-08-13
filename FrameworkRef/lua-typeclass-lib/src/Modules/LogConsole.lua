-- ============================================================================
-- WoW Enterprise Logging Framework - LogConsole
-- UI Console for displaying and managing log entries
-- ============================================================================

local ADDON_NAME = ...
local Addon = select(2, ...) or _G.GuildRecruiter
local LogConsole = {}

-- ============================================================================
-- Module Dependencies & Registration
-- ============================================================================

-- Register this module with the package loader
if Addon and Addon.provide then
    Addon.provide("LogConsole", LogConsole)
elseif GuildRecruiter and GuildRecruiter.provide then
    GuildRecruiter.provide("LogConsole", LogConsole)
else
    -- Fallback for direct access
    _G[ADDON_NAME .. "_LogConsole"] = LogConsole
end

-- ============================================================================
-- Configuration & Constants
-- ============================================================================

local CONFIG = {
    DEFAULT_BUFFER_SIZE = 1000,
    DEFAULT_FILTER = "DEBUG",  -- Show all levels by default
    DEFAULT_WIDTH = 800,
    DEFAULT_HEIGHT = 600,
    LOG_LINE_HEIGHT = 16,
    COLORS = {
        DEBUG = {0.7, 0.7, 0.7, 1},   -- Light gray
        INFO = {1, 1, 1, 1},          -- White
        WARN = {1, 0.8, 0, 1},        -- Yellow
        ERROR = {1, 0.4, 0.4, 1},     -- Light red
        FATAL = {1, 0.2, 0.2, 1}      -- Red
    },
    LEVEL_ORDER = {"DEBUG", "INFO", "WARN", "ERROR", "FATAL"},
    LEVEL_VALUES = {DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5}
}

-- ============================================================================
-- State Management
-- ============================================================================

local state = {
    frame = nil,
    scrollFrame = nil,
    logLines = {},
    filteredLines = {},
    isVisible = false,
    currentFilter = CONFIG.DEFAULT_FILTER,
    bufferSize = CONFIG.DEFAULT_BUFFER_SIZE,
    totalLines = 0,
    selectedLine = nil,
    autoScroll = true
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function GetLevelValue(level)
    return CONFIG.LEVEL_VALUES[level] or 0
end

local function ShouldShowLevel(level)
    return GetLevelValue(level) >= GetLevelValue(state.currentFilter)
end

local function ColorizeLevel(level)
    local color = CONFIG.COLORS[level] or CONFIG.COLORS.INFO
    return string.format("|cff%02x%02x%02x%s|r", 
        color[1] * 255, color[2] * 255, color[3] * 255, level)
end

local function FormatLogLine(entry)
    local levelText = ColorizeLevel(entry.level)
    local message = entry.message or "No message"
    
    -- Add context information if available
    local contextInfo = ""
    if entry.context and next(entry.context) then
        local parts = {}
        for k, v in pairs(entry.context) do
            table.insert(parts, k .. "=" .. tostring(v))
        end
        contextInfo = " [" .. table.concat(parts, ", ") .. "]"
    end
    
    return string.format("[%s] %s: %s%s", 
        entry.timestamp or "??:??:??", 
        levelText, 
        message, 
        contextInfo)
end

-- ============================================================================
-- UI Creation Functions
-- ============================================================================

local function CreateMainFrame()
    local frame = CreateFrame("Frame", ADDON_NAME .. "LogConsoleFrame", UIParent)
    frame:SetSize(CONFIG.DEFAULT_WIDTH, CONFIG.DEFAULT_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    
    -- Title Bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(24)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function() frame:StartMoving() end)
    titleBar:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    
    -- Title Text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 5, 0)
    titleText:SetText(ADDON_NAME .. " - Log Console")
    titleText:SetTextColor(1, 1, 1, 1)
    
    frame.titleBar = titleBar
    frame.titleText = titleText
    
    return frame
end

local function CreateControls(parent)
    local controlFrame = CreateFrame("Frame", nil, parent)
    controlFrame:SetHeight(30)
    controlFrame:SetPoint("TOPLEFT", parent.titleBar, "BOTTOMLEFT", 0, -5)
    controlFrame:SetPoint("TOPRIGHT", parent.titleBar, "BOTTOMRIGHT", 0, -5)
    
    -- Filter Dropdown
    local filterLabel = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("LEFT", controlFrame, "LEFT", 5, 0)
    filterLabel:SetText("Filter:")
    
    local filterDropdown = CreateFrame("Frame", ADDON_NAME .. "FilterDropdown", controlFrame, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("LEFT", filterLabel, "RIGHT", 10, 0)
    filterDropdown:SetWidth(100)
    
    local UIDropDownMenu_SetText = rawget(_G, 'UIDropDownMenu_SetText')
    local UIDropDownMenu_Initialize = rawget(_G, 'UIDropDownMenu_Initialize')
    local UIDropDownMenu_CreateInfo = rawget(_G, 'UIDropDownMenu_CreateInfo')
    local UIDropDownMenu_AddButton = rawget(_G, 'UIDropDownMenu_AddButton')
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(filterDropdown, state.currentFilter) end
    if UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(filterDropdown, function(self, level)
        for _, levelName in ipairs(CONFIG.LEVEL_ORDER) do
            local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
            info.text = levelName
            info.value = levelName
            info.func = function()
                LogConsole.SetFilter(levelName)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(filterDropdown, levelName) end
            end
            info.checked = (levelName == state.currentFilter)
            if UIDropDownMenu_AddButton then UIDropDownMenu_AddButton(info, level) end
        end
    end) end
    
    -- Clear Button
    local clearButton = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(60, 22)
    clearButton:SetPoint("LEFT", filterDropdown, "RIGHT", 20, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        LogConsole.ClearLogs()
    end)
    
    -- Stats Button
    local statsButton = CreateFrame("Button", nil, controlFrame, "UIPanelButtonTemplate")
    statsButton:SetSize(60, 22)
    statsButton:SetPoint("LEFT", clearButton, "RIGHT", 5, 0)
    statsButton:SetText("Stats")
    statsButton:SetScript("OnClick", function()
        LogConsole.ShowStats()
    end)
    
    -- Auto-scroll Checkbox
    local autoScrollCheck = CreateFrame("CheckButton", nil, controlFrame, "UICheckButtonTemplate")
    autoScrollCheck:SetPoint("LEFT", statsButton, "RIGHT", 20, 0)
    autoScrollCheck:SetSize(20, 20)
    autoScrollCheck:SetChecked(state.autoScroll)
    
    local autoScrollLabel = controlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoScrollLabel:SetPoint("LEFT", autoScrollCheck, "RIGHT", 5, 0)
    autoScrollLabel:SetText("Auto-scroll")
    
    autoScrollCheck:SetScript("OnClick", function()
        state.autoScroll = autoScrollCheck:GetChecked()
        if state.autoScroll then
            LogConsole.ScrollToBottom()
        end
    end)
    
    -- Close Button
    local closeButton = CreateFrame("Button", nil, controlFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        LogConsole.Hide()
    end)
    
    parent.controls = controlFrame
    parent.filterDropdown = filterDropdown
    parent.clearButton = clearButton
    parent.statsButton = statsButton
    parent.autoScrollCheck = autoScrollCheck
    parent.closeButton = closeButton
end

local function CreateScrollFrame(parent)
    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "LogScrollFrame", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent.controls, "BOTTOMLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 10)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    
    scrollFrame.content = content
    return scrollFrame
end

local function CreateLogLines(parent, count)
    local lines = {}
    for i = 1, count do
        local line = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -(i-1) * CONFIG.LOG_LINE_HEIGHT)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -(i-1) * CONFIG.LOG_LINE_HEIGHT)
        line:SetHeight(CONFIG.LOG_LINE_HEIGHT)
        line:SetJustifyH("LEFT")
        line:SetJustifyV("TOP")
        line:Hide()
        
        -- Enable mouse interaction for copying
        line:EnableMouse(true)
        line:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                LogConsole.CopyLineToClipboard(i)
            end
        end)
        
        lines[i] = line
    end
    return lines
end

-- ============================================================================
-- Core UI Management
-- ============================================================================

local function InitializeUI()
    if state.frame then
        return -- Already initialized
    end
    
    state.frame = CreateMainFrame()
    CreateControls(state.frame)
    state.scrollFrame = CreateScrollFrame(state.frame)
    
    -- Calculate how many lines we can display
    local maxLines = math.floor(state.scrollFrame:GetHeight() / CONFIG.LOG_LINE_HEIGHT)
    state.logLines = CreateLogLines(state.scrollFrame.content, maxLines)
    
    -- Initially hidden
    state.frame:Hide()
    state.isVisible = false
end

local function UpdateDisplay()
    if not state.frame or not state.frame:IsVisible() then
        return
    end
    
    -- Filter logs based on current filter
    state.filteredLines = {}
    for _, entry in ipairs(state.allLogEntries or {}) do
        if ShouldShowLevel(entry.level) then
            table.insert(state.filteredLines, entry)
        end
    end
    
    -- Update visible lines
    local startIndex = math.max(1, #state.filteredLines - #state.logLines + 1)
    for i, line in ipairs(state.logLines) do
        local entryIndex = startIndex + i - 1
        if entryIndex <= #state.filteredLines then
            local entry = state.filteredLines[entryIndex]
            line:SetText(FormatLogLine(entry))
            line:Show()
        else
            line:Hide()
        end
    end
    
    -- Update scroll position
    if state.autoScroll then
        LogConsole.ScrollToBottom()
    end
    
    -- Update content height
    local contentHeight = math.max(#state.filteredLines * CONFIG.LOG_LINE_HEIGHT, state.scrollFrame:GetHeight())
    state.scrollFrame.content:SetHeight(contentHeight)
end

-- ============================================================================
-- Public API
-- ============================================================================

function LogConsole.Show()
    InitializeUI()
    state.frame:Show()
    state.isVisible = true
    UpdateDisplay()
end

function LogConsole.Hide()
    if state.frame then
        state.frame:Hide()
        state.isVisible = false
    end
end

function LogConsole.Toggle()
    if state.isVisible then
        LogConsole.Hide()
    else
        LogConsole.Show()
    end
end

function LogConsole.IsVisible()
    return state.isVisible and state.frame and state.frame:IsVisible()
end

function LogConsole.AddLogEntry(entry)
    -- Initialize log storage if not exists
    if not state.allLogEntries then
        state.allLogEntries = {}
    end
    
    -- Add to main log buffer
    table.insert(state.allLogEntries, entry)
    state.totalLines = state.totalLines + 1
    
    -- Maintain buffer size
    while #state.allLogEntries > state.bufferSize do
        table.remove(state.allLogEntries, 1)
    end
    
    -- Update display if visible
    if state.isVisible then
        UpdateDisplay()
    end
end

function LogConsole.SetFilter(level)
    if CONFIG.LEVEL_VALUES[level] then
        state.currentFilter = level
        UpdateDisplay()
    end
end

function LogConsole.GetFilter()
    return state.currentFilter
end

function LogConsole.SetBufferSize(size)
    if type(size) == "number" and size > 0 then
        state.bufferSize = size
        
        -- Trim existing entries if needed
        if state.allLogEntries and #state.allLogEntries > size then
            local excess = #state.allLogEntries - size
            for i = 1, excess do
                table.remove(state.allLogEntries, 1)
            end
        end
        
        UpdateDisplay()
    end
end

function LogConsole.GetBufferSize()
    return state.bufferSize
end

function LogConsole.ClearLogs()
    state.allLogEntries = {}
    state.totalLines = 0
    UpdateDisplay()
end

function LogConsole.RefreshDisplay()
    UpdateDisplay()
end

function LogConsole.ScrollToBottom()
    if state.scrollFrame then
        local maxScroll = state.scrollFrame:GetVerticalScrollRange()
        state.scrollFrame:SetVerticalScroll(maxScroll)
    end
end

function LogConsole.CopyLineToClipboard(lineIndex)
    if state.filteredLines and state.filteredLines[lineIndex] then
        local entry = state.filteredLines[lineIndex]
        local text = FormatLogLine(entry)
        -- Remove color codes for clipboard
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        
        -- In WoW, we can't directly access clipboard, but we can show the text
        -- Create a simple dialog to display the text for manual copying
        StaticPopupDialogs["LOGCONSOLE_COPY"] = {
            text = "Copy this text:",
            button1 = "OK",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            hasEditBox = true,
            editBoxWidth = 500,
            OnShow = function(self)
                self.editBox:SetText(text)
                self.editBox:HighlightText()
            end,
        }
        StaticPopup_Show("LOGCONSOLE_COPY")
    end
end

function LogConsole.ShowStats()
    local stats = LogConsole.GetStats()
    local message = string.format(
        "Log Console Statistics:\n" ..
        "Total Lines: %d\n" ..
        "Filtered Lines: %d\n" ..
        "Current Filter: %s\n" ..
        "Buffer Size: %d\n" ..
        "Auto-scroll: %s",
        stats.totalLines, 
        stats.filteredLines, 
        stats.currentFilter, 
        stats.bufferSize,
        stats.autoScroll and "Enabled" or "Disabled"
    )
    
    StaticPopupDialogs["LOGCONSOLE_STATS"] = {
        text = message,
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("LOGCONSOLE_STATS")
end

function LogConsole.GetStats()
    return {
        totalLines = state.totalLines,
        filteredLines = state.filteredLines and #state.filteredLines or 0,
        currentFilter = state.currentFilter,
        bufferSize = state.bufferSize,
        isVisible = state.isVisible,
        autoScroll = state.autoScroll
    }
end

-- ============================================================================
-- Console Commands & Integration
-- ============================================================================

-- Create console commands (use a unique key to avoid collisions with other refs)
SLASH_TSLOGSMOD1 = "/tslogs-mod"
SLASH_TSLOGSMOD2 = "/logconsole2"
if not SlashCmdList["TSLOGSMOD"] then
SlashCmdList["TSLOGSMOD"] = function(msg)
    local args = {strsplit(" ", msg:lower())}
    local command = args[1]
    
    if command == "show" then
        LogConsole.Show()
    elseif command == "hide" then
        LogConsole.Hide()
    elseif command == "toggle" or command == "" then
        LogConsole.Toggle()
    elseif command == "clear" then
        LogConsole.ClearLogs()
        print("Log console cleared.")
    elseif command == "stats" then
        LogConsole.ShowStats()
    elseif command == "filter" and args[2] then
        local level = args[2]:upper()
        if CONFIG.LEVEL_VALUES[level] then
            LogConsole.SetFilter(level)
            print("Log filter set to: " .. level)
        else
            print("Invalid log level. Use: DEBUG, INFO, WARN, ERROR, or FATAL")
        end
    elseif command == "size" and args[2] then
        local size = tonumber(args[2])
        if size and size > 0 then
            LogConsole.SetBufferSize(size)
            print("Buffer size set to: " .. size)
        else
            print("Invalid buffer size. Must be a positive number.")
        end
    elseif command == "test" then
        LogConsole.RunTest()
    else
        print("Log Console Commands:")
        print("  /tslogs - Toggle console")
        print("  /tslogs show/hide - Show/hide console")
        print("  /tslogs clear - Clear all logs")
        print("  /tslogs stats - Show statistics")
        print("  /tslogs filter <level> - Set filter level")
        print("  /tslogs size <number> - Set buffer size")
        print("  /tslogs test - Run test sequence")
    end
end
end

-- ============================================================================
-- Testing & Demonstration
-- ============================================================================

function LogConsole.RunTest()
    LogConsole.Show()
    
    -- Simulate various log entries
    local testEntries = {
        {level = "DEBUG", message = "Debug test message", timestamp = "12:00:01"},
        {level = "INFO", message = "Information test message", timestamp = "12:00:02"},
        {level = "WARN", message = "Warning test message", timestamp = "12:00:03"},
        {level = "ERROR", message = "Error test message", timestamp = "12:00:04"},
        {level = "FATAL", message = "Fatal test message", timestamp = "12:00:05"},
        {level = "INFO", message = "Message with context", timestamp = "12:00:06", context = {module = "Test", player = "TestPlayer"}},
    }
    
    for _, entry in ipairs(testEntries) do
        LogConsole.AddLogEntry(entry)
    end
    
    print("Test entries added to log console.")
end

-- ============================================================================
-- Auto-Registration with Logger (if available)
-- ============================================================================

-- Register as a sink with the Logger if it's available
local function RegisterWithLogger()
    local success, Logger = pcall(function()
        if Addon and Addon.require then
            return Addon.require("Logger")
        elseif GuildRecruiter and GuildRecruiter.require then
            return GuildRecruiter.require("Logger")
        end
        return nil
    end)
    
    if success and Logger and Logger.AddSink then
        Logger.AddSink(LogConsole.AddLogEntry, 1, "LogConsole")  -- Accept all levels
        print(ADDON_NAME .. ": LogConsole registered with Logger")
    end
end

-- Delay registration to ensure Logger is loaded first
C_Timer.After(1, RegisterWithLogger)

-- ============================================================================
-- Module Export
-- ============================================================================

return LogConsole