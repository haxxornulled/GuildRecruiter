local _, Addon = ...
local SettingsUI = {}

function SettingsUI:Create(parent)
  -- Pro path: ScrollBox + DataProvider (Dragonflight+). Falls back to static layout if API unavailable or fails.
  local cfg = Addon.Config
  local bus = Addon.EventBus
  if CreateScrollBoxListLinearView and ScrollUtil and CreateDataProvider then
    local ok, result = pcall(function()
      local outer = CreateFrame("Frame", nil, parent)
      outer:SetAllPoints(parent)

      local scrollBox = CreateFrame("Frame", nil, outer, "WowScrollBoxList")
      local scrollBar  = CreateFrame("EventFrame", nil, outer, "MinimalScrollBar")
      scrollBox:SetPoint("TOPLEFT", 0, 0)
      scrollBox:SetPoint("BOTTOMRIGHT", -20, 0)
      scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 0, 0)
      scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 0, 0)

      local view = CreateScrollBoxListLinearView()
      view:SetPadding(8, 8, 12, 8, 0) -- top, bottom, left, right, between

      -- Element factory supporting multiple kinds.
      view:SetElementFactory(function(factory, elementData)
        local kind = elementData.kind
        if kind == "header" then
          factory("BackdropTemplate", function(f, data)
            if not f._built then
              f:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8" })
              f:SetBackdropColor(0.12,0.12,0.14,0.55)
              local line = f:CreateTexture(nil, "ARTWORK")
              line:SetColorTexture(0.35,0.34,0.30,0.80)
              line:SetPoint("BOTTOMLEFT", 0, 0)
              line:SetPoint("BOTTOMRIGHT", 0, 0)
              line:SetHeight(1)
              f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
              f.text:SetPoint("LEFT", 6, 0)
              f.text:SetTextColor(0.9,0.8,0.6)
              f._built = true
            end
            f:SetHeight(26)
            f.text:SetText(data.text or "")
          end)
        elseif kind == "spacer" then
          factory("Frame", function(f, data) f:SetHeight(data.height or 12) end)
        elseif kind == "message" then
          factory("BackdropTemplate", function(f, data)
            if not f._built then
              f:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10, tile=true, tileSize=8, insets={left=2,right=2,top=2,bottom=2} })
              f:SetBackdropColor(0,0,0,0.25)
              f:SetBackdropBorderColor(0.3,0.3,0.35,0.85)
              f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
              f.label:SetPoint("TOPLEFT", 8, -6)
              local scroll = CreateFrame("ScrollFrame", nil, f, "InputScrollFrameTemplate")
              scroll:SetPoint("TOPLEFT", 8, -24)
              scroll:SetPoint("BOTTOMRIGHT", -8, 8)
              f.edit = scroll.EditBox or scroll:GetScrollChild()
              if not f.edit then f.edit = CreateFrame("EditBox", nil, scroll); scroll:SetScrollChild(f.edit) end
              local edit = f.edit
              edit:SetMultiLine(true)
              edit:SetMaxLetters(255)
              edit:SetAutoFocus(false)
              edit:SetFontObject(ChatFontNormal)
              edit:SetTextColor(1,1,1,1)
              edit:SetWidth(scroll:GetWidth()-18)
              scroll:HookScript("OnSizeChanged", function(_, w) if w and w>20 then edit:SetWidth(w-18) end end)
              f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
              f.counter:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
              f._built = true
            end
            f:SetHeight(120)
            local idx = data.index
            f.label:SetText("Message "..tostring(idx))
            local key = "customMessage"..idx
            local edit = f.edit
            if not f._hooked then
              edit:HookScript("OnTextChanged", function(self, user)
                if user then
                  local text = self:GetText() or ""
                  if cfg and cfg.Set then cfg:Set(key, text) end
                  if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", key, text) end
                  if (self:GetNumLetters() or (#text)) == 0 then C_Timer.After(0, function() if self:IsVisible() and not self:HasFocus() then self:SetFocus() end end) end
                end
                local len = self:GetNumLetters() or (#self:GetText())
                local pct = len/255
                local r,g,b = 0.70,0.70,0.70
                if pct>=0.95 then r,g,b=1,0.15,0.15 elseif pct>=0.85 then r,g,b=1,0.55,0.10 elseif pct>=0.70 then r,g,b=1,0.85,0.10 end
                f.counter:SetTextColor(r,g,b)
                f.counter:SetText( (len or 0).."/255" )
              end)
              f._hooked = true
            end
            if cfg and cfg.Get then
              local cur = cfg:Get(key, "") or ""
              if edit:GetText() ~= cur then edit:SetText(cur) end
            end
            -- Force counter refresh
            edit:GetScript("OnTextChanged")(edit, false)
          end)
        elseif kind == "toggle" then
          factory("CheckButton", function(cb, data)
            if not cb._built then
              cb.Text = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
              cb.Text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
              cb:SetScript("OnClick", function(self)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                local v = self:GetChecked() and true or false
                if cfg and cfg.Set then cfg:Set(data.key, v) end
                if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", data.key, v) end
              end)
              cb._built = true
            end
            cb:SetHeight(24)
            cb.Text:SetText(data.label or data.key)
            if cfg and cfg.Get then cb:SetChecked(cfg:Get(data.key, data.default or false) and true or false) end
          end)
        elseif kind == "slider" then
          factory("BackdropTemplate", function(f, data)
            if not f._built then
              f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
              f.label:SetPoint("TOPLEFT", 4, -2)
              f.slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
              f.slider:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -6)
              f.slider:SetWidth(200)
              f.valueText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
              f.valueText:SetPoint("LEFT", f.slider, "RIGHT", 10, 0)
              f._built = true
            end
            f:SetHeight(54)
            f.label:SetText(data.label)
            local s = f.slider
            s:SetMinMaxValues(data.min, data.max)
            s:SetValueStep(data.step or 1)
            local current = cfg and cfg:Get(data.key, data.default or data.min) or data.min
            s:SetScript("OnValueChanged", function(_, v)
              if data.step and data.step>=1 then v = math.floor(v+0.5) end
              if cfg and cfg.Set then cfg:Set(data.key, v) end
              if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", data.key, v) end
              f.valueText:SetText( (data.fmt and data.fmt(v)) or tostring(v) )
            end)
            s:SetValue(current)
            f.valueText:SetText( (data.fmt and data.fmt(current)) or tostring(current) )
          end)
        elseif kind == "dropdown" then
          factory("BackdropTemplate", function(f, data)
            if not f._built then
              f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
              f.label:SetPoint("TOPLEFT", 4, -4)
              f.dd = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
              f.dd:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", -16, -2)
              f._built = true
            end
            f:SetHeight(60)
            f.label:SetText(data.label)
            local current = cfg and cfg:Get(data.key, data.default) or data.default
            UIDropDownMenu_Initialize(f.dd, function()
              for _, item in ipairs(data.entries) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text; info.value = item.value
                info.checked = (item.value == current)
                info.func = function()
                  current = item.value
                  UIDropDownMenu_SetText(f.dd, item.text)
                  if cfg and cfg.Set then cfg:Set(data.key, current) end
                  if bus and bus.Publish then pcall(bus.Publish, bus, "ConfigChanged", data.key, current) end
                end
                UIDropDownMenu_AddButton(info)
              end
            end)
            for _, item in ipairs(data.entries) do if item.value==current then UIDropDownMenu_SetText(f.dd, item.text) break end end
          end)
        end
      end)

      ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
      local provider = CreateDataProvider()

      provider:Insert({ kind="header", text="Recruitment Messages (Rotation)" })
      for i=1,3 do provider:Insert({ kind="message", index=i }) end
      provider:Insert({ kind="spacer", height=14 })
      provider:Insert({ kind="header", text="Core Options" })
      provider:Insert({ kind="toggle", key="broadcastEnabled", label="Enable Broadcast Rotation", default=false })
      provider:Insert({ kind="slider", key="broadcastInterval", label="Base Interval (sec)", min=60, max=900, step=5, default=300, fmt=function(v) return v.."s" end })
      provider:Insert({ kind="slider", key="jitterPercent", label="Interval Jitter (± %)", min=0, max=50, step=1, default=15, fmt=function(v) return v.."%" end })
      provider:Insert({ kind="slider", key="inviteClickCooldown", label="Invite Cooldown (sec)", min=0, max=10, step=1, default=3, fmt=function(v) return v.."s" end })
      provider:Insert({ kind="slider", key="invitePillDuration", label="Invite Status Pill (sec)", min=0, max=10, step=1, default=3, fmt=function(v) return v.."s" end })
      provider:Insert({ kind="toggle", key="inviteCycleEnabled", label="Cycle Invite Messages", default=true })
      provider:Insert({ kind="toggle", key="autoBlacklistDeclines", label="Auto-Blacklist Declines", default=true })
      provider:Insert({ kind="toggle", key="devMode", label="Developer Mode (Debug Tab)", default=false })
      provider:Insert({ kind="dropdown", key="broadcastChannel", label="Broadcast Channel", default="AUTO", entries={
        { text="AUTO (Trade > General > Say)", value="AUTO" },
        { text="SAY", value="SAY" },
        { text="YELL", value="YELL" },
        { text="GUILD", value="GUILD" },
        { text="OFFICER", value="OFFICER" },
        { text="INSTANCE_CHAT", value="INSTANCE_CHAT" },
        { text="CHANNEL:Trade", value="CHANNEL:Trade" },
        { text="CHANNEL:General", value="CHANNEL:General" },
      } })

      scrollBox:SetDataProvider(provider)

      -- Title (non-virtual) anchored above list using overlay frame.
      local title = outer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      title:SetPoint("TOPLEFT", 16, -16)
      title:SetText("Settings (Rebuild)")
      local note = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
      note:SetWidth(520)
      note:SetJustifyH("LEFT")
      note:SetText("ScrollBox prototype — virtualized settings list.")

      scrollBox:ClearAllPoints()
      scrollBox:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -8, -12)
      scrollBox:SetPoint("BOTTOMRIGHT", -8, 8)
      return outer
    end)
    if ok and result then return result end
  end

  -- Fallback (static) original layout below
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints(parent)
  -- reuse cfg & bus down in static path
  cfg = cfg or Addon.Config
  bus = bus or Addon.EventBus
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
  return frame
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
