-- UI.Settings.lua — Settings page with improved padding and spacing
local Addon = select(2, ...)

-- Analyzer-safe guards for WoW globals (stubs when not in-game)
local _G = _G or {}
local ChatFontNormal = rawget(_G, "ChatFontNormal") or {}
local C_Timer = rawget(_G, "C_Timer") or { After = function(_, fn) if type(fn) == 'function' then pcall(fn) end end }
local PlaySound = rawget(_G, "PlaySound") or function(...) end
local SOUNDKIT = rawget(_G, "SOUNDKIT") or {}
local UIDropDownMenu_SetText = rawget(_G, "UIDropDownMenu_SetText") or function(...) end
local UIDropDownMenu_SetWidth = rawget(_G, "UIDropDownMenu_SetWidth") or function(...) end
local UIDropDownMenu_Initialize = rawget(_G, "UIDropDownMenu_Initialize") or function(...) end
local UIDropDownMenu_CreateInfo = rawget(_G, "UIDropDownMenu_CreateInfo") or function(...) return {} end
local UIDropDownMenu_AddButton = rawget(_G, "UIDropDownMenu_AddButton") or function(...) end
local CreateFrame = rawget(_G, "CreateFrame") or (function()
  local function noop(...) end
  local function makeFS() return {
    SetPoint = noop, SetText = noop, SetWidth = noop, SetJustifyH = noop,
    SetJustifyV = noop, SetTextColor = noop, SetFontObject = noop,
  } end
  local function frameStub()
    return {
      SetAllPoints = noop, Hide = noop, Show = noop, IsShown = function() return false end,
      SetPoint = noop, SetSize = noop, SetBackdrop = noop, SetBackdropColor = noop,
      SetBackdropBorderColor = noop, CreateFontString = function(...) return makeFS() end,
      CreateTexture = function(...) return { SetColorTexture = noop, SetPoint = noop, SetHeight = noop, SetAllPoints = noop } end,
      GetFrameLevel = function() return 1 end, SetFrameLevel = noop, EnableMouseWheel = noop,
      EnableMouse = noop, SetScript = noop, HookScript = noop, SetScrollChild = noop,
      SetObeyStepOnDrag = noop, SetMinMaxValues = noop, SetValueStep = noop, SetValue = noop,
      GetWidth = function() return 400 end,
    }
  end
  return function(ftype, name, parent, template) return frameStub() end
end)()

local SettingsUI = {}
local PAD, GAP = 16, 12 -- Increased base padding

-- Lazy logger accessor
local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Settings")) or nil
end

local function CreateCheck(parent, text, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
  -- Avoid injecting fields; create a separate label
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", cb, "RIGHT", 4, 0); label:SetText(text)
  label:SetTextColor(0.9, 0.9, 0.9)
  cb:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if onClick then onClick(self:GetChecked() and true or false) end
  end)
  return cb
end

local function CreateSlider(parent, title, minV, maxV, step, initV, fmt, onChanged)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetObeyStepOnDrag(true); s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetSize(220, 16)
  -- Use separate labels; avoid touching template internals (Low/High/Text)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); label:SetText(title)
  label:SetTextColor(0.9, 0.8, 0.6) -- Gold tint
  local val   = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  val:SetTextColor(0.8, 0.8, 0.9) -- Light blue
  local function render(v) val:SetText(fmt and fmt(v) or tostring(v)) end
  s:SetScript("OnValueChanged", function(_, v)
    v = (step >= 1) and math.floor(v + 0.5) or tonumber(string.format("%.2f", v))
    render(v); if onChanged then onChanged(v) end
  end)
  s:SetValue(initV); render(initV)
  return s, label, val
end

local function CreateDropdown(parent, width)
  local f = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(f, width or 240); return f
end

function SettingsUI:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(parent)

  -- Add semi-transparent background to match other pages
  local bgFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
  bgFrame:SetAllPoints()
  bgFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  bgFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.85) -- Dark semi-transparent
  bgFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
  bgFrame:SetFrameLevel(f:GetFrameLevel() + 1)
  f:SetFrameLevel(bgFrame:GetFrameLevel() + 1)

  local Config = (Addon.require and Addon.require("IConfiguration")) or (Addon.Get and Addon.Get("IConfiguration"))
  local Bus    = Addon.EventBus
  -- Defer logger retrieval on-demand to avoid analyzer's impossible branch warnings
  -- local Log = LOG()

  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 8, -PAD - 8)
  header:SetText("Settings")
  header:SetTextColor(0.9, 0.8, 0.6) -- Gold tint

  -- Scroll container (pattern similar to UI_Prospects: fixed header, scrollable body)
  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -8)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 24, PAD + 8)
  local content = CreateFrame("Frame", nil, scroll)
  -- Explicit initial size; width adjusted dynamically on scroll frame resize.
  content:SetSize(scroll:GetWidth() - 28, 400)
  -- Anchor top-left so scrolling behaves; avoid anchoring RIGHT simultaneously (scroll child prefers fixed width).
  content:SetPoint("TOPLEFT")
  scroll:HookScript("OnSizeChanged", function(self, w)
    local newW = math.max(300, (w or 0) - 28)
    if math.abs((content:GetWidth() or 0) - newW) > 0.5 then
  content:SetWidth(newW)
  -- force a deferred recalculation
  C_Timer.After(0, content._recalc)
    end
  end)
  scroll:SetScrollChild(content)
  f._scrollContent = content

  local grid = CreateFrame("Frame", nil, content, "InsetFrameTemplate3")
  grid:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
  grid:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -4)
  grid:SetHeight(230)

  local left  = CreateFrame("Frame", nil, grid);  left:SetPoint("TOPLEFT", 10, -10); left:SetPoint("BOTTOM", grid, "BOTTOM", -8, 10); left:SetPoint("RIGHT", grid, "CENTER", -9, 0)
  local right = CreateFrame("Frame", nil, grid); right:SetPoint("TOPRIGHT", -10, -10); right:SetPoint("BOTTOM", grid, "BOTTOM", 8, 10); right:SetPoint("LEFT", grid, "CENTER", 9, 0)

  -- Rotation enable
  local enableCB = CreateCheck(left, "Enable Broadcast Rotation", function(enabled)
    Config:Set("broadcastEnabled", enabled)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "broadcastEnabled", enabled) end
  -- optional log omitted for analyzer cleanliness
  end)
  enableCB:SetPoint("TOPLEFT", 0, 0)
  enableCB:SetChecked((Config:Get("broadcastEnabled") and true) or false)

  -- Base interval
  local sInterval, lblInterval, valInterval = CreateSlider(
    left, "Base Interval (seconds)", 60, 900, 5,
    tonumber(Config:Get("broadcastInterval")) or 300,
    function(v) return string.format("%ds", v) end,
    function(v) Config:Set("broadcastInterval", v); if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "broadcastInterval", v) end end
  )
  lblInterval:SetPoint("BOTTOMLEFT", sInterval, "TOPLEFT", 0, 6)
  sInterval:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -18)
  valInterval:SetPoint("LEFT", sInterval, "RIGHT", 10, 0)

  -- Jitter
  local sJitter, lblJitter, valJitter = CreateSlider(
    left, "Interval Jitter (± %)", 0, 50, 1,
    math.floor((tonumber(Config:Get("jitterPercent")) or 0.15) * 100 + 0.5),
    function(v) return string.format("%d%%", v) end,
    function(v)
      local pct = math.max(0, math.min(50, v))/100.0
      Config:Set("jitterPercent", pct)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "jitterPercent", pct) end
    end
  )
  lblJitter:SetPoint("BOTTOMLEFT", sJitter, "TOPLEFT", 0, 6)
  sJitter:SetPoint("TOPLEFT", sInterval, "BOTTOMLEFT", 0, -22)
  valJitter:SetPoint("LEFT", sJitter, "RIGHT", 10, 0)

  -- Invite button cooldown (0..10s)
  local sInviteCD, lblInviteCD, valInviteCD = CreateSlider(
    left, "Invite button cooldown (sec)", 0, 10, 1,
    tonumber(Config:Get("inviteClickCooldown", 3)) or 3,
    function(v) return string.format("%ds", v) end,
    function(v)
      Config:Set("inviteClickCooldown", v)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "inviteClickCooldown", v) end
  -- optional log omitted for analyzer cleanliness
    end
  )
  lblInviteCD:SetPoint("BOTTOMLEFT", sInviteCD, "TOPLEFT", 0, 6)
  sInviteCD:SetPoint("TOPLEFT", sJitter, "BOTTOMLEFT", 0, -22)
  valInviteCD:SetPoint("LEFT", sInviteCD, "RIGHT", 10, 0)

  -- Invite status pill duration (0..10s)
  local sInvitePill, lblInvitePill, valInvitePill = CreateSlider(
    left, "Invite status pill duration (sec)", 0, 10, 1,
    tonumber(Config:Get("invitePillDuration", 3)) or 3,
    function(v) return string.format("%ds", v) end,
    function(v)
      Config:Set("invitePillDuration", v)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "invitePillDuration", v) end
  -- optional log omitted for analyzer cleanliness
    end
  )
  lblInvitePill:SetPoint("BOTTOMLEFT", sInvitePill, "TOPLEFT", 0, 6)
  sInvitePill:SetPoint("TOPLEFT", sInviteCD, "BOTTOMLEFT", 0, -22)
  valInvitePill:SetPoint("LEFT", sInvitePill, "RIGHT", 10, 0)

  -- Invite cycling toggle
  local cycleCB = CreateCheck(left, "Cycle invite whisper messages", function(on)
    Config:Set("inviteCycleEnabled", on and true or false)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "inviteCycleEnabled", on and true or false) end
  end)
  cycleCB:SetPoint("TOPLEFT", sInvitePill, "BOTTOMLEFT", 0, -18)
  cycleCB:SetChecked(Config:Get("inviteCycleEnabled", true) and true or false)

  -- Auto-blacklist declines toggle
  local autoBlacklistCB = CreateCheck(left, "Auto-blacklist invite declines", function(on)
    Config:Set("autoBlacklistDeclines", on and true or false)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "autoBlacklistDeclines", on and true or false) end
  end)
  autoBlacklistCB:SetPoint("TOPLEFT", cycleCB, "BOTTOMLEFT", 0, -12)
  autoBlacklistCB:SetChecked(Config:Get("autoBlacklistDeclines", true) and true or false)

  -- Invite history cap slider
  local sHist, lblHist, valHist = CreateSlider(
    left, "Invite History Cap", 100, 5000, 50,
    tonumber(Config:Get("inviteHistoryMax", 1000)) or 1000,
    function(v) return tostring(v) end,
    function(v)
      Config:Set("inviteHistoryMax", v)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "inviteHistoryMax", v) end
  -- optional log omitted for analyzer cleanliness
    end
  )
  lblHist:SetPoint("BOTTOMLEFT", sHist, "TOPLEFT", 0, 6)
  sHist:SetPoint("TOPLEFT", autoBlacklistCB, "BOTTOMLEFT", 0, -26)
  valHist:SetPoint("LEFT", sHist, "RIGHT", 10, 0)

  -- Dev Mode toggle (top of right column)
  local devCB = CreateCheck(right, "Developer Mode (show Debug tab)", function(on)
    local newVal = on and true or false
    Config:Set("devMode", newVal)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "devMode", newVal) end
    if Addon.UI and Addon.UI.Main and Addon.UI.Main.ShowToast then
      pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, newVal and "Dev Mode ENABLED" or "Dev Mode DISABLED", 3, true)
    end
  end)
  devCB:SetPoint("TOPLEFT", 0, 0)
  devCB:SetChecked(Config:Get("devMode", false) and true or false)

  -- Dispose container toggle (right column, under dev mode)
  local disposeCB = CreateCheck(right, "Dispose DI container on logout", function(on)
    Config:Set("disposeContainerOnShutdown", on and true or false)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "disposeContainerOnShutdown", on and true or false) end
  end)
  disposeCB:SetPoint("TOPLEFT", devCB, "BOTTOMLEFT", 0, -12)
  disposeCB:SetChecked(Config:Get("disposeContainerOnShutdown", true) and true or false)

  -- Chat overlay: close in combat (right column)
  local overlayCloseCB = CreateCheck(right, "Close Chat Overlay in combat", function(on)
    Config:Set("chatOverlayCloseInCombat", on and true or false)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "chatOverlayCloseInCombat", on and true or false) end
  end)
  overlayCloseCB:SetPoint("TOPLEFT", disposeCB, "BOTTOMLEFT", 0, -12)
  overlayCloseCB:SetChecked(Config:Get("chatOverlayCloseInCombat", true) and true or false)

  -- Channel dropdown (right column)
  local chLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  chLabel:SetPoint("TOPLEFT", disposeCB, "BOTTOMLEFT", 0, -14); chLabel:SetText("Broadcast Channel")
  chLabel:SetTextColor(0.9, 0.8, 0.6) -- Gold tint
  local chanDrop = CreateDropdown(right, 240); chanDrop:SetPoint("TOPLEFT", chLabel, "BOTTOMLEFT", -16, -6)
  local current = Config:Get("broadcastChannel") or "AUTO"
  local function OnSelect(_, arg1, valueText)
    current = arg1; Config:Set("broadcastChannel", arg1)
    UIDropDownMenu_SetText(chanDrop, valueText or arg1)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "broadcastChannel", arg1) end
  end
  UIDropDownMenu_Initialize(chanDrop, function()
    local info = UIDropDownMenu_CreateInfo(); info.func = function(self, spec) OnSelect(self, spec, self.valueText) end; info.minWidth=240
    for _, e in ipairs({
      {display="AUTO (Trade > General > Say)", spec="AUTO"},
      {display="SAY", spec="SAY"}, {display="YELL", spec="YELL"},
      {display="GUILD", spec="GUILD"}, {display="OFFICER", spec="OFFICER"},
      {display="INSTANCE_CHAT", spec="INSTANCE_CHAT"},
      {display="CHANNEL:Trade", spec="CHANNEL:Trade"},
      {display="CHANNEL:General", spec="CHANNEL:General"},
    }) do
      info.text=e.display; info.value=e.spec; info.arg1=e.spec; info.checked=(e.spec==current); info.valueText=e.display
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetText(chanDrop, current=="AUTO" and "AUTO (Trade > General > Say)" or current)

  -- Rotation Messages container with improved spacing
  local msgsFrame = CreateFrame("Frame", nil, content, "InsetFrameTemplate3")
  msgsFrame:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 4, -PAD)
  msgsFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, 0)
  msgsFrame:SetHeight(450) -- Increased height for better spacing

  local msgHeader = msgsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  msgHeader:SetPoint("TOPLEFT", PAD, -PAD) -- Better header positioning
  msgHeader:SetText("Rotation Messages")
  msgHeader:SetTextColor(0.9, 0.8, 0.6) -- Gold tint

  -- Enhanced multiline editors for the 3 rotation messages with improved layout
  local editors = {}
  local TOKEN_HINT = "Tokens: {Guild} {Player} {Class} {Level} {Realm} {Date} {Time}"
  
  local function CreateMessageEditor(label, key, yOffset, placeholderText)
    local container = CreateFrame("Frame", nil, msgsFrame, "BackdropTemplate")
    container:SetBackdrop({ 
      bgFile = "Interface/Buttons/WHITE8x8", 
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border", 
      edgeSize = 12, 
      tile = true, 
      tileSize = 16, 
      insets = { left = 4, right = 4, top = 4, bottom = 4 } 
    })
    -- Better contrast for text areas
    container:SetBackdropColor(0.08, 0.08, 0.10, 0.90)
    container:SetBackdropBorderColor(0.35, 0.35, 0.40, 0.85)
    
    -- Position with much better spacing
    container:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", 0, yOffset)
    container:SetPoint("RIGHT", msgsFrame, "RIGHT", -24, 0) -- Increased right margin
    container:SetHeight(100) -- Increased height for breathing room

    -- Add subtle gradient
    local grad = container:CreateTexture(nil, "BACKGROUND", nil, -7)
    grad:SetPoint("TOPLEFT", 3, -3)
    grad:SetPoint("BOTTOMRIGHT", -3, 3)
    grad:SetColorTexture(0.12, 0.12, 0.14, 0.3)

    -- Message label with better spacing
    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 12, -8) -- More padding from edge
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.8, 0.6)

    -- Create the text input area using InputScrollFrameTemplate
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "InputScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -8) -- More space below label
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -16, 32) -- Much more room for counter
    
    -- Configure the EditBox
    local editBox = scrollFrame.EditBox
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(255)
    editBox:SetTextInsets(8, 8, 6, 6) -- Much better text padding
    
    -- Hide the default character count
    if scrollFrame.CharCount then 
      scrollFrame.CharCount:Hide() 
    end

    -- Custom character counter with much better positioning
    local counter = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    counter:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -12, 8) -- Much better positioning
    counter:SetTextColor(0.70, 0.70, 0.72, 0.90)

    -- Placeholder text with proper insets
    local placeholder = container:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholder:SetPoint("TOPLEFT", editBox, "TOPLEFT", 8, -6) -- Match text insets
    placeholder:SetJustifyH("LEFT")
    placeholder:SetJustifyV("TOP")
    placeholder:SetTextColor(0.5, 0.5, 0.55, 0.7)
    placeholder:SetText(placeholderText or "Enter recruitment message...")

    -- Update functions
    local function UpdateCounter()
      local len = editBox:GetNumLetters() or 0
      local pct = len / 255
      if pct >= 0.95 then 
        counter:SetTextColor(1, 0.15, 0.15, 1)
      elseif pct >= 0.85 then 
        counter:SetTextColor(1, 0.55, 0.10, 1)
      elseif pct >= 0.70 then 
        counter:SetTextColor(1, 0.85, 0.10, 1)
      else 
        counter:SetTextColor(0.70, 0.70, 0.72, 0.90) 
      end
      counter:SetText(string.format("%d/255", len))
    end

    local function UpdatePlaceholder()
      local text = editBox:GetText() or ""
      placeholder:SetShown(text == "")
    end

    -- Event handlers
    editBox:SetScript("OnEditFocusLost", function(self)
      local text = self:GetText() or ""
      Config:Set(key, text)
      if Bus and Bus.Publish then 
        Bus:Publish("ConfigChanged", key, text) 
      end
  -- optional log omitted for analyzer cleanliness
    end)

    editBox:SetScript("OnTextChanged", function(self, userInput)
      if userInput then
        UpdateCounter()
        UpdatePlaceholder()
      end
    end)

    editBox:SetScript("OnEscapePressed", function(self) 
      self:ClearFocus() 
    end)

    editBox:SetScript("OnEnterPressed", function(self) 
      self:Insert("\n") 
    end)

    -- Mouse wheel support for scrolling
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
      if scroll and scroll.GetVerticalScroll and scroll.SetVerticalScroll then
        local cur = scroll:GetVerticalScroll() or 0
        local step = 24
        scroll:SetVerticalScroll(math.max(0, cur - (delta * step)))
      end
    end)

    -- Initialize with saved value
    editBox:SetText(Config:Get(key, ""))
    UpdateCounter()
    UpdatePlaceholder()

    editors[#editors + 1] = editBox
    return container, editBox
  end

  -- Create the three message editors with much better spacing
  local c1, e1 = CreateMessageEditor("Message 1", "customMessage1", -20, "Intro / hook message...")
  local c2, e2 = CreateMessageEditor("Message 2", "customMessage2", -132, "Benefits / what we offer...")
  local c3, e3 = CreateMessageEditor("Message 3", "customMessage3", -244, "Call to action / contact...")

  -- Add token hint at the bottom with better positioning
  local tokenHint = msgsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tokenHint:SetPoint("TOPLEFT", c3, "BOTTOMLEFT", 8, -12) -- Better spacing
  tokenHint:SetTextColor(0.60, 0.75, 0.95, 0.85)
  tokenHint:SetText(TOKEN_HINT)

  -- Recalculate content height with new spacing
  local function Recalc()
  local totalHeight = 4 + 230 + PAD + 450 + PAD + 60 -- extra space for footer buttons
    content:SetHeight(totalHeight)
  end
  
  content._recalc = Recalc
  C_Timer.After(0.1, Recalc)

  function f:Render() 
    -- Refresh any dynamic content if needed
  end

  -- Footer actions (Reset to Defaults)
  local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  resetBtn:SetSize(160, 24)
  resetBtn:SetPoint("TOPLEFT", msgsFrame, "BOTTOMLEFT", 0, -40)
  resetBtn:SetText("Reset to Defaults")
  resetBtn:SetScript("OnClick", function()
    local ok, cfg = pcall(function() return Config end)
    if ok and cfg and cfg.Reset then
      cfg:Reset()
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "*reset*", true) end
      -- Re-render sliders / checkboxes with fresh values
      enableCB:SetChecked(cfg:Get("broadcastEnabled") and true or false)
      sInterval:SetValue(tonumber(cfg:Get("broadcastInterval")) or 300)
      sJitter:SetValue(math.floor((tonumber(cfg:Get("jitterPercent")) or 0.15) * 100 + 0.5))
      sInviteCD:SetValue(tonumber(cfg:Get("inviteClickCooldown", 3)) or 3)
      sInvitePill:SetValue(tonumber(cfg:Get("invitePillDuration", 3)) or 3)
      cycleCB:SetChecked(cfg:Get("inviteCycleEnabled", true) and true or false)
      autoBlacklistCB:SetChecked(cfg:Get("autoBlacklistDeclines", true) and true or false)
      sHist:SetValue(tonumber(cfg:Get("inviteHistoryMax", 1000)) or 1000)
      devCB:SetChecked(cfg:Get("devMode", false) and true or false)
      disposeCB:SetChecked(cfg:Get("disposeContainerOnShutdown", true) and true or false)
      overlayCloseCB:SetChecked(cfg:Get("chatOverlayCloseInCombat", true) and true or false)
      e1:SetText(cfg:Get("customMessage1", ""))
      e2:SetText(cfg:Get("customMessage2", ""))
      e3:SetText(cfg:Get("customMessage3", ""))
            local current = cfg:Get("broadcastChannel") or "AUTO"
            UIDropDownMenu_SetText(chanDrop, current == "AUTO" and "AUTO (Trade > General > Say)" or current)
      if Addon.UI and Addon.UI.Main and Addon.UI.Main.ShowToast then
        pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, "Settings reset", 3)
      end
    else
      print("|cffff5555[GR]|r Reset failed")
    end
  end)
  
  return f
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
