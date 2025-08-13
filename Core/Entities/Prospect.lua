---@class Prospect
---@field guid string
---@field name string
---@field realm string|nil
---@field faction string|nil
---@field classToken string|nil
---@field className string|nil
---@field level integer
---@field firstSeen integer
---@field lastSeen integer
---@field seenCount integer
---@field status string   # 'New'|'Invited'|'Blacklisted'|'Rejected'
---@field sources table<string,boolean>
-- Domain entity for a recruitable player prospect.
-- Pure data + minimal invariants (no WoW API calls here). Other layers adapt.
local Prospect = {}
Prospect.__index = Prospect

-- ctor(table fields) or Prospect.new(id, name,...)
---@param fields table
---@return Prospect
function Prospect.new(fields)
    if type(fields) ~= 'table' then
        error('Prospect.new expects table of fields')
    end
    local self = setmetatable({}, Prospect)
    self.guid = fields.guid
    self.name = fields.name
    self.realm = fields.realm
    self.faction = fields.faction
    self.classToken = fields.classToken
    self.className = fields.className
    self.level = fields.level or 0
    self.firstSeen = fields.firstSeen
    self.lastSeen = fields.lastSeen or fields.firstSeen
    self.seenCount = fields.seenCount or 1
    self.status = fields.status or 'New'
    self.sources = fields.sources or {}
    return self
end

---@param ts integer|nil
function Prospect:Touch(ts)
    ts = ts or 0 -- entity stays pure; caller supplies time
    self.lastSeen = ts
    self.seenCount = (self.seenCount or 0) + 1
end

return Prospect
