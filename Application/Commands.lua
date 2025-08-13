-- Commands.lua — central slash/command registry
---@diagnostic disable: undefined-global
local ADDON_NAME, Addon = ...

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
    local id = Addon._OptionsCategoryID or "Guild Recruiter"
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
    if msg == "" or msg == "ui" or msg == "toggle" then toggleMainUI(); return
    elseif msg == "settings" or msg == "options" then openSettings(); return
    else println("Unknown command. Try /gr help.") end
end

-- Slash aliases
SLASH_GUILDRECRUITER1 = "/gr"
SLASH_GUILDRECRUITER2 = "/guildrecruiter"
SLASH_GUILDRECRUITER3 = "/guildrec"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList.GUILDRECRUITER = handleSlash
