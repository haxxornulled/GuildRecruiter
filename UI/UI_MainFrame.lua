-- UI_MainFrame.lua
-- Guild Recruiter — Main UI (modular pages)

local ADDON_NAME, Addon = ...
local UI = {}
Addon.UI = UI

-- Lazy logger accessor (avoid top-level DI resolves)
local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Main")) or nil
end

-- Optional theme/style modules (via Addon.provide)
local Theme        = Addon.Theme_Dragonfly or Addon.Theme
local StyleMod     = Addon.require and Addon.require("UI.Style") or nil
local SidePanelMod = Addon.require and Addon.require("UI.SidePanel") or (Addon.UI and Addon.UI.SidePanel)

local STYLE = {
  PAD = 12, GAP = 8, ROW_H = 24,
  COLORS = { SUBTLN = {1,1,1,0.07} }
}

local categories = {
  { key = "summary",   label = "Summary",  },
  { key = "prospects", label = "Prospects" },
  { key = "blacklist", label = "Blacklist" },
  { key = "settings",  label = "Settings"  },
  { key = "debug",     label = "Debug"     },
}

local selectedCategory = 1
local mainFrame, sidebar, contentParent = nil, nil, nil
local catButtons, contentFrames = {}, {}

local function SkinCollectionsBackdrop(frame)
  if frame.Bg then frame.Bg:SetAlpha(0.10) end
  if not frame._GR_Gradient then
    local grad = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    grad:SetAllPoints()
    local top = (CreateColor and CreateColor(0.11,0.12,0.14,0.12)) or { GetRGBA=function() return 0.11,0.12,0.14,0.12 end }
    local bot = (CreateColor and CreateColor(0.07,0.08,0.09,0.18)) or { GetRGBA=function() return 0.07,0.08,0.09,0.18 end }
    if Theme and Theme.gradient then top = Theme.gradient.top or top; bot = Theme.gradient.bottom or bot end
    if grad.SetGradient and type(top)=="table" and top.GetRGBA then
      grad:SetColorTexture(0,0,0,0); grad:SetGradient("VERTICAL", top, bot)
    else
      grad:SetColorTexture(0.09,0.09,0.10,0.12)
    end
    frame._GR_Gradient = grad
  end
  if not frame._GR_InnerLine then
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(STYLE.COLORS.SUBTLN))
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("BOTTOMRIGHT", -1, 1)
    frame._GR_InnerLine = line
  end
end

local function CreateSummaryPage(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(); f:Hide()
  local g = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  g:SetPoint("TOP", 0, -32)
  local name = GetGuildInfo("player")
  if name then g:SetText(name) else g:SetText("Not in a Guild"); g:SetTextColor(.85,.85,.85) end
  local w = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w:SetPoint("TOP", g, "BOTTOM", 0, -16); w:SetText("Welcome to Guild Recruiter")
  local h = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  h:SetPoint("TOP", w, "BOTTOM", 0, -10)
  h:SetJustifyH("CENTER")
  h:SetText("• Prospects: live queue from target/mouseover/nameplates\n• Blacklist: do-not-invite list\n• Settings: rotation + messages")
  function f:Render() end
  return f
end

local function CreateDebugPage(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(); f:Hide()

  local host = CreateFrame("Frame", "GR_DebugEdit", f, "ScrollingEditBoxTemplate")
  host:SetPoint("TOPLEFT", 12, -12)
  host:SetPoint("BOTTOMRIGHT", -28, 46)
  local editBox =
    host.EditBox or
    (host.ScrollFrame and host.ScrollFrame.EditBox) or
    (host.ScrollBox and host.ScrollBox.GetScrollTarget and host.ScrollBox:GetScrollTarget())
  if editBox and editBox.GetObjectType and editBox:GetObjectType() ~= "EditBox" then editBox = nil end

  local scrollBar = host.ScrollBar
  if not editBox or not scrollBar then
    local sf = CreateFrame("ScrollFrame", "GR_DebugScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -12); sf:SetPoint("BOTTOMRIGHT", -28, 46)
    editBox = CreateFrame("EditBox", nil, sf); editBox:SetMultiLine(true); editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false); editBox:SetWidth(sf:GetWidth() - 8); editBox:SetText("")
    sf:SetScrollChild(editBox)
    scrollBar = _G["GR_DebugScrollScrollBar"]
    sf:SetScript("OnSizeChanged", function(_, w) editBox:SetWidth((w or 0) - 8) end)
  end

  editBox:EnableMouse(true)
  editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  editBox:SetScript("OnEnterPressed",  function(self) self:Insert("\n") end)

  local userScrolling=false
  local function markUser() userScrolling=true; C_Timer.After(1.0, function() userScrolling=false end) end
  local wheelHost = host.ScrollBox or host.ScrollFrame or host or f
  if wheelHost.EnableMouseWheel then
    wheelHost:EnableMouseWheel(true)
    wheelHost:SetScript("OnMouseWheel", function(_, delta)
      if not scrollBar then return end
      markUser(); local step = (delta>0) and -40 or 40
      scrollBar:SetValue((scrollBar:GetValue() or 0) + step)
    end)
  end
  if scrollBar and scrollBar.HookScript then scrollBar:HookScript("OnValueChanged", function() markUser() end) end
  local function scrollToBottom()
    if not scrollBar then return end
    local _, max = scrollBar:GetMinMaxValues(); scrollBar:SetValue(max or 0)
  end

  function f:RenderLog()
    local buffer = Addon.LogBuffer or {}
    editBox:SetText(table.concat(buffer, "\n"))
    C_Timer.After(0, function() if not userScrolling then scrollToBottom() end end)
  end
  if Addon.EventBus and Addon.EventBus.Subscribe then
    Addon.EventBus:Subscribe("LogUpdated", function() if f:IsShown() then f:RenderLog() end end)
  end
  f:HookScript("OnShow", function() f:RenderLog() end)

  local reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reloadBtn:SetPoint("BOTTOMRIGHT", -12, 12); reloadBtn:SetSize(120, 24)
  reloadBtn:SetText("Reload UI"); reloadBtn:SetScript("OnClick", ReloadUI)

  function f:Render() f:RenderLog() end
  return f
end

local function AttachPage(key, moduleName)
  local ok, mod = pcall(Addon.require, moduleName)
  if ok and mod and type(mod.Create) == "function" then
    local page = mod:Create(contentParent)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", contentParent, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", contentParent, "BOTTOMRIGHT", 0, 0)
    contentFrames[key] = page
  else
    local page = CreateFrame("Frame", nil, contentParent); page:SetAllPoints()
    local msg = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    msg:SetPoint("CENTER"); msg:SetText(("|cffff5555%s failed.|r"):format(moduleName))
    contentFrames[key] = page
    local L = LOG(); if L then L:Warn("AttachPage failed {Mod}: {Err}", { Mod = moduleName, Err = tostring(mod) }) end
  end
end

function UI:SelectCategory(idx)
  selectedCategory = idx
  for i, btn in ipairs(catButtons) do if btn.SetSelected then btn:SetSelected(i==idx) end end
  for _, frame in pairs(contentFrames) do if frame.Hide then frame:Hide() end end
  local catKey = categories[idx].key
  local page = contentFrames[catKey]
  if not page then print("|cffff2222[GuildRecruiter][UI]|r Missing content for tab:", tostring(catKey)); return end
  if page.Show then page:Show() end
  if page.Render then pcall(page.Render, page) end
end

function UI:Build()
  if mainFrame then return end
  local W, H = 940, 560
  mainFrame = CreateFrame("Frame", "GuildRecruiterFrame", UIParent, "PortraitFrameTemplate")
  mainFrame:SetSize(W, H); mainFrame:SetPoint("CENTER")
  mainFrame:SetFrameStrata("DIALOG"); mainFrame:EnableMouse(true); mainFrame:SetMovable(true)
  mainFrame:RegisterForDrag("LeftButton")
  mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
  mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
  if mainFrame.SetTitle then mainFrame:SetTitle("Guild Recruiter")
  elseif mainFrame.TitleContainer and mainFrame.TitleContainer.TitleText then
    mainFrame.TitleContainer.TitleText:SetText("Guild Recruiter")
  end

  -- Sidebar
  local sidebarButtons = {}
  if SidePanelMod and SidePanelMod.Create then
    sidebar, sidebarButtons = SidePanelMod:Create(mainFrame, categories, function(i) UI:SelectCategory(i) end)
    sidebar:ClearAllPoints(); sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10)
  else
    sidebar = CreateFrame("Frame", nil, mainFrame, "InsetFrameTemplate3")
    sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10); sidebar:SetWidth(170)
    local line = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
    line:SetAllPoints(); line:SetColorTexture(0,0,0,0.15)
  end
  catButtons = sidebarButtons

  -- Content
  contentParent = CreateFrame("Frame", nil, mainFrame, "InsetFrameTemplate3")
  contentParent:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 14, 0)
  contentParent:SetPoint("BOTTOMRIGHT", -12, 10)
  SkinCollectionsBackdrop(contentParent)
  if Theme and Theme.ApplyBackground then pcall(Theme.ApplyBackground, Theme, contentParent) end

  -- Pages
  contentFrames.summary = CreateSummaryPage(contentParent)
  AttachPage("prospects", "UI.Prospects")
  AttachPage("blacklist", "UI.Blacklist")
  AttachPage("settings",  "UI.Settings")
  contentFrames.debug = CreateDebugPage(contentParent)

  UI:SelectCategory(1)
end

function UI:Show()
  if InCombatLockdown and InCombatLockdown() then print("|cffff5555[GuildRecruiter]|r Cannot open UI in combat."); return end
  if not _G.GuildRecruiterFrame then UI:Build() end
  _G.GuildRecruiterFrame:Show()
end

function UI:Hide() if _G.GuildRecruiterFrame then _G.GuildRecruiterFrame:Hide() end end

Addon.provide("UI.Main", UI)
return UI
