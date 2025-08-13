---@diagnostic disable: undefined-global, undefined-field, need-check-nil
local __args = {...}; local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})

local M = {}

local overlayFrame, content
local isBuilt = false

local function CFG() return (Addon.Get and Addon.Get('IConfiguration')) or (Addon.require and Addon.require('IConfiguration')) end
local function SV() return (Addon.Get and Addon.Get('SavedVarsService')) or (Addon.require and Addon.require('SavedVarsService')) end

local function loadState(f)
  local sv = SV(); if not (sv and f) then return end
  local w = tonumber(sv:Get('ui','overlayChatW', 480)) or 480
  local h = tonumber(sv:Get('ui','overlayChatH', 220)) or 220
  local x = tonumber(sv:Get('ui','overlayChatL', nil))
  local y = tonumber(sv:Get('ui','overlayChatT', nil))
  f:SetSize(math.max(360, math.min(w, 1200)), math.max(180, math.min(h, 640)))
  if x and y then f:ClearAllPoints(); f:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x, y) else f:SetPoint('CENTER') end
end

local function saveState(f)
  local sv = SV(); if not (sv and f) then return end
  if f:GetWidth() and f:GetHeight() then
    sv:Set('ui','overlayChatW', math.floor(f:GetWidth()+0.5))
    sv:Set('ui','overlayChatH', math.floor(f:GetHeight()+0.5))
  end
  local l = f:GetLeft(); local t = f:GetTop()
  if l and t then sv:Set('ui','overlayChatL', math.floor(l+0.5)); sv:Set('ui','overlayChatT', math.floor(t+0.5)) end
end

local function build()
  if isBuilt then return end
  overlayFrame = CreateFrame('Frame', 'GuildRecruiterChatOverlay', UIParent)
  overlayFrame:SetFrameStrata('DIALOG')
  overlayFrame:EnableMouse(true)
  overlayFrame:SetMovable(true)
  overlayFrame:RegisterForDrag('LeftButton')
  overlayFrame:SetScript('OnDragStart', overlayFrame.StartMoving)
  overlayFrame:SetScript('OnDragStop', function(self) self:StopMovingOrSizing(); saveState(self) end)
  overlayFrame:SetResizable(true)
  loadState(overlayFrame)

  -- Styling (glass-like panel)
  local bg = overlayFrame:CreateTexture(nil, 'BACKGROUND', nil, -8)
  bg:SetAllPoints(); bg:SetColorTexture(0,0,0,0.86)
  local inner = overlayFrame:CreateTexture(nil, 'BACKGROUND', nil, -7)
  inner:SetPoint('TOPLEFT', 1, -1); inner:SetPoint('BOTTOMRIGHT', -1, 1)
  inner:SetColorTexture(1,1,1,0.08)

  -- Corner resize grip
  local rh = CreateFrame('Frame', nil, overlayFrame)
  rh:SetSize(16,16); rh:SetPoint('BOTTOMRIGHT', -2, 2); rh:EnableMouse(true)
  local tex = rh:CreateTexture(nil, 'OVERLAY'); tex:SetAllPoints(); tex:SetTexture('Interface/Tooltips/UI-Tooltip-Background'); tex:SetVertexColor(1,1,1,0.15)
  rh:SetScript('OnEnter', function() tex:SetVertexColor(1,1,1,0.35) end)
  rh:SetScript('OnLeave', function() tex:SetVertexColor(1,1,1,0.15) end)
  rh:SetScript('OnMouseDown', function(_, btn) if btn=='LeftButton' then overlayFrame:StartSizing('BOTTOMRIGHT'); overlayFrame:SetUserPlaced(true) end end)
  rh:SetScript('OnMouseUp', function(_, btn)
    if btn=='LeftButton' then
      overlayFrame:StopMovingOrSizing()
      local w = math.max(360, math.min(overlayFrame:GetWidth(), 1200))
      local h = math.max(180, math.min(overlayFrame:GetHeight(), 640))
      overlayFrame:SetSize(w, h)
      saveState(overlayFrame)
    end
  end)

  -- Embed the shared ChatPanel singleton
  local ChatPanel = (Addon.Get and Addon.Get('UI.ChatPanel')) or (Addon.require and Addon.require('UI.ChatPanel'))
  if ChatPanel and ChatPanel.Attach then
    content = ChatPanel:Attach(overlayFrame)
    if content and content.Frame then
      local f = content.Frame
      f:ClearAllPoints()
      f:SetPoint('TOPLEFT', overlayFrame, 'TOPLEFT', 6, -6)
      f:SetPoint('BOTTOMRIGHT', overlayFrame, 'BOTTOMRIGHT', -6, 6)
      if f.Show then f:Show() end
    end
  end

  -- Close button (top-right of overlay)
  local closeBtn = CreateFrame('Button', nil, overlayFrame, 'UIPanelCloseButton')
  closeBtn:SetPoint('TOPRIGHT', overlayFrame, 'TOPRIGHT', -4, -4)
  closeBtn:SetScript('OnClick', function()
    if overlayFrame and overlayFrame.Hide then overlayFrame:Hide() end
  end)

  -- Minimize/Dock button (re-dock chat to main UI)
  local dockBtn = CreateFrame('Button', nil, overlayFrame)
  dockBtn:SetSize(24, 24)
  -- Place to the left of the close button to avoid overlap
  dockBtn:SetPoint('RIGHT', closeBtn, 'LEFT', -4, 0)
  if dockBtn.SetFrameStrata then dockBtn:SetFrameStrata('DIALOG') end
  if dockBtn.SetFrameLevel and closeBtn and closeBtn.GetFrameLevel then dockBtn:SetFrameLevel(closeBtn:GetFrameLevel() + 1) end
  dockBtn:SetNormalTexture('Interface/Buttons/UI-Panel-MinimizeButton-Up')
  dockBtn:SetPushedTexture('Interface/Buttons/UI-Panel-MinimizeButton-Down')
  dockBtn:SetHighlightTexture('Interface/Buttons/UI-Panel-MinimizeButton-Highlight')
  local nt = dockBtn:GetNormalTexture(); if nt then nt:ClearAllPoints(); nt:SetAllPoints(); nt:SetTexCoord(0,1,0,1) end
  local pt = dockBtn:GetPushedTexture(); if pt then pt:ClearAllPoints(); pt:SetAllPoints(); pt:SetTexCoord(0,1,0,1) end
  local ht = dockBtn:GetHighlightTexture(); if ht then ht:ClearAllPoints(); ht:SetAllPoints(); ht:SetTexCoord(0,1,0,1) end
  if dockBtn.SetHitRectInsets then dockBtn:SetHitRectInsets(0, 0, 0, 0) end
  dockBtn:SetScript('OnClick', function()
    -- Show main UI which will re-dock the chat and hide the overlay
    pcall(function()
      local UIM = Addon.UI and Addon.UI.Main
      if UIM and UIM.Show then UIM:Show() end
    end)
    if overlayFrame and overlayFrame.Hide then overlayFrame:Hide() end
  end)

  -- Combat auto-close (opt-in; default true)
  local closeOnCombat = true
  pcall(function() local cfg = CFG(); if cfg and cfg.Get then closeOnCombat = cfg:Get('chatOverlayCloseInCombat', true) end end)
  if not overlayFrame._combatDriver then
    local drv = CreateFrame('Frame'); overlayFrame._combatDriver = drv
    drv:SetScript('OnEvent', function(_, ev)
      if ev == 'PLAYER_REGEN_DISABLED' then
        local enabled = true; pcall(function() local cfg = CFG(); if cfg and cfg.Get then enabled = cfg:Get('chatOverlayCloseInCombat', true) end end)
        if enabled and overlayFrame and overlayFrame.Hide then overlayFrame:Hide() end
      end
    end)
    drv:RegisterEvent('PLAYER_REGEN_DISABLED')
  end

  isBuilt = true
end

function M:Show()
  if not isBuilt then build() end
  -- Ensure the main UI is hidden when overlay is shown
  pcall(function()
    local UIM = Addon.UI and Addon.UI.Main
    if UIM and UIM.Hide then UIM:Hide() end
  end)
  -- Ensure the chat content is visible inside the overlay
  if content and content.Frame and content.Frame.Show then content.Frame:Show() end
  if overlayFrame then overlayFrame:Show() end
end
function M:Hide() if overlayFrame then overlayFrame:Hide() end end
function M:Toggle() if not isBuilt then build() end; if overlayFrame then if overlayFrame:IsShown() then overlayFrame:Hide() else overlayFrame:Show() end end end

if Addon.provide then Addon.provide('UI.ChatOverlay', M, { lifetime = 'SingleInstance', meta = { layer = 'UI', area = 'chat' } }) end
return M
