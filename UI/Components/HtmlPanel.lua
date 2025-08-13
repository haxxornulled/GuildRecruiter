-- UI/Components/HtmlPanel.lua
-- SimpleHTML-backed panel wrapper for rendering static/semi-static rich text.
-- Usage:
--   local HtmlPanel = require('UI.Components.HtmlPanel') -- or dofile path via TOC
--   local panel = HtmlPanel.new({ EventBus = Addon.Get and Addon.Get('EventBus') })
--   local frame = panel:Create(parent)
--   panel:SetContent('<html><body><h1 align="center">Title</h1><p>Hello</p></body></html>')
--   -- Optional with Markdown helper: panel:SetMarkdown(mdText)

local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local HtmlPanel = {}
HtmlPanel.__index = HtmlPanel

local function mapFonts(h)
  -- Map basic tags to Blizzard fonts; customize via UI/Style if desired
  if h.SetFontObject then
    pcall(h.SetFontObject, h, "h1", GameFontHighlightLarge)
    pcall(h.SetFontObject, h, "h2", GameFontNormalLarge)
    pcall(h.SetFontObject, h, "h3", GameFontNormal)
    pcall(h.SetFontObject, h, "p",  GameFontHighlight)
  end
end

function HtmlPanel.new(deps)
  return setmetatable({ deps = deps or {}, ui = {} }, HtmlPanel)
end

function HtmlPanel:Create(parent)
  local h = CreateFrame("SimpleHTML", nil, parent)
  h:SetPoint("TOPLEFT", 10, -10)
  h:SetPoint("BOTTOMRIGHT", -10, 10)
  mapFonts(h)
  if h.SetHyperlinksEnabled then h:SetHyperlinksEnabled(true) end
  h:SetScript("OnHyperlinkClick", function(_, link, text, button)
    local bus = self.deps and self.deps.EventBus
    if bus and type(bus.Publish) == 'function' then
      pcall(bus.Publish, bus, ADDON_NAME..".UI.Hyperlink", link, text, button)
    end
    -- Fallback: copy to chat edit box
    local editBox = nil
    if type(_G.ChatEdit_GetActiveWindow) == 'function' then
      local ok, eb = pcall(_G.ChatEdit_GetActiveWindow)
      if ok then editBox = eb end
    end
    if not editBox then editBox = rawget(_G, 'ChatFrame1EditBox') end
    if editBox and editBox.IsShown and editBox.Insert then
      local shownOk, isShown = pcall(editBox.IsShown, editBox)
      if shownOk and isShown then pcall(editBox.Insert, editBox, text or link) end
    end
  end)
  self.ui.html = h
  return h
end

function HtmlPanel:SetContent(html)
  local h = self.ui and self.ui.html
  if h and h.SetText then h:SetText(tostring(html or "")) end
end

function HtmlPanel:SetMarkdown(md)
  local mdMod = Addon and (Addon.Get and Addon.Get('Tools.Markdown'))
  if not mdMod or type(mdMod.ToSimpleHTML) ~= 'function' then
    -- graceful fallback: set plain text wrapped as paragraph
    return self:SetContent(string.format('<html><body><p>%s</p></body></html>', tostring(md or "")))
  end
  local html = mdMod.ToSimpleHTML(md or "")
  self:SetContent(html)
end

return HtmlPanel
