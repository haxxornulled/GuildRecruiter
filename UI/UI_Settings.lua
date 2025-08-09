-- UI.Settings.lua — Settings page (uses Config + EventBus)
local _, Addon = ...

local SettingsUI = {}
local PAD, GAP = 12, 10

-- Lazy logger accessor
local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Settings")) or nil
end

local function CreateCheck(parent, text, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
  cb.Text = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.Text:SetPoint("LEFT", cb, "RIGHT", 4, 0); cb.Text:SetText(text)
  cb:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if onClick then onClick(self:GetChecked() and true or false) end
  end)
  return cb
end

local function CreateSlider(parent, title, minV, maxV, step, initV, fmt, onChanged)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetObeyStepOnDrag(true); s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetSize(220, 16)
  if s.Low then s.Low:SetText("") end; if s.High then s.High:SetText("") end; if s.Text then s.Text:SetText("") end
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); label:SetText(title)
  local val   = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local function render(v) val:SetText(fmt and fmt(v) or tostring(v)) end
  s:SetScript("OnValueChanged", function(_, v)
    v = (step >= 1) and math.floor(v + 0.5) or tonumber(string.format("%.2f", v))
    render(v); if onChanged then onChanged(v) end
  end)
  s:SetValue(initV); render(initV); s._label, s._valText = label, val
  return s
end

local function CreateDropdown(parent, width)
  local f = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(f, width or 240); return f
end

function SettingsUI:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(parent)

  local Config = Addon.Config
  local Bus    = Addon.EventBus
  local Log    = LOG()

  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD); header:SetText("Settings")

  local grid = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
  grid:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -PAD + 4, -GAP)
  grid:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -GAP)
  grid:SetHeight(210) -- +30 to make space for the extra slider row

  local left  = CreateFrame("Frame", nil, grid);  left:SetPoint("TOPLEFT", 10, -10); left:SetPoint("BOTTOM", grid, "BOTTOM", -8, 10); left:SetPoint("RIGHT", grid, "CENTER", -9, 0)
  local right = CreateFrame("Frame", nil, grid); right:SetPoint("TOPRIGHT", -10, -10); right:SetPoint("BOTTOM", grid, "BOTTOM", 8, 10); right:SetPoint("LEFT", grid, "CENTER", 9, 0)

  -- Rotation enable
  local enableCB = CreateCheck(left, "Enable Broadcast Rotation", function(enabled)
    Config:Set("broadcastEnabled", enabled)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "broadcastEnabled", enabled) end
    if Log then Log:Info("BroadcastEnabled={Val}", { Val = enabled }) end
  end)
  enableCB:SetPoint("TOPLEFT", 0, 0)
  enableCB:SetChecked((Config:Get("broadcastEnabled") and true) or false)

  -- Base interval
  local sInterval = CreateSlider(
    left, "Base Interval (seconds)", 60, 900, 5,
    tonumber(Config:Get("broadcastInterval")) or 300,
    function(v) return string.format("%ds", v) end,
    function(v) Config:Set("broadcastInterval", v); if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "broadcastInterval", v) end end
  )
  sInterval._label:SetPoint("BOTTOMLEFT", sInterval, "TOPLEFT", 0, 6)
  sInterval:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -18)
  sInterval._valText:SetPoint("LEFT", sInterval, "RIGHT", 10, 0)

  -- Jitter
  local sJitter = CreateSlider(
    left, "Interval Jitter (± %)", 0, 50, 1,
    math.floor((tonumber(Config:Get("jitterPercent")) or 0.15) * 100 + 0.5),
    function(v) return string.format("%d%%", v) end,
    function(v)
      local pct = math.max(0, math.min(50, v))/100.0
      Config:Set("jitterPercent", pct)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "jitterPercent", pct) end
    end
  )
  sJitter._label:SetPoint("BOTTOMLEFT", sJitter, "TOPLEFT", 0, 6)
  sJitter:SetPoint("TOPLEFT", sInterval, "BOTTOMLEFT", 0, -22)
  sJitter._valText:SetPoint("LEFT", sJitter, "RIGHT", 10, 0)

  -- Invite button cooldown (0..10s)
  local sInviteCD = CreateSlider(
    left, "Invite button cooldown (sec)", 0, 10, 1,
    tonumber(Config:Get("inviteClickCooldown", 3)) or 3,
    function(v) return string.format("%ds", v) end,
    function(v)
      Config:Set("inviteClickCooldown", v)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "inviteClickCooldown", v) end
      if Log then Log:Debug("Invite cooldown set {Val}", { Val = v }) end
    end
  )
  sInviteCD._label:SetPoint("BOTTOMLEFT", sInviteCD, "TOPLEFT", 0, 6)
  sInviteCD:SetPoint("TOPLEFT", sJitter, "BOTTOMLEFT", 0, -22)
  sInviteCD._valText:SetPoint("LEFT", sInviteCD, "RIGHT", 10, 0)

  -- NEW: Invite status pill duration (0..10s)
  local sInvitePill = CreateSlider(
    left, "Invite status pill duration (sec)", 0, 10, 1,
    tonumber(Config:Get("invitePillDuration", 3)) or 3,
    function(v) return string.format("%ds", v) end,
    function(v)
      Config:Set("invitePillDuration", v)
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "invitePillDuration", v) end
      if Log then Log:Debug("Invite pill duration set {Val}", { Val = v }) end
    end
  )
  sInvitePill._label:SetPoint("BOTTOMLEFT", sInvitePill, "TOPLEFT", 0, 6)
  sInvitePill:SetPoint("TOPLEFT", sInviteCD, "BOTTOMLEFT", 0, -22)
  sInvitePill._valText:SetPoint("LEFT", sInvitePill, "RIGHT", 10, 0)

  -- Channel dropdown (right column)
  local chLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  chLabel:SetPoint("TOPLEFT", 0, 0); chLabel:SetText("Broadcast Channel")
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

  -- Messages header + boxes
  local msgHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  msgHeader:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", PAD, -PAD); msgHeader:SetText("Rotation Messages")

  local function makeBox(y, key, label)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("TOPLEFT", PAD+2, y); fs:SetText(label)
    local box = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
    box:SetPoint("TOPLEFT", PAD, y - 18); box:SetPoint("RIGHT", f, "RIGHT", -PAD, 0); box:SetHeight(90)
    if box.CharCount then box.CharCount:Hide() end
    local eb = box.EditBox; eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false); eb:SetMultiLine(true)
    eb:SetMaxLetters(0); eb:SetText(Config:Get(key, "")); eb:ClearFocus()
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(self) self:Insert("\n") end)
    eb:SetScript("OnEditFocusLost", function(self)
      Config:Set(key, self:GetText() or "")
      if Bus and Bus.Publish then Bus:Publish("ConfigChanged", key, self:GetText() or "") end
      if Log then Log:Debug("Message changed {Key}", { Key=key }) end
    end)
    return box
  end

  local topY = - (PAD + grid:GetHeight() + 24)
  local b1 = makeBox(topY,         "customMessage1", "Message 1")
  local b2 = makeBox(topY-120-12,  "customMessage2", "Message 2")
  local b3 = makeBox(topY-240-24,  "customMessage3", "Message 3")

  function f:Render() end
  return f
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
