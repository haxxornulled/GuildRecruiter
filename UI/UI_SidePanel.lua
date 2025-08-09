-- UI_SidePanel.lua — Blizzard-style left sidebar (no icons), DI-neutral
local _, Addon = ...
local SidePanel = {}

local STYLE = {
  BTN_W=126, BTN_H=28, GAP=4, PAD_X=12,
  FONT="GameFontHighlight",
  SEL_BG={1.00,0.82,0.00,0.15}, HOVER_BG={1.00,0.95,0.55,0.08},
}

local function CreateCategoryButton(parent, text)
  local btn = CreateFrame("Button", nil, parent); btn:SetSize(STYLE.BTN_W, STYLE.BTN_H)
  btn.bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1); btn.bg:SetAllPoints(); btn.bg:SetColorTexture(0,0,0,0)
  btn.text = btn:CreateFontString(nil, "ARTWORK", STYLE.FONT); btn.text:SetPoint("LEFT", STYLE.PAD_X, 0); btn.text:SetText(text)
  btn:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(STYLE.HOVER_BG)); self.text:SetTextColor(1,0.95,0.55) end)
  btn:SetScript("OnLeave", function(self)
    if self._selected then self.bg:SetColorTexture(unpack(STYLE.SEL_BG)); self.text:SetTextColor(1,0.82,0.0)
    else self.bg:SetColorTexture(0,0,0,0); self.text:SetTextColor(1,1,1) end
  end)
  function btn:SetSelected(sel)
    self._selected = sel
    if sel then self.bg:SetColorTexture(unpack(STYLE.SEL_BG)); self.text:SetTextColor(1,0.82,0.0)
    else self.bg:SetColorTexture(0,0,0,0); self.text:SetTextColor(1,1,1) end
  end
  return btn
end

function SidePanel:Create(parent, categories, onSelectIndex)
  local sidebar = CreateFrame("Frame", nil, parent, "InsetFrameTemplate3")
  sidebar:SetWidth(STYLE.BTN_W + 10); sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10)

  local tex = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
  tex:SetAllPoints(); tex:SetTexture("Interface/AchievementFrame/UI-Achievement-Character-Stats"); tex:SetAlpha(0.3)

  local scroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame"); child:SetSize(1,1); scroll:SetScrollChild(child)

  local btns = {}
  for i, cat in ipairs(categories) do
    local btn = CreateCategoryButton(child, cat.label)
    btn:SetPoint("TOPLEFT", 0, -(i-1)*(STYLE.BTN_H + STYLE.GAP))
    btn:SetScript("OnClick", function()
      for _, b in ipairs(btns) do b:SetSelected(false) end
      btn:SetSelected(true)
      if type(onSelectIndex)=="function" then onSelectIndex(i, cat) end
    end)
    btns[i] = btn
  end
  child:SetHeight(#categories * (STYLE.BTN_H + STYLE.GAP))
  return sidebar, btns
end

Addon.UI = Addon.UI or {}; Addon.UI.SidePanel = SidePanel
if Addon.provide then Addon.provide("UI.SidePanel", SidePanel) end
return SidePanel
