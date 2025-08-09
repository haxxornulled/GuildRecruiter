-- Helpers/RoleHelper.lua — role inference utilities (no Core require)
local _, Addon = ...

local RoleHelper = {}
Addon.RoleHelper = RoleHelper
if Addon.provide then Addon.provide("RoleHelper", RoleHelper) end

-- Static class→role weights (Retail baseline; tweak to taste)
local classRoleWeights = {
  DRUID       = { TANK = 0.20, HEALER = 0.40, DPS = 0.40 },
  PALADIN     = { TANK = 0.30, HEALER = 0.40, DPS = 0.30 },
  MONK        = { TANK = 0.25, HEALER = 0.35, DPS = 0.40 },
  SHAMAN      = { HEALER = 0.50, DPS = 0.50 },
  PRIEST      = { HEALER = 0.60, DPS = 0.40 },
  DEMONHUNTER = { TANK = 0.30, DPS = 0.70 },
  WARRIOR     = { TANK = 0.40, DPS = 0.60 },
  HUNTER      = { DPS = 1.00 },
  ROGUE       = { DPS = 1.00 },
  WARLOCK     = { DPS = 1.00 },
  MAGE        = { DPS = 1.00 },
  EVOKER      = { HEALER = 0.50, DPS = 0.50 },
}

-- Returns "TANK" | "HEALER" | "DPS"
function RoleHelper:InferRole(classToken)
  local weights = classRoleWeights[tostring(classToken or ""):upper()]
  if not weights then return "DPS" end
  local roll, acc = math.random(), 0
  for role, w in pairs(weights) do
    acc = acc + (tonumber(w) or 0)
    if roll <= acc then return role end
  end
  return "DPS"
end

-- Use Blizzard’s assignment if we can see it, else fall back to probabilities.
-- unit: "player"/"target"/"nameplateX"/etc.; classToken: "WARRIOR"…
function RoleHelper:GetEffectiveRole(unit, classToken)
  if UnitGroupRolesAssigned and (IsInGroup() or IsInRaid()) and UnitExists(unit) then
    local r = UnitGroupRolesAssigned(unit)
    if r and r ~= "NONE" then
      return (r == "DAMAGER") and "DPS" or r
    end
  end
  return self:InferRole(classToken)
end

return RoleHelper
