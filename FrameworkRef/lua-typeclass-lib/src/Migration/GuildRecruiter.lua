-- GuildRecruiter.lua - Addon Entrypoint
-- FIXED: Proper initialization order and error handling

-- Ensure Core is loaded first
local Core = _G.GuildRecruiterCore
if not Core then
    error("GuildRecruiterCore not loaded! Make sure Domain/Core.lua is loaded before this file.")
end

-- Only initialize the export table if it does not exist (to avoid wiping data)
if _G.GuildRecruiter_ExportData == nil then
    _G.GuildRecruiter_ExportData = {}
end

-- Helper for other modules to save data to the export table
function _G.GuildRecruiter_SaveExportData(record)
    if type(record) == "table" then
        table.insert(_G.GuildRecruiter_ExportData, record)
    else
        -- Optionally log or raise error for invalid data
        print("|cffff0000[GuildRecruiter]|r Tried to save invalid export data!")
    end
end

-- Main initialization frame
local frame = CreateFrame("Frame", "GuildRecruiterMainFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function InitializeAddon()
    print("|cff33ff99[GuildRecruiter]|r Starting addon initialization...")
    
    -- Initialize the global namespace
    _G.GuildRecruiter = _G.GuildRecruiter or {}
    
    -- Initialize core services
    local success, error = pcall(function()
        Core.InitAll()
    end)
    
    if not success then
        print("|cffff0000[GuildRecruiter]|r CRITICAL ERROR during initialization: " .. tostring(error))
        return false
    end
    
    -- Initialize WoWApiAdapter instance specifically
    local apiAdapter
    success, error = pcall(function()
        apiAdapter = Core.Resolve("WoWApiAdapter")
    end)
    
    if success and apiAdapter then
        _G.GuildRecruiter.WoWApiAdapter = { Instance = apiAdapter }
        print("|cff33ff99[GuildRecruiter]|r WoWApiAdapter initialized successfully")
    else
        print("|cffff0000[GuildRecruiter]|r Failed to initialize WoWApiAdapter: " .. tostring(error))
    end
    
    -- Initialize Logger
    local logger
    success, error = pcall(function()
        logger = Core.Resolve("Logger")
    end)
    
    if success and logger then
        _G.GuildRecruiter.Logger = logger
        logger:Info("GuildRecruiter addon initialized successfully")
    else
        print("|cffff0000[GuildRecruiter]|r Failed to initialize Logger: " .. tostring(error))
    end
    
    -- Initialize RecruitmentService and start listening for whispers
    local recruitmentService
    success, error = pcall(function()
        recruitmentService = Core.Resolve("RecruitmentService")
        if recruitmentService and recruitmentService.InitListeners then
            recruitmentService.InitListeners()
        end
    end)
    
    if success then
        print("|cff33ff99[GuildRecruiter]|r RecruitmentService initialized")
    else
        print("|cffff0000[GuildRecruiter]|r Failed to initialize RecruitmentService: " .. tostring(error))
    end
    
    print("|cff33ff99[GuildRecruiter]|r Addon initialization complete!")
    print("|cff33ff99[GuildRecruiter]|r Use /gr help for available commands")
    
    return true
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "GuildRecruiter" then
        print("|cff33ff99[GuildRecruiter]|r Addon loaded, waiting for player login...")
        
    elseif event == "PLAYER_LOGIN" then
        -- Small delay to ensure all Blizzard APIs are ready
        C_Timer.After(1, function()
            InitializeAddon()
        end)
        
        -- Unregister events since we only need them once
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Add a global function to reinitialize if needed
function _G.GuildRecruiter_Reinitialize()
    print("|cff33ff99[GuildRecruiter]|r Attempting to reinitialize addon...")
    return InitializeAddon()
end

-- Add diagnostic function
function _G.GuildRecruiter_Diagnose()
    print("|cff33ff99[GuildRecruiter]|r Running full diagnostic...")
    
    print("Core exists:", _G.GuildRecruiterCore ~= nil)
    print("GuildRecruiter table exists:", _G.GuildRecruiter ~= nil)
    
    if _G.GuildRecruiterCore then
        _G.GuildRecruiterCore.DiagnoseServices()
    end
    
    if IsInGuild() then
        print("Player is in guild:", GetGuildInfo("player") or "Unknown")
        print("Guild members:", GetNumGuildMembers())
    else
        print("Player is not in a guild")
    end
end