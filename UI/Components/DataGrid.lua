---@diagnostic disable: undefined-global, assign-type-mismatch, param-type-mismatch, need-check-nil
-- Public API (unchanged):
--   local grid = DataGrid:Create(parent, columns, opts)
--   grid:SetData(arrayOfRecords)
--   grid:SetFilter(fn)
--   grid:SetSort(key, desc)
--   grid:GetSelection()
--   grid:ClearSelection()
--   grid:SetRowHeight(h)
-- Behavior:
-- - Uses WowScrollBoxList + WowTrimScrollBar + CreateDataProvider
-- - Virtualized rows with element initializer; row has subcells for each column
-- - Column header with sort toggles and optional resize grabbers
-- - Row selection (multi with Ctrl/Shift), onRowClick callback
-- - Optional rowStyler and onRenderRow hooks

local ADDON_NAME, Addon = ...
local DataGrid = {}
DataGrid.__index = DataGrid

-- Utility localizations
local floor, max, min = math.floor, math.max, math.min

local function defaultRenderer(cell, value, _)
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
  o.selection = {}

  -- Outer frame and header
  local frame = CreateFrame('Frame', nil, parent)
  frame:SetAllPoints()
  o.frame = frame

  local header = CreateFrame('Frame', nil, frame)
  header:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
  header:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -16, 0) -- leave room for scrollbar
  header:SetHeight(o.headerHeight)
  o.header = header
  local hbg = header:CreateTexture(nil, 'BACKGROUND'); hbg:SetAllPoints(); hbg:SetColorTexture(0.15,0.15,0.15,0.9)
  header._colButtons = {}

  local function buildHeader()
    local x = o.padding
    for i=#header._colButtons,1,-1 do local b=header._colButtons[i]; b:Hide(); header._colButtons[i]=nil end
    for idx, col in ipairs(o.columns) do
      local btn = CreateFrame('Button', nil, header)
      btn:SetPoint('LEFT', header, 'LEFT', x, 0)
      btn:SetSize(col.width, o.headerHeight)
      local fs = btn:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
      fs:SetPoint('LEFT', btn, 'LEFT', 4, 0)
      fs:SetJustifyH(col.align or 'LEFT')
      btn.labelFS = fs; btn.colDef = col
      function btn:update()
        local text = col.label or col.key
        if col.sortable and o.sortKey == col.key then text = text .. (o.sortDesc and ' ▼' or ' ▲') end
        fs:SetText(text)
      end
      btn:update()
      if col.sortable then
        btn:SetScript('OnClick', function()
          if o.sortKey == col.key then o.sortDesc = not o.sortDesc else o.sortKey = col.key; o.sortDesc = false end
          pcall(function()
            local sv = Addon.Get and Addon.Get('SavedVarsService') or (Addon.require and Addon.require('SavedVarsService'))
            if sv and sv.Set then sv:Set('ui', 'prospectsSort', { key=o.sortKey, desc=o.sortDesc }) end
          end)
          o:applyTransform(); o:render()
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
        grab:SetWidth(6); grab:EnableMouse(true)
        grab:SetScript('OnEnter', function(g) if not o._resizing then g:SetAlpha(0.35) end end)
        grab:SetScript('OnLeave', function(g) if not o._resizing then g:SetAlpha(1) end end)
        local tex = grab:CreateTexture(nil,'OVERLAY'); tex:SetAllPoints(); tex:SetColorTexture(0.9,0.8,0.5,0.15); grab.tex = tex
        grab:SetScript('OnMouseDown', function(g)
          local scale = g:GetEffectiveScale() or 1
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
  end
  buildHeader()

  -- ScrollBox + TrimScrollBar
  local scrollBox = CreateFrame('Frame', nil, frame, 'WowScrollBoxList')
  scrollBox:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, -2)
  scrollBox:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -16, 0)
  o.scrollBox = scrollBox
  local scrollBar = CreateFrame('EventFrame', nil, frame, 'WowTrimScrollBar')
  scrollBar:SetPoint('TOPLEFT', header, 'TOPRIGHT', 0, -16)
  scrollBar:SetPoint('BOTTOMLEFT', frame, 'BOTTOMRIGHT', 0, 16)
  o.scrollBar = scrollBar

  -- Empty overlay
  local empty = frame:CreateFontString(nil,'OVERLAY','GameFontDisableLarge')
  empty:SetPoint('CENTER'); empty:SetText(''); empty:Hide(); o._emptyFS = empty

  -- View + initializer
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer('Button', function(row, elementData)
    row:SetHeight(o.rowHeight)
    if not row._gridInit then
      row.cols = {}
      local x = 0
      for _, col in ipairs(o.columns) do
        local cell = CreateFrame('Frame', nil, row)
        cell:SetPoint('TOPLEFT', row, 'TOPLEFT', x, 0)
        cell:SetSize(col.width, o.rowHeight)
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
      local bg = row:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0.1,0.1,0.1,0.1); row._bg = bg
      local hl = row:CreateTexture(nil, 'ARTWORK'); hl:SetAllPoints(); hl:SetColorTexture(0.6,0.6,0.8,0.18); hl:Hide(); row._hl = hl
      row:SetScript('OnEnter', function(r) if r._hl and not r._selected then r._hl:Show() end end)
      row:SetScript('OnLeave', function(r) if r._hl and not r._selected then r._hl:Hide() end end)
      row:SetScript('OnClick', function(btn)
        local rec = btn._record; if not rec then return end
        local key = rec.guid or rec.id or rec.key or tostring(rec)
        if o.multiSelect then
          if IsShiftKeyDown() and o._lastNavIndex then
            local start = math.min(o._lastNavIndex, btn._recordIndex or o._lastNavIndex)
            local finish = math.max(o._lastNavIndex, btn._recordIndex or o._lastNavIndex)
            if not IsControlKeyDown() then o.selection = {} end
            for i=start,finish do local r = o.filtered[i]; if r then local k2 = r.guid or r.id or r.key or tostring(r); o.selection[k2] = true end end
          else
            if IsControlKeyDown() then if o.selection[key] then o.selection[key]=nil else o.selection[key]=true end else o.selection = {}; o.selection[key]=true end
          end
        else
          o.selection = {}; o.selection[key] = true
        end
        if o.onRowClick then pcall(o.onRowClick, rec) end
        if o.scrollBox and o.dataProvider then o.dataProvider:NotifyDataChanged() end
      end)
      row._gridInit = true
    end
    -- Bind record and render
    local rec = elementData
    row._record = rec; row._recordIndex = elementData._index or 1
    local key = rec and (rec.guid or rec.id or rec.key or tostring(rec))
    row._selected = key and o.selection[key] and true or false
    if row._selected then row._bg:SetColorTexture(0.2,0.45,0.85,0.45); if row._hl then row._hl:Hide() end else
      if (row._recordIndex % 2)==0 then row._bg:SetColorTexture(0.12,0.12,0.14,0.22) else row._bg:SetColorTexture(0.10,0.10,0.12,0.18) end
    end
    for _, col in ipairs(o.columns) do
      local cell = row.cols[col.key]
      if cell then
        if col.key == 'actions' then
          if o.onRenderRow then pcall(o.onRenderRow, row, rec, cell) end
        else
          local val = rec[col.key]
          local renderer = col.renderer or defaultRenderer
          renderer(cell, val, rec)
        end
      end
    end
    if o.onRenderRow then pcall(o.onRenderRow, row, rec) end
    if o.rowStyler then pcall(o.rowStyler, row, rec, row._recordIndex) end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  -- Data provider
  o.dataProvider = CreateDataProvider()
  scrollBox:SetDataProvider(o.dataProvider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)

  -- Public helpers on object
  function o:updateLayout()
    local x = self.padding
    for i, btn in ipairs(self.header._colButtons or {}) do
      local col = self.columns[i]
      btn:ClearAllPoints(); btn:SetPoint('LEFT', self.header, 'LEFT', x, 0)
      btn:SetSize(col.width, self.headerHeight)
      x = x + col.width
    end
    if self.scrollBox and self.scrollBox.ForEachFrame then
      self.scrollBox:ForEachFrame(function(row)
        local rx = 0
        for _, col in ipairs(self.columns) do
          local cell = row.cols and row.cols[col.key]
          if cell then cell:ClearAllPoints(); cell:SetPoint('TOPLEFT', row, 'TOPLEFT', rx, 0); cell:SetSize(col.width, self.rowHeight) end
          rx = rx + col.width
        end
        row:SetHeight(self.rowHeight)
      end)
    end
    -- Persist column widths
    pcall(function()
      local sv = Addon.Get and Addon.Get('SavedVarsService') or (Addon.require and Addon.require('SavedVarsService'))
      if sv and sv.Set then local widths = {}; for i,c in ipairs(self.columns) do widths[c.key or i] = c.width end; sv:Set('ui', 'prospectsColumns', widths) end
    end)
  end

  o.updateHeader = function()
    for _, b in ipairs(header._colButtons) do if b.update then b:update() end end
  end

  -- Expose resize helpers
  function o:StartResizing()
    if self._resizeFrame then return end
    self.frame:SetScript('OnUpdate', function()
      local r = self._resizing; if not r then return end
      local col = self.columns[r.index]; if not col then return end
      local scale = self.header:GetEffectiveScale() or 1
      local cx = GetCursorPosition() / scale
      local delta = cx - r.startX
      local newW = math.max(24, math.floor(r.startW + delta))
      if newW ~= col.width then col.width = newW; self:updateLayout() end
    end)
    self._resizeFrame = true
  end
  function o:StopResizing()
    self._resizing = nil
    if self.frame and self.frame:GetScript('OnUpdate') then
      ---@diagnostic disable-next-line: param-type-mismatch
      self.frame:SetScript('OnUpdate', nil)
    end
    self._resizeFrame = nil
  end

  -- Rebuild header once in case caller changed columns before Create returned
  buildHeader()
  return o
end

-- Public API
function DataGrid:SetData(data)
  self.data = data or {}
  -- Track new entries
  local now = GetTime and GetTime() or time()
  for i=1,#self.data do local r=self.data[i]; local key=r.guid or r.id or r.key or tostring(r); if not self._known[key] then self._known[key]=true; self._newKeys[key]=now end end
  self:applyTransform(); self:render()
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
  -- Update data provider
  if self.dataProvider then
    self.dataProvider:Flush()
    -- tag index for alt-row striping and selection math
    for i, rec in ipairs(filtered) do rec._index = i; self.dataProvider:Insert(rec) end
    self.dataProvider:NotifyDataChanged()
  end
  -- Update header glyphs
  if self.header and self.header._colButtons then for _,b in ipairs(self.header._colButtons) do if b.update then b:update() end end end
end

function DataGrid:render()
  if not self.scrollBox or not self.dataProvider then return end
  -- Empty messaging
  if (#self.filtered)==0 then
    if (#self.data)==0 then if self._emptyFS then self._emptyFS:SetText('No data'); self._emptyFS:Show() end
    else if self._emptyFS then self._emptyFS:SetText('No rows match filters'); self._emptyFS:Show() end end
  else if self._emptyFS then self._emptyFS:Hide() end end
end

-- Optional: keyboard nav placeholder (retain API)
function DataGrid:HandleKeyDown(key)
  if key == 'HOME' then self._lastNavIndex = 1 elseif key == 'END' then self._lastNavIndex = #self.filtered end
  if self.dataProvider then self.dataProvider:NotifyDataChanged() end
end

-- Export & registration
if Addon.provide then Addon.provide('UI.DataGrid', DataGrid) end
Addon.UI = Addon.UI or {}
Addon.UI.DataGrid = DataGrid

return DataGrid
