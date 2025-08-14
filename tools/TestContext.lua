-- tools/TestContext.lua
-- Centralized test isolation utilities. Loaded only in development (TOC before test specs).
local ADDON_NAME, Addon = ...
Addon = Addon or _G[ADDON_NAME] or {}

local M = {}

function M.BeforeEach()
  _G.GR_TEST_MODE = true
  -- Reset persisted data
  local sv = (Addon.Get and Addon.Get('SavedVarsService')) or (Addon.Peek and Addon.Peek('SavedVarsService'))
  if sv and sv.GetNamespace then
    local root = sv:GetNamespace('', { prospects = {}, queue = {}, blacklist = {} })
    -- wipe tables in-place so existing references stay valid
    if root.prospects then for k in pairs(root.prospects) do root.prospects[k]=nil end end
    if root.blacklist then for k in pairs(root.blacklist) do root.blacklist[k]=nil end end
    root.queue = {}
  end
  -- Reset services that maintain internal ephemeral state
  local q = Addon.Get and Addon.Get('QueueService'); if q and q.ResetState then pcall(function() q:ResetState() end) end
  local inv = Addon.Get and Addon.Get('InviteService'); if inv and inv.ResetState then pcall(function() inv:ResetState() end) end
  local b = Addon.Get and (Addon.Get('IBroadcastService') or Addon.Get('BroadcastService')); if b and b.ResetState then pcall(function() b:ResetState() end) end
end

function M.AfterEach()
  -- Placeholder for future cleanup
end

Addon.TestContext = M
return M
