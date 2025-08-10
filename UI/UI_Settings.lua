local _, Addon = ...
local SettingsUI = {}

function SettingsUI:Create(parent)
  -- Outer frame (returned) fills parent; inner scroll child hosts content
  local outer = CreateFrame("Frame", nil, parent)
  outer:SetAllPoints(parent)
  local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  local frame = CreateFrame("Frame", nil, scroll) -- content frame
  frame:SetPoint("TOPLEFT")
  frame:SetWidth(parent:GetWidth() - 36) -- leave room for scrollbar
  scroll:SetScrollChild(frame)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local step = 40
    if delta > 0 then
      self:SetVerticalScroll(math.max(0, current - step))
    else
      self:SetVerticalScroll(math.min(self:GetVerticalScrollRange(), current + step))
    end
  end)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Settings (Rebuild)")
  local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  note:SetWidth(520)
  note:SetJustifyH("LEFT")
  note:SetText("Rebuild in progress. Tell me which feature to add first.")

    ------------------------------------------------------------------
    -- Recruitment Messages (rotation) section
    ------------------------------------------------------------------
    local cfg = Addon.Config
    local bus = Addon.EventBus

    local msgsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgsHeader:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -24)
    msgsHeader:SetText("Recruitment Messages (Rotation)")
    msgsHeader:SetTextColor(0.9, 0.8, 0.6)

    local container = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    container:SetPoint("TOPLEFT", msgsHeader, "BOTTOMLEFT", -4, -8)
    container:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    container:SetHeight(390) -- enough for 3 boxes
    container:SetBackdrop({ bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    container:SetBackdropColor(0.05,0.05,0.08,0.85)
    container:SetBackdropBorderColor(0.25,0.25,0.30,0.85)

    local function colorForUsage(pct)
      if pct >= 0.95 then return 1,0.15,0.15
      elseif pct >= 0.85 then return 1,0.55,0.10
      elseif pct >= 0.70 then return 1,0.85,0.10
      end
      return 0.70,0.70,0.70
    end

    local function createMessageBox(parent, index)
      local key = "customMessage"..index
      local boxFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
      boxFrame:SetSize(parent:GetWidth()-24, 110)
      boxFrame:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10, tile=true, tileSize=8, insets={left=2,right=2,top=2,bottom=2} })
      boxFrame:SetBackdropColor(0,0,0,0.25)
      boxFrame:SetBackdropBorderColor(0.3,0.3,0.35,0.85)

      local label = boxFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("TOPLEFT", 8, -6)
      label:SetText(string.format("Message %d", index))

      local scroll = CreateFrame("ScrollFrame", nil, boxFrame, "InputScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", 8, -24)
      scroll:SetPoint("BOTTOMRIGHT", -8, 8)
      local edit = scroll.EditBox or scroll:GetScrollChild()
      if not edit then
        edit = CreateFrame("EditBox", nil, scroll)
        scroll:SetScrollChild(edit)
      end
      edit:SetMultiLine(true)
      edit:SetMaxLetters(255)
      edit:SetAutoFocus(false)
      edit:SetFontObject(ChatFontNormal)
      edit:SetTextColor(1,1,1,1) -- explicit white for readability
      edit:SetWidth(scroll:GetWidth()-18)
      -- Keep width in sync after layout (initial size can be 0 during creation)
      scroll:HookScript("OnSizeChanged", function(_, w)
        if w and w > 20 then edit:SetWidth(w - 18) end
      end)
      edit:SetText(cfg and cfg:Get(key, "") or "")

      local counter = boxFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      counter:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -6, 6)
      counter:SetTextColor(0.7,0.7,0.7)

      local function updateCounter()
        local len = edit:GetNumLetters() or (edit:GetText() and #edit:GetText() or 0)
        local r,g,b = colorForUsage(len/255)
        counter:SetTextColor(r,g,b)
        counter:SetText(string.format("%d/255", len))
      end

      edit:HookScript("OnTextChanged", function(self, userInput)
        updateCounter()
        if userInput then
          local text = self:GetText() or ""
          if cfg and cfg.Set then cfg:Set(key, text) end
          if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", key, text) end
          -- Prevent losing focus when buffer becomes empty due to some templates auto-blurring
          if (self:GetNumLetters() or (self:GetText() and #self:GetText() or 0)) == 0 then
            C_Timer.After(0, function()
              if self and self:IsVisible() and not self:HasFocus() then self:SetFocus() end
            end)
          end
        end
      end)
      edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      edit:SetScript("OnEnterPressed", function(self) self:Insert("\n") end)
      edit:SetScript("OnEditFocusGained", function(self)
        local n = self:GetNumLetters() or 0
        self:SetCursorPosition(n)
      end)
      edit:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText() or ""
        if cfg and cfg.Set then cfg:Set(key, text) end
      end)

      C_Timer.After(0, updateCounter)
      return boxFrame
    end

    local y = -8
    local lastBox
    for i=1,3 do
      local box = createMessageBox(container, i)
      box:SetPoint("TOPLEFT", 8, y)
      box:SetPoint("RIGHT", -8, 0)
      y = y - 122
      lastBox = box
    end
    -- Resize container to fit exactly the boxes (so following options can be placed just below)
    container:SetHeight(-y - 8)

    ------------------------------------------------------------------
    -- Core Options (reintroduced)
    ------------------------------------------------------------------
  local optsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- Previously anchored to container bottom (which pushed it off-screen). Now anchor to last message box.
    if lastBox then
      optsHeader:SetPoint("TOPLEFT", lastBox, "BOTTOMLEFT", 4, -32)
    else
      optsHeader:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 4, -16)
    end
    optsHeader:SetText("Core Options")
    optsHeader:SetTextColor(0.9,0.8,0.6)

    -- Helpers
    local function CreateCheck(parent, label, getFn, setFn)
      local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
      cb.Text = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      cb.Text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
      cb.Text:SetText(label)
      cb:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if setFn then setFn(self:GetChecked()) end
      end)
      if getFn then cb:SetChecked(getFn() and true or false) end
      return cb
    end

    local function CreateSlider(parent, label, minV, maxV, step, getFn, setFn, fmt)
      local holder = CreateFrame("Frame", nil, parent)
      holder:SetSize(260, 42)
      local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("TOPLEFT", 0, 0); text:SetText(label); text:SetTextColor(0.9,0.8,0.6)
      local slider = CreateFrame("Slider", nil, holder, "OptionsSliderTemplate")
      slider:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
      slider:SetWidth(180)
      slider:SetMinMaxValues(minV, maxV)
      slider:SetValueStep(step)
      if slider.Low then slider.Low:SetText("") end
      if slider.High then slider.High:SetText("") end
      if slider.Text then slider.Text:SetText("") end
      local valText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      valText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
      local function render(v) valText:SetText((fmt and fmt(v)) or tostring(v)) end
      slider:SetScript("OnValueChanged", function(_, v)
        if step >= 1 then v = math.floor(v + 0.5) end
        render(v)
        if setFn then setFn(v) end
      end)
      local init = getFn and getFn() or minV
      slider:SetValue(init)
      render(init)
      holder.slider = slider
      return holder
    end

    local function CreateDropdown(parent, label, width, entries, getFn, setFn)
      local holder = CreateFrame("Frame", nil, parent)
      holder:SetSize(width + 40, 52)
      local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("TOPLEFT", 0, 0); text:SetText(label); text:SetTextColor(0.9,0.8,0.6)
      local dd = CreateFrame("Frame", nil, holder, "UIDropDownMenuTemplate")
      dd:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -16, -4)
      UIDropDownMenu_SetWidth(dd, width)
      local current = getFn and getFn() or entries[1].value
      UIDropDownMenu_Initialize(dd, function()
        for _, item in ipairs(entries) do
          local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.checked = (item.value == current)
            info.func = function()
              current = item.value
              UIDropDownMenu_SetText(dd, item.text)
              if setFn then setFn(item.value) end
            end
          UIDropDownMenu_AddButton(info)
        end
      end)
      for _, item in ipairs(entries) do if item.value == current then UIDropDownMenu_SetText(dd, item.text) break end end
      return holder
    end

    local colLeft  = CreateFrame("Frame", nil, frame)
    colLeft:SetPoint("TOPLEFT", optsHeader, "BOTTOMLEFT", 0, -8)
    colLeft:SetSize(340, 260)
    local colRight = CreateFrame("Frame", nil, frame)
    colRight:SetPoint("TOPLEFT", colLeft, "TOPRIGHT", 40, 0)
    colRight:SetSize(340, 260)

    -- Broadcast enable
    local broadcastCB = CreateCheck(colLeft, "Enable Broadcast Rotation",
      function() return cfg and cfg:Get("broadcastEnabled", false) end,
      function(v)
        if cfg and cfg.Set then cfg:Set("broadcastEnabled", v and true or false) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "broadcastEnabled", v and true or false) end
      end)
    broadcastCB:SetPoint("TOPLEFT", 0, 0)

    -- Base interval
    local intervalSlider = CreateSlider(colLeft, "Base Interval (sec)", 60, 900, 5,
      function() return tonumber(cfg and cfg:Get("broadcastInterval", 300)) or 300 end,
      function(v)
        if cfg and cfg.Set then cfg:Set("broadcastInterval", v) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "broadcastInterval", v) end
      end,
      function(v) return string.format("%ds", v) end)
    intervalSlider:SetPoint("TOPLEFT", broadcastCB, "BOTTOMLEFT", 0, -18)

    -- Jitter
    local jitterSlider = CreateSlider(colLeft, "Interval Jitter (± %)", 0, 50, 1,
      function() return math.floor(((cfg and cfg:Get("jitterPercent", 0.15)) or 0.15) * 100 + 0.5) end,
      function(v)
        local pct = math.max(0, math.min(50, v)) / 100.0
        if cfg and cfg.Set then cfg:Set("jitterPercent", pct) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "jitterPercent", pct) end
      end,
      function(v) return string.format("%d%%", v) end)
    jitterSlider:SetPoint("TOPLEFT", intervalSlider, "BOTTOMLEFT", 0, -22)

    -- Invite cooldown
    local inviteCDSlider = CreateSlider(colLeft, "Invite Cooldown (sec)", 0, 10, 1,
      function() return tonumber(cfg and cfg:Get("inviteClickCooldown", 3)) or 3 end,
      function(v)
        if cfg and cfg.Set then cfg:Set("inviteClickCooldown", v) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "inviteClickCooldown", v) end
      end,
      function(v) return string.format("%ds", v) end)
    inviteCDSlider:SetPoint("TOPLEFT", jitterSlider, "BOTTOMLEFT", 0, -22)

    -- Invite pill duration
    local pillSlider = CreateSlider(colLeft, "Invite Status Pill (sec)", 0, 10, 1,
      function() return tonumber(cfg and cfg:Get("invitePillDuration", 3)) or 3 end,
      function(v)
        if cfg and cfg.Set then cfg:Set("invitePillDuration", v) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "invitePillDuration", v) end
      end,
      function(v) return string.format("%ds", v) end)
    pillSlider:SetPoint("TOPLEFT", inviteCDSlider, "BOTTOMLEFT", 0, -22)

    -- Cycle messages
    local cycleCB = CreateCheck(colRight, "Cycle Invite Messages",
      function() return cfg and cfg:Get("inviteCycleEnabled", true) end,
      function(v)
        if cfg and cfg.Set then cfg:Set("inviteCycleEnabled", v and true or false) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "inviteCycleEnabled", v and true or false) end
      end)
    cycleCB:SetPoint("TOPLEFT", 0, 0)

    -- Auto-blacklist declines
    local autoBL = CreateCheck(colRight, "Auto-Blacklist Declines",
      function() return cfg and cfg:Get("autoBlacklistDeclines", true) end,
      function(v)
        if cfg and cfg.Set then cfg:Set("autoBlacklistDeclines", v and true or false) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "autoBlacklistDeclines", v and true or false) end
      end)
    autoBL:SetPoint("TOPLEFT", cycleCB, "BOTTOMLEFT", 0, -14)

    -- Dev mode
    local devCB = CreateCheck(colRight, "Developer Mode (Debug Tab)",
      function() return cfg and cfg:Get("devMode", false) end,
      function(v)
        if cfg and cfg.Set then cfg:Set("devMode", v and true or false) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "devMode", v and true or false) end
      end)
    devCB:SetPoint("TOPLEFT", autoBL, "BOTTOMLEFT", 0, -14)

    -- Broadcast channel
    local channelDD = CreateDropdown(colRight, "Broadcast Channel", 220, {
        { text = "AUTO (Trade > General > Say)", value = "AUTO" },
        { text = "SAY", value = "SAY" },
        { text = "YELL", value = "YELL" },
        { text = "GUILD", value = "GUILD" },
        { text = "OFFICER", value = "OFFICER" },
        { text = "INSTANCE_CHAT", value = "INSTANCE_CHAT" },
        { text = "CHANNEL:Trade", value = "CHANNEL:Trade" },
        { text = "CHANNEL:General", value = "CHANNEL:General" },
      },
      function() return cfg and cfg:Get("broadcastChannel", "AUTO") end,
      function(val)
        if cfg and cfg.Set then cfg:Set("broadcastChannel", val) end
        if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", "broadcastChannel", val) end
      end)
    channelDD:SetPoint("TOPLEFT", devCB, "BOTTOMLEFT", 0, -26)
  function frame:Render() end
  -- After one frame, measure bottom element and set content height to enable scrolling.
  C_Timer.After(0, function()
    if not outer or not frame or not frame:IsVisible() then return end
    local lowest = 0
    -- Try to find the lowest child (approximate)
    for _, child in ipairs({frame:GetChildren()}) do
      if child:IsShown() then
        local bottom = child:GetBottom()
        if bottom and bottom < lowest or lowest == 0 then lowest = bottom end
      end
    end
    local top = frame:GetTop()
    if top and lowest and lowest > 0 then
      local h = top - lowest + 40
      if h < 400 then h = 400 end
      frame:SetHeight(h)
    else
      -- Fallback height
      frame:SetHeight(1000)
    end
  end)
  return outer
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
