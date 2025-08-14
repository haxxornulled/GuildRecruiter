-- Core/ProspectStatus.lua
-- Canonical prospect status constants & helper predicates.
local __args = {...}
local ADDON_NAME, Addon = __args[1], (__args[2] or {})
Addon = Addon or _G[ADDON_NAME] or {}

local Status = {
  New = 'New',
  Invited = 'Invited',
  Blacklisted = 'Blacklisted',
  Rejected = 'Rejected',
}

Status._all = { 'New','Invited','Blacklisted','Rejected' }

function Status.IsActive(s)
  return s ~= Status.Blacklisted
end

function Status.IsNew(s)
  return s == Status.New
end

function Status.IsBlacklisted(s)
  return s == Status.Blacklisted
end

function Status.List()
  local copy = {}; for i,v in ipairs(Status._all) do copy[i]=v end; return copy
end

if Addon and Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('ProspectStatus')) then
  Addon.safeProvide('ProspectStatus', function() return Status end, { lifetime='SingleInstance', meta = { layer='Core', role='constants' } })
end

return Status
