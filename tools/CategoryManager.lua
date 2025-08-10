-- Tools/CategoryManager.lua
-- Extracted category management + decorators from UI_MainFrame for reuse.

local ADDON_NAME, Addon = ...
local CategoryManager = {}

-- Internal state
local categories = {}
local decorators = {} -- key -> function(cat) return suffix string or nil end
local selectedIndex = 1
local initialized = false

local DEFAULT_CATEGORIES = {
  { key = "summary",   label = "Summary"   },
  { key = "prospects", label = "Prospects" },
  { key = "blacklist", label = "Blacklist" },
  { type = "separator" },
  { key = "settings",  label = "Settings"  },
  { key = "debug",     label = "Debug"     },
}

-- Utility
local function SortCategories()
  table.sort(categories, function(a,b)
    local ao = a.order or 1000
    local bo = b.order or 1000
    if ao == bo then
      local ak = a.key or (a.type=="separator" and "~sep"..tostring(a._seq) or "")
      local bk = b.key or (b.type=="separator" and "~sep"..tostring(b._seq) or "")
      return ak < bk
    end
    return ao < bo
  end)
end

local function EvaluateVisibility(cat)
  if cat.type == "separator" then return true end
  if cat.visible == nil then return true end
  if type(cat.visible) == "function" then
    local ok, res = pcall(cat.visible, cat)
    if ok then return not not res end
    return true
  end
  return not not cat.visible
end

local function ApplyDecorators()
  for _, cat in ipairs(categories) do
    if cat.type ~= "separator" then
      local deco = decorators[cat.key]
      if deco then
        local ok, label = pcall(deco, cat)
        if ok and label and label ~= "" then
          cat._renderedLabel = (cat.label or cat.key)..label
        else
          cat._renderedLabel = cat.label or cat.key
        end
      else
        cat._renderedLabel = cat.label or cat.key
      end
    end
  end
end

-- Public API
function CategoryManager:Init(initial)
  categories = {}
  if type(initial)=="table" and #initial>0 then
    for _, v in ipairs(initial) do categories[#categories+1] = v end
  else
    for _, v in ipairs(DEFAULT_CATEGORIES) do categories[#categories+1] = v end
  end
  initialized = true
  SortCategories(); ApplyDecorators();
end

function CategoryManager:EnsureInitialized()
  if not initialized or #categories==0 then self:Init(categories) end
end

function CategoryManager:AddCategory(def)
  if not def or type(def) ~= "table" or not def.key then return end
  for _, c in ipairs(categories) do if c.key == def.key then return end end
  def.type = def.type or "category"
  categories[#categories+1] = def
  SortCategories(); ApplyDecorators()
end

function CategoryManager:AddSeparator(order)
  categories[#categories+1] = { type = "separator", order = order }
  SortCategories()
end

function CategoryManager:RemoveCategory(key)
  for i=#categories,1,-1 do
    local c = categories[i]
    if c.key == key then table.remove(categories, i) end
  end
end

function CategoryManager:SetCategoryVisible(key, visible)
  for _, c in ipairs(categories) do if c.key == key then c.visible = visible; break end end
end

function CategoryManager:RegisterCategoryDecorator(key, fn)
  if type(fn) == "function" then decorators[key] = fn else decorators[key] = nil end
  ApplyDecorators()
end

function CategoryManager:ListCategories()
  local out = {}
  for _, c in ipairs(categories) do if c.type ~= "separator" and EvaluateVisibility(c) then out[#out+1] = c.key end end
  return out
end

function CategoryManager:GetAll()
  self:EnsureInitialized();
  ApplyDecorators();
  return categories
end

function CategoryManager:SelectIndex(idx)
  if categories[idx] then selectedIndex = idx end
end
function CategoryManager:GetSelectedIndex() return selectedIndex end

function CategoryManager:SelectCategoryByKey(key)
  for i, c in ipairs(categories) do if c.key == key then self:SelectIndex(i); return true end end
  return false
end

function CategoryManager:EvaluateVisibility(cat) return EvaluateVisibility(cat) end
function CategoryManager:ApplyDecorators() ApplyDecorators() end

Addon.provide("Tools.CategoryManager", function() return CategoryManager end, { lifetime = "SingleInstance" })
return CategoryManager
