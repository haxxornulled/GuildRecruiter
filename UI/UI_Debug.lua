-- UI.Debug.lua — Debug / Logs page
local _, Addon = ...
local M = {}

local function LOG()
  local L = Addon.Logger
  return (L and L.ForContext and L:ForContext("UI.Debug")) or nil
end

function M:Create(parent)
  local f = CreateFrame("Frame", nil, parent); f:SetAllPoints(); f:Hide()
  local host = CreateFrame("Frame", "GR_DebugEdit", f, "ScrollingEditBoxTemplate")
  host:SetPoint("TOPLEFT", 12, -44)
  host:SetPoint("BOTTOMRIGHT", -28, 12)
  local editBox = host.EditBox or (host.ScrollFrame and host.ScrollFrame.EditBox) or (host.ScrollBox and host.ScrollBox.GetScrollTarget and host.ScrollBox:GetScrollTarget())
  if editBox and editBox.GetObjectType and editBox:GetObjectType() ~= "EditBox" then editBox = nil end
  local scrollBar = host.ScrollBar
  if not editBox or not scrollBar then
    local sf = CreateFrame("ScrollFrame", "GR_DebugScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -44); sf:SetPoint("BOTTOMRIGHT", -28, 12)
    editBox = CreateFrame("EditBox", nil, sf); editBox:SetMultiLine(true); editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false); editBox:SetWidth(sf:GetWidth() - 8); editBox:SetText("")
    sf:SetScrollChild(editBox)
    scrollBar = _G["GR_DebugScrollScrollBar"]
    sf:SetScript("OnSizeChanged", function(_, w) editBox:SetWidth((w or 0) - 8) end)
  end
  editBox:EnableMouse(true)
  editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  editBox:SetScript("OnEnterPressed",  function(self) self:Insert("\n") end)
  editBox:SetScript("OnMouseDown", function(self, btn) self:SetFocus(); if btn=="RightButton" then self:HighlightText() end end)
  editBox:SetScript("OnEditFocusGained", function(self) self:SetCursorPosition(self:GetNumLetters()) end)
  editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0,0) end)
  local userScrolling=false
  local function markUser() userScrolling=true; C_Timer.After(1, function() userScrolling=false end) end
  local wheelHost = host.ScrollBox or host.ScrollFrame or host
  if wheelHost.EnableMouseWheel then
    wheelHost:EnableMouseWheel(true)
    wheelHost:SetScript("OnMouseWheel", function(_, delta)
      if not scrollBar then return end
      markUser(); local step=(delta>0) and -40 or 40
      scrollBar:SetValue((scrollBar:GetValue() or 0)+step)
    end)
  end
  if scrollBar and scrollBar.HookScript then scrollBar:HookScript("OnValueChanged", function() markUser() end) end
  local function scrollToBottom() if scrollBar then local _,max=scrollBar:GetMinMaxValues(); scrollBar:SetValue(max or 0) end end
  function f:RenderLog()
    local buffer = Addon.LogBuffer or {}
    f._logCurrent = table.concat(buffer, "\n")
    editBox:SetText(f._logCurrent)
    f._lastLogCount=#buffer
    C_Timer.After(0,function() if not userScrolling then scrollToBottom() end if f.UpdateScrollbarVisibility then f:UpdateScrollbarVisibility() end end)
  end
  local function AppendNewLogs()
    if not f._lastLogCount then return f:RenderLog() end
    local buffer=Addon.LogBuffer or {}; local count=#buffer
    if count <= (f._lastLogCount or 0) then return end
    for i=(f._lastLogCount or 0)+1,count do local line=buffer[i]; if line then f._logCurrent = (f._logCurrent and f._logCurrent.."\n"..line) or line end end
    editBox:SetText(f._logCurrent or ""); f._lastLogCount=count
    if not userScrolling then C_Timer.After(0,function() scrollToBottom(); if f.UpdateScrollbarVisibility then f:UpdateScrollbarVisibility() end end) end
  end
  if Addon.EventBus and Addon.EventBus.Subscribe then Addon.EventBus:Subscribe("LogUpdated", function() if f:IsShown() then AppendNewLogs() end end) end
  f:HookScript("OnShow", function() f:RenderLog() end)
  function f:UpdateScrollbarVisibility()
    if not scrollBar or not scrollBar.GetMinMaxValues then return end
    local _,max=scrollBar:GetMinMaxValues(); local needs=(max or 0)>0
    if needs and not scrollBar._shown then scrollBar:Show(); scrollBar._shown=true; host:SetPoint("BOTTOMRIGHT", -28, 12)
    elseif (not needs) and scrollBar._shown then scrollBar:Hide(); scrollBar._shown=false; host:SetPoint("BOTTOMRIGHT", -12, 12) end
    if editBox and editBox.SetWidth then local w=host:GetWidth()-8; if w>0 then editBox:SetWidth(w) end end
  end
  C_Timer.After(0.05,function() if f.UpdateScrollbarVisibility then f:UpdateScrollbarVisibility() end end)
  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib"); local reloadBtn
  if not ButtonLib then ButtonLib={ Create=function(_,parent,opts) local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize((opts and opts.width) or 90,22); b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); b.text:SetPoint("CENTER"); b.text:SetText(opts.text or "Button"); b:SetScript("OnClick", opts.onClick); b:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Buttons/WHITE8x8", edgeSize=1 }); b:SetBackdropColor(0.15,0.15,0.16,0.9); b:SetBackdropBorderColor(0.3,0.3,0.35,1); b:SetHighlightTexture("Interface/Buttons/WHITE8x8"); local hl=b:GetHighlightTexture(); hl:SetVertexColor(0.4,0.4,0.5,0.25); function b:SetText(t) if b.text then b.text:SetText(t) end end; return b end } end
  reloadBtn = ButtonLib:Create(f,{ text="Reload UI", variant="danger", size="sm", onClick=ReloadUI })
  reloadBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
  local function EnsureCopyFrame() if f._copyFrame then return f._copyFrame end local cf=CreateFrame("Frame","GR_DebugCopyFrame",UIParent,"BackdropTemplate"); cf:SetSize(600,360); cf:SetPoint("CENTER"); cf:SetFrameStrata("DIALOG"); cf:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=14, insets={left=4,right=4,top=4,bottom=4} }); cf:SetBackdropColor(0,0,0,0.95); cf:SetBackdropBorderColor(0.8,0.75,0.15,1); cf:Hide(); cf:EnableMouse(true); cf:SetMovable(true); cf:RegisterForDrag("LeftButton"); cf:SetScript("OnDragStart", cf.StartMoving); cf:SetScript("OnDragStop", cf.StopMovingOrSizing); local title=cf:CreateFontString(nil,"OVERLAY","GameFontNormal"); title:SetPoint("TOPLEFT",12,-10); title:SetText("Debug Log (Copy)"); local close=ButtonLib and ButtonLib:Create(cf,{ text="×", size="sm", variant="ghost", onClick=function() cf:Hide() end }) or ButtonLib:Create(cf,{ text="X", size="sm", variant="ghost", onClick=function() cf:Hide() end }); close:SetPoint("TOPRIGHT", -8, -6); local sf=CreateFrame("ScrollFrame","GR_DebugCopyScroll", cf, "UIPanelScrollFrameTemplate"); sf:SetPoint("TOPLEFT",12,-32); sf:SetPoint("BOTTOMRIGHT", -32,12); local eb=CreateFrame("EditBox", nil, sf); eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(true); eb:SetWidth(sf:GetWidth()-8); eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); cf:Hide() end); eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end); eb:SetScript("OnTextChanged", function(self) local w=sf:GetWidth()-8; if w>0 then self:SetWidth(w) end end); sf:SetScrollChild(eb); cf.editBox=eb; f._copyFrame=cf; return cf end
  local function ShowCopy() local cf=EnsureCopyFrame(); local text=f._logCurrent or (Addon.LogBuffer and table.concat(Addon.LogBuffer, "\n")) or "(no logs)"; cf.editBox:SetText(text); cf:Show(); cf.editBox:SetFocus(); cf.editBox:HighlightText() end
  local copyBtn = ButtonLib:Create(f,{ text="Copy", variant="secondary", size="sm", onClick=ShowCopy })
  copyBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -6, 0)
  local function DoClear()
    -- Purge top-level buffer
    Addon.LogBuffer = {}
    -- Purge any sink buffers (memory sink + others if they expose buffer)
    if Addon.ResolveAll then
      local sinks = Addon.ResolveAll("LogSink") or {}
      for _, s in ipairs(sinks) do
        if type(s) == "table" and s.buffer then
          for i=#s.buffer,1,-1 do s.buffer[i]=nil end
        end
      end
    end
    f._logCurrent = ""
    editBox:SetText("")
    f._lastLogCount = 0
    local L = LOG(); if L then L:Info("Logs cleared") end
  end
  local function ClearLogs()
    if IsShiftKeyDown() then DoClear(); return end
    if not StaticPopupDialogs then DoClear(); return end
    StaticPopupDialogs = StaticPopupDialogs or {}
    if not StaticPopupDialogs["GUILDRECRUITER_CLEAR_LOGS"] then
  local yesLabel = rawget(_G, "YES") or "Yes"
  local cancelLabel = rawget(_G, "CANCEL") or "Cancel"
      StaticPopupDialogs["GUILDRECRUITER_CLEAR_LOGS"] = {
        text = "Clear all Guild Recruiter logs?",
        button1 = yesLabel,
        button2 = cancelLabel,
        OnAccept = function() DoClear() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    end
  local spShow = rawget(_G, "StaticPopup_Show")
  if spShow then spShow("GUILDRECRUITER_CLEAR_LOGS") else DoClear() end
  end
  local clearBtn = ButtonLib:Create(f,{ text="Clear", variant="ghost", size="sm", onClick=ClearLogs, tooltip="Clear all logs (Shift+Click to skip confirm)" })
  clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)
  -- Diagnostics button (EventBus stats + sink purge)
  local function ShowDiagnostics()
    local lines = {}
    -- EventBus diagnostics
    local bus = Addon.EventBus
    if bus and bus.Diagnostics then
      local d = bus:Diagnostics()
      lines[#lines+1] = string.format("EventBus: publishes=%d errors=%d events=%d", d.publishes or 0, d.errors or 0, #(d.events or {}))
      for _, ev in ipairs(d.events or {}) do
        lines[#lines+1] = string.format("  %s (%d handlers)", ev.event, ev.handlers)
      end
    else
      lines[#lines+1] = "EventBus diagnostics not available"
    end
    -- Logger sinks
    if Addon.ResolveAll then
      local sinks = Addon.ResolveAll("LogSink") or {}
      lines[#lines+1] = string.format("LogSinks: %d", #sinks)
      for i,s in ipairs(sinks) do
        local cap = (s.capacity and ("cap="..s.capacity)) or ""
        local len = (s.buffer and ("size="..#s.buffer)) or ""
        lines[#lines+1] = string.format("  Sink #%d %s %s", i, cap, len)
      end
    end
    local text = table.concat(lines, "\n")
    local cf = f._diagFrame
    if not cf then
      cf = CreateFrame("Frame", nil, f, "BackdropTemplate")
      cf:SetPoint("TOPLEFT", f, "TOPLEFT", 180, -48)
      cf:SetSize(420, 260)
      cf:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
      cf:SetBackdropColor(0,0,0,0.85); cf:SetBackdropBorderColor(0.8,0.75,0.15,0.9)
      local sf = CreateFrame("ScrollFrame", nil, cf, "UIPanelScrollFrameTemplate")
      sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -26, 8)
      local eb = CreateFrame("EditBox", nil, sf)
      eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false)
      eb:SetWidth(380); sf:SetScrollChild(eb)
      cf.editBox = eb
      local close = ButtonLib:Create(cf, { text="Close", size="sm", variant="ghost", onClick=function() cf:Hide() end })
      close:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -6, -6)
      f._diagFrame = cf
    end
    cf.editBox:SetText(text)
    cf:Show(); cf.editBox:HighlightText(); cf.editBox:SetFocus()
  end
  local diagBtn = ButtonLib:Create(f,{ text="Diagnostics", variant="secondary", size="sm", onClick=ShowDiagnostics, tooltip="Show EventBus + Logger diagnostics" })
  diagBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
  local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  searchBox:SetAutoFocus(false); searchBox:SetSize(160, 20)
  searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -16)
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local lvlDD = CreateFrame("Frame", "GR_DebugLevelDrop", f, "UIDropDownMenuTemplate")
  lvlDD:SetPoint("LEFT", searchBox, "RIGHT", -12, -2)
  local LEVELS = { "TRACE","DEBUG","INFO","WARN","ERROR","FATAL" }
  f._minLevel = nil
  local function Refilter()
    if not f._logCurrent then return end
    local term = searchBox:GetText() or ""
    term = term:lower()
    local minL = f._minLevel
    local lines = { strsplit("\n", f._logCurrent) }
    if (term == "" or not term) and not minL then
      editBox:SetText(f._logCurrent)
      C_Timer.After(0,function() if not userScrolling then scrollToBottom() end end)
      return
    end
    local out = {}
    for _, line in ipairs(lines) do
      local keep=true
      if term ~= "" then keep = line:lower():find(term, 1, true) ~= nil end
      if keep and minL then
        local lvl = line:match("%] (%u+)%s") or line:match("%] (%u+)$")
        if lvl then
          local order = { TRACE=0, DEBUG=1, INFO=2, WARN=3, ERROR=4, FATAL=5 }
          keep = (order[lvl] or 99) >= (order[minL] or 0)
        end
      end
      if keep then out[#out+1]=line end
    end
    editBox:SetText(table.concat(out, "\n"))
    if not userScrolling then C_Timer.After(0, scrollToBottom) end
  end
  searchBox:SetScript("OnTextChanged", function() Refilter() end)
  UIDropDownMenu_SetWidth(lvlDD, 100)
  UIDropDownMenu_Initialize(lvlDD, function(_, level)
    for i, name in ipairs({ "(All)", unpack(LEVELS) }) do
      local info = UIDropDownMenu_CreateInfo(); info.text=name; info.func=function()
        if name == "(All)" then f._minLevel=nil else f._minLevel=name end
        UIDropDownMenu_SetSelectedID(lvlDD, i); Refilter()
      end; info.checked = (name == "(All)" and not f._minLevel) or (f._minLevel==name)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(lvlDD,1)
  local searchLabel = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 4, 2)
  searchLabel:SetText("Search")
  local levelLabel = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  levelLabel:SetPoint("BOTTOMLEFT", lvlDD, "TOPLEFT", 20, 2)
  levelLabel:SetText("Min Level")
  f._refilter = Refilter
  function f:Render() f:RenderLog() end
  return f
end

Addon.provide("UI.Debug", M)
return M
