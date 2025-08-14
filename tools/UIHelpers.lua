---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local __p = { ... }
local ADDON_NAME, Addon = __p[1], (__p[2] or _G[__p[1]] or _G.GuildRecruiter or {})
-- Use non-building peek at file load; resolve later on demand
local Tokens = (Addon.Peek and Addon.Peek("Tools.Tokens")) or nil
local CreateColor = _G and _G.CreateColor
local DEFAULT_CHAT_FRAME = _G and _G.DEFAULT_CHAT_FRAME
local SlashCmdList = _G and _G.SlashCmdList or {}
local time = _G and _G.time or function() return 0 end
local ChatFontNormal = _G and (_G.ChatFontNormal or _G.GameFontNormal)
local function tremove(t) return table.remove(t) end
local function wipe(t) for k in pairs(t) do t[k]=nil end end
local UIHelpers = {}
local AccordionSections = (Addon.Peek and (Addon.Peek("Collections.AccordionSections") or Addon.Peek("AccordionSections")))
-- Fallback (in case load order or registration failed) to avoid hard error; minimal subset
if not AccordionSections then
  AccordionSections = {}
  AccordionSections.__index = AccordionSections
  function AccordionSections.new() return setmetatable({ _list = {} }, AccordionSections) end
  function AccordionSections:Add(sec) table.insert(self._list, sec) end
  function AccordionSections:ForEach(fn) for i,v in ipairs(self._list) do fn(v,i) end end
  function AccordionSections:Count() return #self._list end
  function AccordionSections:Get(i) return self._list[i] end
  function AccordionSections:RemoveAt(i) if i<1 or i>#self._list then return end table.remove(self._list,i) end
end
local List = (Addon.Peek and Addon.Peek("Collections.List")) or Addon.List

-- Gradient application (vertical only for simplicity)
function UIHelpers.ApplyGradient(tex, top, bottom)
  if not tex then return end
  local function AsColor(c)
    if not c or type(c) ~= "table" then return nil end
    if c.GetRGBA then return c end
    local r,g,b,a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    if CreateColor then return CreateColor(r,g,b,a) end
    return { GetRGBA = function() return r,g,b,a end }
  end
  if tex.SetGradient and top and bottom then
    local cTop    = AsColor(top)
    local cBottom = AsColor(bottom)
    if cTop and cBottom then
      tex:SetColorTexture(0,0,0,0)
      pcall(tex.SetGradient, tex, "VERTICAL", cTop, cBottom)
      return
    end
  end
  local r,g,b,a = (top and top[1]) or 1, (top and top[2]) or 1, (top and top[3]) or 1, (top and top[4]) or 0.15
  tex:SetColorTexture(r,g,b,a)
end

-- Shadow / glow layer helper
function UIHelpers.ApplyShadow(tex, color, alphaOverride)
  if not tex then return end
  local c = color or (Tokens and Tokens.shadows and Tokens.shadows.low) or {0,0,0,0.25}
  tex:SetColorTexture(c[1], c[2], c[3], alphaOverride or c[4] or 0.25)
end

-- Simple fade animation (manual OnUpdate). Not frame-manager heavy.
function UIHelpers.Fade(frame, targetAlpha, duration, onDone)
  if not frame or not duration or duration <= 0 then if frame then frame:SetAlpha(targetAlpha or 1) end if onDone then pcall(onDone) end return end
  frame._fadeFrom = frame:GetAlpha() or 1
  frame._fadeTo = targetAlpha or 1
  frame._fadeTime = 0
  frame._fadeDur = duration
  frame._fadeOnDone = onDone
  frame:SetScript("OnUpdate", function(self, elapsed)
    self._fadeTime = self._fadeTime + elapsed
    local p = math.min(1, self._fadeTime / self._fadeDur)
    local a = self._fadeFrom + (self._fadeTo - self._fadeFrom) * p
    self:SetAlpha(a)
    if p >= 1 then
      self:SetScript("OnUpdate", nil)
      if self._fadeOnDone then pcall(self._fadeOnDone) end
      self._fadeOnDone = nil
    end
  end)
end

-- Animate a numeric property via a setter callback
-- setter(progressValue) will be called each frame with the interpolated value
function UIHelpers.AnimateNumber(from, to, duration, setter, onDone)
  if not setter or not duration or duration <= 0 then if setter then setter(to) end if onDone then pcall(onDone) end return end
  local elapsed = 0
  local done = false
  local host = CreateFrame("Frame")
  host:Show()
  host:SetScript("OnUpdate", function(_, dt)
    if done then return end
    elapsed = elapsed + dt
    local p = math.min(1, elapsed / duration)
    local v = from + (to - from) * p
    pcall(setter, v)
    if p >= 1 then
      done = true
      host:Hide() -- stop OnUpdate firing
      -- keep a no-op to satisfy analyzers that dislike nil handlers
      host:SetScript("OnUpdate", function() end)
      if onDone then pcall(onDone) end
    end
  end)
end

-- Slide a frame's width from -> to over duration; optional per-step callback
function UIHelpers.SlideWidth(frame, from, to, duration, onStep, onDone)
  if not frame then if onDone then pcall(onDone) end return end
  local function setter(v)
    v = math.max(0, math.floor(v + 0.5))
    frame:SetWidth(v)
    if onStep then pcall(onStep, v) end
  end
  UIHelpers.AnimateNumber(from or frame:GetWidth() or 0, to or 0, duration or 0.20, setter, onDone)
end

-- Basic frame pooling (homogeneous frame type). Caller supplies createFn(parent) -> frame.
function UIHelpers.GetPool(createFn)
  local pool = { _free = {}, _active = {} }
  function pool:Acquire(parent)
    local f = tremove(self._free)
    if not f then f = createFn(parent) end
    self._active[#self._active+1] = f
    f:Show()
    return f
  end
  function pool:ReleaseAll()
    for i, f in ipairs(self._active) do if f.Hide then f:Hide() end self._free[#self._free+1] = f end
    wipe(self._active)
  end
  return pool
end

-- Reusable Accordion Component
-- DEPRECATED note: The accordion's automatic multiline message editing (default build)
-- has been superseded by simpler message editors in UI_Settings.lua (Aug 2025). This
-- component remains for structural grouping only and can be removed once no modules
-- depend on dynamic Add/Remove message sections.
-- API: local acc = UIHelpers.CreateAccordion(parent, sections, opts)
-- sections: array of { key=string, label=string, build=function(container, section) -> frame (optional),
--                      getText=function() return text end, setText=function(text) end,
--                      expanded=bool }
-- opts: { collapsedHeight=number, contentHeight=number, singleExpand=true, iconCollapsed, iconExpanded }
function UIHelpers.CreateAccordion(parent, sections, opts)
  opts = opts or {}
  local collapsedH = opts.collapsedHeight or 26
  local contentH   = opts.contentHeight or 100
  local singleExpand = (opts.singleExpand ~= false) -- default true
  local iconCollapsed = opts.iconCollapsed or "+"
  local iconExpanded  = opts.iconExpanded  or "–"
  local timing = (Tokens and Tokens.timing and Tokens.timing.slow) or 0.25
  local neutral = Tokens and Tokens.colors and Tokens.colors.neutral or nil
  local accent  = Tokens and Tokens.colors and Tokens.colors.accent or nil

  local frame = CreateFrame("Frame", nil, parent)
  rawset(frame, 'sections', AccordionSections.new())
  local function Sections() return rawget(frame, 'sections') end

  local function Relayout()
    local y = 0
    local total = 0
  Sections():ForEach(function(sec)
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", 0, -y)
        sec:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        local target = sec._expanded and (collapsedH + contentH + 12) or collapsedH
        if sec._animating then target = sec._animHeight or target end
        sec:SetHeight(target)
        y = y + target + 4
        total = total + target + 4
  end)
    frame:SetHeight(total)
  end

  local function CollapseOthers(except)
    if not singleExpand then return end
    Sections():ForEach(function(s)
      if s ~= except and s._expanded then
        s._expanded = false
        if s.content then s.content:Hide() end
        if s.arrow then s.arrow:SetText(iconCollapsed) end
      end
    end)
  end

  local function AnimateHeight(sec, from, to)
    sec._animating = true
    sec._animHeight = from
    sec._animElapsed = 0
    sec._animFrom, sec._animTo = from, to
    sec:SetScript("OnUpdate", function(self, elapsed)
      self._animElapsed = self._animElapsed + elapsed
      local p = math.min(1, self._animElapsed / timing)
      local h = self._animFrom + (self._animTo - self._animFrom) * p
      self._animHeight = h
      self:SetHeight(h)
      if p >= 1 then
        self._animating = false
        self:SetScript("OnUpdate", nil)
        self._animHeight = nil
        Relayout()
      end
    end)
  end

  local keyMap = {}
  
  -- Public accessor for direct section lookup
  function frame:GetSection(key) return keyMap[key] end

  function frame:SetSingleExpand(v) singleExpand = (v and true) or false end
  function frame:IsSingleExpand() return singleExpand end
  function frame:Open(k)
    local s = keyMap[k]; if not s then return end
    if s._expanded then return end
    if singleExpand then CollapseOthers(s) end
    s._expanded = true; if s.arrow then s.arrow:SetText(iconExpanded) end
    s.content:Show(); UIHelpers.Fade(s.content, 1, timing/2)
    AnimateHeight(s, s:GetHeight(), collapsedH + contentH + 12)
    Relayout()
  end
  function frame:Close(k)
    local s = keyMap[k]; if not s or not s._expanded then return end
    s._expanded=false; if s.arrow then s.arrow:SetText(iconCollapsed) end
    UIHelpers.Fade(s.content, 0, timing/2, function() if not s._expanded then s.content:Hide() end end)
    AnimateHeight(s, s:GetHeight(), collapsedH)
    Relayout()
  end
  function frame:Toggle(k)
    local s = keyMap[k]; if not s then return end
    if s._expanded then frame:Close(k) else frame:Open(k) end
  end
  function frame:CloseAll() for k,_ in pairs(keyMap) do frame:Close(k) end end
  function frame:OpenAll() if singleExpand then return end for k,_ in pairs(keyMap) do frame:Open(k) end end

  local function CreateSection(def, index)
    local sec = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sec.key = def.key or ("sec"..index)
    sec._expanded = def.expanded and true or false
    sec:SetBackdrop({ bgFile="Interface/Buttons/WHITE8x8", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10, tile=true, tileSize=8, insets={left=2,right=2,top=2,bottom=2} })
    local topG = (Tokens and Tokens.gradients and Tokens.gradients.panel and Tokens.gradients.panel.top) or {0.15,0.15,0.17,0.55}
    local botG = (Tokens and Tokens.gradients and Tokens.gradients.panel and Tokens.gradients.panel.bottom) or {0.08,0.08,0.09,0.80}
    if not sec._gradient then
      local g = sec:CreateTexture(nil, "BACKGROUND", nil, -7)
      g:SetPoint("TOPLEFT", 3, -3)
      g:SetPoint("BOTTOMRIGHT", -3, 3)
      UIHelpers.ApplyGradient(g, topG, botG)
      sec._gradient = g
    end
    sec:SetBackdropColor(0,0,0,0.30)
    if accent and accent.subtle then
      sec:SetBackdropBorderColor(accent.subtle[1], accent.subtle[2], accent.subtle[3], 0.85)
    else
      sec:SetBackdropBorderColor(0.35,0.35,0.38,0.75)
    end

    -- Header button
    local btn = CreateFrame("Button", nil, sec)
    btn:SetPoint("TOPLEFT", 4, -4)
    btn:SetPoint("TOPRIGHT", -4, -4)
    btn:SetHeight(collapsedH-6)
    btn:RegisterForClicks("LeftButtonUp")
    -- Use a very subtle highlight (the default listbox highlight produced a persistent looking white box near our custom icons)
    btn:SetHighlightTexture("Interface/Buttons/WHITE8x8")
    local hl = btn:GetHighlightTexture()
    if hl then
      hl:SetVertexColor(1,1,1,0.08)
      hl:ClearAllPoints()
      hl:SetPoint("TOPLEFT", 2, -2)
      hl:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    -- Ensure no leftover normal/pushed textures create opaque squares
  -- Clearing textures safely (avoid nil assignment type warning)
  if btn.SetNormalTexture then btn:SetNormalTexture("") end
  if btn.SetPushedTexture then btn:SetPushedTexture("") end
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow:SetPoint("LEFT", 4, 0)
    arrow:SetText(sec._expanded and iconExpanded or iconCollapsed)
    sec.arrow = arrow
    local title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
    title:SetText(def.label or sec.key)
    sec.titleFS = title

    -- Content container
    local content = CreateFrame("Frame", nil, sec)
    content:SetPoint("TOPLEFT", 6, -collapsedH)
    content:SetPoint("RIGHT", -6, 0)
    content:SetHeight(contentH)
    sec.content = content

  -- (Removed erroneous def:buildPlaceholder() call that prevented section construction)
    -- Build content: either custom builder or default multiline edit box with get/set
    local eb
    if def.build and type(def.build) == "function" then
      local built = def.build(content, sec)
      if built and built.EditBox then eb = built.EditBox end
    else
      -- Prefer modern Blizzard multiline edit box (Dragonflight+ look) then fallback.
      local box
  local okNew, newBox = pcall(CreateFrame, "Frame", nil, content, "ScrollingEditBoxTemplate")
      if okNew and newBox and newBox.EditBox then
        box = newBox
        box:SetPoint("TOPLEFT", 0, 0); box:SetPoint("BOTTOMRIGHT", 0, 0)
        eb = box.EditBox
      else
        box = CreateFrame("ScrollFrame", nil, content, "InputScrollFrameTemplate")
        box:SetPoint("TOPLEFT", 0, 0); box:SetPoint("BOTTOMRIGHT", 0, 0)
        if box.CharCount then box.CharCount:Hide() end
        eb = box.EditBox
      end
      eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false); eb:SetMultiLine(true)
      local maxChars = def.maxChars or 255 -- default WoW chat message soft limit
      -- Use explicit cap; previously 0 (then 1000) caused UX issues & invalid lengths.
      if maxChars > 0 then eb:SetMaxLetters(maxChars) end
      eb:ClearFocus()
      -- Ensure sensible initial sizing so user can click & type (some clients require explicit height/width)
  eb:SetWidth(content:GetWidth() - 16)
  eb:SetHeight(60)
  -- Hide scrollbar until overflow actually happens (support both templates)
  local scrollBar = box.ScrollBar or box.scrollBar or box.ScrollBarWidget or _G[box:GetName() and (box:GetName().."ScrollBar") or ""]
      if scrollBar then scrollBar:Hide(); scrollBar._autoHidden = true end
      local useDynamicHeight = (not okNew) -- Only attempt dynamic sizing for legacy InputScrollFrameTemplate
      local function ResizeForContent()
        if not useDynamicHeight then
          -- For modern template just toggle scrollbar based on simple heuristics
          local textLen = eb:GetNumLetters() or (#eb:GetText())
          local multiline = (eb:GetText():find("\n")) and true or false
          if (textLen > 180 or multiline) and scrollBar then scrollBar:Show() else if scrollBar and scrollBar._autoHidden then scrollBar:Hide() end end
          return
        end
        local needed
        if eb.GetStringHeight then
          needed = eb:GetStringHeight() + 24
        else
          needed = (eb:GetHeight() or 60)
        end
        if needed < 60 then needed = 60 end
        if needed > content:GetHeight() - 4 then
          if scrollBar then scrollBar:Show() end
        else
          if scrollBar and scrollBar._autoHidden then scrollBar:Hide() end
        end
        eb:SetHeight(needed)
        if box.UpdateScrollChildRect then box:UpdateScrollChildRect() end
      end
      -- Dynamic character counter (bottom-right) showing current / max with color ramp.
      local counter = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      counter:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 4)
      counter:SetTextColor(0.75,0.75,0.75,0.9)
      local function UpdateCounter()
        local len = eb:GetNumLetters() or (#eb:GetText())
        local pct = (maxChars > 0) and (len / maxChars) or 0
        if maxChars > 0 then
          if pct >= 0.95 then counter:SetTextColor(1,0.15,0.15,1)
          elseif pct >= 0.85 then counter:SetTextColor(1,0.55,0.10,1)
          elseif pct >= 0.70 then counter:SetTextColor(1,0.85,0.10,1)
          else counter:SetTextColor(0.70,0.70,0.70,0.9) end
          counter:SetText(string.format("%d/%d", len, maxChars))
        else
          counter:SetText(tostring(len))
        end
        ResizeForContent()
      end
      eb:HookScript("OnTextChanged", function(self)
        UpdateCounter()
        -- Live edit event (avoid spam mitigation for now; lightweight payload)
        local Bus = Addon.EventBus
        if Bus and Bus.Publish then
          pcall(Bus.Publish, Bus, "MessageEditing", sec.key, self:GetText(), self:GetNumLetters() or #self:GetText(), maxChars)
        end
      end)
  C_Timer.After(0, function() UpdateCounter(); ResizeForContent() end)
    end
    if eb then
      if def.getText then eb:SetText(def.getText() or "") end
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEnterPressed",  function(self) self:Insert("\n") end)
      eb:SetScript("OnEditFocusGained", function(self)
        -- Preserve existing text but position cursor at end (no auto highlight to avoid accidental overwrite)
        local n = self:GetNumLetters() or 0
        self:SetCursorPosition(n)
      end)
      eb:EnableMouse(true)
      eb:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" then
          -- Right-click = select all & copy to clipboard via temporary copy frame (user can Ctrl-C)
          self:HighlightText()
        else
          self:SetFocus()
        end
      end)
      -- Mousewheel scroll support (within the InputScrollFrameTemplate)
      if eb:GetParent() and eb:GetParent().EnableMouseWheel then
        local host = eb:GetParent()
        host:EnableMouseWheel(true)
        host:SetScript("OnMouseWheel", function(frame, delta)
          local sb = frame.ScrollBar or frame.scrollBar or _G[frame:GetName() and (frame:GetName().."ScrollBar") or ""]
          if sb and sb.SetValue and sb.GetValue then
            local step = 20 * (delta>0 and -1 or 1)
            sb:SetValue((sb:GetValue() or 0) + step)
          end
        end)
      end
      eb:SetScript("OnEditFocusLost", function(self)
        if def.setText then def.setText(self:GetText()) end
        self:HighlightText(0,0)
      end)
    end
    sec.editBox = eb

  if not sec._expanded then content:Hide() else content:SetAlpha(1) end

  btn:SetScript("OnClick", function() frame:Toggle(sec.key) end)

  Sections():Add(sec)
  keyMap[sec.key] = sec
    return sec
  end

  if sections then for i, def in ipairs(sections) do CreateSection(def, i) end end

  -- Dynamic mutations
  function frame:AddSection(def)
    local idx = frame.sections:Count() + 1
    local sec = CreateSection(def, idx)
    Relayout()
    return sec
  end
  function frame:RemoveSection(key)
    local sec = keyMap[key]; if not sec then return false end
    -- Find index in collection
    local removeIndex = nil
    frame.sections:ForEach(function(s, i) if s == sec then removeIndex = i end end)
    if removeIndex then
      if frame.sections.RemoveAt then frame.sections:RemoveAt(removeIndex) end
    end
    if sec.Hide then sec:Hide() end
    keyMap[key] = nil
    Relayout()
    return true
  end
  function frame:RemoveAllSections()
    frame.sections:ForEach(function(s) if s.Hide then s:Hide() end end)
    -- Recreate empty collection to drop references
    frame.sections = AccordionSections.new()
    for k in pairs(keyMap) do keyMap[k] = nil end
    Relayout()
  end
  Relayout()
  return frame
end

Addon.provide("Tools.UIHelpers", UIHelpers)

-- Extended Help (/gr-help) moved here to centralize helper utilities
do
  if not _G.SLASH_GUILDRECRUITER_HELP1 then
    local function println(msg)
      if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff66ccff[%s]|r %s", ADDON_NAME or "GR", msg))
      else
        print("["..(ADDON_NAME or "GR").."] "..msg)
      end
    end
    local function Spacer() println(" ") end
  local function ShowExtendedHelp()
  println("|cffffff00Guild Prospector - Slash Commands|r")
  local t = (Addon and Addon.TITLE) or "Guild Prospector"
  println("|cffffff00"..t.." - Slash Commands|r")
      println("|cffccccccPrimary:|r  /gr  /guildrecruiter  /guildrec")
      println("  /gr ui|toggle        - Open main UI window")
      println("  /gr settings|options - Open settings (or /groptions /grsettings)")
      println("  /gr help             - Short help summary (try /gr-help for full)")
      println("  /gr-help             - Full detailed help list")
      Spacer()
      println("|cffccccccRotation Messages:|r")
      println("  /gr messages add <n>    - Add new rotation message slot <n>")
      println("  /gr messages remove <n> - Remove message slot <n> (>3 only)")
      println("  /gr messages list       - List existing message indices")
      Spacer()
      println("|cffccccccDeveloper / Diagnostics:|r")
      println("  /gr devmode on|off|toggle - Show/hide Debug tab")
  println("  /gr diag                  - Diagnostics summary")
  println("  /gr events                - EventBus diagnostics dump")
  println("  /gr sv list               - List SavedVars namespaces")
  println("  /gr sv get <ns> [key]     - Dump namespace or a single key")
  println("  /gr sv export <ns>        - Table form for namespace")
  println("  /gr sv json <ns> [key]    - JSON (compact) export (optionally a single key)")
  println("  /gr sv jsonp <ns> [key]   - JSON (pretty) export (optionally a single key)")
  println("  /gr sv prune <ns> <key> <max> - Size prune list to <max> items (keep newest)")
  println("  /gr sv prune.f <ns> <key> [tokens] - Filter prune. Tokens:")
  println("       max:<n> limit size after filter; age:<secAgo> min age; match:<substr> include; drop:<substr> exclude")
  println("  /gr prune prospects <max>  - Trim prospects list to newest <max>")
  println("  /gr prune blacklist <max>  - Trim blacklist to most recent <max>")
  println("  /gr test decline <Name>    - Simulate a decline (dev mode)")
      Spacer()
      println("|cffccccccOptions Shortcuts:|r  /groptions  /grsettings")
      Spacer()
      println("|cffccccccNotes:|r")
      println("  Tokens: {Guild} {Player} {Class} {Level} {Realm} {Date} {Time}")
      println("  Dev Mode unlocks the Debug log tab.")
    end
    -- Register /gr-help centrally now that legacy UI/UI_Help.lua removed
    if not _G.SLASH_GUILDRECRUITER_HELP1 then
      SLASH_GUILDRECRUITER_HELP1 = "/gr-help"
    end
  SlashCmdList.GUILDRECRUITER_HELP = function() ShowExtendedHelp() end
    -- Expose helper
    Addon.UI = Addon.UI or {}
    Addon.UI.ShowExtendedHelp = ShowExtendedHelp
    -- Extend existing /gr root dispatcher if present_elsewhere; minimal inline version
  if not _G.SLASH_GUILDRECRUITER1 then
      SLASH_GUILDRECRUITER1 = "/gr"
      SLASH_GUILDRECRUITER2 = "/guildrecruiter"
      SLASH_GUILDRECRUITER3 = "/guildrec"
      local function dispatch(msg)
        msg = (msg or ""):gsub("^%s+","" ):gsub("%s+$", "")
        if msg == "" or msg == "ui" or msg == "toggle" then
          if Addon.UI and Addon.UI.Main and Addon.UI.Main.Toggle then Addon.UI.Main:Toggle() else println("UI not ready") end; return
        end
        local args = {}
        for w in msg:gmatch("%S+") do args[#args+1]=w end
        local cmd = args[1] and args[1]:lower() or ""
        if cmd == "events" then
          local bus = Addon.EventBus
          if bus and bus.Diagnostics then
            local d = bus:Diagnostics()
            println(string.format("EventBus publishes=%d errors=%d events=%d", d.publishes or 0, d.errors or 0, #(d.events or {})))
            for _, ev in ipairs(d.events or {}) do
              println(string.format("  %s (%d handlers)", ev.event, ev.handlers))
            end
          else
            println("EventBus diagnostics not available")
          end
          return
        elseif cmd == "sv" then
          local sub = (args[2] or ""):lower()
          local SV = Addon.SavedVars
          if sub == "list" then
            local root = SV:GetNamespace("")
            local names = {}
            for k,v in pairs(root) do if type(v)=="table" and k:sub(1,2) ~= "__" then names[#names+1]=k end end
            table.sort(names)
            println("SavedVars namespaces: "..( (#names>0) and table.concat(names, ", ") or "(none)" ))
            return
          elseif sub == "get" then
            local ns = args[3]; if not ns then println("Usage: /gr sv get <ns> [key]") return end
            local key = args[4]
            if key then
              local val = SV:Get(ns, key, nil)
              println(string.format("%s[%s] = %s", ns, key, tostring(val)))
            else
              local tbl = SV:GetNamespace(ns)
              println("Namespace "..ns..":")
              local n=0; for k,v in pairs(tbl) do n=n+1; if type(v)~="table" then println("  "..k.." = "..tostring(v)) end end
              println(string.format("  (%d keys, tables omitted)", n))
            end
            return
          elseif sub == "export" then
            local ns = args[3]; if not ns then println("Usage: /gr sv export <ns>") return end
            local snapshot = SV:Export(ns)
            println("Export "..ns.." -> table (use /dump in macro for full view)")
            _G.GUILDRECRUITER_LAST_EXPORT = snapshot
            println("Stored at _G.GUILDRECRUITER_LAST_EXPORT")
            return
          elseif sub == "json" or sub == "jsonp" then
            local ns = args[3]; if not ns then println("Usage: /gr sv json <ns> [key]") return end
            local key = args[4]
            local snapshot
            if key then
              local v = SV:Get(ns, key, nil)
              if type(v) == "table" then
                snapshot = v
              else
                snapshot = { [key] = v }
              end
            else
              snapshot = SV:Export(ns)
            end
            local encoder = Addon.JSON or (Addon.require and Addon.require("Tools.JSON"))
            if not encoder or not encoder.Encode then println("JSON encoder missing") return end
            local json
            if sub == "jsonp" and encoder.EncodePretty then
              local ok, pretty = pcall(encoder.EncodePretty, snapshot)
              if ok and type(pretty) == "string" then json = pretty end
            end
            if not json then
              local ok2, compact = pcall(encoder.Encode, snapshot)
              json = (ok2 and compact) or "{}"
            end
            local prettyFlag = (sub=="jsonp")
            if prettyFlag then _G.GUILDRECRUITER_LAST_JSON_PRETTY = json else _G.GUILDRECRUITER_LAST_JSON = json end
            -- Also persist via SavedVars service for later sessions (exports namespace)
            pcall(function() if Addon.SavedVars and Addon.SavedVars.Set then Addon.SavedVars:Set("exports", prettyFlag and "lastPrettyJSON" or "lastJSON", json) end end)
            local len = #json
            println(string.format("%s JSON stored (%d chars). Global: %s", prettyFlag and "Pretty" or "Compact", len, prettyFlag and "_G.GUILDRECRUITER_LAST_JSON_PRETTY" or "_G.GUILDRECRUITER_LAST_JSON"))
            local maxPrint = prettyFlag and 800 or 400
            if len <= maxPrint then
              println(json)
            else
              -- Print head + tail for context
              println("(Truncated) First 300 chars:")
              println(json:sub(1,300).."...")
              println("Use copy from global variable for full content.")
            end
            return
          elseif sub == "prune" then
            local ns, key, maxStr = args[3], args[4], args[5]
            if not (ns and key and maxStr) then println("Usage: /gr sv prune <ns> <key> <max>") return end
            local max = tonumber(maxStr)
            if not max or max < 0 then println("Invalid max") return end
            if not Addon.SavedVars or not Addon.SavedVars.Prune then println("SavedVars service missing Prune") return end
            local newLen = Addon.SavedVars:Prune(ns, key, max)
            println(string.format("Pruned %s.%s to %d items", ns, key, newLen))
            return
          elseif sub == "prune.f" then
            local ns, key = args[3], args[4]
            if not (ns and key) then println("Usage: /gr sv prune.f <ns> <key> [tokens]") return end
            if not Addon.SavedVars or not Addon.SavedVars.PruneFiltered then println("SavedVars service missing PruneFiltered") return end
            local opts = {}
            for i=5,#args do
              local token = args[i]
              local k,v = token:match("^(%w+):(.*)$")
              if k and v and v ~= "" then
                if k == "max" then opts.max = tonumber(v)
                elseif k == "age" then
                  local sec = tonumber(v); if sec and sec > 0 then opts.minTimestamp = (time() - sec) end
                elseif k == "match" then opts.match = v
                elseif k == "drop" then opts.drop = v
                end
              end
            end
            local res = Addon.SavedVars:PruneFiltered(ns, key, opts)
            println(string.format("Filtered prune %s.%s removed %d (now %d from %d)", ns, key, res.removed or 0, res.after or 0, res.before or 0))
            return
          else
            println("sv subcommands: list|get|export|json|jsonp|prune|prune.f")
            return
          end
        elseif cmd == "help" then
          ShowExtendedHelp(); return
        elseif cmd == "prune" then
          local target = args[2]
          local max = tonumber(args[3] or "")
          if not target or not max then println("Usage: /gr prune prospects|blacklist <max>") return end
          local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
          if not pm then println("ProspectManager unavailable") return end
          if target == "prospects" and pm.PruneProspects then
            local removed = pm:PruneProspects(max) or 0
            println("Pruned prospects removed="..removed)
          elseif target == "blacklist" and pm.PruneBlacklist then
            local removed = pm:PruneBlacklist(max) or 0
            println("Pruned blacklist removed="..removed)
          else
            println("Invalid target (use prospects|blacklist)")
          end
          return
        elseif cmd == "test" and args[2] == "decline" then
          local cfg = Addon.require and Addon.require("IConfiguration")
          if not (cfg and cfg.Get and cfg:Get("devMode", false)) then println("Dev mode required (/gr devmode on)") return end
          local who = args[3]; if not who then println("Usage: /gr test decline <Name>") return end
          local pm = (Addon.Get and Addon.Get('IProspectManager')) or (Addon.require and Addon.require('ProspectsManager'))
          if not pm then println("ProspectManager unavailable") return end
          local guidMatch
          if pm.GetAllGuids and pm.GetProspect then
            for _,pg in ipairs(pm:GetAllGuids() or {}) do local p = pm:GetProspect(pg); if p and p.name and p.name:lower()==who:lower() then guidMatch=pg break end end
          end
          if guidMatch then
            if pm and pm.Blacklist then pm:Blacklist(guidMatch, "decline-test") end
            local bus = Addon.require and Addon.require("EventBus")
            if bus and bus.Publish then bus:Publish("InviteService.InviteDeclined", guidMatch, who) end
            println("Simulated decline for "..who)
          else
            println("Prospect not found: "..who)
          end
          return
        end
        println("Unknown command. Try /gr help or /gr-help")
      end
      SlashCmdList.GUILDRECRUITER = dispatch
    end
  end
end

return UIHelpers
