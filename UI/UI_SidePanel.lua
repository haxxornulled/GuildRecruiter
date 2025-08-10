-- UI_SidePanel.lua — Blizzard-style left sidebar (no icons), DI-neutral
local _, Addon = ...
local SidePanel = {}

local STYLE = {
  BTN_W=150, BTN_H=30, GAP=4, PAD_X=14,
  FONT="GameFontHighlight",
  TEXT_COLOR = {0.92,0.92,0.92},
  TEXT_HOVER_COLOR = {1.00,1.00,0.96},
  TEXT_SELECTED_COLOR = {1.00,0.97,0.80},
  GRAD_DARK_TOP = {0.13,0.13,0.15,0.75},
  GRAD_DARK_BOTTOM = {0.08,0.08,0.09,0.85},
  GRAD_HOVER_TOP = {0.22,0.22,0.25,0.85},
  GRAD_HOVER_BOTTOM = {0.14,0.14,0.16,0.95},
  GRAD_SELECTED_TOP = {0.32,0.30,0.06,0.90},
  GRAD_SELECTED_BOTTOM = {0.26,0.20,0.02,0.95},
  BORDER_COLOR = {1,1,1,0.10},
  BORDER_SELECTED = {1,0.85,0.15,0.55},
  ACCENT_COLOR_HOVER = {1,0.85,0.25,0.80},
  ACCENT_COLOR_SELECTED = {1,0.80,0.05,1.0},
  ACCENT_W = 4,
  SHADOW_COLOR = {0,0,0,0.55},
  SHADOW_HOVER_ALPHA = 0.45,
  SHADOW_SELECTED_ALPHA = 0.65,
  SEPARATOR_COLOR = {1,1,1,0.06},
  SEPARATOR_GAP_TOP = 8,
  SEPARATOR_GAP_BOTTOM = 4,
}

local function ApplyGradient(tex, top, bottom)
  if not tex then return end
  local function AsColor(c)
    if not c or type(c) ~= "table" then return nil end
    if c.GetRGBA then return c end
    local r,g,b,a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    if CreateColor then return CreateColor(r,g,b,a) end
    return { GetRGBA = function() return r,g,b,a end }
  end
  if tex.SetGradient and top and bottom then
    local cTop    = AsColor(top)
    local cBottom = AsColor(bottom)
    if cTop and cBottom then
      tex:SetColorTexture(0,0,0,0)
      pcall(tex.SetGradient, tex, "VERTICAL", cTop, cBottom)
      return
    end
  end
  local r,g,b,a = (top and top[1]) or 1, (top and top[2]) or 1, (top and top[3]) or 1, (top and top[4]) or 0.15
  tex:SetColorTexture(r,g,b,a)
end

local function CreateCategoryButton(parent, text)
  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")
  if not ButtonLib then
    local fallback = CreateFrame("Button", nil, parent)
    fallback:SetSize(STYLE.BTN_W, STYLE.BTN_H)
    local fs = fallback:CreateFontString(nil, "OVERLAY", STYLE.FONT)
    fs:SetPoint("CENTER"); fs:SetText(text)
    fallback.text = fs
    function fallback:SetSelected(sel) if sel then self.text:SetTextColor(1,0.9,0.4) else self.text:SetTextColor(0.9,0.9,0.9) end end
    return fallback
  end
  local btn = ButtonLib:Create(parent, { text=text, variant="ghost", size="sm" })
  btn:SetSize(STYLE.BTN_W, STYLE.BTN_H)
  function btn:SetSelected(sel)
    if sel then
      self:SetVariant("primary")
    else
      self:SetVariant("ghost")
    end
  end
  return btn
end

-- Internal builder used by :Create and :Rebuild
local function BuildButtons(sidebar, categories)
  local scroll = sidebar._scroll
  local child  = sidebar._child
  local onSelectIndex = sidebar._onSelect
  local old = sidebar._buttons or {}
  for _, b in ipairs(old) do if b.Hide then b:Hide() end end
  wipe(old)
  local y = 0
  local btns = {}
  for i, cat in ipairs(categories) do
    if cat.type == "separator" then
      y = y + (STYLE.SEPARATOR_GAP_TOP or 6)
      local sep = CreateFrame("Frame", nil, child)
      sep:SetPoint("TOPLEFT", 0, -y)
      sep:SetSize(STYLE.BTN_W, 4)
      local line = sep:CreateTexture(nil, "BACKGROUND")
      local c = STYLE.SEPARATOR_COLOR or {1,1,1,0.08}
      line:SetColorTexture(unpack(c))
      line:SetPoint("TOPLEFT", 2, -1)
      line:SetPoint("TOPRIGHT", -2, -1)
      y = y + 4 + (STYLE.SEPARATOR_GAP_BOTTOM or 2)
    else
      local btn = CreateCategoryButton(child, cat._renderedLabel or cat.label or cat.key)
      btn:SetPoint("TOPLEFT", 0, -y)
      btn.catKey = cat.key
      btn.index  = i
      btn:SetScript("OnClick", function()
        for _, b in ipairs(btns) do if b.SetSelected then b:SetSelected(false) end end
        if btn.SetSelected then btn:SetSelected(true) end
        if type(onSelectIndex)=="function" then onSelectIndex(i, cat) end
      end)
      btns[#btns+1] = btn
      y = y + STYLE.BTN_H + STYLE.GAP
    end
  end
  child:SetHeight(y)
  sidebar._buttons = btns
  -- Hide underline of any category that is immediately followed by a separator to prevent stacked lines
  for i, cat in ipairs(categories) do
  -- no underline system anymore
  end
  -- re-evaluate scrollbar if public helper exists
  if sidebar.EvaluateScrollbar then C_Timer.After(0, sidebar.EvaluateScrollbar) end
end

function SidePanel:Create(parent, categories, onSelectIndex)
  local sidebar = CreateFrame("Frame", nil, parent, "InsetFrameTemplate3")
  sidebar:SetWidth(STYLE.BTN_W + 10); sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10)

  local tex = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
  tex:SetAllPoints(); tex:SetTexture("Interface/AchievementFrame/UI-Achievement-Character-Stats"); tex:SetAlpha(0.3)

  local scroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame"); child:SetSize(1,1); scroll:SetScrollChild(child)

  sidebar._scroll = scroll
  sidebar._child  = child
  sidebar._onSelect = onSelectIndex
  BuildButtons(sidebar, categories)
  local btns = sidebar._buttons

  -- Dynamic scrollbar evaluation (hide when content fits, restore when needed)
  local originalShow = scroll.ScrollBar and scroll.ScrollBar.Show
  local function EvaluateScrollbar()
    local visibleH = scroll:GetHeight()
    if not visibleH or visibleH <= 0 then return end
    local needsScroll = child:GetHeight() > (visibleH + 1)
    if scroll.ScrollBar then
      if needsScroll then
        -- Ensure room for scrollbar
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -26, 4)
        if originalShow then scroll.ScrollBar.Show = originalShow end
        scroll.ScrollBar:Show()
      else
        -- Collapse right padding, hide scrollbar
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -4, 4)
        scroll.ScrollBar:Hide()
      end
    end
  end

  -- Defer evaluation until after layout, and on size changes
  C_Timer.After(0, EvaluateScrollbar)
  sidebar:HookScript("OnSizeChanged", function() C_Timer.After(0, EvaluateScrollbar) end)
  scroll:HookScript("OnSizeChanged", function() C_Timer.After(0, EvaluateScrollbar) end)
  -- Public helper if external modules add/remove categories later
  sidebar.EvaluateScrollbar = EvaluateScrollbar
  function sidebar:Rebuild(newCategories)
    BuildButtons(sidebar, newCategories)
  end
  function sidebar:SetCategoryLabel(key, newLabel)
    for _, b in ipairs(sidebar._buttons or {}) do
      if b.catKey == key and b.text and newLabel then b.text:SetText(newLabel) return true end
    end
  end
  function sidebar:SelectIndex(idx)
    for _, b in ipairs(sidebar._buttons or {}) do if b.index == idx then if b:GetScript("OnClick") then b:GetScript("OnClick")() end end end
  end
  return sidebar, btns
end

Addon.UI = Addon.UI or {}; Addon.UI.SidePanel = SidePanel
if Addon.provide then Addon.provide("UI.SidePanel", SidePanel) end
return SidePanel
