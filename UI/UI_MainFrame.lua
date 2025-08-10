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
local Theme        = Addon.Get("Theme_Dragonfly") or Addon.Get("Theme")
local StyleMod     = Addon.Get("UI.Style")
local SidePanelMod = Addon.Get("UI.SidePanel") or (Addon.UI and Addon.UI.SidePanel)
local Tokens       = Addon.Get("Tools.Tokens")
local UIHelpers    = Addon.Get("Tools.UIHelpers")
local List         = Addon.Get("Collections.List") or Addon.List
local Queue        = Addon.Get("Collections.Queue")

local STYLE = { PAD = 12, GAP = 8, ROW_H = 24, COLORS = { SUBTLN = {1,1,1,0.07} } }
local TOAST = { FADE_IN = 0.18, FADE_OUT = 0.25, MAX = 5 }

-- Config helper (UI-only write of layout persistence keys)
local function CFG()
  return (Addon.Config) or (Addon.require and Addon.require("Config"))
end

local function LoadFrameState(f)
  local cfg = CFG(); if not (cfg and f) then return end
  local w = tonumber(cfg:Get("ui_main_w")) or nil
  local h = tonumber(cfg:Get("ui_main_h")) or nil
  local x = tonumber(cfg:Get("ui_main_l")) or nil
  local y = tonumber(cfg:Get("ui_main_t")) or nil
  if w and h and w > 300 and h > 300 then f:SetSize(math.min(w, 1400), math.min(h, 1000)) end
  if x and y then
    f:ClearAllPoints()
    -- Stored as left & top relative to UIParent bottom-left
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  end
end

local function SaveFrameState(f)
  local cfg = CFG(); if not (cfg and f) then return end
  if f:GetWidth() and f:GetHeight() then
    cfg:Set("ui_main_w", math.floor(f:GetWidth()+0.5))
    cfg:Set("ui_main_h", math.floor(f:GetHeight()+0.5))
  end
  local l = f:GetLeft(); local t = f:GetTop()
  if l and t then
    cfg:Set("ui_main_l", math.floor(l+0.5))
    cfg:Set("ui_main_t", math.floor(t+0.5))
  end
end

-- Category management via DI container (lazy accessor to avoid stale reference)
local function CATM()
  local cm = Addon.Get("Tools.CategoryManager")
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
  -- Determine which filtered index corresponds to the raw selected index/key
  local rawSel = CM:GetSelectedIndex() or 1
  local targetKey = raw[rawSel] and raw[rawSel].key
  local filteredIndex = nil
  if targetKey then
    for i, c in ipairs(filtered) do if c.key == targetKey then filteredIndex = i break end end
  end
  if not filteredIndex or not filtered[filteredIndex] or filtered[filteredIndex].type == "separator" then
    -- Fallback: pick first non-separator
    for i, c in ipairs(filtered) do if c.type ~= "separator" then filteredIndex = i break end end
  end
  if filteredIndex then sidebar:SelectIndex(filteredIndex) end
end

-- Subscribe to ConfigChanged devMode events (lazy registration after EventBus available)
local function EnsureDevModeSubscription()
  if UI._devModeSubscribed then return end
  local Bus = Addon.EventBus or (Addon.require and Addon.require("EventBus"))
  if not Bus or not Bus.Subscribe then return end
  Bus:Subscribe("ConfigChanged", function(_, key, value)
    if key == "devMode" then
      local cfg = (Addon.require and Addon.require("Config")) or Addon.Config
      -- Capture whether debug is currently selected BEFORE rebuild
      local wasDebugSelected = false
      do
        local CM = CATM()
        if CM and CM.GetSelectedIndex and CM.GetAll then
          local raw = CM:GetAll() or {}
            local sel = CM:GetSelectedIndex() or 1
            local cat = raw[sel]
            if cat and cat.key == "debug" then wasDebugSelected = true end
        end
      end
      -- Re-evaluate sidebar categories to show/hide debug tab
      local CM = CATM(); if CM and CM.EnsureInitialized then CM:EnsureInitialized() end
      if UI.RefreshCategories then UI:RefreshCategories() end
      -- If turning off and debug WAS selected, switch to summary; otherwise preserve current tab
      if (not cfg:Get("devMode", false)) and wasDebugSelected and UI.SelectCategoryByKey then
        UI:SelectCategoryByKey("summary")
      end
      if UI.ShowToast then
        local state = (value and true) and "Dev Mode ENABLED" or "Dev Mode DISABLED"
        -- Flush so the state change is always immediate & not hidden behind old toasts
        pcall(UI.ShowToast, UI, state, 3, true)
      end
    end
  end)
  UI._devModeSubscribed = true
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

-- Summary & Debug pages now live in separate modules (UI.Summary, UI.Debug).

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

local MODULE_MAP = {
  summary   = "UI.Summary",
  prospects = "UI.Prospects",
  blacklist = "UI.Blacklist",
  settings  = "UI.Settings",
  debug     = "UI.Debug",
}

function UI:SelectCategory(idx)
  local filtered = GetCategories()
  local cat = filtered[idx]
  if not cat or cat.type == "separator" then return end
  -- Map filtered cat back to raw index for persistence
  local CM = CATM(); local rawIdx = nil
  if CM and CM.GetAll then
    local raw = CM:GetAll() or {}
    for i, c in ipairs(raw) do if c == cat then rawIdx = i break end end
  end
  if rawIdx then SetSelected(rawIdx) end
  -- Visual selection among filtered buttons
  for i, btn in ipairs(catButtons) do if btn.SetSelected then btn:SetSelected(i==idx) end end
  -- Hide all pages, then show requested
  for _, frame in pairs(contentFrames) do if frame.Hide then frame:Hide() end end
  local page = contentFrames[cat.key]
  if not page then
    -- Lazy attach (especially for debug page, which we only instantiate when devMode true and requested)
    local modName = MODULE_MAP[cat.key]
    if modName then
      AttachPage(cat.key, modName)
      page = contentFrames[cat.key]
    end
    if not page then
      print("|cffff2222[GuildRecruiter][UI]|r Missing content for tab:", tostring(cat.key))
      return
    end
  end
  if page.Show then page:Show() end
  if page.Render then pcall(page.Render, page) end
end

function UI:Build()
  if mainFrame then return end
  local W, H = 940, 560
  mainFrame = CreateFrame("Frame", "GuildRecruiterFrame", UIParent, "PortraitFrameTemplate")
  mainFrame:SetSize(W, H); mainFrame:SetPoint("CENTER")
  -- Load persisted position/size before anything else adjusts
  LoadFrameState(mainFrame)
  mainFrame:SetFrameStrata("DIALOG"); mainFrame:EnableMouse(true); mainFrame:SetMovable(true)
  mainFrame:RegisterForDrag("LeftButton")
  mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
  mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing(); SaveFrameState(self) end)
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
  -- Now filter after predicate assignment
  local categories = {}
  local CM = CATM()
  for _, c in ipairs(rawCategories) do if CM:EvaluateVisibility(c) then categories[#categories+1] = c end end
  if SidePanelMod and SidePanelMod.Create then
    sidebar, sidebarButtons = SidePanelMod:Create(mainFrame, categories, function(i) UI:SelectCategory(i) end)
    sidebar:ClearAllPoints(); sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10)
  else
    sidebar = CreateFrame("Frame", nil, mainFrame, "InsetFrameTemplate3")
    sidebar:SetPoint("TOPLEFT", 6, -42); sidebar:SetPoint("BOTTOMLEFT", 6, 10); sidebar:SetWidth(140)
    local line = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
    line:SetAllPoints(); line:SetColorTexture(0,0,0,0.15)
  end
  catButtons = sidebarButtons

  -- Content
  contentParent = CreateFrame("Frame", nil, mainFrame, "InsetFrameTemplate3")
  contentParent:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
  contentParent:SetPoint("BOTTOMRIGHT", -12, 10)
  SkinCollectionsBackdrop(contentParent)
  if Theme and Theme.ApplyBackground then pcall(Theme.ApplyBackground, Theme, contentParent) end

  -- Pages
  AttachPage("summary",   MODULE_MAP.summary)
  AttachPage("prospects", MODULE_MAP.prospects)
  AttachPage("blacklist", MODULE_MAP.blacklist)
  AttachPage("settings",  MODULE_MAP.settings)
  -- Debug page now lazy-loaded only if devMode currently enabled
  local cfg = (Addon.require and Addon.require("Config")) or Addon.Config
  if cfg and cfg.Get and cfg:Get("devMode", false) then
    AttachPage("debug", MODULE_MAP.debug)
  end
  local CM = CATM(); local rawSel = (CM and CM.GetSelectedIndex and CM:GetSelectedIndex()) or 1
  -- Find filtered index matching rawSel key
  local raw = (CM and CM.GetAll and CM:GetAll()) or {}
  local targetKey = raw[rawSel] and raw[rawSel].key
  local filtered = GetCategories()
  local filteredIndex = 1
  if targetKey then
    for i, c in ipairs(filtered) do if c.key == targetKey then filteredIndex = i break end end
  end
  UI:SelectCategory(filteredIndex)

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

  -- Ensure we react to devMode changes via EventBus
  EnsureDevModeSubscription()

  -- Resize handle (bottom-right) with persistence
  if not mainFrame._resizer then
    local rh = CreateFrame("Frame", nil, mainFrame)
    rh:SetSize(16,16)
    rh:SetPoint("BOTTOMRIGHT", -2, 2)
    rh:EnableMouse(true)
    local tex = rh:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(); tex:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
    tex:SetVertexColor(1,1,1,0.15)
    rh:SetScript("OnEnter", function() tex:SetVertexColor(1,1,1,0.35) end)
    rh:SetScript("OnLeave", function() tex:SetVertexColor(1,1,1,0.15) end)
    rh:SetScript("OnMouseDown", function(_, btn)
      if btn=="LeftButton" then
        mainFrame:StartSizing("BOTTOMRIGHT")
        mainFrame:SetUserPlaced(true)
      end
    end)
    rh:SetScript("OnMouseUp", function(_, btn)
      if btn=="LeftButton" then
        mainFrame:StopMovingOrSizing()
        -- Clamp size
        local w = math.max(780, math.min(mainFrame:GetWidth(), 1400))
        local h = math.max(420, math.min(mainFrame:GetHeight(), 1000))
        mainFrame:SetSize(w, h)
        SaveFrameState(mainFrame)
      end
    end)
    mainFrame:SetResizable(true)
    mainFrame._resizer = rh
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
-- Show a transient toast. If flush==true, clear any queued toasts so the new one appears immediately.
function UI:ShowToast(msg, durationSec, flush)
  if not mainFrame or not msg or msg=="" then return end
  UI._toastQueue = UI._toastQueue or (Queue and Queue.new() or {})
  if flush then
    -- Clear queue & cancel active (simple approach: hide frame and mark inactive)
    if UI._toastQueue.Clear then
      UI._toastQueue:Clear()
    else
      -- fallback manual wipe
      for i=#UI._toastQueue,1,-1 do UI._toastQueue[i]=nil end
    end
    if UI._toastFrame then UI._toastFrame:Hide() end
    UI._toastActive = false
  end
  if UI._toastQueue.Enqueue then
    -- Enforce cap
    while (UI._toastQueue._count or 0) >= TOAST.MAX do
      -- consume one
      UI._toastQueue:Dequeue()
    end
    UI._toastQueue:Enqueue({ text = msg, dur = durationSec or 3 })
  else
    while #UI._toastQueue >= TOAST.MAX do table.remove(UI._toastQueue,1) end
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
      UIHelpers.Fade(f, 1, TOAST.FADE_IN, function()
        C_Timer.After(nextToast.dur, function()
          UIHelpers.Fade(f, 0, TOAST.FADE_OUT, function()
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
