-- Commands.lua — central slash/command registry
---@diagnostic disable: undefined-global
local t = {...}; local ADDON_NAME = t[1]; local Addon = t[2]

local function println(msg)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME, tostring(msg)))
end

-- Show main UI
local function toggleMainUI()
    if Addon.UI and Addon.UI.Show then
        Addon.UI:Show()
        return
    end
    local mf = _G["GuildRecruiterFrame"]
    if mf then
        if mf:IsShown() then mf:Hide() else mf:Show() end
    else
        println("Main UI not ready yet.")
    end
end

-- Open settings
local function openSettings()
    local id = Addon._OptionsCategoryID or (Addon and Addon.TITLE) or "Guild Prospector"
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(id)
    else
        println("Settings not available.")
    end
end

-- Parse command args
local function parseArgs(msg)
    local t = {}
    for w in msg:gmatch("%S+") do table.insert(t, w) end
    return t
end

local function handleSlash(msg)
    -- Delegate to Application.SlashCommandHandler if present
    local Handler = Addon.require and Addon.require("Application.SlashCommandHandler")
    if Handler and Handler.new then
        local ok, inst = pcall(Handler.new)
        if ok and inst and inst.Handle then return inst:Handle(msg) end
    end
    -- Minimal fallback if handler not found
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg == "test" or msg == "tests" then
        local addon = _G[ADDON_NAME]; if addon and addon.RunInGameTests then addon.RunInGameTests() else println("In-game test runner not loaded.") end; return
    end
    if msg == "" or msg == "ui" or msg == "toggle" then toggleMainUI(); return end
    if msg == "settings" or msg == "options" then openSettings(); return end
    println("Unknown command. Try /gr help.")
end

-- Slash aliases
SLASH_GUILDRECRUITER1 = "/gr"            -- legacy short
SLASH_GUILDRECRUITER2 = "/guildrecruiter" -- legacy long
SLASH_GUILDRECRUITER3 = "/guildrec"       -- legacy alt
SLASH_GUILDPROSPECTOR1 = "/gp"            -- new short alias
SLASH_GUILDPROSPECTOR2 = "/guildprospector" -- new long alias
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.GUILDRECRUITER = handleSlash
_G.SlashCmdList.GUILDPROSPECTOR = handleSlash

-- Direct settings aliases (bypass parser and open settings immediately)
SLASH_GRSETTINGS1 = "/grsettings"
SLASH_GROPTIONS1  = "/groptions"
_G.SlashCmdList.GRSETTINGS = function()
    local Addon = _G[ADDON_NAME]
    if Addon and Addon.OpenSettings then Addon.OpenSettings() else handleSlash("settings") end
end
_G.SlashCmdList.GROPTIONS = _G.SlashCmdList.GRSETTINGS
