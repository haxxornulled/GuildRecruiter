---@diagnostic disable: missing-fields, undefined-field, need-check-nil
---@class Texture @forward declare for language server if stubs not loaded yet
---@class GRMainUI : table
---@field frame Frame|nil Main frame reference
---@field host table|nil Tabs host object
---@field portrait Texture|nil Player portrait texture
---@field Build fun(self:GRMainUI)
---@field Show fun(self:GRMainUI)
---@field Hide fun(self:GRMainUI)
---@field Toggle fun(self:GRMainUI)
---@field AddCategory fun(self:GRMainUI, def:table)
---@field AddSeparator fun(self:GRMainUI, opts:table|nil)
---@field RemoveCategory fun(self:GRMainUI, key:string)
---@field SetCategoryVisible fun(self:GRMainUI, key:string, visible:boolean)
---@field RegisterCategoryDecorator fun(self:GRMainUI, key:string, fn:function)
---@field ListCategories fun(self:GRMainUI):table
---@field SelectCategoryByKey fun(self:GRMainUI, key:string):boolean
---@field RefreshCategories fun(self:GRMainUI)
---@field UpdatePortrait fun(self:GRMainUI)
---@field ShowToast fun(self:GRMainUI, msg:string, hold:number|nil)

---@class GRCategoryManager
---@field EnsureInitialized fun(self:GRCategoryManager)
---@field AddCategory fun(self:GRCategoryManager, def:table)
---@field AddSeparator fun(self:GRCategoryManager, order:number|nil)
---@field RemoveCategory fun(self:GRCategoryManager, key:string)
---@field SetCategoryVisible fun(self:GRCategoryManager, key:string, visible:boolean|function)
---@field RegisterCategoryDecorator fun(self:GRCategoryManager, key:string, fn:function|nil)
---@field ApplyDecorators fun(self:GRCategoryManager)
---@field ListCategories fun(self:GRCategoryManager):table
---@field SelectCategoryByKey fun(self:GRCategoryManager, key:string):boolean

local ADDON_NAME = 'GuildRecruiter'
local Addon = _G[ADDON_NAME] or {}
local UI = {} ---@type GRMainUI
Addon.UI = Addon.UI or {}
Addon.UI.Main = UI

-- DI registration (single instance)
if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('UI.Main')) then
    Addon.safeProvide('UI.Main', function() return UI end, { lifetime = 'SingleInstance' })
elseif Addon.provide and not (Addon.IsProvided and Addon.IsProvided('UI.Main')) then
    Addon.provide('UI.Main', function() return UI end, { lifetime = 'SingleInstance' })
end

---@return table|nil
local function CATM()
    ---@type GRCategoryManager|nil
    local cm = (Addon.Get and (Addon.Get('UI.CategoryManager') or Addon.Get('Tools.CategoryManager'))) or nil
    if cm then -- runtime safety; linter previously flagged redundant guard
        pcall(function() cm:EnsureInitialized() end)
    end
    return cm
end

---@return table|nil
local function CFG()
    return (Addon.Get and Addon.Get('IConfiguration')) or (Addon.require and Addon.require('IConfiguration')) or
        Addon.Config
end

---@return table|nil
local function LOG()
    local L = Addon.Logger
    return (L and L.ForContext and L:ForContext('UI.Main')) or nil
end

local frame, host, portrait

-- Provide fallback Mixin implementation if Blizzard's isn't available (for analyzer friendliness)
local Mixin = _G.Mixin or function(obj, ...)
    for i = 1, select('#', ...) do
        local mix = select(i, ...)
        if type(mix) == 'table' then
            for k, v in pairs(mix) do obj[k] = v end
        end
    end
    return obj
end

-- Main frame mixin (conversion from procedural Build)
local GuildRecruiterMainFrameMixin = {}

function GuildRecruiterMainFrameMixin:OnLoad()
    -- Optional callback registry integration (Blizzard CallbackRegistryMixin if present)
    local CRM = rawget(_G, 'CallbackRegistryMixin')
    if CRM and not self._grCallbacksInit then
        Mixin(self, CRM)
        pcall(CRM.OnLoad, self)
        if self.GenerateCallbackEvents then
            -- Events consumers can listen to for finer grained UI reactions
            self:GenerateCallbackEvents({ 'GR_MAIN_SHOWN', 'GR_MAIN_HIDDEN', 'GR_CATEGORIES_REFRESHED' })
        end
        self._grCallbacksInit = true
    end
end

---@return table|nil
local function TOAST()
    return (Addon.Get and (Addon.Get('IToastService') or Addon.Get('ToastService'))) or
        (Addon.require and (Addon.require('IToastService') or Addon.require('ToastService')))
end

---@param f Frame
local function LoadFrameState(f)
    local cfg = CFG(); if not (cfg and f) then return end
    local w = tonumber(cfg:Get('ui_main_w'))
    local h = tonumber(cfg:Get('ui_main_h'))
    local l = tonumber(cfg:Get('ui_main_l'))
    local t = tonumber(cfg:Get('ui_main_t'))
    if w and h and w > 300 and h > 300 then f:SetSize(math.min(w, 1400), math.min(h, 1000)) end
    if l and t then
        f:ClearAllPoints(); f:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l, t)
    end
end

---@param f Frame
local function SaveFrameState(f)
    local cfg = CFG(); if not (cfg and f) then return end
    if f.GetWidth then
        cfg:Set('ui_main_w', math.floor((f:GetWidth() or 0) + 0.5))
        cfg:Set('ui_main_h', math.floor((f:GetHeight() or 0) + 0.5))
    end
    local L = f:GetLeft(); local T = f:GetTop()
    if L and T then
        cfg:Set('ui_main_l', math.floor(L + 0.5))
        cfg:Set('ui_main_t', math.floor(T + 0.5))
    end
end

function UI:Build()
    if frame then return end
    frame = CreateFrame('Frame', 'GuildRecruiterFrame', UIParent)
    Mixin(frame, GuildRecruiterMainFrameMixin)
    if frame.OnLoad then pcall(frame.OnLoad, frame) end
    -- Lightweight callback registry fallback
    if not frame.TriggerEvent then
        local listeners = {}
        function frame:Register(event, fn)
            if not event or type(fn) ~= 'function' then return end
            local list = listeners[event]; if not list then
                list = {}; listeners[event] = list
            end
            list[#list + 1] = fn; return fn
        end

        function frame:Unregister(event, fn)
            local list = listeners[event]; if not list then return end
            for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
        end

        function frame:TriggerEvent(event, ...)
            local list = listeners[event]; if not list then return end
            for i = 1, #list do
                local cb = list[i]; if cb then pcall(cb, event, ...) end
            end
        end
    end
    frame:SetSize(940, 560)
    frame:SetPoint('CENTER')
    -- Use MEDIUM so fullscreen UI like the World Map (HIGH/DIALOG) will overlay us.
    frame:SetFrameStrata('MEDIUM')
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', frame.StartMoving)
    frame:SetScript('OnDragStop', function(s)
        s:StopMovingOrSizing(); SaveFrameState(s)
    end)
    LoadFrameState(frame)
    pcall(function() if frame.SetTitle then frame:SetTitle('Guild Prospector') end end)
    local title = (Addon and Addon.TITLE) or 'Guild Prospector'
    pcall(function() if frame.SetTitle then frame:SetTitle(title) end end)

    local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT', -6, -6)
    close:SetScript('OnClick', function() UI:Hide() end)

    local bg = frame:CreateTexture(nil, 'BACKGROUND', nil, -8)
    bg:SetPoint('TOPLEFT', 2, -2)
    bg:SetPoint('BOTTOMRIGHT', -2, 2)
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.55)

    portrait = frame:CreateTexture(nil, 'ARTWORK')
    portrait:SetSize(48, 48)
    portrait:SetPoint('TOPLEFT', 10, -8)
    pcall(portrait.SetMask, portrait, 'Interface/CharacterFrame/TempPortraitAlphaMask')

    local HostMod = (Addon.Get and Addon.Get('UI.MainTabsHost')) or (Addon.require and Addon.require('UI.MainTabsHost'))
    if not HostMod then
        local log = LOG(); if log and log.Warn then log:Warn('MainTabsHost missing') end
    end
    host = HostMod and HostMod:Create(frame, { tabWidth = 140 }) or nil

    -- World Map overlap mitigation: lower our strata & hide portrait while map is visible.
    local function SetupMapOverlapMitigation()
        local map = _G.WorldMapFrame
        if not map or not frame or frame._grStrataHooked then return end
        local function apply()
            if not frame then return end
            if map:IsShown() then
                frame:SetFrameStrata('LOW')
                portrait:Hide()
            else
                frame:SetFrameStrata('MEDIUM')
                portrait:Show()
            end
        end
        apply() -- initial state
        map:HookScript('OnShow', apply)
        map:HookScript('OnHide', apply)
        frame._grStrataHooked = true
    end
    SetupMapOverlapMitigation()

    self:UpdatePortrait()

    local bus = (Addon.Get and Addon.Get('EventBus')) or (Addon.require and Addon.require('EventBus')) or Addon.EventBus
    if bus and bus.Subscribe then
        if host then
            bus:Subscribe('CategoriesChanged', function()
                if host and host.RebuildTabs then host:RebuildTabs() end
            end)
        end
        bus:Subscribe('CategorySelected', function(key)
            if not (host and host.tabs and host.tabs.GetSelected) then return end
            local sel = host.tabs:GetSelected()
            if not sel or sel.id ~= key then
                if host.RebuildTabs then host:RebuildTabs() end
                if host.tabs.SelectTab then host.tabs:SelectTab(key, true) end
            end
        end)
    end

    if host and host.tabs then
        local first = host.tabs:ListTabs()[1]
        if first then host.tabs:SelectTab(first.id, true) end
    end
    if frame.TriggerEvent then frame:TriggerEvent('GR_CATEGORIES_REFRESHED') end
end

function UI:Show()
    if InCombatLockdown() then
        print('|cffff5555[GuildRecruiter]|r Cannot open UI in combat.')
        return
    end
    if not frame then self:Build() end
    frame:Show(); if frame.TriggerEvent then frame:TriggerEvent('GR_MAIN_SHOWN') end
end

function UI:Hide()
    if not frame then return end
    frame:Hide(); if frame.TriggerEvent then frame:TriggerEvent('GR_MAIN_HIDDEN') end
end

function UI:Toggle()
    if not frame or not frame:IsShown() then self:Show() else self:Hide() end
end

---@param d table
function UI:AddCategory(d)
    local cm = CATM(); if cm and cm.AddCategory then cm:AddCategory(d) end
end

---@param o table|nil
function UI:AddSeparator(o)
    local cm = CATM(); if cm and cm.AddSeparator then cm:AddSeparator(o) end
end

---@param k string
function UI:RemoveCategory(k)
    local cm = CATM(); if cm and cm.RemoveCategory then cm:RemoveCategory(k) end
end

---@param k string
---@param v boolean
function UI:SetCategoryVisible(k, v)
    local cm = CATM(); if cm and cm.SetCategoryVisible then cm:SetCategoryVisible(k, v) end
end

---@param k string
---@param fn function
function UI:RegisterCategoryDecorator(k, fn)
    local cm = CATM(); if cm and cm.RegisterCategoryDecorator then cm:RegisterCategoryDecorator(k, fn) end
end

---@return table
function UI:ListCategories()
    local cm = CATM(); return (cm and cm:ListCategories()) or {}
end

---@param k string
---@return boolean
function UI:SelectCategoryByKey(k)
    local cm = CATM(); if cm and cm.SelectCategoryByKey then return cm:SelectCategoryByKey(k) end
    return false
end

function UI:RefreshCategories()
    local cm = CATM(); if cm and cm.ApplyDecorators then cm:ApplyDecorators() end
    if host and host.RebuildTabs then host:RebuildTabs() end
    if frame and frame.TriggerEvent then frame:TriggerEvent('GR_CATEGORIES_REFRESHED') end
end

function UI:UpdatePortrait()
    if not portrait then return end -- guard: events can fire before Build creates portrait
    local SPT = rawget(_G, 'SetPortraitTexture')
    local ok = type(SPT) == 'function' and pcall(SPT, portrait, 'player') or false
    if not ok or not portrait:GetTexture() then
        local UCFn = rawget(_G, 'UnitClass')
        local class = (type(UCFn) == 'function' and select(2, UCFn('player'))) or 'PRIEST'
        local coords = rawget(_G, 'CLASS_ICON_TCOORDS'); coords = coords and coords[class]
        pcall(portrait.ClearMask, portrait)
        portrait:SetTexture('Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES')
        if coords then
            portrait:SetTexCoord(unpack(coords))
        else
            portrait:SetTexCoord(0, 1, 0, 1)
        end
    end
end

local pe = CreateFrame('Frame')
pe:RegisterEvent('PLAYER_ENTERING_WORLD')
pe:RegisterEvent('UNIT_PORTRAIT_UPDATE')
pe:SetScript('OnEvent', function(_, ev, u)
    if ev == 'UNIT_PORTRAIT_UPDATE' and u ~= 'player' then return end
    UI:UpdatePortrait()
end)

---@param msg string
---@param hold number|nil
function UI:ShowToast(msg, hold)
    local svc = TOAST()
    if svc and svc.Show then svc:Show(msg, hold) else if msg and msg ~= '' then print('|cffffaa33[GR]|r ' .. msg) end end
end

return UI
