-- Infrastructure/Messaging/EventBus.lua — lightweight pub/sub + WoW event bridge (adapter)
local ADDON_NAME, Addon = ...

-- Factory function for DI container (no top-level resolves)
local function CreateEventBus()
	local function newBus()
		local self = {}
		local seq = 0
		local handlers = {}          -- [event] = { { token=..., fn=..., ns=... }, ... }
		local tokenIndex = {}        -- [token] = { event=..., idx=... }
		local stats = { publishes = 0, errors = 0 }
		local wowRegistered = {}
		local wowFrame = CreateFrame("Frame")

		local function logErr(msg)
			if Addon.Logger and Addon.Logger.Error then
				pcall(Addon.Logger.Error, Addon.Logger, "{Msg}", { Msg = msg })
			else
				print("|cffff5555[GuildRecruiter][EventBus]|r " .. tostring(msg))
			end
		end

		function self:Publish(ev, ...)
			stats.publishes = stats.publishes + 1
			local list = handlers[ev]
			if not list or #list == 0 then return end
			local snapshot = {}
			for i=1,#list do snapshot[i] = list[i] end
			for i=1,#snapshot do
				local h = snapshot[i]
				if h and h.fn then
					local ok, err = pcall(h.fn, ev, ...)
					if not ok then
						stats.errors = stats.errors + 1
						logErr("Handler error for "..ev..": "..tostring(err))
					end
				end
			end
		end

		function self:Subscribe(ev, fn, opts)
			if not ev or type(fn) ~= "function" then return end
			handlers[ev] = handlers[ev] or {}
			seq = seq + 1
			local token = ev..":"..seq
			handlers[ev][#handlers[ev]+1] = { token = token, fn = fn, ns = opts and opts.namespace }
			tokenIndex[token] = { event = ev }
			return token
		end

		function self:Once(ev, fn, opts)
			local holder = { token = nil }
			holder.token = self:Subscribe(ev, function(event, ...)
				-- unsubscribe first to ensure single execution
				local t = holder.token
				if t ~= nil then self:Unsubscribe(t); holder.token = false end
				fn(event, ...)
			end, opts)
			return holder.token
		end

		local function maybeUnregister(event)
			local list = handlers[event]
			if list and #list == 0 and wowRegistered[event] then
				wowFrame:UnregisterEvent(event)
				wowRegistered[event] = nil
			end
		end

		function self:Unsubscribe(token)
			local meta = tokenIndex[token]; if not meta then return end
			local ev = meta.event
			if not meta.sentinel then
				local list = handlers[ev]
				if list ~= nil then
					for i=#list,1,-1 do
						if list[i].token == token then
							table.remove(list, i)
						end
					end
				end
			end
			tokenIndex[token] = nil
			maybeUnregister(ev)
		end

		function self:UnsubscribeNamespace(ns)
			if not ns then return end
			for ev, list in pairs(handlers) do
				for i=#list,1,-1 do if list[i].ns == ns then table.remove(list, i) end end
				maybeUnregister(ev)
			end
		end

		function self:ListEvents()
			local evs = {}
			for ev,_ in pairs(handlers) do evs[#evs+1] = ev end
			table.sort(evs)
			return evs
		end

		function self:HandlerCount(ev)
			local list = handlers[ev]; return list and #list or 0
		end

		function self:Diagnostics(opts)
			local withHandlers = opts and opts.withHandlers
			local diag = { publishes = stats.publishes, errors = stats.errors, events = {} }
			for ev,list in pairs(handlers) do
				local entry = { event=ev, handlers=#list }
				if withHandlers then
					local hn = {}
					for i,h in ipairs(list) do hn[#hn+1] = { ns = h.ns or "", token = h.token } end
					entry.details = hn
				end
				diag.events[#diag.events+1] = entry
			end
			table.sort(diag.events, function(a,b) return a.event < b.event end)
			return diag
		end

		function self:RegisterWoWEvent(ev)
			if not ev or ev == "" then return { token=nil, event=ev } end
			if not wowRegistered[ev] then
				wowFrame:RegisterEvent(ev)
				wowRegistered[ev] = { registered = true }
			end
			local token = "WOWREG:"..ev
			if not tokenIndex[token] then tokenIndex[token] = { event = ev, sentinel = true } end
			return { token = token, event = ev }
		end

		wowFrame:SetScript("OnEvent", function(_, event, ...)
			self:Publish(event, ...)
		end)

		return self
	end

	return newBus()
end

-- Registration function for Init.lua
local function RegisterEventBusFactory()
	if not Addon.provide then
		error("EventBus: Addon.provide not available")
	end
  
	if not (Addon.IsProvided and Addon.IsProvided("EventBus")) then
		Addon.provide("EventBus", function()
			local bus = CreateEventBus()
			bus.__implements = bus.__implements or {}; bus.__implements['IEventBus']=true
			return bus
		end, { lifetime = "SingleInstance", meta = { layer = 'Infrastructure', area = 'messaging' } })
		if not (Addon.IsProvided and Addon.IsProvided('IEventBus')) then
			Addon.safeProvide('IEventBus', function(sc) return sc:Resolve('EventBus') end, { lifetime='SingleInstance' })
		end
	end

	-- Lazy export (safe)
	Addon.EventBus = setmetatable({}, {
		__index = function(_, k) 
			if Addon._booting then
				error("Cannot access EventBus during boot phase")
			end
			local inst = Addon.require("EventBus")
			return inst[k] 
		end,
		__call = function(_, ...) return Addon.require("EventBus"), ... end
	})
end

-- Export the registration function for Init.lua to call
Addon._RegisterEventBus = RegisterEventBusFactory

return RegisterEventBusFactory

