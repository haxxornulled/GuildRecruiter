-- Tools/UIHelpers.lua
-- Reusable UI helper utilities: gradient, shadows, animations (lightweight), pooling.

local ADDON_NAME, Addon = ...
local Tokens = Addon.require and Addon.require("Tools.Tokens")
local UIHelpers = {}
local AccordionSections = Addon.require and (Addon.require("Collections.AccordionSections") or Addon.require("AccordionSections"))
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
local List = Addon.require and Addon.require("Collections.List")

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
  frame.sections = AccordionSections.new()

  local function Relayout()
    local y = 0
    local total = 0
  frame.sections:ForEach(function(sec)
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
    frame.sections:ForEach(function(s)
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
    btn:SetHighlightTexture("Interface/Buttons/UI-Listbox-Highlight2")
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

    if def.build then
      def:buildPlaceholder() -- ensure colon isn't misused accidentally
    end
    -- Build content: either custom builder or default multiline edit box with get/set
    local eb
    if def.build and type(def.build) == "function" then
      local built = def.build(content, sec)
      if built and built.EditBox then eb = built.EditBox end
    else
      local box = CreateFrame("ScrollFrame", nil, content, "InputScrollFrameTemplate")
      box:SetPoint("TOPLEFT", 0, 0); box:SetPoint("BOTTOMRIGHT", 0, 0)
      if box.CharCount then box.CharCount:Hide() end
      eb = box.EditBox; eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false); eb:SetMultiLine(true)
      eb:SetMaxLetters(0); eb:ClearFocus()
    end
    if eb then
      if def.getText then eb:SetText(def.getText() or "") end
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEnterPressed",  function(self) self:Insert("\n") end)
      eb:SetScript("OnEditFocusLost", function(self)
        if def.setText then def.setText(self:GetText()) end
      end)
    end
    sec.editBox = eb

  if not sec._expanded then content:Hide() else content:SetAlpha(1) end

  btn:SetScript("OnClick", function() frame:Toggle(sec.key) end)

  frame.sections:Add(sec)
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
return UIHelpers
