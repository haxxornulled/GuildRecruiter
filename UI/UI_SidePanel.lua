-- UI_SidePanel.lua — Modern ButtonLib-powered sidebar with snazzy CSS-style buttons
---@diagnostic disable: undefined-global, undefined-field, inject-field
local Addon = select(2, ...)
local SidePanel = {}

-- Optimized button configuration for compact sidebar
local BUTTON_CONFIG = {
  width = 140,        -- Smaller width for compact panel
  height = 28,        -- Reduced height for better fit
  gap = 3,            -- Tighter spacing between buttons
  paddingX = 8,       -- Less padding from edges
  
  -- Button variants for different states
  variants = {
    default = "subtle",     -- Unselected buttons use subtle variant
    selected = "primary",   -- Selected button uses primary (gold) variant
    hover = "secondary",    -- Hover state uses secondary variant
  },
  
  -- Button sizes
  size = "sm",              -- Small size buttons for compact design
  
  -- Compact spacing
  separatorGap = 8,         -- Reduced gap around separators
  separatorHeight = 1,      -- Thinner separator line
}

-- Professional separator styling
local SEPARATOR_STYLE = {
  height = 1,
  leftPadding = 12,
  rightPadding = 12,
  mainColor = {0.6, 0.5, 0.3, 0.8},     -- Gold separator line
  glowColor = {1, 0.85, 0.4, 0.15},     -- Subtle glow
  glowHeight = 3,
}

local function CreateModernSeparator(parent)
  local sep = CreateFrame("Frame", nil, parent)
  sep:SetHeight(BUTTON_CONFIG.separatorGap)
  
  -- Subtle glow effect (background)
  local glow = sep:CreateTexture(nil, "BACKGROUND", nil, -1)
  glow:SetColorTexture(unpack(SEPARATOR_STYLE.glowColor))
  glow:SetPoint("LEFT", SEPARATOR_STYLE.leftPadding - 2, 0)
  glow:SetPoint("RIGHT", -SEPARATOR_STYLE.rightPadding + 2, 0)
  glow:SetHeight(SEPARATOR_STYLE.glowHeight)
  
  -- Main separator line (foreground)
  local line = sep:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(unpack(SEPARATOR_STYLE.mainColor))
  line:SetPoint("LEFT", SEPARATOR_STYLE.leftPadding, 0)
  line:SetPoint("RIGHT", -SEPARATOR_STYLE.rightPadding, 0)
  line:SetHeight(SEPARATOR_STYLE.height)
  
  return sep
end

local function CreateModernCategoryButton(parent, text, categoryData)
  local ButtonLib = Addon.require and Addon.require("Tools.ButtonLib")
  
  if not ButtonLib then
    -- Enhanced fallback for when ButtonLib isn't available
  local btn = CreateFrame("Button", nil, parent)
  pcall(function() btn:SetNormalFontObject("GameFontNormal") end)
    btn:SetSize(BUTTON_CONFIG.width, BUTTON_CONFIG.height)
    btn:SetText(text)
    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetHighlightFontObject("GameFontHighlight")
    
    function btn:SetSelected(selected)
      if selected then
        btn:SetNormalFontObject("GameFontHighlight")
        btn:GetNormalTexture():SetVertexColor(1, 0.85, 0.1, 0.8)
      else
        btn:SetNormalFontObject("GameFontHighlightSmall")
        btn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8, 0.6)
      end
    end
    
    return btn
  end
  
  -- Create modern ButtonLib button
  local btn = ButtonLib:Create(parent, {
    text = text,
    variant = BUTTON_CONFIG.variants.default,
    size = BUTTON_CONFIG.size,
    onClick = nil -- Will be set later
  })
  
  -- Set consistent size
  btn:SetSize(BUTTON_CONFIG.width, BUTTON_CONFIG.height)
  
  -- Store category data
  btn._categoryData = categoryData
  btn._isSelected = false
  btn._originalVariant = BUTTON_CONFIG.variants.default
  
  -- Enhanced selection system
  function btn:SetSelected(selected)
    self._isSelected = selected
    if selected then
      self._originalVariant = BUTTON_CONFIG.variants.selected
      self:SetVariant(BUTTON_CONFIG.variants.selected)
    else
      self._originalVariant = BUTTON_CONFIG.variants.default
      self:SetVariant(BUTTON_CONFIG.variants.default)
    end
  end
  
  -- Add count display functionality for categories with counts
  function btn:UpdateCount(count)
    if not count or count <= 0 then
      self:SetText(text)
    else
      self:SetText(string.format("%s (%d)", text, count))
    end
  end
  
  -- Override the ButtonLib hover effects to work with our selection system
  local originalOnEnter = btn:GetScript("OnEnter")
  local originalOnLeave = btn:GetScript("OnLeave")
  
  btn:SetScript("OnEnter", function(self)
    -- Only change variant on hover if not selected
    if not self._isSelected then
      self:SetVariant(BUTTON_CONFIG.variants.hover)
    end
    
    -- Add tooltip if category has description
    if categoryData and categoryData.description then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine(text, 1, 1, 1)
      GameTooltip:AddLine(categoryData.description, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
    
    -- Call original ButtonLib OnEnter if it exists
    if originalOnEnter then
      originalOnEnter(self)
    end
  end)
  
  btn:SetScript("OnLeave", function(self)
    -- Restore original variant when leaving hover
    if not self._isSelected then
      self:SetVariant(self._originalVariant)
    end
    
    GameTooltip:Hide()
    
    -- Call original ButtonLib OnLeave if it exists
    if originalOnLeave then
      originalOnLeave(self)
    end
  end)
  
  return btn
end

-- Enhanced button layout with better spacing
local function BuildModernButtons(sidebar, categories)
  local scroll = sidebar._scroll
  local child = sidebar._child
  local onSelectIndex = sidebar._onSelect
  
  -- Clean up old buttons
  local oldButtons = sidebar._buttons or {}
  for _, btn in ipairs(oldButtons) do
    if btn and btn.Hide then
      btn:Hide()
    end
  end
  if type(wipe) == "function" then wipe(oldButtons) else for i=#oldButtons,1,-1 do oldButtons[i]=nil end end
  
  local buttons = {}
  local currentY = BUTTON_CONFIG.gap -- Start with some top padding
  
  for i, category in ipairs(categories) do
    if category.type == "separator" then
      -- Create modern separator
      local separator = CreateModernSeparator(child)
      separator:SetPoint("TOPLEFT", BUTTON_CONFIG.paddingX, -currentY)
      separator:SetPoint("RIGHT", -BUTTON_CONFIG.paddingX, 0)
      
      currentY = currentY + BUTTON_CONFIG.separatorGap
    else
      -- Create modern button
      local buttonText = category._renderedLabel or category.label or category.key
      local btn = CreateModernCategoryButton(child, buttonText, category)
      
      -- Position the button
      btn:SetPoint("TOPLEFT", BUTTON_CONFIG.paddingX, -currentY)
      btn:SetPoint("RIGHT", -BUTTON_CONFIG.paddingX, 0)
      
      -- Store metadata
      btn.catKey = category.key
      btn.index = i
      btn._category = category
      
      -- Set up click handler with enhanced feedback
      btn:SetScript("OnClick", function(clickedBtn)
        -- Update all button states
        for _, otherBtn in ipairs(buttons) do
          if otherBtn.SetSelected then
            otherBtn:SetSelected(false)
          end
        end
        
        -- Select clicked button
        if clickedBtn.SetSelected then
          clickedBtn:SetSelected(true)
        end
        
        -- Call selection callback
        if type(onSelectIndex) == "function" then
          onSelectIndex(i, category)
        end
        
        -- Add subtle sound feedback (optional)
        if clickedBtn._isSelected and type(PlaySound)=="function" and type(SOUNDKIT)=="table" then
          PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
      end)
      
      buttons[#buttons + 1] = btn
      currentY = currentY + BUTTON_CONFIG.height + BUTTON_CONFIG.gap
    end
  end
  
  -- Add bottom padding
  currentY = currentY + BUTTON_CONFIG.gap
  
  -- Update container size
  child:SetHeight(math.max(currentY, 1))
  child:SetWidth(BUTTON_CONFIG.width + (BUTTON_CONFIG.paddingX * 2))
  
  -- Store buttons reference
  sidebar._buttons = buttons
  
  -- Update scrollbar visibility
  if sidebar.EvaluateScrollbar then
    C_Timer.After(0.1, sidebar.EvaluateScrollbar)
  end
end

function SidePanel:Create(parent, categories, onSelectIndex)
  -- Create main sidebar frame with compact sizing
  local sidebar = CreateFrame("Frame", nil, parent)
  sidebar:SetWidth(BUTTON_CONFIG.width + (BUTTON_CONFIG.paddingX * 2) + 12) -- Compact width
  sidebar:SetPoint("TOPLEFT", 6, -42)
  sidebar:SetPoint("BOTTOMLEFT", 6, 10)
  
  -- Enhanced background texture (more subtle)
  local backgroundTexture = sidebar:CreateTexture(nil, "BACKGROUND", nil, -3)
  backgroundTexture:SetAllPoints()
  backgroundTexture:SetTexture("Interface/AchievementFrame/UI-Achievement-Character-Stats")
  backgroundTexture:SetAlpha(0.12) -- Very subtle texture
  
  -- Add a subtle overlay for modern look
  local overlay = sidebar:CreateTexture(nil, "BACKGROUND", nil, -2)
  overlay:SetAllPoints()
  overlay:SetColorTexture(0.05, 0.05, 0.08, 0.7) -- Dark overlay matching other UI
  
  -- Create scroll frame with enhanced styling
  local scroll = CreateFrame("ScrollFrame", nil, sidebar)
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  
  -- Create scroll child
  local child = CreateFrame("Frame")
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  
  -- Store references
  sidebar._scroll = scroll
  sidebar._child = child
  sidebar._onSelect = onSelectIndex
  
  -- Build the modern button layout
  BuildModernButtons(sidebar, categories)
  
  -- Enhanced scrollbar management
  local function EvaluateScrollbar()
    local visibleHeight = scroll:GetHeight()
    if not visibleHeight or visibleHeight <= 0 then return end
    
    local contentHeight = child:GetHeight()
    local needsScrollbar = contentHeight > (visibleHeight + 2)
    
    if scroll.ScrollBar then
      if needsScrollbar then
        -- Show scrollbar and adjust layout
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -26, 4)
        scroll.ScrollBar:Show()
      else
        -- Hide scrollbar and expand content area
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", -4, 4)
        scroll.ScrollBar:Hide()
      end
    end
  end
  
  -- Defer scrollbar evaluation
  C_Timer.After(0.1, EvaluateScrollbar)
  sidebar:HookScript("OnSizeChanged", function() 
    C_Timer.After(0.1, EvaluateScrollbar) 
  end)
  scroll:HookScript("OnSizeChanged", function() 
    C_Timer.After(0.1, EvaluateScrollbar) 
  end)
  
  -- Store public method
  sidebar.EvaluateScrollbar = EvaluateScrollbar
  
  -- Enhanced public API
  function sidebar:Rebuild(newCategories)
    BuildModernButtons(sidebar, newCategories)
  end
  
  function sidebar:SetCategoryLabel(key, newLabel, count)
    for _, btn in ipairs(sidebar._buttons or {}) do
      if btn.catKey == key then
        if btn.UpdateCount then
          btn:UpdateCount(count)
        elseif btn._text then
          if count and count > 0 then
            btn._text:SetText(string.format("%s (%d)", newLabel, count))
          else
            btn._text:SetText(newLabel)
          end
        end
        return true
      end
    end
    return false
  end
  
  function sidebar:SelectIndex(index)
    for _, btn in ipairs(sidebar._buttons or {}) do
      if btn.index == index then
        local clickScript = btn:GetScript("OnClick")
        if clickScript then
          clickScript(btn)
        end
        return true
      end
    end
    return false
  end
  
  function sidebar:SelectCategory(categoryKey)
    for _, btn in ipairs(sidebar._buttons or {}) do
      if btn.catKey == categoryKey then
        local clickScript = btn:GetScript("OnClick")
        if clickScript then
          clickScript(btn)
        end
        return true
      end
    end
    return false
  end
  
  function sidebar:UpdateCategoryCounts(countMap)
    for _, btn in ipairs(sidebar._buttons or {}) do
      if btn.catKey and countMap[btn.catKey] and btn.UpdateCount then
        btn:UpdateCount(countMap[btn.catKey])
      end
    end
  end
  
  return sidebar, sidebar._buttons
end

-- Register with addon
Addon.UI = Addon.UI or {}
Addon.UI.SidePanel = SidePanel

if Addon.provide then 
  Addon.provide("UI.SidePanel", SidePanel) 
end

return SidePanel
