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
  -- Dev Mode toggle (top of right column)
  local devCB = CreateCheck(right, "Developer Mode (show Debug tab)", function(on)
    Config:Set("devMode", on and true or false)
    if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "devMode", on and true or false) end
    -- Refresh categories (debug tab visibility)
    if Addon.UI and Addon.UI.Main and Addon.UI.Main.RefreshCategories then
      pcall(Addon.UI.Main.RefreshCategories, Addon.UI.Main)
      if Addon.UI.Main.ShowToast then
        pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, on and "Dev Mode ENABLED" or "Dev Mode DISABLED")
      end
    end
  end)
  devCB:SetPoint("TOPLEFT", 0, 0)
  devCB:SetChecked(Config:Get("devMode", false) and true or false)

  chLabel:SetPoint("TOPLEFT", devCB, "BOTTOMLEFT", 0, -14); chLabel:SetText("Broadcast Channel")
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

  -- Rotation Messages container
  local msgsFrame = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
  msgsFrame:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 4, -PAD)
  msgsFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, 0)
  msgsFrame:SetHeight(260)

  local msgHeader = msgsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  msgHeader:SetPoint("TOPLEFT", 10, -8)
  msgHeader:SetText("Rotation Messages")

  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")
  local addBtn = ButtonLib and ButtonLib:Create(msgsFrame, { text="Add", variant="primary", size="sm" }) or CreateFrame("Button", nil, msgsFrame, "UIPanelButtonTemplate")
  addBtn:SetPoint("TOPRIGHT", -10, -6)
  if not addBtn._text then addBtn:SetText("Add") end
  local removeBtn = ButtonLib and ButtonLib:Create(msgsFrame, { text="Remove", variant="secondary", size="sm" }) or CreateFrame("Button", nil, msgsFrame, "UIPanelButtonTemplate")
  removeBtn:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
  if not removeBtn._text then removeBtn:SetText("Remove") end

  local accordion = CreateFrame("Frame", nil, msgsFrame)
  accordion:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", -2, -10)
  accordion:SetPoint("RIGHT", msgsFrame, "RIGHT", -12, 0)

  local UIHelpers = Addon.require and Addon.require("Tools.UIHelpers")
  if UIHelpers and UIHelpers.CreateAccordion then
    local sections = {
      {
        key="customMessage1", label="Message 1", expanded=true,
        getText=function() return Config:Get("customMessage1", "") end,
        setText=function(txt)
          Config:Set("customMessage1", txt or "")
          if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "customMessage1", txt or "") end
          if Log then Log:Debug("Message changed {Key}", { Key="customMessage1" }) end
        end
      },
      {
        key="customMessage2", label="Message 2",
        getText=function() return Config:Get("customMessage2", "") end,
        setText=function(txt)
          Config:Set("customMessage2", txt or "")
          if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "customMessage2", txt or "") end
          if Log then Log:Debug("Message changed {Key}", { Key="customMessage2" }) end
        end
      },
      {
        key="customMessage3", label="Message 3",
        getText=function() return Config:Get("customMessage3", "") end,
        setText=function(txt)
          Config:Set("customMessage3", txt or "")
          if Bus and Bus.Publish then Bus:Publish("ConfigChanged", "customMessage3", txt or "") end
          if Log then Log:Debug("Message changed {Key}", { Key="customMessage3" }) end
        end
      },
    }
    local acc = UIHelpers.CreateAccordion(accordion, sections, { collapsedHeight=26, contentHeight=100, iconCollapsed="►", iconExpanded="▼" })
    -- Inject small icon to left of each message title (after sections built)
    if acc and acc.sections and acc.sections.ForEach then
      acc.sections:ForEach(function(sec)
        if sec and sec.titleFS and not sec._msgIcon then
          local icon = sec:CreateTexture(nil, "OVERLAY")
          icon:SetSize(14,14)
          icon:SetPoint("LEFT", sec.titleFS, "LEFT", -18, 0)
          icon:SetTexture(134400) -- chat bubble texture ID or generic icon
          sec._msgIcon = icon
          -- Shift title right to make room
          sec.titleFS:ClearAllPoints()
          sec.titleFS:SetPoint("LEFT", sec.arrow, "RIGHT", 24, 0)
        end
      end)
    end
    acc:SetPoint("TOPLEFT", accordion, "TOPLEFT", 0, 0)
    acc:SetPoint("RIGHT", accordion, "RIGHT", 0, 0)
    accordion._component = acc
    -- Expose for dynamic runtime modification via slash commands
    SettingsUI._messageAccordion = acc
    SettingsUI._messageAccordionHost = accordion

    -- Helper to build a section definition for a given message index (backwards compatible with original keys)
    function SettingsUI:BuildMessageSectionDef(index)
      index = tonumber(index)
      if not index or index < 1 then return nil end
      local key = "customMessage"..index
      return {
        key=key,
        label="Message "..index,
        expanded = (index == 1),
        getText=function() return Config:Get(key, "") end,
        setText=function(txt)
          Config:Set(key, txt or "")
          if Bus and Bus.Publish then Bus:Publish("ConfigChanged", key, txt or "") end
          if Log then Log:Debug("Message changed {Key}", { Key=key }) end
        end
      }
    end

    -- Add a message section dynamically (creates config key if missing)
    function SettingsUI:AddMessage(index)
      index = tonumber(index)
      if not index or index < 1 then return false, "Invalid index" end
      local key = "customMessage"..index
      if not Config:Get(key) then Config:Set(key, "") end
      local acc = self._messageAccordion
      if acc and acc.GetSection and not acc:GetSection(key) then
        local def = self:BuildMessageSectionDef(index)
        if def then
          local newSec = acc:AddSection(def)
          if newSec and newSec.titleFS and not newSec._msgIcon then
            local icon = newSec:CreateTexture(nil, "OVERLAY")
            icon:SetSize(14,14)
            icon:SetPoint("LEFT", newSec.titleFS, "LEFT", -18, 0)
            icon:SetTexture(134400)
            newSec._msgIcon = icon
            newSec.titleFS:ClearAllPoints(); newSec.titleFS:SetPoint("LEFT", newSec.arrow, "RIGHT", 24, 0)
          end
        end
        -- Resize host after dynamic addition
        if self._messageAccordionHost then
          self._messageAccordionHost:SetHeight(acc:GetHeight())
        end
        return true, "Added message "..index
      end
      return false, "Message already exists"
    end

    -- Remove a message section dynamically (also clears config key)
    function SettingsUI:RemoveMessage(index)
      index = tonumber(index)
      if not index or index < 1 then return false, "Invalid index" end
      local key = "customMessage"..index
      local acc = self._messageAccordion
      if acc and acc.GetSection and acc:GetSection(key) then
        acc:RemoveSection(key)
        Config:Set(key, nil)
        if self._messageAccordionHost then
          self._messageAccordionHost:SetHeight(acc:GetHeight())
        end
        return true, "Removed message "..index
      end
      return false, "Message not found"
    end

    -- List existing message indices (sequential scan)
    function SettingsUI:ListMessages()
      local list = {}
      for i=1,50 do -- hard cap
        local k = "customMessage"..i
        if Config:Get(k) ~= nil then
          table.insert(list, i)
        end
      end
      return list
    end

    -- Ensure at least default 3 messages present (backwards compatibility for fresh installs)
    for i=1,3 do
      local k = "customMessage"..i
      if Config:Get(k) == nil then Config:Set(k, "") end
    end
    -- After layout adjust bottom anchor margin by extending parent frame
    local totalH = acc:GetHeight()
    accordion:SetHeight(totalH)

    local function RefreshContainerHeight()
      local innerH = acc:GetHeight() + 44
      msgsFrame:SetHeight(math.min(600, innerH))
    end

    addBtn:SetScript("OnClick", function()
      local list = SettingsUI:ListMessages()
      local max = 0; for _,i in ipairs(list) do if i>max then max=i end end
      local nextIndex = max + 1
      local ok, msg = SettingsUI:AddMessage(nextIndex)
      if ok and accordion._component and accordion._component.Open then
        C_Timer.After(0, function()
          RefreshContainerHeight()
          accordion._component:Open("customMessage"..nextIndex)
        end)
      end
      if Addon.UI and Addon.UI.Main and Addon.UI.Main.ShowToast then
        pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, ok and ("Added Message "..nextIndex) or msg)
      end
    end)

    removeBtn:SetScript("OnClick", function()
      local list = SettingsUI:ListMessages(); table.sort(list)
      local last = list[#list]
      if not last or last <= 3 then
        if Addon.UI and Addon.UI.Main and Addon.UI.Main.ShowToast then pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, "Cannot remove core messages") end
        return
      end
      local ok, msg = SettingsUI:RemoveMessage(last)
      if Addon.UI and Addon.UI.Main and Addon.UI.Main.ShowToast then pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, ok and ("Removed Message "..last) or msg) end
      RefreshContainerHeight()
    end)

    C_Timer.After(0, RefreshContainerHeight)
  end

  function f:Render() end
  return f
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
