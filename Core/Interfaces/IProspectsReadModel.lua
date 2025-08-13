-- Core/Interfaces/IProspectsReadModel.lua
-- Interface: Read-only prospects query surface (implemented by ProspectsDataProvider)
local firstArg = select(1, ...)
local Addon = (type(firstArg)=='table' and firstArg) or select(2, ...) or _G.GuildRecruiter or {}
local Interface = (Addon and Addon.Interface) or function(name, methods) local m={} for _,v in ipairs(methods) do m[v]=true end return { __interface=true, __name=name, __methods=m } end
local IProspectsReadModel = Interface('IProspectsReadModel', {
  'GetAll',            -- -> table[] of prospect
  'GetFiltered',       -- (filters, sortColumn?, sortDescending?) -> table[]
  'GetPage',           -- (pageSize, cursor?, opts?) -> items[], nextCursor?
  'Query',             -- (opts { status?, search?, sort?, desc?, page?, pageSize? }) -> { items, total, page, pageSize }
  'GetByGuid',         -- (guid) -> prospect?
  'GetByName',         -- (name, realm?) -> table[] (may return multiple across realms)
  'GetAllGuids',       -- -> table[] of guid strings
  'Exists',            -- (guid) -> boolean
  'GetStats',          -- -> table (counts, etc.)
  'GetVersion'         -- -> number
})
if Addon.provide then Addon.provide('IProspectsReadModel', IProspectsReadModel) end
return IProspectsReadModel
