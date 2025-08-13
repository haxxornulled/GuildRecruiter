-- UI/UI_PanelRegistry.lua
-- Central registration of UI panels with the PanelFactory (IPanelFactory)
---@diagnostic disable: undefined-global, undefined-field
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local function withWrapper(opts, buildInner)
  local parent = (opts and opts.parent) or UIParent
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetPoint("TOP", parent, "TOP", 0, 0)
  panel:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
  panel:SetWidth(parent:GetWidth() or 600)
  panel:Hide()
  local ok, page = pcall(buildInner, panel)
  if ok and type(page) == 'table' and page.ClearAllPoints then
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel._innerPage = page
    panel.Render = function(self)
      if self._innerPage and self._innerPage.Render then
        pcall(self._innerPage.Render, self._innerPage)
      end
    end
  else
    local fallback = CreateFrame("Frame", nil, panel); fallback:SetAllPoints()
    local msg = fallback:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    msg:SetPoint("CENTER"); msg:SetText("|cffff5555Panel build failed|r")
    panel._innerPage = fallback
    panel.Render = function() end
  end
  return panel
end

-- Defer actual registration until PanelFactory is available
local pending = {}
local function register(key, title, area, moduleKey)
  pending[#pending+1] = {
    key = key, title = title, area = area, moduleKey = moduleKey,
    def = function()
      return {
        key = key,
        title = title,
        area = area,
        singleton = true,
        build = function(opts)
          return withWrapper(opts, function(parent)
            local mod = Addon.require and Addon.require(moduleKey)
            if mod and type(mod.Create) == 'function' then
              return mod:Create(parent)
            end
            return CreateFrame('Frame', nil, parent)
          end)
        end,
      }
    end
  }
end

local function flush()
  if not (Addon and Addon.IsProvided and Addon.IsProvided('PanelFactory')) then return false end
  local PF = Addon.require and Addon.require('PanelFactory')
  if not PF or not PF.RegisterPanel then return false end
  for i=1,#pending do
    local p = pending[i]
    local ok, def = pcall(p.def)
    if ok and def then pcall(PF.RegisterPanel, PF, def) end
  end
  for i=#pending,1,-1 do pending[i]=nil end
  return true
end

-- Primary content panels
register('summary',   'Summary',   'ui/summary',   'UI.Summary')
register('prospects', 'Prospects', 'ui/prospects', 'UI.Prospects')
register('blacklist', 'Blacklist', 'ui/blacklist', 'UI.Blacklist')
register('settings',  'Settings',  'ui/settings',  'UI.Settings')
-- Debug panel (factory doesn’t enforce visibility; CategoryManager handles showing/hiding)
register('debug',     'Debug',     'ui/debug',     'UI.Debug')

-- Try immediately; otherwise wait for services-ready or retry a few times
if not flush() then
  local tried = 0
  local function retry()
    if flush() then return end
    tried = tried + 1
    if tried < 10 and C_Timer and C_Timer.After then C_Timer.After(0.1, retry) end
  end
  -- Hook event bus if present
  local bus = rawget(Addon, 'EventBus')
  if bus and type(bus.Subscribe) == 'function' then
    pcall(bus.Subscribe, bus, ADDON_NAME..'.ServicesReady', function()
      retry()
    end, { namespace = 'UI.PanelRegistry' })
  end
  retry()
end

return true
