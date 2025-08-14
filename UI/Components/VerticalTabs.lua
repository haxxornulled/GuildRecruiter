-- UI/Components/VerticalTabs.lua
-- Vertical tab control with animated sliding content panes.
-- Features:
--  * Flush-left vertical tab strip
--  * Optional icon per tab + text label (label to right of icon)
--  * "Hanging" text effect: label slightly overlaps (bleeds) into content region
--  * 250ms ease-out horizontal slide animation for content transitions
--  * Dynamic tab add / remove / select at runtime
--  * Fixed tab column; only content pane animates (old pane slides out / is hidden)
--  * Builder callback per tab used to lazily create content frame (cached)
--  * Minimal API surface:
--        local vt = VerticalTabs:Create(parent, opts)
--        vt:AddTab(id, label, iconPath, builderFn [, order])
--        vt:RemoveTab(id)
--        vt:SelectTab(id[, instant])
--        vt:ListTabs() -> array of { id, label }
--  * Fires callback opts.onTabSelected(id, frame) after animation completes
--  * Basic theming options via opts:
--        tabWidth (default 120), overlap (default 16), contentPadding (default 8)
--        slideDuration (default 0.25), hideInactive (default true)
--        buttonHeight (default 26)
---@diagnostic disable: undefined-global, undefined-field, inject-field

local VerticalTabs = {}
VerticalTabs.__index = VerticalTabs

-- Factory
function VerticalTabs:Create(parent, opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.parent = parent
    o.opts = opts
    o.tabWidth = opts.tabWidth or 120
    o.buttonHeight = opts.buttonHeight or 26
    o.overlap = opts.overlap or 16         -- how many pixels label bleeds into content
    o.slideDuration = opts.slideDuration or 0.25
    o.contentPadding = opts.contentPadding or 8
    o.hideInactive = opts.hideInactive ~= false
    o.onTabSelected = opts.onTabSelected
    o.tabs = {}          -- ordered list entries
    o.tabIndex = {}      -- id -> entry
    o.selectedId = nil
    o.animating = false

    local frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints()
    o.frame = frame

    local tabCol = CreateFrame('Frame', nil, frame)
    tabCol:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
    tabCol:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
    tabCol:SetWidth(o.tabWidth - o.overlap)
    o.tabCol = tabCol

    local content = CreateFrame('Frame', nil, frame)
    content:SetPoint('TOPLEFT', frame, 'TOPLEFT', o.tabWidth - o.overlap, 0)
    content:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    o.contentHost = content

    if not opts.noBackground then
        local bg = content:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(); bg:SetColorTexture(0.07, 0.07, 0.09, 0.85)
        local edge = content:CreateTexture(nil, 'BORDER')
        edge:SetPoint('TOPLEFT', content, 'TOPLEFT', -1, 1)
        edge:SetPoint('BOTTOMLEFT', content, 'BOTTOMLEFT', -1, -1)
        edge:SetWidth(1)
        edge:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    end
    return o
end

local function sortTabs(a, b)
    local oa, ob = a.order or 0, b.order or 0
    if oa ~= ob then return oa < ob end
    return tostring(a.label) < tostring(b.label)
end

function VerticalTabs:_layoutTabs()
    local prev
    for _, t in ipairs(self.tabs) do
        local btn = t.button
        btn:ClearAllPoints()
        if not prev then
            btn:SetPoint('TOPLEFT', self.tabCol, 'TOPLEFT', 0, -4)
        else
            btn:SetPoint('TOPLEFT', prev, 'BOTTOMLEFT', 0, -2)
        end
        btn:SetPoint('RIGHT', self.contentHost, 'LEFT', 0, 0)
        prev = btn
    end
end

function VerticalTabs:_refreshButtonStates()
    for _, t in ipairs(self.tabs) do
        local sel = (t.id == self.selectedId)
        local fs = t.button:GetFontString()
        if sel then
            fs:SetTextColor(1, 0.95, 0.7)
            if t.button._bg then t.button._bg:SetColorTexture(0.25, 0.22, 0.15, 0.85) end
        else
            fs:SetTextColor(0.85, 0.85, 0.9)
            if t.button._bg then t.button._bg:SetColorTexture(0.12, 0.12, 0.15, 0.6) end
        end
    end
end

function VerticalTabs:_resort()
    table.sort(self.tabs, sortTabs)
    self:_layoutTabs()
    self:_refreshButtonStates()
end

function VerticalTabs:_updateButton(entry)
    local btn = entry.button; if not btn then return end
    btn:SetText(entry.label or entry.id)
    if entry.icon then
        if not btn._icon then
            local tex = btn:CreateTexture(nil, 'ARTWORK')
            tex:SetSize(self.buttonHeight - 6, self.buttonHeight - 6)
            tex:SetPoint('LEFT', btn, 'LEFT', 6, 0)
            btn._icon = tex
        end
        btn._icon:SetTexture(entry.icon)
        local fs = btn:GetFontString(); fs:ClearAllPoints(); fs:SetPoint('LEFT', btn._icon, 'RIGHT', 6, 0); fs:SetPoint('RIGHT', btn, 'RIGHT', -6, 0)
    else
        if btn._icon then btn._icon:Hide() end
        local fs = btn:GetFontString(); fs:ClearAllPoints(); fs:SetPoint('LEFT', btn, 'LEFT', 10, 0); fs:SetPoint('RIGHT', btn, 'RIGHT', -6, 0)
    end
end

function VerticalTabs:AddTab(id, label, icon, builder, order)
    assert(type(id) == 'string' and id ~= '', 'AddTab: id required')
    label = label or id
    local existing = self.tabIndex[id]
    if existing then
        existing.label = label; existing.icon = icon; if builder then existing.builder = builder end; existing.order = order or existing.order
        self:_updateButton(existing); self:_resort(); return existing
    end
    local btn = CreateFrame('Button', nil, self.frame, 'UIPanelButtonTemplate')
    btn:SetHeight(self.buttonHeight)
    btn:SetText(label)
    btn:SetNormalFontObject('GameFontHighlightSmall')
    btn:SetHighlightFontObject('GameFontNormalSmall')
    btn._id = id
    btn:SetWidth(self.tabWidth + 40)
    if icon then
        local tex = btn:CreateTexture(nil, 'ARTWORK')
        tex:SetSize(self.buttonHeight - 6, self.buttonHeight - 6)
        tex:SetPoint('LEFT', btn, 'LEFT', 6, 0)
        tex:SetTexture(icon)
        btn._icon = tex
        local fs = btn:GetFontString(); fs:ClearAllPoints(); fs:SetPoint('LEFT', tex, 'RIGHT', 6, 0); fs:SetPoint('RIGHT', btn, 'RIGHT', -6, 0)
    else
        local fs = btn:GetFontString(); fs:ClearAllPoints(); fs:SetPoint('LEFT', btn, 'LEFT', 10, 0); fs:SetPoint('RIGHT', btn, 'RIGHT', -6, 0)
    end
    if not btn._bg then
        local bg = btn:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.12, 0.15, 0.6)
        btn._bg = bg
    end
    btn:SetScript('OnClick', function() self:SelectTab(id) end)
    local entry = { id = id, label = label, icon = icon, builder = builder, order = order, button = btn, frame = nil }
    table.insert(self.tabs, entry); self.tabIndex[id] = entry
    self:_resort()
    if not self.selectedId then self:SelectTab(id, true) end
    return entry
end

function VerticalTabs:RemoveTab(id)
    local entry = self.tabIndex[id]; if not entry then return end
    local wasSelected = (self.selectedId == id)
    if entry.frame then entry.frame:Hide(); entry.frame:SetParent(nil) end
    if entry.button then entry.button:Hide(); entry.button:SetParent(nil) end
    self.tabIndex[id] = nil
    for i, t in ipairs(self.tabs) do if t.id == id then table.remove(self.tabs, i); break end end
    self:_layoutTabs()
    if wasSelected then
        local newSel = self.tabs[1] and self.tabs[1].id or nil
        self.selectedId = nil
        if newSel then self:SelectTab(newSel, true) end
    else
        self:_refreshButtonStates()
    end
end

function VerticalTabs:_ensureFrame(entry)
    if entry.frame and not entry.frame:IsForbidden() then return entry.frame end
    local f = CreateFrame('Frame', nil, self.contentHost)
    f:SetPoint('TOPLEFT', self.contentHost, 'TOPLEFT', self.contentPadding, -self.contentPadding)
    f:SetPoint('BOTTOMRIGHT', self.contentHost, 'BOTTOMRIGHT', -self.contentPadding, self.contentPadding)
    entry.frame = f
    if entry.builder and type(entry.builder) == 'function' then
        local ok, err = pcall(entry.builder, f)
        if not ok then
            local fs = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
            fs:SetPoint('CENTER'); fs:SetText('|cffff5555Builder error:|r '..tostring(err))
        end
    else
        local fs = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        fs:SetPoint('CENTER'); fs:SetText('No content')
    end
    if self.hideInactive then f:Hide() end
    return f
end

function VerticalTabs:SelectTab(id, instant)
    if self.animating then return end
    local entry = self.tabIndex[id]; if not entry or id == self.selectedId then return end
    local previous = self.tabIndex[self.selectedId]
    local newFrame = self:_ensureFrame(entry)
    local oldFrame = previous and previous.frame or nil
    self.selectedId = id; self:_refreshButtonStates()
    if instant then
        if oldFrame and self.hideInactive then oldFrame:Hide() end
        newFrame:ClearAllPoints()
        newFrame:SetPoint('TOPLEFT', self.contentHost, 'TOPLEFT', self.contentPadding, -self.contentPadding)
        newFrame:SetPoint('BOTTOMRIGHT', self.contentHost, 'BOTTOMRIGHT', -self.contentPadding, self.contentPadding)
        newFrame:Show()
        if oldFrame and not self.hideInactive then oldFrame:Hide() end
        if self.onTabSelected then pcall(self.onTabSelected, id, newFrame) end
        return
    end
    local w = self.contentHost:GetWidth() or 400
    newFrame:ClearAllPoints()
    newFrame:SetPoint('TOPLEFT', self.contentHost, 'TOPLEFT', -w * 0.35, -self.contentPadding)
    newFrame:SetPoint('BOTTOMRIGHT', self.contentHost, 'BOTTOMRIGHT', -w - 40, self.contentPadding)
    newFrame:Show()
    local agNew = newFrame:CreateAnimationGroup()
    local moveIn = agNew:CreateAnimation('Translation')
    moveIn:SetOffset(w * 0.35 + self.contentPadding, 0)
    moveIn:SetDuration(self.slideDuration)
    moveIn:SetSmoothing('OUT')
    local agOld, moveOut
    if oldFrame and oldFrame:IsShown() then
        agOld = oldFrame:CreateAnimationGroup()
        moveOut = agOld:CreateAnimation('Translation')
        moveOut:SetOffset(w * 0.25, 0)
        moveOut:SetDuration(self.slideDuration)
        moveOut:SetSmoothing('OUT')
    end
    self.animating = true
    local function finish()
        self.animating = false
        newFrame:ClearAllPoints()
        newFrame:SetPoint('TOPLEFT', self.contentHost, 'TOPLEFT', self.contentPadding, -self.contentPadding)
        newFrame:SetPoint('BOTTOMRIGHT', self.contentHost, 'BOTTOMRIGHT', -self.contentPadding, self.contentPadding)
        if oldFrame then
            oldFrame:ClearAllPoints()
            oldFrame:SetPoint('TOPLEFT', self.contentHost, 'TOPLEFT', self.contentPadding, -self.contentPadding)
            oldFrame:SetPoint('BOTTOMRIGHT', self.contentHost, 'BOTTOMRIGHT', -self.contentPadding, self.contentPadding)
            if self.hideInactive then oldFrame:Hide() else oldFrame:Hide() end
        end
        if self.onTabSelected then pcall(self.onTabSelected, id, newFrame) end
    end
    agNew:SetScript('OnFinished', finish)
    if agOld then agOld:SetScript('OnFinished', function() end) end
    if agOld then agOld:Play() end
    agNew:Play()
end

function VerticalTabs:ListTabs()
    local out = {}
    for _, t in ipairs(self.tabs) do out[#out + 1] = { id = t.id, label = t.label } end
    return out
end

function VerticalTabs:GetSelected() return self.selectedId end

--[[ Example Usage:
local vt = VerticalTabs:Create(parentFrame, { onTabSelected = function(id) print('Selected', id) end })
vt:AddTab('summary', 'Summary', nil, function(f) local fs=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); fs:SetPoint('CENTER'); fs:SetText('Summary!') end, 1)
vt:AddTab('settings', 'Settings', 134400, function(f) local fs=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); fs:SetPoint('CENTER'); fs:SetText('Settings pane') end, 2)
]]

local ADDON_NAME, Addon = ...
if Addon and Addon.provide then
    Addon.provide('UI.VerticalTabs', VerticalTabs, { meta = { layer = 'UI', area = 'components' }, lifetime = 'Prototype' })
end
return VerticalTabs
