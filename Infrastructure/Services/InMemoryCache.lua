-- Infrastructure/Services/InMemoryCache.lua — Injectable cache service backed by Core LRU
local __p = { ... }
local ADDON_NAME, Addon = __p[1], __p[2]

local function CreateInMemoryCacheService()
    local LRU
    do
        local ok, mod = pcall(function() return Addon.require and Addon.require('LRU') end)
        if ok and mod and (mod.New or mod.new) then LRU = mod end
    end

    local svc = {}
    function svc:New(capacity)
        capacity = tonumber(capacity) or 128
        if LRU and LRU.New then
            local lru = LRU.New(capacity)
            return {
                Get = function(_, k) return lru:Get(k) end,
                Set = function(_, k, v) return lru:Set(k, v) end,
                Has = function(_, k) return lru:Has(k) end,
                Size = function() return lru:Size() end,
                Capacity = function() return lru:Capacity() end,
                Clear = function() return lru:Clear() end,
            }
        else
            -- Fallback: tiny map-based cache (no eviction)
            local map, order = {}, {}
            return {
                Get = function(_, k) return map[k] end,
                Set = function(_, k, v)
                    if map[k] == nil then order[#order + 1] = k end
                    map[k] = v
                end,
                Has = function(_, k) return map[k] ~= nil end,
                Size = function() return #order end,
                Capacity = function() return capacity end,
                Clear = function()
                    map = {}; order = {}
                end,
            }
        end
    end

    return svc
end

local function Register()
    if Addon.provide and not (Addon.IsProvided and Addon.IsProvided('InMemoryCache')) then
        Addon.provide('InMemoryCache', function() return CreateInMemoryCacheService() end,
            { lifetime = 'SingleInstance' })
    end
end

Register()
return Register
