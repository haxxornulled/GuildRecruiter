-- UI_MainFrame.lua
---@diagnostic disable: undefined-global, undefined-field, inject-field
---@diagnostic disable: undefined-global, undefined-field, inject-field, need-check-nil
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or _G[__args[1]] or {})
if type(ADDON_NAME) ~= "string" or ADDON_NAME == "" then ADDON_NAME = "GuildRecruiter" end
local UI = {}
Addon.UI = UI

-- Register UI.Main early, before any potential container build
if Addon and (Addon.safeProvide or Addon.provide) then
  -- Prefer idempotent registration to avoid duplicate/late provide errors
  if Addon.safeProvide then
    Addon.safeProvide("UI.Main", function() return UI end, { lifetime = "SingleInstance" })
  elseif not (Addon.IsProvided and Addon.IsProvided("UI.Main")) then
    Addon.provide("UI.Main", function() return UI end, { lifetime = "SingleInstance" })
  end
end

-- Lazy logger accessor (avoid top-level DI resolves)
local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Main")) or nil
end

-- Optional theme/style modules
-- Never call Addon.Get at file load (it builds the container). Use non-building peeks.
local Theme        = (Addon.Peek and (Addon.Peek("Theme_Dragonfly") or Addon.Peek("Theme"))) or nil
local StyleMod     = (Addon.Peek and Addon.Peek("UI.Style")) or nil
local SidePanelMod = (Addon.Peek and Addon.Peek("UI.SidePanel")) or (Addon.UI and Addon.UI.SidePanel)
local Tokens       = (Addon.Peek and Addon.Peek("Tools.Tokens")) or nil
local UIHelpers    = (Addon.Peek and Addon.Peek("Tools.UIHelpers")) or nil
local List         = (Addon.Peek and Addon.Peek("Collections.List")) or Addon.List
local Queue        = (Addon.Peek and Addon.Peek("Collections.Queue")) or nil

local STYLE = { PAD = 12, GAP = 8, ROW_H = 24, COLORS = { SUBTLN = {1,1,1,0.07} } }
local TOAST = { FADE_IN = 0.18, FADE_OUT = 0.25, MAX = 5 }
local SIDEBAR = { WIDTH = 140, SLIDE_DUR = 0.22 }

-- Config helper (UI-only write of layout persistence keys)
local function CFG()
  -- At runtime (on Show/Build), it's safe to resolve the real implementation.
  return (Addon.require and Addon.require("IConfiguration"))
      or ((Addon.Get and Addon.Get("IConfiguration")))
      or (Addon.Config) -- last resort, direct reference
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
  local cm = Addon.Get("UI.CategoryManager") or Addon.Get("Tools.CategoryManager")
  if cm and cm.EnsureInitialized then cm:EnsureInitialized() end
  return cm
end

-- Forward declare UI frame refs for functions defined before Build()
local mainFrame, sidebar, contentParent = nil, nil, nil
local sidebarToggle -- toggle button
local sidebarCollapsed = false
local sidebarWidth = SIDEBAR.WIDTH
local chatMiniCollapsed = false
local chatPanel -- holds { Frame, Feed, Input }

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
  ---@diagnostic disable-next-line: need-check-nil
  sidebar:SelectIndex(filteredIndex or 1)
end

-- Subscribe to ConfigChanged devMode events (lazy registration after EventBus available)
local devModeSubscribed = false
local function EnsureDevModeSubscription()
  if devModeSubscribed == true then return end
  local Bus = Addon.EventBus or (Addon.require and Addon.require("EventBus"))
  if not Bus or not Bus.Subscribe then return end
  Bus:Subscribe("ConfigChanged", function(_, key, value)
    if key == "devMode" then
  local cfg = (Addon.require and Addon.require("IConfiguration")) or (Addon.Get and Addon.Get("IConfiguration"))
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
  UI:RefreshCategories()
      -- If turning off and debug WAS selected, switch to summary; otherwise preserve current tab
      if (not cfg:Get("devMode", false)) and wasDebugSelected and UI.SelectCategoryByKey then
        UI:SelectCategoryByKey("summary")
      end
      
        local state = (value and true) and "Dev Mode ENABLED" or "Dev Mode DISABLED"
        -- Flush so the state change is always immediate & not hidden behind old toasts
    pcall(UI.ShowToast, UI, state, 3, true)
    end
  end)
  devModeSubscribed = true
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
  local CC = rawget(_G, 'CreateColor')
  local top = (type(CC)=='function' and CC(0.11,0.12,0.14,0.12)) or { GetRGBA=function() return 0.11,0.12,0.14,0.12 end }
  local bot = (type(CC)=='function' and CC(0.07,0.08,0.09,0.18)) or { GetRGBA=function() return 0.07,0.08,0.09,0.18 end }
    do
      local ok, t, b = pcall(function()
        local g = Theme and Theme.gradient
        local tt = g and g.top; local bb = g and g.bottom
        return tt, bb
      end)
      if ok then
        if type(CC)=='function' then
          -- if top/bottom are number arrays, convert to Color
          if type(t)=='table' and t[1] then top = CC(t[1], t[2], t[3], t[4] or 1) end
          if type(b)=='table' and b[1] then bot = CC(b[1], b[2], b[3], b[4] or 1) end
        else
          -- keep as rgba tables with GetRGBA accessor
          if type(t)=='table' and t[1] then top = { GetRGBA=function() return t[1],t[2],t[3],t[4] or 1 end } end
          if type(b)=='table' and b[1] then bot = { GetRGBA=function() return b[1],b[2],b[3],b[4] or 1 end } end
        end
      end
    end
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
  -- Create a wrapper panel so we can slide it independently of the page's own layout
  local panel = CreateFrame("Frame", nil, contentParent)
  panel:SetPoint("TOP", contentParent, "TOP", 0, 0)
  panel:SetPoint("BOTTOM", contentParent, "BOTTOM", 0, 0)
  panel:SetWidth(contentParent:GetWidth())
  panel:Hide()
  -- Inner page (actual content) created inside the panel
  local ok, mod = pcall(Addon.require, moduleName)
  if ok and mod and type(mod.Create) == "function" then
    local page = mod:Create(panel)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    -- Expose Render pass-through on panel
    panel._innerPage = page
    panel.Render = function(self) if self._innerPage and self._innerPage.Render then pcall(self._innerPage.Render, self._innerPage) end end
  else
    local fallback = CreateFrame("Frame", nil, panel); fallback:SetAllPoints()
    local msg = fallback:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    msg:SetPoint("CENTER"); msg:SetText(("|cffff5555%s failed.|r"):format(moduleName))
    panel._innerPage = fallback
    panel.Render = function() end
    local L = LOG(); if type(L) == 'table' and L.Warn then L:Warn("AttachPage failed {Mod}: {Err}", { Mod = moduleName, Err = tostring(mod) }) end
  end
  contentFrames[key] = panel
end

local MODULE_MAP = {
  summary   = "UI.Summary",
  prospects = "UI.Prospects",
  blacklist = "UI.Blacklist",
  settings  = "UI.Settings",
  debug     = "UI.Debug",
}

-- Slides the given panel in from fully-left offset to 0
local function SlideInPanel(panel)
  if not panel or not panel.SetPoint then return end
  local parent = contentParent
  local w = math.floor(parent:GetWidth() or 600)
  panel:ClearAllPoints()
  panel:SetPoint("TOP", parent, "TOP", 0, 0)
  panel:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
  panel:SetWidth(w)
  panel:SetPoint("LEFT", parent, "LEFT", -w, 0)
  panel:Show(); panel:SetAlpha(1)
  local dur = 0.22
  local ok = pcall(function()
    local AN = UIHelpers and UIHelpers.AnimateNumber
    if type(AN) == "function" then
      AN(-w, 0, dur, function(x)
        panel:ClearAllPoints()
        panel:SetPoint("TOP", parent, "TOP", 0, 0)
        panel:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
        panel:SetWidth(w)
        panel:SetPoint("LEFT", parent, "LEFT", x, 0)
      end, function()
        -- Snap to fill at end for responsive resizing
        panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
      end)
      return true
    end
  end)
  if not ok then
    -- Fallback: snap to final position
    panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  end
end

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
  SetSelected(rawIdx or 1)
  -- Visual selection among filtered buttons
  for i, btn in ipairs(catButtons) do if btn.SetSelected then btn:SetSelected(i==idx) end end
  -- Hide all panels, then show requested with slide-in effect
  for _, frame in pairs(contentFrames) do if frame.Hide then frame:Hide() end end
  local panel = contentFrames[cat.key]
  if not panel then
    -- Lazy attach (especially for debug page, which we only instantiate when devMode true and requested)
    local modName = MODULE_MAP[cat.key]
    AttachPage(cat.key, modName)
    panel = contentFrames[cat.key]
    if not panel then
      print("|cffff2222[GuildRecruiter][UI]|r Missing content for tab:", tostring(cat.key))
      return
    end
  end
  SlideInPanel(panel)
  if panel.Render then pcall(panel.Render, panel) end
end

function UI:Build()
  if not (mainFrame == nil) then return end
  -- Resolve optional modules now that UI is building (container should be registered by bootstrap)
  pcall(function()
    Theme        = (Addon.Get and (Addon.Get("Theme_Dragonfly") or Addon.Get("Theme"))) or Theme
    StyleMod     = (Addon.Get and Addon.Get("UI.Style")) or StyleMod
    SidePanelMod = (Addon.Get and Addon.Get("UI.SidePanel")) or SidePanelMod
    Tokens       = (Addon.Get and Addon.Get("Tools.Tokens")) or Tokens
    UIHelpers    = (Addon.Get and Addon.Get("Tools.UIHelpers")) or UIHelpers
    List         = (Addon.Get and Addon.Get("Collections.List")) or List
    Queue        = (Addon.Get and Addon.Get("Collections.Queue")) or Queue
  end)
  local W, H = 940, 560
  mainFrame = CreateFrame("Frame", "GuildRecruiterFrame", UIParent)
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

  -- Semi-transparent "glass" background for the whole main frame
  if not mainFrame._GR_Glass then
    local bg = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    local grad = Tokens and Tokens.gradients and Tokens.gradients.panel or { top={0.11,0.12,0.14,0.30}, bottom={0.07,0.08,0.09,0.45} }
    local applied = pcall(function()
      local AG = UIHelpers and UIHelpers.ApplyGradient; if type(AG)=="function" then AG(bg, grad.top, grad.bottom); return true end
    end)
    if not applied then bg:SetColorTexture(0.06,0.07,0.09,0.42) end
    -- Soft inner border
    local border = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
    border:SetPoint("TOPLEFT", 1, -1)
    border:SetPoint("BOTTOMRIGHT", -1, 1)
    border:SetColorTexture(1,1,1,0.06)
    mainFrame._GR_Glass = bg; mainFrame._GR_Border = border
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
  for _, c in ipairs(rawCategories) do
    if CM:EvaluateVisibility(c) then
      categories[#categories+1] = c
    end
  end
  if SidePanelMod and SidePanelMod.Create then
    sidebar, sidebarButtons = SidePanelMod:Create(mainFrame, categories, function(i) UI:SelectCategory(i) end)
    sidebar:ClearAllPoints()
    sidebar:SetPoint("TOPLEFT", 6, -42)
    sidebar:SetPoint("BOTTOMLEFT", 6, 10)
  else
    sidebar = CreateFrame("Frame", nil, mainFrame)
    sidebar:SetPoint("TOPLEFT", 6, -42)
    sidebar:SetPoint("BOTTOMLEFT", 6, 10)
    sidebar:SetWidth(140)
    local line = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
    line:SetAllPoints()
    line:SetColorTexture(0,0,0,0.15)
  end
  -- Cache intended width and apply a subtle translucent gradient for a "glass" feel
  sidebarWidth = math.floor(sidebar:GetWidth() or SIDEBAR.WIDTH)
  if not sidebar._GR_Glass then
    local glass = sidebar:CreateTexture(nil, "BACKGROUND", nil, -6)
    glass:SetAllPoints()
    local grad = Tokens and Tokens.gradients and Tokens.gradients.panel or { top={0.11,0.12,0.14,0.08}, bottom={0.07,0.08,0.09,0.14} }
    local applied = pcall(function()
      local AG = UIHelpers and UIHelpers.ApplyGradient
      if type(AG) == "function" then AG(glass, grad.top, grad.bottom); return true end
    end)
    if not applied then glass:SetColorTexture(0.10,0.10,0.12,0.12) end
    sidebar._GR_Glass = glass
  end
  catButtons = sidebarButtons

  -- Content
  contentParent = CreateFrame("Frame", nil, mainFrame)
  contentParent:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
  contentParent:SetPoint("BOTTOMRIGHT", -12, 10)
  SkinCollectionsBackdrop(contentParent)
  pcall(function()
    local fn = Theme and Theme.ApplyBackground
    if type(fn) == "function" then fn(Theme, contentParent) end
  end)

  -- Pages
  AttachPage("summary",   MODULE_MAP.summary)
  AttachPage("prospects", MODULE_MAP.prospects)
  AttachPage("blacklist", MODULE_MAP.blacklist)
  AttachPage("settings",  MODULE_MAP.settings)
  -- Debug page now lazy-loaded only if devMode currently enabled
  local cfg = (Addon.require and Addon.require("IConfiguration")) or Addon.Get and Addon.Get("IConfiguration")
  if cfg and cfg.Get and cfg:Get("devMode", false) then
    AttachPage("debug", MODULE_MAP.debug)
  end
  local CM = CATM();
  local rawSel = (CM and CM.GetSelectedIndex and CM:GetSelectedIndex()) or 1
  -- Find filtered index matching rawSel key
  local raw = (CM and CM.GetAll and CM:GetAll()) or {}
  local targetKey = raw[rawSel] and raw[rawSel].key
  local filtered = GetCategories()
  local filteredIndex = 1
  if targetKey then
    for i, c in ipairs(filtered) do
      if c.key == targetKey then filteredIndex = i; break end
    end
  end
  UI:SelectCategory(filteredIndex)

  -- Initial portrait fill
  UI:UpdatePortrait()
  if mainFrame.HookScript then
    mainFrame:HookScript("OnShow", function() UI:UpdatePortrait() end)
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

  -- Sidebar toggle button (collapses to 0 width and expands back)
  if not sidebarToggle then
  local btn = CreateFrame("Button", nil, mainFrame)
  btn:SetSize(28, 40)
    btn:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 2, -2)
    -- Background hover plate (very subtle)
    btn:SetNormalTexture("Interface/Buttons/WHITE8x8")
    btn:GetNormalTexture():SetVertexColor(1,1,1,0.02)
    btn:SetHighlightTexture("Interface/Buttons/WHITE8x8")
    btn:GetHighlightTexture():SetVertexColor(1,1,1,0.08)
    -- Arrow icon (use Blizzard HUD atlas if available)
    local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER")
  icon:SetSize(24, 34)
    btn._icon = icon
    local function setArrow(left)
      -- Prefer Dragonflight HUD atlases; if unavailable on this client, fall back to known textures
      local ok = false
      if icon.SetAtlas then
        -- Do NOT use atlas size; keep our custom size
        ok = icon:SetAtlas(left and "hud-MainMenuBar-arrowleft" or "hud-MainMenuBar-arrowright") or false
      end
      if not ok then
        icon:SetTexture(left and "Interface/Buttons/UI-SpellbookIcon-PrevPage-Up" or "Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
      end
      -- Re-assert intended size so atlas/texture changes never shrink the icon
  icon:SetSize(24, 34)
      icon:SetAlpha(0.85)
    end
    local function updateLabel()
      setArrow(not sidebarCollapsed)
    end
    btn:SetScript("OnClick", function()
      if not UIHelpers or not UIHelpers.SlideWidth then
        -- Fallback: hard toggle
        if sidebarCollapsed then sidebar:SetWidth(sidebarWidth) else sidebar:SetWidth(1) end
        sidebarCollapsed = not sidebarCollapsed
        updateLabel()
        return
      end
      if sidebarCollapsed then
        UIHelpers.SlideWidth(sidebar,  sidebar:GetWidth(), sidebarWidth, SIDEBAR.SLIDE_DUR, nil, function() sidebarCollapsed=false; updateLabel() end)
        -- gentle emphasis
        if UIHelpers.Fade then UIHelpers.Fade(sidebar, 1, 0.12) end
      else
        UIHelpers.SlideWidth(sidebar, sidebar:GetWidth(), 1, SIDEBAR.SLIDE_DUR, nil, function() sidebarCollapsed=true; updateLabel() end)
        if UIHelpers.Fade then UIHelpers.Fade(sidebar, 0.35, 0.12) end
      end
    end)
    updateLabel()
    sidebarToggle = btn
  end

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

  -- Docked chat mini-view at bottom of content area
  if not chatPanel then
    local ChatPanel = Addon.Get("UI.ChatPanel") or (Addon.require and Addon.require("UI.ChatPanel"))
    if ChatPanel and ChatPanel.Attach then
      chatPanel = ChatPanel:Attach(contentParent)
      local f = chatPanel and chatPanel.Frame or nil
      if f and f.SetPoint then
        f:ClearAllPoints()
        f:SetPoint("LEFT", contentParent, "LEFT", 0, 0)
        f:SetPoint("RIGHT", contentParent, "RIGHT", 0, 0)
        f:SetPoint("BOTTOM", contentParent, "BOTTOM", 0, 0)
      end
      -- Load persisted collapsed state
      local SV = Addon.Get and Addon.Get("SavedVarsService")
      local state = (SV and SV.Get and SV:Get("ui", "chatMiniCollapsed", false)) or false
      chatMiniCollapsed = not not state
      if f and f.SetShown then f:SetShown(not chatMiniCollapsed) end
      -- Toggle button near sidebar toggle (unified control area)
  local tbtn = CreateFrame("Button", nil, mainFrame)
  tbtn:SetSize(28, 28)
  -- place to the right of sidebar toggle (guaranteed initialized above); fallback position redundant
  tbtn:SetPoint("TOPLEFT", sidebarToggle or contentParent, sidebarToggle and "TOPRIGHT" or "BOTTOMRIGHT", 4, 0)
      -- Subtle hover plate
      tbtn:SetNormalTexture("Interface/Buttons/WHITE8x8")
      tbtn:GetNormalTexture():SetVertexColor(1,1,1,0.02)
      tbtn:SetHighlightTexture("Interface/Buttons/WHITE8x8")
      tbtn:GetHighlightTexture():SetVertexColor(1,1,1,0.08)
      local ico = tbtn:CreateTexture(nil, "ARTWORK")
  ico:SetPoint("CENTER")
  ico:SetSize(24, 24)
      tbtn._icon = ico
      local function updateLabel()
        -- Try modern atlases first, then fall back to scrollbar up/down textures that exist on all clients
        local ok = false
        if ico.SetAtlas then
          -- Keep our own size; don't let the atlas shrink the icon
          ok = ico:SetAtlas(chatMiniCollapsed and "hud-MainMenuBar-arrowup" or "hud-MainMenuBar-arrowdown") or false
        end
        if not ok then
          ico:SetTexture(chatMiniCollapsed and "Interface/Buttons/UI-ScrollBar-ScrollUpButton-Up" or "Interface/Buttons/UI-ScrollBar-ScrollDownButton-Up")
        end
        -- Ensure final size looks right regardless of atlas/texture source
  ico:SetSize(24, 24)
        ico:SetAlpha(0.9)
      end
      updateLabel()
      tbtn:SetScript("OnClick", function()
        chatMiniCollapsed = not chatMiniCollapsed
        if f and f.SetShown then f:SetShown(not chatMiniCollapsed) end
        updateLabel()
        local S = (Addon.Get and Addon.Get("SavedVarsService")) or (Addon.require and Addon.require("SavedVarsService"))
        if S and S.Set then S:Set("ui", "chatMiniCollapsed", chatMiniCollapsed); if S.Sync then S:Sync() end end
      end)
    end
  end
end

function UI:Show()
  if InCombatLockdown and InCombatLockdown() then print("|cffff5555[GuildRecruiter]|r Cannot open UI in combat."); return end
  if not mainFrame then UI:Build() end
  if mainFrame ~= nil then mainFrame:Show() end
end

function UI:Hide()
  if mainFrame ~= nil then mainFrame:Hide() end
end

function UI:Toggle()
  if not mainFrame or not mainFrame.IsShown or not mainFrame:IsShown() then
    self:Show()
  else
    self:Hide()
  end
end

-- Update (or fallback) the player's portrait
function UI:UpdatePortrait()
  if not portraitTex then return end
  local SPT = rawget(_G, 'SetPortraitTexture')
  local ok = (type(SPT)=='function') and pcall(SPT, portraitTex, "player") or false
  local tex = ok and portraitTex:GetTexture() or nil
  if not tex then
    -- Fallback to class icon
    local UCFn = rawget(_G,'UnitClass')
    local class = (type(UCFn)=='function' and select(2, UCFn("player"))) or "PRIEST"
    local iconTable = rawget(_G, "CLASS_ICON_TCOORDS")
    local coords = iconTable and iconTable[class]
    -- Clear mask to allow texcoord cropping for atlas sheet (safe if method exists)
    if portraitTex.ClearMask then pcall(portraitTex.ClearMask, portraitTex) end
    portraitTex:SetTexture("Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES")
    if coords then portraitTex:SetTexCoord(unpack(coords)) else portraitTex:SetTexCoord(0, 1, 0, 1) end
  else
    -- Do not call SetTexCoord on masked portrait; not needed for the player portrait
  end
end

-- Event driver to keep portrait fresh
local portraitEvents = CreateFrame("Frame")
portraitEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
portraitEvents:RegisterEvent("UNIT_PORTRAIT_UPDATE")
portraitEvents:SetScript("OnEvent", function(_, ev, unit)
  if ev == "UNIT_PORTRAIT_UPDATE" and unit ~= "player" then return end
  UI:UpdatePortrait()
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
  if UI._toastFrame ~= nil then UI._toastFrame:Hide() end
  UI._toastActive = 0
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
  f = CreateFrame("Frame", nil, anchor)
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
    if not f._bg then
      local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
      bg:SetAllPoints(); bg:SetColorTexture(0,0,0,0.82); f._bg = bg
      local border = f:CreateTexture(nil, "BACKGROUND", nil, -7)
      border:SetPoint("TOPLEFT", 1, -1)
      border:SetPoint("BOTTOMRIGHT", -1, 1)
      border:SetColorTexture(edgeColor[1], edgeColor[2], edgeColor[3], 0.95)
      f._border = border
    end
    if not f._gradient then
      local g = f:CreateTexture(nil, "BACKGROUND", nil, -7)
      g:SetPoint("TOPLEFT", 2, -2)
      g:SetPoint("BOTTOMRIGHT", -2, 2)
      local grad = Tokens and Tokens.gradients and Tokens.gradients.buttonHover or { top={0.25,0.25,0.27,0.85}, bottom={0.10,0.10,0.11,0.92} }
      local applied = pcall(function()
        local AG = UIHelpers and UIHelpers.ApplyGradient; if type(AG)=="function" then AG(g, grad.top, grad.bottom); return true end
      end)
      if not applied then g:SetColorTexture(0.15,0.15,0.16,0.85) end
      f._gradient = g
    end
    return f
  end
  local function dequeue()
    local activeFlag = tonumber(rawget(UI, "_toastActive") or 0)
    if activeFlag ~= 0 then return end
    local nextToast
    if UI._toastQueue.Dequeue then
      nextToast = UI._toastQueue:Dequeue()
      if not nextToast then return end
    else
      nextToast = table.remove(UI._toastQueue, 1)
    end
    if not nextToast then return end
  UI._toastActive = 1
    local f = ensureFrame()
    f.text:SetText(nextToast.text)
    f:SetWidth(math.min(480, math.max(160, f.text:GetStringWidth() + 48)))
    f:SetHeight(f.text:GetStringHeight() + 22)
    f:Show(); f:SetAlpha(0)
    local F = UIHelpers and UIHelpers.Fade
    if type(F) == "function" then
      F(f, 1, TOAST.FADE_IN, function()
        C_Timer.After(nextToast.dur, function()
          F(f, 0, TOAST.FADE_OUT, function()
            f:Hide(); UI._toastActive = 0; dequeue()
          end)
        end)
      end)
    else
      f:SetAlpha(1)
      C_Timer.After(nextToast.dur, function() f:Hide(); UI._toastActive=0; dequeue() end)
    end
  end
  dequeue()
end

return UI
