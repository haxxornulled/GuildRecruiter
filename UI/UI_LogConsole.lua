-- UI_LogConsole.lua — Floating log console overlay (dev-friendly)
---@diagnostic disable: undefined-global, undefined-field
local __args = { ... }
local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})
-- Analyzer-safe guards for WoW globals (stubs when not in-game)
local _G = _G or {}
local function noop(...) end
local function makeFS()
  return { SetPoint=noop, SetText=noop, SetWidth=noop, SetJustifyH=noop, SetJustifyV=noop }
end
local function frameStub()
  return {
    SetSize=noop, SetPoint=noop, SetBackdrop=noop, SetBackdropColor=noop, SetBackdropBorderColor=noop,
    EnableMouse=noop, SetMovable=noop, RegisterForDrag=noop, SetScript=noop, Hide=noop, Show=noop,
  StartMoving=noop, StopMovingOrSizing=noop, CreateFontString=function(...) return makeFS() end,
  IsShown=function() return false end,
  }
end
local CreateFrame = rawget(_G, 'CreateFrame') or function(ftype, name, parent, template)
  return frameStub()
end
local UIParent = rawget(_G, 'UIParent') or frameStub()

local Console = {}
Console.__index = Console

local function safeBus()
  return (Addon.Get and Addon.Get('EventBus')) or (Addon.Peek and Addon.Peek('EventBus'))
end

local function getLogBuffer()
  return Addon.LogBuffer or {}
end

function Console:EnsureFrame()
  if self._frame ~= nil then return self._frame end
  local f = CreateFrame('Frame', 'GR_LogConsole', UIParent, 'BackdropTemplate')
  f:SetSize(560, 360)
  f:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -40, -120)
  f:SetBackdrop({ bgFile='Interface/Buttons/WHITE8x8', edgeFile='Interface/Tooltips/UI-Tooltip-Border', edgeSize=12, insets={ left=3,right=3,top=3,bottom=3 } })
  f:SetBackdropColor(0,0,0,0.86)
  f:SetBackdropBorderColor(0.85,0.75,0.20,0.9)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', f.StartMoving)
  f:SetScript('OnDragStop', f.StopMovingOrSizing)
  f:Hide()

  self._fontSize = self._fontSize or 14

  local title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  title:SetPoint('TOPLEFT', 10, -8)
  title:SetText('GuildRecruiter — Log Console')

  -- Close button
  local close = CreateFrame('Button', nil, f, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', -6, -6)
  close:SetScript('OnClick', function() self:Hide() end)

  -- Clear button
  local clear = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
  clear:SetPoint('TOPRIGHT', close, 'TOPLEFT', -6, 0)
  clear:SetSize(60, 20)
  clear:SetText('Clear')
  clear:SetScript('OnClick', function() self:Clear() end)

  -- Font size controls (A-/A+)
  local smaller = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
  smaller:SetSize(26, 20)
  smaller:SetPoint('TOPRIGHT', clear, 'TOPLEFT', -6, 0)
  smaller:SetText('A-')
  smaller:SetScript('OnClick', function()
    self._fontSize = math.max(10, (self._fontSize or 14) - 1)
    self:UpdateFont()
  end)

  local bigger = CreateFrame('Button', nil, f, 'UIPanelButtonTemplate')
  bigger:SetSize(26, 20)
  bigger:SetPoint('TOPRIGHT', smaller, 'TOPLEFT', -4, 0)
  bigger:SetText('A+')
  bigger:SetScript('OnClick', function()
    self._fontSize = math.min(22, (self._fontSize or 14) + 1)
    self:UpdateFont()
  end)

  -- Scrollable, selectable log area (EditBox within a ScrollFrame)
  local scroll = CreateFrame('ScrollFrame', nil, f, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', 10, -32)
  scroll:SetPoint('BOTTOMRIGHT', -30, 12)

  local edit = CreateFrame('EditBox', nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:EnableMouse(true)
  edit:SetTextInsets(6, 6, 6, 6)
  edit:SetJustifyH('LEFT')
  edit:SetJustifyV('TOP')
  -- Wide and tall so the scrollframe can clip it; update in sizing
  edit:SetWidth( math.max(300, (scroll:GetWidth() or 500) - 8) )
  edit:SetHeight(4000)
  edit:SetText('')
  edit:SetScript('OnEscapePressed', function(selfEB) selfEB:ClearFocus() end)
  -- Optional: mousewheel to zoom font with Ctrl
  edit:EnableMouseWheel(true)
  edit:SetScript('OnMouseWheel', function(_, delta)
    if IsControlKeyDown and IsControlKeyDown() then
      self._fontSize = math.max(10, math.min(22, (self._fontSize or 14) + (delta>0 and 1 or -1)))
      self:UpdateFont()
    end
  end)

  scroll:SetScrollChild(edit)

  -- React to frame size changes to keep wrapping sensible
  scroll:SetScript('OnSizeChanged', function()
    local w = math.max(300, (scroll:GetWidth() or 500) - 8)
    edit:SetWidth(w)
  end)

  self._frame = f
  self._scroll = scroll
  self._edit = edit
  -- Apply initial font
  self:UpdateFont()
  return f
end

function Console:UpdateFont()
  if not self._edit then return end
  local GF = rawget(_G, 'GameFontHighlight')
  local path, size, flags = nil, nil, nil
  if GF and GF.GetFont then path, size, flags = GF:GetFont() end
  local ok = pcall(function()
    if self._edit.SetFont and path then
      local fflags = (type(flags) == 'string') and flags or ''
      self._edit:SetFont(path, self._fontSize or 14, fflags)
    end
  end)
  if not ok and self._edit.SetFontObject then
    self._edit:SetFontObject('GameFontHighlight')
  end
end

function Console:Render()
  local buf = getLogBuffer()
  local s = table.concat(buf, '\n')
  if self._edit then
    self._edit:SetText(s)
    -- Keep cursor at top to avoid jumping focus
    if self._edit.SetCursorPosition then self._edit:SetCursorPosition(0) end
  end
  -- Auto-scroll to bottom to show newest logs
  if self._scroll and self._scroll.GetVerticalScrollRange then
    local range = self._scroll:GetVerticalScrollRange() or 0
    if self._scroll.SetVerticalScroll then self._scroll:SetVerticalScroll(range) end
  end
end

function Console:HookBus()
  local Bus = safeBus(); if not (Bus and Bus.Subscribe) then return end
  self._busNS = self._busNS or 'UI.LogConsole'
  if Bus.UnsubscribeNamespace then pcall(Bus.UnsubscribeNamespace, Bus, self._busNS) end
  Bus:Subscribe('LogUpdated', function()
  self:Render()
  end, { namespace = self._busNS })
end

function Console:Show()
  self:EnsureFrame(); self:HookBus(); self._visible = true; self:Render(); self._frame:Show()
end

function Console:Hide()
  self._visible = false; self._frame:Hide()
end

function Console:Clear()
  -- Clear only the on-screen view, preserve underlying Addon.LogBuffer unless logger offers a way
  self:EnsureFrame()
  if self._edit then self._edit:SetText('') end
end

local function CreateConsole()
  local self = setmetatable({}, Console)
  -- Initialize fields for static analyzers
  self._frame = nil
  self._scroll = nil
  self._edit = nil
  self._visible = false
  return self
end

-- DI registration (no early resolves)
if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('UI.LogConsole')) then
  Addon.provide('UI.LogConsole', function() return CreateConsole() end, { lifetime = 'SingleInstance' })
end

return CreateConsole
