-- tools/Markdown.lua
-- Tiny Markdown -> SimpleHTML converter (safe subset)
-- Supports: #, ##, ### headers; blank-line separated paragraphs; [text](url) links; ![alt](url) images
-- Output is SimpleHTML-ready: <html><body> ... </body></html>
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local M = {}

local function esc(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return s
end

local function linkify(text)
  -- [text](url)
  text = text:gsub("%[(.-)%]%((.-)%)", function(label, url)
    label = esc(label); url = esc(url)
    -- Use WoW hyperlink format for custom urls: |Hurl:<url>|h[label]|h
    return string.format("|Hurl:%s|h[%s]|h", url, label)
  end)
  return text
end

local function imgify(text)
  -- ![alt](url) -> <img src="url"/>
  text = text:gsub("!%[(.-)%]%((.-)%)", function(_, url)
    url = esc(url)
    return string.format('<img src="%s"/>', url)
  end)
  return text
end

function M.ToSimpleHTML(md)
  local lines = {}
  for line in tostring(md or ""):gmatch("([^\n]*)\n?") do lines[#lines+1] = line end
  local out = { "<html><body>" }
  local function emit(chunk) out[#out+1] = chunk end
  for _,ln in ipairs(lines) do
    local s = ln:match("^%s*(.-)%s*$")
    if s == "" then
      emit('<p></p>')
    else
      local h1 = s:match('^#%s+(.+)$')
      local h2 = not h1 and s:match('^##%s+(.+)$')
      local h3 = not h1 and not h2 and s:match('^###%s+(.+)$')
      if h1 then
        emit(string.format('<h1>%s</h1>', esc(h1)))
      elseif h2 then
        emit(string.format('<h2>%s</h2>', esc(h2)))
      elseif h3 then
        emit(string.format('<h3>%s</h3>', esc(h3)))
      else
        s = imgify(s)
        s = linkify(s)
        emit(string.format('<p>%s</p>', s))
      end
    end
  end
  emit("</body></html>")
  return table.concat(out)
end

-- DI provide for reuse
if Addon and Addon.provide then
  Addon.provide('Tools.Markdown', M, { lifetime = 'SingleInstance', meta = { layer = 'Infrastructure', area = 'tools/markdown' } })
end

return M
