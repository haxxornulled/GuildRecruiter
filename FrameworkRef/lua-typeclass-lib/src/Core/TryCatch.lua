local ADDON_NAME = "TaintedSin" -- Change this ONCE per project!
_G[ADDON_NAME] = _G[ADDON_NAME] or {}
local Addon = _G[ADDON_NAME]

Addon._modules = Addon._modules or {}

if not Addon.provide then
    function Addon.provide(name, mod)
        if not name or not mod then
            error("Usage: Addon.provide(name, mod)")
        end
        Addon._modules[name] = mod
    end
end

if not Addon.require then
    function Addon.require(name)
        local m = Addon._modules[name]
        if not m then
            error("Module '"..tostring(name).."' not found. " ..
                "Did you forget to load the file in your .toc, or forget Addon.provide?")
        end
        return m
    end
end

-- TryCatch.lua
-- try/catch/finally idiom for Lua 5.1+
local function try(blocks)
    assert(type(blocks) == "table", "try: blocks must be a table")
    local ok, result = xpcall(blocks[1], function(err)
        if blocks.catch then
            blocks.catch(err)
        else
            print("Unhandled error: " .. tostring(err))
        end
        return err
    end)
    if blocks.finally then blocks.finally() end
    return ok, result
end

Addon.provide("TryCatch", try)

return try
