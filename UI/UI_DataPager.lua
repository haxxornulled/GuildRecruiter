-- This UI adapter has been moved to Infrastructure/Persistence/DataPager.lua.
-- Keep a tiny forwarder to avoid breaking any legacy require()s.
local __p = { ... }
local ADDON_NAME, Addon = __p[1], __p[2]
local function Register()
    local reg = Addon and Addon._RegisterDataPager
    if type(reg) == 'function' then return reg() end
    -- Ensure service exists; no-op if already provided
    local get = Addon and Addon.Get
    if get and get('DataPager') then return end
    -- If not available, attempt to require infrastructure file via TOC order
end
Register()
return Register
