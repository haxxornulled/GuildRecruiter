-- UI/MainTabsHost.lua
-- Reusable host that wires VerticalTabs to CategoryManager + PanelFactory.
---@diagnostic disable: undefined-global, undefined-field, inject-field
local __args = {...}
local AddonName, Addon = __args[1], (__args[2] or _G[__args[1]] or {})
local Host = {}
Host.__index = Host

local function CATM()
    local cm = (Addon.Get and (Addon.Get('UI.CategoryManager') or Addon.Get('Tools.CategoryManager'))) or nil
    if cm and cm.EnsureInitialized then cm:EnsureInitialized() end
    return cm
end

local function GetVisibleCategories()
    local cm = CATM(); if not cm then return {} end
    local raw = cm:GetAll() or {}
    local out = {}
    for _,c in ipairs(raw) do if cm:EvaluateVisibility(c) then out[#out+1]=c end end
    table.sort(out, function(a,b) return (a.order or 0) < (b.order or 0) end)
    return out
end

function Host:Create(mainFrame, opts)
    opts = opts or {}
    local VerticalTabs = (Addon.Get and Addon.Get('UI.VerticalTabs')) or (Addon.require and Addon.require('UI.VerticalTabs'))
    assert(VerticalTabs, 'VerticalTabs component not available')
    local o = setmetatable({}, self)
    o.mainFrame = mainFrame
    o.opts = opts
    o.tabs = VerticalTabs:Create(mainFrame, {
        tabWidth = opts.tabWidth or 140,
        overlap = opts.overlap or 18,
        slideDuration = opts.slideDuration or 0.25,
        onTabSelected = function(key, hostFrame)
            o.contentHost = hostFrame
            o:ShowPanel(key)
        end
    })
    o.tabs.frame:SetPoint('TOPLEFT', mainFrame, 'TOPLEFT', 6, -42)
    o.tabs.frame:SetPoint('BOTTOMRIGHT', mainFrame, 'BOTTOMRIGHT', -12, 10)
    o:RebuildTabs()
    return o
end

function Host:ShowPanel(key)
    self._contentFrames = self._contentFrames or {}
    for _,frame in pairs(self._contentFrames) do if frame.Hide then frame:Hide() end end
    if not self._contentFrames[key] then
        local pf = (Addon.Get and Addon.Get('IPanelFactory')) or (Addon.require and Addon.require('IPanelFactory'))
        local parent = self.contentHost
        if pf and pf.GetPanel then
            local ok, panel = pcall(function() return pf:GetPanel(key, { parent = parent, slot = 'main' }) end)
            if ok and panel then
                panel:ClearAllPoints(); panel:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, 0); panel:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0, 0)
                self._contentFrames[key] = panel
            else
                local fb = CreateFrame('Frame', nil, parent); fb:SetAllPoints(); local fs=fb:CreateFontString(nil,'OVERLAY','GameFontNormal'); fs:SetPoint('CENTER'); fs:SetText('Failed to load '..key); self._contentFrames[key]=fb
            end
        end
    end
    local panel = self._contentFrames[key]
    if panel then panel:Show(); if panel.Render then pcall(panel.Render, panel) end end
end

function Host:RebuildTabs()
    local cats = GetVisibleCategories()
    -- Snapshot existing
    local existing = {}
    for _,t in ipairs(self.tabs:ListTabs()) do existing[t.id]=true end
    -- Remove tabs no longer present
    for id,_ in pairs(existing) do
        local still=false; for _,c in ipairs(cats) do if c.key==id and c.type~='separator' then still=true break end end
        if not still then self.tabs:RemoveTab(id) end
    end
    -- Add new
    for _,c in ipairs(cats) do if c.type~='separator' then self:_ensureTab(c) end end
    -- Ensure selection
    local sel=self.tabs:GetSelected(); if not sel then local first=self.tabs:ListTabs()[1]; if first then self.tabs:SelectTab(first.id, true) end end
end

function Host:_ensureTab(cat)
    for _,t in ipairs(self.tabs:ListTabs()) do if t.id==cat.key then return end end
    self.tabs:AddTab(cat.key, cat.label or cat.key, cat.icon, nil, cat.order)
end

-- Public helpers for UI.Main to forward
function Host:AddCategory(catDef)
    self:RebuildTabs()
end
function Host:RemoveCategory(key)
    self:RebuildTabs()
end

-- DI provide
if Addon.provide then
    Addon.provide('UI.MainTabsHost', Host, { lifetime='SingleInstance', meta={ layer='UI', area='main-tabs' } })
end
return Host
