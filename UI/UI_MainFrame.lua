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
local Tokens       = Addon.require and Addon.require("Tools.Tokens")
local UIHelpers    = Addon.require and Addon.require("Tools.UIHelpers")
local List         = Addon.require and Addon.require("Collections.List")
local Queue        = Addon.require and Addon.require("Collections.Queue")

local STYLE = { PAD = 12, GAP = 8, ROW_H = 24, COLORS = { SUBTLN = {1,1,1,0.07} } }

-- Category management via DI container (lazy accessor to avoid stale reference)
local function CATM()
  local cm = Addon.require and Addon.require("Tools.CategoryManager")
  if cm and cm.EnsureInitialized then cm:EnsureInitialized() end
  return cm
end

-- Forward declare UI frame refs for functions defined before Build()
local mainFrame, sidebar, contentParent = nil, nil, nil

-- Rebuild wrapper hooking into SidePanel
local function RebuildSidebar()
  if not sidebar or not sidebar.Rebuild then return end
  local CM = CATM(); if not CM then return end
  local raw = CM:GetAll() or {}
  CM:ApplyDecorators()
  -- Filter by visibility predicate
  local filtered = {}
  for _, c in ipairs(raw) do
    if CM:EvaluateVisibility(c) then filtered[#filtered+1] = c end
  end
  sidebar:Rebuild(filtered)
  local sel = CM:GetSelectedIndex() or 1
  if filtered[sel] and filtered[sel].type ~= "separator" then sidebar:SelectIndex(sel) else sidebar:SelectIndex(1) end
end

-- Public expose (slash command may call UI.Main:RefreshCategories())
function UI:RefreshCategories()
  RebuildSidebar()
end

-- Forwarding API to manager plus rebuild
function UI:AddCategory(def) local CM=CATM(); if CM then CM:AddCategory(def); RebuildSidebar() end end
function UI:AddSeparator(order) local CM=CATM(); if CM then CM:AddSeparator(order); RebuildSidebar() end end
function UI:RemoveCategory(key) local CM=CATM(); if CM then CM:RemoveCategory(key); RebuildSidebar() end end
function UI:SetCategoryVisible(key, visible) local CM=CATM(); if CM then CM:SetCategoryVisible(key, visible); RebuildSidebar() end end
function UI:RegisterCategoryDecorator(key, fn) local CM=CATM(); if CM then CM:RegisterCategoryDecorator(key, fn); RebuildSidebar() end end
function UI:ListCategories() local CM=CATM(); return (CM and CM:ListCategories()) or {} end
function UI:SelectCategoryByKey(key) local CM=CATM(); return (CM and CM:SelectCategoryByKey(key)) or false end
local function GetCategories()
  local CM=CATM(); if not CM then return {} end
  local raw = CM:GetAll() or {}
  local out = {}
  for _, c in ipairs(raw) do if CM:EvaluateVisibility(c) then out[#out+1] = c end end
  return out
end
local function SetSelected(i) local CM=CATM(); if CM and CM.SelectIndex then CM:SelectIndex(i) end end
local catButtons, contentFrames = {}, {}
local portraitTex -- player portrait texture reference

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

  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")
  local reloadBtn
  if ButtonLib then
    reloadBtn = ButtonLib:Create(f, { text="Reload UI", variant="danger", size="sm", onClick=ReloadUI })
    reloadBtn:SetPoint("BOTTOMRIGHT", -12, 12)
  else
    reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reloadBtn:SetPoint("BOTTOMRIGHT", -12, 12); reloadBtn:SetSize(120, 24)
    reloadBtn:SetText("Reload UI"); reloadBtn:SetScript("OnClick", ReloadUI)
  end

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
  local categories = GetCategories()
  if not categories[idx] then return end
  SetSelected(idx)
  for i, btn in ipairs(catButtons) do if btn.SetSelected then btn:SetSelected(i==idx) end end
  for _, frame in pairs(contentFrames) do if frame.Hide then frame:Hide() end end
  local cat = categories[idx]
  if cat.type == "separator" then return end
  local catKey = cat.key
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

  -- Acquire or create portrait texture (retail template usually provides one)
  local portrait = mainFrame.portrait or mainFrame.Portrait or (mainFrame.PortraitContainer and mainFrame.PortraitContainer.portrait)
  if not portrait then
    portrait = mainFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(58,58)
    portrait:SetPoint("TOPLEFT", 7, -6)
    if portrait.SetMask then
      portrait:SetMask("Interface/CharacterFrame/TempPortraitAlphaMask")
    end
  end
  portraitTex = portrait

  -- Sidebar
  local sidebarButtons = {}
  local rawCategories = (CATM() and CATM():GetAll()) or {}
  -- Enforce dev-mode visibility predicate for debug category (toggled via Config)
  local cfg = (Addon.require and Addon.require("Config")) or Addon.Config
  if cfg and cfg.IsDev then
    for _, c in ipairs(rawCategories) do
      if c.key == "debug" then
        c.visible = function() return cfg:IsDev() end
      end
    end
  end
  -- Now filter after predicate assignment
  local categories = {}
  local CM = CATM()
  for _, c in ipairs(rawCategories) do if CM:EvaluateVisibility(c) then categories[#categories+1] = c end end
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

  local CM = CATM(); local sel = (CM and CM.GetSelectedIndex and CM:GetSelectedIndex()) or 1
  UI:SelectCategory(sel)

  -- Initial portrait fill
  if UI.UpdatePortrait then UI:UpdatePortrait() end
  if mainFrame.HookScript then
    mainFrame:HookScript("OnShow", function() if UI.UpdatePortrait then UI:UpdatePortrait() end end)
  end

  -- Lightweight toast anchor
  if not UI._toastAnchor then
    local ta = CreateFrame("Frame", nil, mainFrame)
    ta:SetPoint("TOP", mainFrame, "TOP", 0, -26)
    ta:SetSize(W-240, 28)
    UI._toastAnchor = ta
  end
end

function UI:Show()
  if InCombatLockdown and InCombatLockdown() then print("|cffff5555[GuildRecruiter]|r Cannot open UI in combat."); return end
  if not mainFrame then UI:Build() end
  if mainFrame then mainFrame:Show() end
end

function UI:Hide()
  if mainFrame then mainFrame:Hide() end
end

-- Update (or fallback) the player's portrait
function UI:UpdatePortrait()
  if not portraitTex then return end
  local ok = pcall(SetPortraitTexture, portraitTex, "player")
  local tex = ok and portraitTex:GetTexture() or nil
  if not tex then
    -- Fallback to class icon
  local class = select(2, UnitClass("player")) or "PRIEST"
  local iconTable = rawget(_G, "CLASS_ICON_TCOORDS")
  local coords = iconTable and iconTable[class]
    portraitTex:SetTexture("Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES")
    if coords then portraitTex:SetTexCoord(unpack(coords)) else portraitTex:SetTexCoord(0,1,0,1) end
  else
    portraitTex:SetTexCoord(0,1,0,1) -- ensure normal portrait coords
  end
end

-- Event driver to keep portrait fresh
local portraitEvents = CreateFrame("Frame")
portraitEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
portraitEvents:RegisterEvent("UNIT_PORTRAIT_UPDATE")
portraitEvents:SetScript("OnEvent", function(_, ev, unit)
  if ev == "UNIT_PORTRAIT_UPDATE" and unit ~= "player" then return end
  if UI.UpdatePortrait then UI:UpdatePortrait() end
end)

-- Simple toast display (text fades out). durationSec optional (default 3)
function UI:ShowToast(msg, durationSec)
  if not mainFrame or not msg or msg=="" then return end
  UI._toastQueue = UI._toastQueue or (Queue and Queue.new() or {})
  if UI._toastQueue.Enqueue then
    UI._toastQueue:Enqueue({ text = msg, dur = durationSec or 3 })
  else
    table.insert(UI._toastQueue, { text = msg, dur = durationSec or 3 }) -- fallback
  end
  local function ensureFrame()
    local anchor = UI._toastAnchor or mainFrame
    local f = UI._toastFrame
    if not f then
      f = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
      UI._toastFrame = f
      f:SetFrameStrata("TOOLTIP")
      f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      f.text:SetPoint("CENTER")
      f.text:SetJustifyH("CENTER")
      f:SetAlpha(0)
    end
    f:ClearAllPoints(); f:SetPoint("TOP", anchor, "TOP", 0, 0)
    -- Style
    local edgeColor = (Tokens and Tokens.colors and Tokens.colors.accent and Tokens.colors.accent.base) or {0.8,0.7,0.1}
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12, tile = true, tileSize = 16, insets = { left=3,right=3,top=3,bottom=3 } })
    f:SetBackdropColor(0,0,0,0.82)
    f:SetBackdropBorderColor(edgeColor[1], edgeColor[2], edgeColor[3], 0.95)
    if not f._gradient then
      local g = f:CreateTexture(nil, "BACKGROUND", nil, -7)
      g:SetPoint("TOPLEFT", 2, -2)
      g:SetPoint("BOTTOMRIGHT", -2, 2)
      local grad = Tokens and Tokens.gradients and Tokens.gradients.buttonHover or { top={0.25,0.25,0.27,0.85}, bottom={0.10,0.10,0.11,0.92} }
      if UIHelpers and UIHelpers.ApplyGradient then UIHelpers.ApplyGradient(g, grad.top, grad.bottom) else g:SetColorTexture(0.15,0.15,0.16,0.85) end
      f._gradient = g
    end
    return f
  end
  local function dequeue()
    if UI._toastActive then return end
    local nextToast
    if UI._toastQueue.Dequeue then
      nextToast = UI._toastQueue:Dequeue()
      if not nextToast then return end
    else
      nextToast = table.remove(UI._toastQueue, 1)
    end
    if not nextToast then return end
    UI._toastActive = true
    local f = ensureFrame()
    f.text:SetText(nextToast.text)
    f:SetWidth(math.min(480, math.max(160, f.text:GetStringWidth() + 48)))
    f:SetHeight(f.text:GetStringHeight() + 22)
    f:Show(); f:SetAlpha(0)
    if UIHelpers and UIHelpers.Fade then
      UIHelpers.Fade(f, 1, 0.18, function()
        C_Timer.After(nextToast.dur, function()
          UIHelpers.Fade(f, 0, 0.25, function()
            f:Hide(); UI._toastActive = false; dequeue()
          end)
        end)
      end)
    else
      f:SetAlpha(1)
      C_Timer.After(nextToast.dur, function() f:Hide(); UI._toastActive=false; dequeue() end)
    end
  end
  dequeue()
end

Addon.provide("UI.Main", UI)
return UI
