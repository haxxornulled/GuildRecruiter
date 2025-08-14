-- tools/SlashCommandsTestHarness.lua
-- Lightweight headless harness to exercise slash command dispatch outside WoW UI frames.
-- Usage (in game dev console or test environment):
--   /run GuildProspectorTest('stats')
-- This will simulate entering a slash command text and route through handler.
---@diagnostic disable: undefined-global
local p = { ... }
local ADDON_NAME = p[1] or 'GuildRecruiter'
local Addon = p[2] or _G[ADDON_NAME] or {}

local function ensureHandler()
    local HandlerMod = Addon and Addon.require and Addon.require('Application.SlashCommandHandler')
    if HandlerMod and HandlerMod.new then
        local ok, inst = pcall(HandlerMod.new)
        if ok then return inst end
    end
end

_G.GuildProspectorTest = function(msg)
    local handler = ensureHandler()
    if not handler then
        print('[GP-Test] Handler unavailable.')
        return
    end
    print('[GP-Test] >> ' .. tostring(msg))
    handler:Handle(msg)
end

return true
