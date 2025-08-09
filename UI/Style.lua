-- UI/Style.lua – Central design tokens & helpers (2025 modernization)
local _, Addon = ...

local Style = {}

Style.COLORS = {
  ACCENT        = {1.0, 0.82, 0.0},   -- gold accent
  ACCENT_SOFT   = {1.0, 0.82, 0.0, 0.12},
  TEXT_PRIMARY  = {0.90, 0.90, 0.92, 1},
  TEXT_MUTED    = {0.72, 0.74, 0.76, 1},
  TEXT_HIGHLIGHT= {1.0, 0.95, 0.60, 1},
  BG_DARK_GLASS = {0.05, 0.06, 0.08, 0.55},
  BG_PANEL      = {0.07, 0.08, 0.10, 0.35},
  BORDER_SOFT   = {1, 1, 1, 0.06},
  BORDER_STRONG = {1, 1, 1, 0.15},
  DANGER        = {0.95, 0.25, 0.25, 1},
}

function Style.Color(fs, col)
  if fs and fs.SetTextColor and col then fs:SetTextColor(col[1], col[2], col[3], col[4] or 1) end
end

function Style.ThinBorder(frame, color)
  if not frame or frame._GRThinBorder then return end
  local c = color or Style.COLORS.BORDER_SOFT
  local t = frame:CreateTexture(nil, "BORDER")
  t:SetPoint("TOPLEFT", 1, -1)
  t:SetPoint("BOTTOMRIGHT", -1, 1)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  frame._GRThinBorder = t
end

function Style.StripInset(frame)
  if not frame then return end
  if frame.NineSlice then frame.NineSlice:Hide() end
  if frame.Bg then frame.Bg:Hide() end
end

Addon.provide("UI.Style", Style)
return Style
