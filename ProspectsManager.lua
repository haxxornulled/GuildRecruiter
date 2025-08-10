local ADDON_NAME, Addon = ...

-- Factory so DI container injects Recruiter once; avoids repeated Addon.Get lookups.
local function CreateProspectsManager(scope)
    local recruiter = scope:Resolve("Recruiter") -- hard fail early if missing
    local logger = scope:Resolve("Logger"):ForContext("ProspectsAdapter")
    local bus = scope:Resolve("EventBus")

    local Adapter = { _recruiter = recruiter, _bus = bus, _log = logger }

    local function publish(ev, ...)
        local ok, err = pcall(bus.Publish, bus, ev, ...)
        if not ok then logger:Error("Bus publish failed {Err}", { Err = err }) end
    end

    local function warnOnce()
        if Adapter._warned then return end
        Adapter._warned = true
        logger:Warn("ProspectsManager adapter used (deprecated). Use Recruiter API.")
        publish("ProspectsAdapter.DeprecatedUsed")
    end

    function Adapter:GetList()
        warnOnce()
        local r = self._recruiter
        local guids = r.GetAllGuids and r:GetAllGuids() or {}
        local out = {}
        for _,g in ipairs(guids) do
            local p = r:GetProspect(g)
            if p then
                out[#out+1] = {
                    name = (p.name or "") .. ((p.realm and p.realm ~= "") and ("-"..p.realm) or ""),
                    level = p.level or 0,
                    class = p.classToken or p.className or "",
                    classLocal = p.className or p.classToken or "",
                    zone = "",
                    guid = p.guid,
                    online = true,
                    source = "adapter",
                    seenAt = p.lastSeen or p.firstSeen,
                }
            end
        end
        table.sort(out, function(a,b) return (a.seenAt or 0) > (b.seenAt or 0) end)
        publish("ProspectsAdapter.GetList", #out)
        -- Use Debug to avoid log spam
        logger:Debug("GetList returned {Count} entries", { Count = #out })
        return out
    end

    function Adapter:GetBlacklist()
        warnOnce()
        local bl = self._recruiter.GetBlacklist and self._recruiter:GetBlacklist() or {}
        publish("ProspectsAdapter.GetBlacklist", bl and (bl.count or 0))
        logger:Debug("GetBlacklist invoked")
        return bl
    end

    function Adapter:IsBlacklisted(name)
        warnOnce()
        local r = self._recruiter
        local guid
        for _,g in ipairs(r:GetAllGuids() or {}) do
            local p = r:GetProspect(g); if p and p.name == name then guid = g break end
        end
        local result = guid and r:IsBlacklisted(guid) or false
        publish("ProspectsAdapter.IsBlacklisted", name, result)
        logger:Trace("IsBlacklisted {Name} -> {Result}", { Name = name, Result = tostring(result) })
        return result
    end

    function Adapter:Clear()
        warnOnce(); local r = self._recruiter
        local count = 0
        for _,g in ipairs(r:GetAllGuids() or {}) do r:RemoveProspect(g); count = count + 1 end
        publish("ProspectsAdapter.Clear", count)
        logger:Info("Clear removed {Count} prospects", { Count = count })
    end

    function Adapter:Remove(name)
        warnOnce(); local r = self._recruiter
        local removed = false
        for _,g in ipairs(r:GetAllGuids() or {}) do
            local p = r:GetProspect(g)
            if p and p.name == name then r:RemoveProspect(g); removed = true; break end
        end
        publish("ProspectsAdapter.Remove", name, removed)
        logger:Info("Remove {Name} -> {Removed}", { Name = name, Removed = tostring(removed) })
    end

    function Adapter:AddToBlacklist(name, reason)
        warnOnce(); local r = self._recruiter
        local added = false
        for _,g in ipairs(r:GetAllGuids() or {}) do
            local p = r:GetProspect(g)
            if p and p.name == name then r:Blacklist(g, reason or "manual"); added = true; break end
        end
        publish("ProspectsAdapter.AddToBlacklist", name, added, reason)
        logger:Info("AddToBlacklist {Name} ({Reason}) -> {Added}", { Name = name, Reason = reason or "manual", Added = tostring(added) })
    end

    function Adapter:RemoveFromBlacklist(name)
        warnOnce(); local r = self._recruiter
        local removed = false
        for _,g in ipairs(r:GetAllGuids() or {}) do
            local p = r:GetProspect(g)
            if p and p.name == name then r:Unblacklist(g); removed = true; break end
        end
        publish("ProspectsAdapter.RemoveFromBlacklist", name, removed)
        logger:Info("RemoveFromBlacklist {Name} -> {Removed}", { Name = name, Removed = tostring(removed) })
    end

    function Adapter:TryAddUnit()
        warnOnce(); publish("ProspectsAdapter.TryAddUnit")
        logger:Warn("TryAddUnit called on deprecated adapter (ignored)")
        return false, "redirect"
    end

    function Adapter:TryAddName()
        warnOnce(); publish("ProspectsAdapter.TryAddName")
        logger:Warn("TryAddName called on deprecated adapter (ignored)")
        return false, "redirect"
    end

    return Adapter
end

-- Register with DI so consumers resolving ProspectsManager get the adapter instance.
if Addon.provide then
    Addon.provide("ProspectsManager", function(scope) return CreateProspectsManager(scope) end, { lifetime = "SingleInstance" })
end

-- Legacy global style export (optional)
Addon.ProspectsManager = setmetatable({}, { __index = function(_, k) return Addon.require("ProspectsManager")[k] end })

return CreateProspectsManager
