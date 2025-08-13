-- UI/DataGrid.lua - Reusable high-performance virtualized data grid
-- Lightweight, no-lib implementation optimized for large datasets.
-- API:
--   local grid = DataGrid:Create(parent, columns, opts)
--   grid:SetData(arrayOfRecords)         -- full replace (records are tables)
--   grid:Refresh()                       -- re-render (after changing filters externally)
--   grid:SetFilter(fn(record)->bool)     -- optional filter predicate
--   grid:SetSort(key, descending)        -- apply sort programmatically
--   grid:GetSelection() -> set (guid->true)
-- Columns definition: { { key='name', label='Name', width=120, sortable=true, align='LEFT', renderer=function(cellFrame, value, record) end }, ... }
-- opts = { rowHeight=22, headerHeight=24, padding=4, onRowClick=function(record, button), multiSelect=true, onRenderRow=function(rowFrame, record) }
-- Added: opts.rowStyler(rowFrame, record, index) for external theming.

local ADDON_NAME, Addon = ...
local DataGrid = {}
DataGrid.__index = DataGrid

-- Utility localizations
local floor, max, min = math.floor, math.max, math.min

local function defaultRenderer(cell, value)
  if cell.text then cell.text:SetText(value == nil and '' or tostring(value)) end
end

function DataGrid:Create(parent, columns, opts)
  opts = opts or {}
  local o = setmetatable({}, self)
  o.parent = parent
  o.columns = columns or {}
  o.opts = opts
  o.rowHeight = opts.rowHeight or 22
  o.headerHeight = opts.headerHeight or 24
  o.padding = opts.padding or 4
  o.multiSelect = opts.multiSelect ~= false -- default true
  o._known = {}
  o._newKeys = {}
  o._lastNavIndex = 1
  o.onRowClick = opts.onRowClick
  o.onRenderRow = opts.onRenderRow
  o.rowStyler = opts.rowStyler
  o.resizable = opts.resizable and true or false
  o.data = {}
  o.filtered = {}
  o.filterFn = nil
  o.sortKey = nil
  o.sortDesc = false
  o.scrollOffset = 0
  o.visibleRows = 0
  o.selection = {}
  o.rowPool = {}
  o.inUse = {}

  local frame = CreateFrame('Frame', nil, parent)
  frame:SetAllPoints()
  o.frame = frame

  -- Header
  local header = CreateFrame('Frame', nil, frame)
  header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
  header:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -16, 0) -- leave room for scrollbar
  header:SetHeight(o.headerHeight)
  o.header = header
  local hbg = header:CreateTexture(nil, 'BACKGROUND')
  hbg:SetAllPoints(); hbg:SetColorTexture(0.15,0.15,0.15,0.9)

  header._colButtons = {}
  local x = o.padding
  for idx, col in ipairs(o.columns) do
    local btn = CreateFrame('Button', nil, header)
    btn:SetPoint('LEFT', header, 'LEFT', x, 0)
    btn:SetSize(col.width, o.headerHeight)
    local fs = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    fs:SetPoint('LEFT', btn, 'LEFT', 4, 0)
    fs:SetJustifyH(col.align or 'LEFT')
    btn.labelFS = fs
    btn.colDef = col

    function btn:update()
      local text = col.label or col.key
      if col.sortable and o.sortKey == col.key then
        text = text .. (o.sortDesc and ' ▼' or ' ▲')
      end
      fs:SetText(text)
    end
    btn:update()

    if col.sortable then
      btn:SetScript('OnClick', function()
        if o.sortKey == col.key then
          o.sortDesc = not o.sortDesc
        else
          o.sortKey = col.key; o.sortDesc = false
        end
        -- Persist sort state
        pcall(function()
          local sv = Addon.Get and Addon.Get('SavedVarsService') or (Addon.require and Addon.require('SavedVarsService'))
          if sv and sv.Set then sv:Set('ui', 'prospectsSort', { key=o.sortKey, desc=o.sortDesc }) end
        end)
        o:applyTransform()
        o:render()
      end)
      btn:SetScript('OnEnter', function() btn:SetAlpha(0.85) end)
      btn:SetScript('OnLeave', function() btn:SetAlpha(1.0) end)
    end

    header._colButtons[#header._colButtons+1] = btn

    -- Column resize grabber
    if o.resizable and idx < #o.columns then
      local grab = CreateFrame('Frame', nil, btn)
      grab:SetPoint('TOPRIGHT', btn, 'TOPRIGHT', 0, 0)
      grab:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 0, 0)
      grab:SetWidth(6)
      grab:EnableMouse(true)
      grab:SetScript('OnEnter', function(g) if not o._resizing then g:SetAlpha(0.35) end end)
      grab:SetScript('OnLeave', function(g) if not o._resizing then g:SetAlpha(1) end end)
      local tex = grab:CreateTexture(nil,'OVERLAY')
      tex:SetAllPoints(); tex:SetColorTexture(0.9,0.8,0.5,0.15)
      grab.tex = tex
      grab:SetScript('OnMouseDown', function(g)
        local scale = g:GetEffectiveScale()
        local cx = GetCursorPosition() / scale
        o._resizing = { index = idx, startX = cx, startW = col.width }
        g.tex:SetColorTexture(1,0.95,0.6,0.4)
        o:StartResizing()
      end)
      grab:SetScript('OnMouseUp', function(g)
  if o._resizing then o:StopResizing(); if o.opts and o.opts.onColumnsChanged then pcall(o.opts.onColumnsChanged, o, o.columns) end end
      end)
    end
    x = x + col.width
  end

  -- Scroll area
  local scrollArea = CreateFrame('Frame', nil, frame)
  scrollArea:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, -2)
  -- (stray patch line removed)
  o.scrollArea = scrollArea

  -- Empty state overlay
  local empty = scrollArea:CreateFontString(nil,'OVERLAY','GameFontDisableLarge')
  empty:SetPoint('CENTER')
  empty:SetText('')
  empty:Hide()
  o._emptyFS = empty

  -- Scrollbar
  local scrollbar = CreateFrame('Slider', nil, frame, 'UIPanelScrollBarTemplate')
  scrollbar:SetPoint('TOPLEFT', scrollArea, 'TOPRIGHT', 0, -16)
  scrollbar:SetPoint('BOTTOMLEFT', scrollArea, 'BOTTOMRIGHT', 0, 16)
  scrollbar:SetMinMaxValues(0, 0)
  scrollbar:SetValueStep(1)
  scrollbar:SetObeyStepOnDrag(true)
  o.scrollbar = scrollbar
  scrollbar:SetScript('OnValueChanged', function(_, value)
    value = floor(value + 0.5)
    if value ~= o.scrollOffset then
      o.scrollOffset = value
      o:render()
    end
  end)

  scrollArea:EnableMouseWheel(true)
  scrollArea:SetScript('OnMouseWheel', function(_, delta)
    local step = (delta > 0) and -3 or 3
    local newVal = min(max(0, o.scrollOffset + step), o:getMaxOffset())
    scrollbar:SetValue(newVal)
  end)

  scrollArea:SetScript('OnSizeChanged', function()
    o:render()
  end)

  return o
end

-- Begin live resize handling
function DataGrid:StartResizing()
  if self._resizeFrame then return end
  local f = self.frame
  f:SetScript('OnUpdate', function()
    local r = self._resizing; if not r then return end
    local col = self.columns[r.index]; if not col then return end
    local scale = self.header:GetEffectiveScale() or 1
    local cx = GetCursorPosition() / scale
    local delta = cx - r.startX
    local newW = math.max(24, math.floor(r.startW + delta))
    if newW ~= col.width then
      col.width = newW
      self:updateLayout()
    end
  end)
  self._resizeFrame = true
end

function DataGrid:StopResizing()
  self._resizing = nil
  if self.frame and self.frame:GetScript('OnUpdate') then
    self.frame:SetScript('OnUpdate', nil)
  end
  self._resizeFrame = nil
end

function DataGrid:updateLayout()
  if not self.header then return end
  local x = self.padding
  for i, btn in ipairs(self.header._colButtons or {}) do
    local col = self.columns[i]
    btn:ClearAllPoints()
    btn:SetPoint('LEFT', self.header, 'LEFT', x, 0)
    btn:SetSize(col.width, self.headerHeight)
    x = x + col.width
  end
  -- Adjust rows
  for _, row in ipairs(self.inUse) do
    local rx = 0
    for _, col in ipairs(self.columns) do
      local cell = row.cols[col.key]
      if cell then
        cell:ClearAllPoints()
        cell:SetPoint('TOPLEFT', row, 'TOPLEFT', rx, 0)
        cell:SetSize(col.width, self.rowHeight)
        rx = rx + col.width
      end
    end
  end
  self:render()
  -- Persist column widths after layout update
  pcall(function()
    local sv = Addon.Get and Addon.Get('SavedVarsService') or (Addon.require and Addon.require('SavedVarsService'))
    if sv and sv.Set then
      local widths = {}
      for i,c in ipairs(self.columns) do widths[c.key or i] = c.width end
      sv:Set('ui', 'prospectsColumns', widths)
    end
  end)
end

-- Public API
function DataGrid:SetData(data)
  self.data = data or {}
    -- Track new records for flash effect
    local now = GetTime and GetTime() or time()
    local newKeys = {}
    for i=1,#self.data do
      local r = self.data[i]
      local key = r.guid or r.id or r.key or tostring(r)
      if not self._known[key] then
        self._known[key] = true
        self._newKeys[key] = now
        newKeys[#newKeys+1] = key
      end
    end
  self:applyTransform()
  self:render()
end

function DataGrid:SetFilter(fn)
  self.filterFn = fn
  self:applyTransform(); self:render()
end

function DataGrid:SetSort(key, desc)
  self.sortKey = key; self.sortDesc = desc and true or false
  self:applyTransform(); self:render()
end

function DataGrid:GetSelection() return self.selection end
function DataGrid:ClearSelection() for k in pairs(self.selection) do self.selection[k]=nil end; self:render() end

function DataGrid:SetRowHeight(h)
  self.rowHeight = h or self.rowHeight
  self:render()
end

-- Internal transform (filter+sort)
function DataGrid:applyTransform()
  local filtered = {}
  local fn = self.filterFn
  if fn then
    for i=1,#self.data do local r=self.data[i]; if fn(r) then filtered[#filtered+1]=r end end
  else
    for i=1,#self.data do filtered[i]=self.data[i] end
  end
  if self.sortKey then
    table.sort(filtered, function(a,b)
      local va, vb = a[self.sortKey], b[self.sortKey]
      if va == vb then return false end
      if self.sortDesc then return (va or 0) > (vb or 0) else return (va or 0) < (vb or 0) end
    end)
  end
  self.filtered = filtered
  -- Adjust scrollbar bounds
  local maxOff = self:getMaxOffset()
  self.scrollOffset = min(self.scrollOffset, maxOff)
  self.scrollbar:SetMinMaxValues(0, maxOff)
  self.scrollbar:SetValue(self.scrollOffset)
  -- Update header sort glyphs
  if self.header and self.header._colButtons then for _,b in ipairs(self.header._colButtons) do if b.update then b:update() end end end
end

function DataGrid:getMaxOffset()
  if not self.scrollArea then return 0 end
  local h = self.scrollArea:GetHeight() or 0
  local visible = floor(h / self.rowHeight)
  if visible < 1 then visible = 1 end
  self.visibleRows = visible
  local extra = #self.filtered - visible
  return extra > 0 and extra or 0
end

-- Row pooling
local function acquireRow(self)
  local row = table.remove(self.rowPool)
  if not row then
  row = CreateFrame('Button', nil, self.scrollArea)
    row:SetHeight(self.rowHeight)
    row.cols = {}
    local x = 0
    for _, col in ipairs(self.columns) do
      local cell = CreateFrame('Frame', nil, row)
      cell:SetPoint('TOPLEFT', row, 'TOPLEFT', x, 0)
      cell:SetSize(col.width, self.rowHeight)
      if col.key ~= 'actions' then
        local fs = cell:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        fs:SetPoint('LEFT', cell, 'LEFT', 4, 0)
        fs:SetPoint('RIGHT', cell, 'RIGHT', -4, 0)
        fs:SetJustifyH(col.align or 'LEFT')
        cell.text = fs
      end
      row.cols[col.key] = cell
      x = x + col.width
    end
    local bg = row:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints(); bg:SetColorTexture(0.1,0.1,0.1,0.1)
    row._bg = bg
  local hl = row:CreateTexture(nil, 'ARTWORK')
  hl:SetAllPoints(); hl:SetColorTexture(0.6,0.6,0.8,0.18); hl:Hide(); row._hl = hl
    row:SetScript('OnClick', function(btn)
      local rec = btn._record; if not rec then return end
      local key = rec.guid or rec.id or rec.key or tostring(rec)
      if self.multiSelect then
        if IsShiftKeyDown() and self._lastNavIndex then
          -- Range select from last nav index to current row index
          local start = math.min(self._lastNavIndex, btn._recordIndex or self._lastNavIndex)
          local finish = math.max(self._lastNavIndex, btn._recordIndex or self._lastNavIndex)
          if not IsControlKeyDown() then self.selection = {} end
          for i=start,finish do
            local r = self.filtered[i]
            if r then
              local k2 = r.guid or r.id or r.key or tostring(r)
              self.selection[k2] = true
            end
          end
        else
          if IsControlKeyDown() then
            if self.selection[key] then self.selection[key]=nil else self.selection[key]=true end
          else
            self.selection = {}; self.selection[key] = true
          end
        end
      else
        self.selection = {}; self.selection[key] = true
      end
      if self.onRowClick then pcall(self.onRowClick, rec) end
      self:render() -- refresh selection visuals
    end)
  row:SetScript('OnEnter', function(r) if r._hl and not r._selected then r._hl:Show() end end)
  row:SetScript('OnLeave', function(r) if r._hl and not r._selected then r._hl:Hide() end end)
  end
  row:Show()
  self.inUse[#self.inUse+1] = row
  return row
end

local function releaseAll(self)
  for i=#self.inUse,1,-1 do local r=self.inUse[i]; r:Hide(); r._record=nil; self.rowPool[#self.rowPool+1]=r; self.inUse[i]=nil end
end

function DataGrid:render()
  if not self.scrollArea then return end
  releaseAll(self)
  local h = self.scrollArea:GetHeight() or 0
  local visible = floor(h / self.rowHeight)
  if visible < 1 then visible = 1 end
  self.visibleRows = visible
  local startIndex = self.scrollOffset + 1
  local stopIndex = min(#self.filtered, startIndex + visible - 1)
  local y = 0
  for i=startIndex, stopIndex do
    local rec = self.filtered[i]
    local row = acquireRow(self)
  row._recordIndex = i
    row._record = rec
    row:SetPoint('TOPLEFT', self.scrollArea, 'TOPLEFT', 0, -y)
    row:SetPoint('TOPRIGHT', self.scrollArea, 'TOPRIGHT', -16, -y)
    local key = rec.guid or rec.id or rec.key or tostring(rec)
    local selected = self.selection[key]
    row._selected = selected and true or false
    if selected then
      row._bg:SetColorTexture(0.2,0.45,0.85,0.45)
      if row._hl then row._hl:Hide() end
    else
      if (i % 2)==0 then row._bg:SetColorTexture(0.12,0.12,0.14,0.22) else row._bg:SetColorTexture(0.10,0.10,0.12,0.18) end
    end
    for _, col in ipairs(self.columns) do
      local cell = row.cols[col.key]
      if cell then
        if col.key == 'actions' then
          if self.onRenderRow then pcall(self.onRenderRow, row, rec, cell) end
        else
          local val = rec[col.key]
          local renderer = col.renderer or defaultRenderer
          renderer(cell, val)
        end
      end
    end
    if self.onRenderRow then pcall(self.onRenderRow, row, rec) end
    if self.rowStyler then pcall(self.rowStyler, row, rec, i) end
    y = y + self.rowHeight
  end
  -- Empty state messaging
  if (#self.filtered)==0 then
    if (#self.data)==0 then
      if self._emptyFS then self._emptyFS:SetText('No data'); self._emptyFS:Show() end
    else
      if self._emptyFS then self._emptyFS:SetText('No rows match filters'); self._emptyFS:Show() end
    end
  else
    if self._emptyFS then self._emptyFS:Hide() end
  end
  local maxOff = self:getMaxOffset()
  self.scrollbar:SetMinMaxValues(0, maxOff)
  self.scrollbar:SetValue(self.scrollOffset)
end

  -- Keyboard navigation (Up/Down/Enter) - call EnableKeyboard externally then set frame:SetPropagateKeyboardInput(true/false) as needed
  function DataGrid:HandleKeyDown(key)
    if key == "UP" then
      self._lastNavIndex = math.max(1, self._lastNavIndex - 1)
    elseif key == "DOWN" then
      self._lastNavIndex = math.min(#self.filtered, self._lastNavIndex + 1)
    elseif key == "HOME" then
      self._lastNavIndex = 1
    elseif key == "END" then
      self._lastNavIndex = #self.filtered
    elseif key == "ENTER" then
      local rec = self.filtered[self._lastNavIndex]
      if rec then
        local keyVal = rec.guid or rec.id or rec.key or tostring(rec)
        self.selection = { [keyVal] = true }
        if self.onRowClick then pcall(self.onRowClick, rec) end
      end
    else
      return -- unhandled
    end
    -- Adjust scroll if needed
    if self.scrollArea then
      local visible = self.visibleRows or 1
      local top = self.scrollOffset + 1
      local bottom = top + visible - 1
      if self._lastNavIndex < top then
        self.scrollOffset = self._lastNavIndex - 1
      elseif self._lastNavIndex > bottom then
        self.scrollOffset = self._lastNavIndex - visible
      end
    end
    self:render()
  end

-- Export & registration
if Addon.provide then Addon.provide('UI.DataGrid', DataGrid) end
Addon.UI = Addon.UI or {}
Addon.UI.DataGrid = DataGrid

return DataGrid
