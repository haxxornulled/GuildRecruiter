-- Infrastructure/UI/PanelFactory.lua
-- Default implementation of IPanelFactory with DI registration.
---@diagnostic disable: undefined-global
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local function printf(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME or "GR", tostring(msg))) end
end

local PanelFactory = {}
PanelFactory.__index = PanelFactory

-- Design notes:
-- - Registry-driven: panels register themselves with metadata (key, builder, singleton?)
-- - GetPanel returns an existing single-instance frame or builds via builder
-- - Supports late/lazy panel modules; builders may require() their module
-- - Extensible via RegisterPanel and RemovePanel

function PanelFactory.new()
  local self = setmetatable({}, PanelFactory)
  self._defs = {}         -- key -> { build = fn(opts)->frame, singleton = bool, title = string?, area=string? }
  self._instances = {}    -- key -> frame
  return self
end

-- Register a panel definition
-- def = { key=string, build=function(opts)->frame, singleton=true|false, title=string? }
function PanelFactory:RegisterPanel(def)
  if not def or type(def) ~= 'table' then error("RegisterPanel(def) requires table") end
  local key = def.key; if type(key) ~= 'string' or key == '' then error("Panel def requires key") end
  if type(def.build) ~= 'function' then error("Panel def requires build function") end
  if self._defs[key] then -- allow override in dev mode only
    local dev = false; pcall(function() local cfg = Addon.Get and Addon.Get('IConfiguration'); dev = cfg and cfg.Get and cfg:Get('devMode', false) or false end)
    if not dev then error("Panel key already registered: "..key) end
  end
  self._defs[key] = {
    build = def.build,
    singleton = (def.singleton ~= false),
    title = def.title,
    area = def.area,
  }
end

function PanelFactory:RemovePanel(key) self._defs[key] = nil; self._instances[key] = nil end

-- Get or build a panel by key
-- opts = { forceNew=false, params=table?, parent=Frame? }
function PanelFactory:GetPanel(key, opts)
  opts = opts or {}
  local def = self._defs[key]
  if not def then error("Unknown panel key: "..tostring(key)) end
  if def.singleton and not opts.forceNew then
    local existing = self._instances[key]
    if existing and existing.GetParent and (not opts.parent or existing:GetParent() == opts.parent) then
      return existing
    end
  end
  local ok, frame = pcall(def.build, opts)
  if not ok then error("Panel build failed for "..tostring(key)..": "..tostring(frame)) end
  if type(frame) ~= 'table' then error("Panel build did not return a frame for "..tostring(key)) end
  if def.singleton and not opts.forceNew then self._instances[key] = frame end
  return frame
end

-- Convenience helpers
function PanelFactory:List()
  local keys = {}; for k,_ in pairs(self._defs) do keys[#keys+1]=k end; table.sort(keys); return keys
end
function PanelFactory:TryGet(key)
  local ok, res = pcall(function() return self:GetPanel(key) end); if ok then return res end
end

-- DI registration
local function RegisterPanelFactory()
  if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('PanelFactory')) then
    Addon.safeProvide('PanelFactory', function() return PanelFactory.new() end, { lifetime = 'SingleInstance', meta = { layer = 'Infrastructure', area = 'ui/panel-factory' } })
  end
  if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('IPanelFactory')) then
    Addon.safeProvide('IPanelFactory', function(sc) return sc:Resolve('PanelFactory') end, { lifetime = 'SingleInstance', meta = { layer = 'Infrastructure', role = 'contract-alias' } })
  end
end

RegisterPanelFactory()
return PanelFactory
