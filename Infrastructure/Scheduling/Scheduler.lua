-- Infrastructure/Scheduling/Scheduler.lua — compact OnUpdate scheduler (Retail/Classic safe)
local ADDON_NAME, Addon = ...
if type(ADDON_NAME) ~= "string" or ADDON_NAME == "" then ADDON_NAME = "GuildRecruiter" end

local function now()
	local clk = (Addon and ((Addon.Peek and Addon.Peek('Clock')) or (Addon.Get and Addon.Get('Clock'))))
	if clk and clk.Now then return clk:Now() end
	return (GetTime and GetTime()) or 0
end

local function CreateScheduler()
	local self = {}
	local tasks = {} -- kept sorted by due ascending
	local canceled = {}
	local nsIndex = {}
	local deb, thr = {}, {}
	local nextId = 0

	-- Create the frame eagerly to avoid static analyzer false-positives
	local frame = CreateFrame and CreateFrame("Frame", ADDON_NAME.."_Scheduler") or nil
	if frame then
		frame:SetScript("OnUpdate", function()
			if #tasks == 0 then return end
			local tnow = now()
			while true do
				local first = tasks[1]
				if not first or first.due > tnow then break end
				table.remove(tasks,1)
				if not canceled[first.id] then
					pcall(first.fn, tnow, first.id)
					thr._ran = (thr._ran or 0) + 1
					if first.interval and not canceled[first.id] then
						first.due = first.due + first.interval
						-- reinsert maintaining order
						local inserted = false
						for i=1,#tasks do if first.due < tasks[i].due then table.insert(tasks,i,first); inserted=true; break end end
						if not inserted then tasks[#tasks+1] = first end
					else
						if first.ns and nsIndex[first.ns] then nsIndex[first.ns][first.id] = nil end
					end
				else
					canceled[first.id] = nil
				end
			end
		end)
	end

	local function newId()
		nextId = nextId + 1
		return "sch#"..tostring(nextId)
	end

	local function schedule(due, fn, interval, ns)
		local id = newId()
		local entry = { id = id, due = due, fn = fn, interval = interval, ns = ns }
		-- binary insertion into tasks (tasks already sorted)
		local inserted = false
		for i=1,#tasks do if due < tasks[i].due then table.insert(tasks, i, entry); inserted=true; break end end
		if not inserted then tasks[#tasks+1] = entry end
		if ns then nsIndex[ns] = nsIndex[ns] or {}; nsIndex[ns][id] = true end
		thr._peak = math.max(thr._peak or 0, #tasks)
		return id
	end

	function self:NextTick(fn, opts) opts=opts or {}; return schedule(now(), fn, nil, opts.namespace) end
	function self:After(delay, fn, opts) opts=opts or {}; return schedule(now() + math.max(0, delay or 0), fn, nil, opts.namespace) end
	function self:Every(interval, fn, opts) assert(interval and interval>0, "Every(interval>0)"); opts=opts or {}; return schedule(now()+interval, fn, interval, opts.namespace) end

	function self:Cancel(id)
		if not id then return false end
		canceled[id] = true
		return true
	end
	function self:CancelNamespace(ns)
		local set = nsIndex[ns]; if not set then return 0 end
		local n=0; for id in pairs(set) do if not canceled[id] then canceled[id]=true; n=n+1 end end
		nsIndex[ns] = nil
		return n
	end

	-- Debounce(key, window, fn, opts={namespace,args})
	function self:Debounce(key, window, fn, opts)
		assert(type(key)=="string" and window and window>=0 and type(fn)=="function", "Debounce")
		opts = opts or {}
		local e = deb[key] or {}
		if e.pending then self:Cancel(e.pending) end
		e.ns = opts.namespace; e.fn = fn; e.args = opts.args or {}
		e.pending = schedule(now()+window, function()
			deb[key] = nil
			pcall(fn, unpack(e.args))
		end, nil, e.ns)
		deb[key] = e
		return e.pending
	end

	-- Throttle(key, window, fn, opts={namespace,args,leading=true,trailing=true})
	function self:Throttle(key, window, fn, opts)
		assert(type(key)=="string" and window and window>0 and type(fn)=="function", "Throttle")
		opts = opts or {}
		local e = thr[key] or { lastFire = 0, ns = opts.namespace, leading = (opts.leading ~= false), trailing = (opts.trailing ~= false) }
		local tnow = now()
		local remaining = (e.lastFire + window) - tnow
		if remaining <= 0 then
			e.lastFire = tnow
			if e.leading then pcall(fn, unpack(opts.args or {})) end
			if e.trailingId then self:Cancel(e.trailingId); e.trailingId=nil end
		else
			if e.trailing then
				e.trailingArgs = opts.args or e.trailingArgs
				if not e.trailingId then
					e.trailingId = schedule(e.lastFire + window, function()
						e.lastFire = now(); local a=e.trailingArgs; e.trailingArgs=nil; e.trailingId=nil; if a then pcall(fn, unpack(a)) end
					end, nil, e.ns)
				end
			end
		end
		thr[key] = e
		return e.trailingId
	end

	-- Coalesce(bus, event, window, reducerFn, publishAs, opts)
	function self:Coalesce(bus, event, window, reducerFn, publishAs, opts)
		assert(bus and type(bus.Subscribe)=="function" and type(bus.Publish)=="function", "Coalesce: need EventBus")
		opts = opts or {}; local ns = opts.namespace or ("Coalesce:"..tostring(event))
		local acc, have, timerId = nil, false, nil
		local tok = bus:Subscribe(event, function(_, ...)
			acc = reducerFn(have and acc or nil, ...); have = true
			if not timerId then
				timerId = self:After(window, function()
					local out = acc; acc, have, timerId = nil, false, nil
					bus:Publish(publishAs or event, out)
				end, { namespace = ns })
			end
		end, { namespace = ns })
		return { unsubscribe = function() if tok and bus.Unsubscribe then bus:Unsubscribe(tok) end; self:CancelNamespace(ns) end }
	end

	-- no-op, frame is created eagerly
	function self:Start() return true end
	function self:Stop()
		tasks, canceled, nsIndex, deb, thr = {}, {}, {}, {}, {}
		if frame and frame.SetScript then frame:SetScript('OnUpdate', function() end) end
	end

	function self:Diagnostics()
		return { tasks = #tasks, ran = thr._ran or 0, peak = thr._peak or #tasks }
	end

	return self
end

local function RegisterScheduler()
	assert(Addon and Addon.provide, "Scheduler: Addon.provide not available")
	if not (Addon.IsProvided and Addon.IsProvided('Scheduler')) then
		Addon.provide('Scheduler', function() return CreateScheduler() end, { lifetime = 'SingleInstance', meta = { layer = 'Infrastructure', area = 'scheduling' } })
	end
	if Addon.safeProvide and not (Addon.IsProvided and Addon.IsProvided('IScheduler')) then
		Addon.safeProvide('IScheduler', function(sc) return sc:Resolve('Scheduler') end, { lifetime = 'SingleInstance' })
	end
	Addon.Scheduler = setmetatable({}, {
		__index = function(_, k)
			if Addon._booting then error('Cannot access Scheduler during boot phase') end
			local inst = Addon.require('Scheduler'); return inst[k]
		end,
		__call = function(_, ...) return Addon.require('Scheduler'), ... end
	})
end

Addon._RegisterScheduler = RegisterScheduler
return RegisterScheduler
