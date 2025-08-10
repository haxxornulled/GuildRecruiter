local _, Addon = ...
local SettingsUI = {}

function SettingsUI:Create(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints(parent)
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
      edit:SetWidth(scroll:GetWidth()-18)
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
    for i=1,3 do
      local box = createMessageBox(container, i)
      box:SetPoint("TOPLEFT", 8, y)
      box:SetPoint("RIGHT", -8, 0)
      y = y - 122
    end
  function frame:Render() end
  return frame
end

Addon.provide("UI.Settings", SettingsUI)
return SettingsUI
