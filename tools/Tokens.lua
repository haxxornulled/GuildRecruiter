-- Tools/Tokens.lua
-- Central design tokens (colors, spacing, radii, typography, shadows, transitions)
-- These are source-of-truth values to be referenced by style helpers & components.

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or {})
local Tokens = {}

-- Color palette (WCAG-ish contrast minded). Naming: role + intensity.
Tokens.colors = {
  -- Neutrals (dark UI baseline)
  neutral = {
    0,   -- placeholder index (keep 1-based mental map if desired)
    {0.06,0.06,0.07}, --1
    {0.09,0.09,0.10}, --2 BG subtle
    {0.12,0.12,0.14}, --3 BG raised
    {0.16,0.16,0.18}, --4 Panel
    {0.22,0.22,0.25}, --5 Hover
    {0.30,0.30,0.33}, --6 Border Strong
    {0.58,0.58,0.62}, --7 Text Muted
    {0.82,0.82,0.86}, --8 Text Primary
    {0.95,0.95,0.97}, --9 Highlight
  },
  accent = {
    base = {0.85,0.70,0.10},
    hover = {0.95,0.80,0.18},
    active= {1.00,0.82,0.05},
    subtle= {0.60,0.48,0.08},
  },
  status = {
    success = {0.18,0.70,0.25},
    danger  = {0.85,0.20,0.18},
    warn    = {0.95,0.60,0.15},
    info    = {0.20,0.55,0.95},
  }
}

-- Spacing scale (in pixels)
Tokens.spacing = { xxs=4, xs=6, sm=8, md=12, lg=16, xl=24, xxl=32 }

-- Radii
Tokens.radius = { none=0, sm=2, md=4, lg=6 }

-- Typography roles mapping to WoW font objects
Tokens.typography = {
  title    = "GameFontNormalHuge",
  section  = "GameFontNormalLarge",
  body     = "GameFontHighlight",
  meta     = "GameFontDisable",
  button   = "GameFontHighlight",
  badge    = "GameFontNormalSmall",
}

-- Shadows (alpha overlays). We'll implement via simple backdrop textures.
Tokens.shadows = {
  low    = {0,0,0,0.25},
  mid    = {0,0,0,0.40},
  high   = {0,0,0,0.55},
  glowAccent = {1.0,0.82,0.10,0.55},
}

-- Transition timings (seconds)
Tokens.timing = { fast=0.08, base=0.16, slow=0.28 }

-- Gradients presets used by interactive surfaces
Tokens.gradients = {
  buttonIdle     = { top={0.13,0.13,0.15,0.75}, bottom={0.08,0.08,0.09,0.85} },
  buttonHover    = { top={0.22,0.22,0.25,0.85}, bottom={0.14,0.14,0.16,0.95} },
  buttonSelected = { top={0.32,0.30,0.06,0.90}, bottom={0.26,0.20,0.02,0.95} },
  panel          = { top={0.11,0.12,0.14,0.12}, bottom={0.07,0.08,0.09,0.18} },
}

-- Utility: fetch color safely (returns r,g,b[,a])
function Tokens:GetColor(path, fallback)
  local cursor = self.colors
  if type(cursor) ~= "table" then
    if type(fallback) == "table" then local r=fallback[1] or 1; local g=fallback[2] or 1; local b=fallback[3] or 1; local a=fallback[4] or 1; return r,g,b,a end
    return 1,1,1,1
  end
  local target = cursor
  for seg in string.gmatch(path or "", "[^%.]+") do
    if type(target) ~= "table" then target = nil; break end
    target = target[seg]
  end
  if type(target) == "table" then
    local r = target[1] or (fallback and fallback[1]) or 1
    local g = target[2] or (fallback and fallback[2]) or 1
    local b = target[3] or (fallback and fallback[3]) or 1
    local a = target[4] or (fallback and fallback[4]) or 1
    return r,g,b,a
  end
  if type(fallback) == "table" then
    local r = fallback[1] or 1; local g = fallback[2] or 1; local b = fallback[3] or 1; local a = fallback[4] or 1
    return r,g,b,a
  end
  return 1,1,1,1
end

if Addon.provide then Addon.provide("Tools.Tokens", Tokens) end
return Tokens
