-- Application/SlashCommandHandler.lua
-- Concrete implementation for slash commands, delegating to services/UI
---@diagnostic disable: undefined-global

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})

local Handler = {}
Handler.__index = Handler

local function printf(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME or "GR", tostring(msg))) end
end

local function Args(msg)
    local t = {}
    if not msg then return t end
    for w in tostring(msg):gmatch("%S+") do t[#t + 1] = w end
    return t
end

function Handler.new()
    return setmetatable({}, Handler)
end

local function loadFactory()
    if Addon.require then
        local ok, mod = pcall(Addon.require, 'Application.SlashCommandsFactory')
        if ok and mod and mod.Build then return mod end
    end
    -- fallback to global if provided
    return Addon.SlashCommandsFactory or (Addon.Get and Addon.Get('SlashCommandsFactory'))
end

function Handler:Help()
    if not self._help then
        local factory = loadFactory()
        if factory and factory.Build then
            local bundle = factory.Build()
            self._help = bundle.help or {}
            self._dispatch = bundle.dispatch or {}
            self._argsFn = bundle.Args
            self._meta = bundle.meta or {}
            self._validate = bundle.validate
            self._completion = bundle.completion or {}
            -- expose completion globally for any UI auto-complete consumer
            _G.GuildProspectorCommandCompletion = self._completion
        else
            self._help = { 'Slash command help unavailable (factory missing).' }
            self._dispatch = {}
        end
    end
    return self._help
end

function Handler:Handle(msg)
    msg = tostring(msg or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if not self._dispatch then self:Help() end -- lazy init
    local dispatch = self._dispatch or {}
    local argsFn = self._argsFn or Args
    if msg == '' then return (dispatch.ui or function() printf('Main UI command unavailable.') end)(self, {}) end
    -- If ui command not yet registered, try late-load attempt once
    if not dispatch.ui and Addon and Addon.require then
        local tried = self._triedLateLoad
        if not tried then
            self._triedLateLoad = true
            pcall(Addon.require, 'UI.CompositionRoot')
            pcall(Addon.require, 'UI.UI_MainFrame')
            local factory = loadFactory(); if factory and factory.Build then local bundle = factory.Build(); self._dispatch = bundle.dispatch or self._dispatch end
            dispatch = self._dispatch or dispatch
        end
        if msg == '' then return (dispatch.ui or function() printf('Main UI not ready (loading...).') end)(self,{}) end
    end
    local args = argsFn(msg)
    local key = string.lower(args[1] or '')
    if key == 'diag' and args[2] == 'layers' then key = 'diag' end
    local fn = dispatch[key]
    if fn then
        -- schema validation (only if validator present)
        if self._validate then
            local ok, err = self._validate(key, args)
            if not ok then printf('Arg error: ' .. tostring(err)); return end
        end
        fn(self, args); return
    end
    if key == 'toggle' and dispatch.ui then dispatch.ui(self, args); return end
    if key == 'help' and dispatch.help then dispatch.help(self, args); return end
    printf('Unknown command. Try /gr help or /gp help.')
end

if Addon.provide then
    Addon.provide('Application.SlashCommandHandler', Handler, { lifetime = 'SingleInstance', meta = { layer = 'Application', area = 'ui/commands' } })
    Addon.provide('ISlashCommandHandler', Handler, { lifetime = 'SingleInstance', meta = { layer = 'Application', area = 'ui/commands', alias = true } })
end
return Handler
