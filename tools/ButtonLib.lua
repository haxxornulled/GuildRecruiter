---@diagnostic disable
-- Tools/ButtonLib.lua
-- Custom skinnable button library (CSS-like variants + states) for GuildRecruiter
-- Goals: consistent sizing, color system via Tokens, hover/active/disabled states, semantic variants.
-- API:
--   local BL = Addon.require("Tools.ButtonLib")
--   local btn = BL:Create(parent, { text="Click", variant="primary", size="md", icon=texturePath, onClick=function(self) ... end })
--   btn:SetText("New") / btn:SetEnabled(bool) / btn:SetVariant(name) / btn:SetSizeVariant(size)
-- Variants: primary, secondary, subtle, danger, ghost.
-- Sizes: sm, md, lg (affect padding, font).
-- Exposes style tokens so future components can share.

local ADDON_NAME, Addon = ...
-- Lazy getters so we don't force DI container build at file load time
local function GetTokens()
  if Addon and Addon.Get then
    local ok, t = pcall(Addon.Get, "Tools.Tokens")
    if ok then return t end
  end
end
local function GetUIHelpers()
  if Addon and Addon.Get then
    local ok, h = pcall(Addon.Get, "Tools.UIHelpers")
    if ok then return h end
  end
end

local ButtonLib = {}
ButtonLib.__index = ButtonLib

-- Variant style map (colors + gradient + border)
local VARIANTS = {
  primary = function()
    local T = GetTokens()
    return {
      gradIdle   = T and T.gradients.buttonIdle,
      gradHover  = T and T.gradients.buttonHover,
      gradActive = T and T.gradients.buttonSelected,
      border     = (T and T.colors.accent.subtle) or {0.6,0.5,0.15},
      glow       = (T and T.shadows.glowAccent) or {1,1,1,0.4},
      textColor  = (T and T.colors.accent.active) or {1,0.85,0.1},
    }
  end,
  secondary = function() return {
    gradIdle   = { top={0.16,0.16,0.18,0.70}, bottom={0.10,0.10,0.11,0.80} },
    gradHover  = { top={0.22,0.22,0.24,0.80}, bottom={0.14,0.14,0.16,0.90} },
    gradActive = { top={0.28,0.28,0.30,0.85}, bottom={0.18,0.18,0.20,0.95} },
    border     = {0.32,0.32,0.34},
    glow       = {1,1,1,0.10},
    textColor  = ((GetTokens() and GetTokens().colors.neutral[9]) or {0.95,0.95,0.97}),
  } end,
  subtle = function()
    local T = GetTokens()
    return {
    gradIdle   = { top={0.12,0.12,0.13,0.30}, bottom={0.09,0.09,0.10,0.35} },
    gradHover  = { top={0.16,0.16,0.17,0.38}, bottom={0.11,0.11,0.12,0.42} },
    gradActive = { top={0.18,0.18,0.19,0.46}, bottom={0.13,0.13,0.14,0.50} },
    border     = {0.20,0.20,0.22},
    glow       = {1,1,1,0.08},
    textColor  = (T and T.colors.neutral[8]) or {0.82,0.82,0.86},
  }
  end,
  danger = function()
    local T = GetTokens()
    return {
    gradIdle   = { top={0.30,0.08,0.06,0.80}, bottom={0.22,0.05,0.04,0.90} },
    gradHover  = { top={0.40,0.12,0.10,0.85}, bottom={0.30,0.09,0.08,0.95} },
    gradActive = { top={0.48,0.15,0.12,0.92}, bottom={0.36,0.12,0.10,0.98} },
    border     = (T and T.colors.status.danger) or {0.85,0.2,0.18},
    glow       = {0.85,0.20,0.18,0.25},
    textColor  = {1,0.90,0.90},
  }
  end,
  ghost = function() return {
    gradIdle   = { top={0.10,0.10,0.11,0.10}, bottom={0.07,0.07,0.08,0.12} },
    gradHover  = { top={0.14,0.14,0.15,0.18}, bottom={0.10,0.10,0.11,0.24} },
    gradActive = { top={0.16,0.16,0.17,0.25}, bottom={0.12,0.12,0.13,0.32} },
    border     = {0.18,0.18,0.20},
    glow       = {1,1,1,0.05},
    textColor  = ((GetTokens() and GetTokens().colors.neutral[8]) or {0.82,0.82,0.86}),
  } end,
}

local SIZE_MAP = {
  sm = { padX=8,  padY=4,  font=(GetTokens() and GetTokens().typography.button) or "GameFontHighlightSmall" },
  md = { padX=12, padY=6,  font=(GetTokens() and GetTokens().typography.button) or "GameFontHighlight" },
  lg = { padX=16, padY=8,  font=(GetTokens() and GetTokens().typography.button) or "GameFontNormal" },
}

local function ApplyGradient(tex, grad)
  local H = GetUIHelpers()
  if H and H.ApplyGradient then
    H.ApplyGradient(tex, grad.top, grad.bottom)
  else
    local c=grad.top or {0.2,0.2,0.2,0.8}; tex:SetColorTexture(c[1],c[2],c[3],c[4] or 1)
  end
end

local function StyleButton(btn)
  local st = btn._style
  if not st then return end
  if not btn._bg then
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", 2, -2); bg:SetPoint("BOTTOMRIGHT", -2, 2)
    btn._bg = bg
  end
  if not btn._highlight then
    local hl = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    hl:SetPoint("TOPLEFT", 2, -2); hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1,1,1,0.06)
    hl:Hide(); btn._highlight = hl
  end
  if not btn._border then
    local bd = btn:CreateTexture(nil, "BORDER", nil, 1)
    bd:SetPoint("TOPLEFT", 1, -1); bd:SetPoint("BOTTOMRIGHT", -1, 1)
    local b = st.border or {0.3,0.3,0.3}
    bd:SetColorTexture(b[1],b[2],b[3],0.90); btn._border = bd
  end
  ApplyGradient(btn._bg, st.gradIdle or st.grad)
  local tc = st.textColor or {1,1,1}
  if btn._text then btn._text:SetTextColor(tc[1],tc[2],tc[3],tc[4] or 1) end
end

local function SetSizeVariant(btn, sizeKey)
  local sz = SIZE_MAP[sizeKey] or SIZE_MAP.md
  btn._sizeKey = sizeKey
  if not btn._text then
    local fs = btn:CreateFontString(nil, "OVERLAY", sz.font)
    fs:SetPoint("CENTER")
    btn._text = fs
  else
    btn._text:SetFontObject(sz.font)
  end
  local textW = (btn._text:GetStringWidth() or 0)
  local padX, padY = sz.padX, sz.padY
  btn:SetHeight(padY*2 + (btn._text:GetStringHeight() or 12))
  btn:SetWidth(padX*2 + textW)
end

local function UpdateVisualState(btn, state)
  local st = btn._style; if not st then return end
  local grad
  if state == "hover" then grad = st.gradHover or st.gradIdle
  elseif state == "active" then grad = st.gradActive or st.gradHover or st.gradIdle
  else grad = st.gradIdle end
  if grad and btn._bg then ApplyGradient(btn._bg, grad) end
  if btn._highlight then btn._highlight:SetShown(state == "hover") end
  if state == "disabled" then
    if btn._text then btn._text:SetAlpha(0.45) end
    btn:Disable()
  else
    if btn._text then btn._text:SetAlpha(1) end
    btn:Enable()
  end
end

local function AttachStateScripts(btn)
  btn:HookScript("OnEnter", function(self) if not self:IsEnabled() then return end UpdateVisualState(self, "hover") end)
  btn:HookScript("OnLeave", function(self) if self:IsEnabled() then UpdateVisualState(self, "idle") end end)
  btn:HookScript("OnMouseDown", function(self) if self:IsEnabled() then UpdateVisualState(self, "active") end end)
  btn:HookScript("OnMouseUp", function(self) if self:IsEnabled() then UpdateVisualState(self, "hover") end end)
end

function ButtonLib:Create(parent, opts)
  opts = opts or {}
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetFrameStrata(opts.strata or "MEDIUM")
  btn._variantKey = opts.variant or "primary"
  btn._style = (VARIANTS[btn._variantKey] and VARIANTS[btn._variantKey]()) or VARIANTS.primary()
  btn:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10, tile=true, tileSize=8, insets={left=2,right=2,top=2,bottom=2} })
  btn:SetBackdropColor(0,0,0,0.40)
  btn:SetBackdropBorderColor(0,0,0,0.75)
  SetSizeVariant(btn, opts.size or "md")
  if opts.text then btn._text:SetText(opts.text); SetSizeVariant(btn, btn._sizeKey) end
  StyleButton(btn)
  AttachStateScripts(btn)
  if opts.onClick then btn:SetScript("OnClick", function(self, ...) opts.onClick(self, ...) end) end

  function btn:SetText(t) if self._text then self._text:SetText(t); SetSizeVariant(self, self._sizeKey) end end
  function btn:SetVariant(v)
    local f = VARIANTS[v] or VARIANTS.primary
    self._variantKey = v or "primary"
    self._style = f()
    StyleButton(self); UpdateVisualState(self, "idle")
  end
  function btn:SetSizeVariant(sz) SetSizeVariant(self, sz) end
  function btn:SetEnabledState(on)
    if on then self:Enable(); UpdateVisualState(self, "idle") else UpdateVisualState(self, "disabled") end
  end

  UpdateVisualState(btn, "idle")
  return btn
end

Addon.provide("Tools.ButtonLib", ButtonLib, { lifetime = "SingleInstance" })
return ButtonLib
