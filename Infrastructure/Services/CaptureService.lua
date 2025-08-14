---@diagnostic disable: undefined-global, undefined-field, inject-field, param-type-mismatch, lowercase-global, duplicate-set-field, redundant-return, align-assign
local _, Addon = ...

local CaptureService = {}
-- Prospect status constants (resolved lazily for safety / test harnesses)
local Status = (Addon and Addon.ResolveOptional and Addon.ResolveOptional('ProspectStatus')) or {
    New='New', Invited='Invited', Rejected='Rejected', Blacklisted='Blacklisted',
    IsActive=function(s) return s ~= 'Blacklisted' end,
    IsNew=function(s) return s == 'New' end,
}

local function root()
    local sv = (Addon.Get and Addon.Get('SavedVarsService')) or (Addon.Peek and Addon.Peek('SavedVarsService'))
    if sv and sv.GetNamespace then return sv:GetNamespace('', { prospects = {}, blacklist = {}, queue = {} }) end
    _G.GuildRecruiterDB = _G.GuildRecruiterDB or { prospects = {}, blacklist = {}, queue = {} }
    return _G.GuildRecruiterDB
end
local function bus() return (Addon.Get and Addon.Get('EventBus')) or (Addon.Peek and Addon.Peek('EventBus')) end
local function scheduler() return (Addon.Get and Addon.Get('Scheduler')) or (Addon.Peek and Addon.Peek('Scheduler')) end
local function logger() local l=(Addon.Get and Addon.Get('Logger')) or (Addon.Peek and Addon.Peek('Logger')); return l and l:ForContext('Subsystem','CaptureService') or { Info=function() end, Debug=function() end } end
local function queueSvc() return (Addon.Get and Addon.Get('QueueService')) or (Addon.Peek and Addon.Peek('QueueService')) end
local function pm() return (Addon.Get and Addon.Get('IProspectManager')) or (Addon.Peek and Addon.Peek('IProspectManager')) end

local function now_s() return (_G.time and _G.time()) or os.time() end
local function UnitGUID(u) if _G.UnitGUID then return _G.UnitGUID(u) end end
local function UnitIsPlayer(u) if _G.UnitIsPlayer then return _G.UnitIsPlayer(u) end return false end
local function UnitFactionGroup(u) if _G.UnitFactionGroup then return _G.UnitFactionGroup(u) end return nil end
local function GetGuildInfo(u) if _G.GetGuildInfo then return _G.GetGuildInfo(u) end return nil end
local function UnitName(u) if _G.UnitName then return _G.UnitName(u) end return nil,nil end
local function UnitClass(u) if _G.UnitClass then return _G.UnitClass(u) end return nil,nil,nil end
local function UnitRace(u) if _G.UnitRace then return _G.UnitRace(u) end return nil,nil end
local function UnitLevel(u) if _G.UnitLevel then return _G.UnitLevel(u) end return 0 end
local function UnitSex(u) if _G.UnitSex then return _G.UnitSex(u) end return 0 end
local function UnitExists(u) if _G.UnitExists then return _G.UnitExists(u) end return false end

-- Legacy local STATUS table replaced by canonical constants; keep name for minimal diff
local STATUS = Status

local function unitGUIDPlayer(unit)
    local g = UnitGUID(unit)
    if g and g:find('^Player') then return g end
end
local function unitIsUnguilded(unit)
    if not UnitIsPlayer(unit) then return false end
    local g = GetGuildInfo(unit)
    return g == nil
end

local function unitBasics(unit)
    local name, realm = UnitName(unit)
    local clsName, clsToken, classID = UnitClass(unit)
    local raceName, raceToken = UnitRace(unit)
    local level = UnitLevel(unit)
    local sex = UnitSex(unit)
    return { name=name, realm=realm, classID=classID, classToken=clsToken, className=clsName, raceName=raceName, raceToken=raceToken, level=level, sex=sex }
end

function CaptureService:Start()
    if self._started then return end
    self._started = true
    local b = bus()
    local sched = scheduler()
    local log = logger()
    local db = root()
    local function upsert(unit, src)
        local guid = unitGUIDPlayer(unit); if not guid then return end
        local pf = UnitFactionGroup('player'); local uf = UnitFactionGroup(unit); if uf ~= pf then return end
        if not unitIsUnguilded(unit) then return end
        if db.blacklist[guid] then return end
        local t = now_s(); local p = db.prospects[guid]
        if not p then
            local bsc = unitBasics(unit)
            p = {
                guid=guid, name=bsc.name, realm=bsc.realm, faction=uf,
                classID=bsc.classID, classToken=bsc.classToken, className=bsc.className,
                raceName=bsc.raceName, raceToken=bsc.raceToken, level=bsc.level, sex=bsc.sex,
                firstSeen=t, lastSeen=t, seenCount=1, sources={ [src]=true }, status=Status.New,
            }
            db.prospects[guid]=p
            db.queue[#db.queue+1]=guid
            local qs = queueSvc(); if qs and qs.Requeue then qs:Requeue(guid) end -- ensure runtime queue picks it up
            local pmgr = pm(); if pmgr and pmgr.GetProspect then -- sync into read model if needed
                local svc = (Addon.Get and Addon.Get('ProspectsService')); if svc and svc.Upsert then svc:Upsert(p) end
            end
                        if b and b.Publish then
                            local E = (Addon.ResolveOptional and Addon.ResolveOptional('Events')) or error('Events constants missing')
                            b:Publish(E.Prospects.Changed,'queued',guid)
                        end
            if log and log.Info then log:Info('Captured prospect {GUID}', { GUID = guid }) end
        else
            p.lastSeen = t; p.seenCount = (p.seenCount or 0) + 1; p.sources = p.sources or {}; p.sources[src]=true
            local bsc = unitBasics(unit)
            p.level = bsc.level or p.level; p.classID=bsc.classID or p.classID; p.classToken=bsc.classToken or p.classToken
            p.className=bsc.className or p.className; p.raceName=bsc.raceName or p.raceName; p.raceToken=bsc.raceToken or p.raceToken
                        if b and b.Publish then
                            local E = (Addon.ResolveOptional and Addon.ResolveOptional('Events')) or error('Events constants missing')
                            b:Publish(E.Prospects.Changed,'updated',guid)
                        end
        end
    end
    local function capture(unit, src)
        if not UnitExists(unit) then return end
        local guid = unitGUIDPlayer(unit)
        local key = 'capture:'..src..':'..(guid or 'noguid')
        if sched and sched.Throttle then
            sched:Throttle(key, 0.10, function() upsert(unit, src) end)
        else
            upsert(unit, src)
        end
    end
    if b and b.RegisterWoWEvent and b.Subscribe then
        self._tokens = {}
        local t1 = b:RegisterWoWEvent('PLAYER_TARGET_CHANGED'); if t1 then self._tokens[#self._tokens+1] = t1.token end
        local s1 = b:Subscribe('PLAYER_TARGET_CHANGED', function() capture('target','target') end, { namespace='CaptureService' }); if s1 then self._tokens[#self._tokens+1] = s1 end
        local t2 = b:RegisterWoWEvent('UPDATE_MOUSEOVER_UNIT'); if t2 then self._tokens[#self._tokens+1] = t2.token end
        local s2 = b:Subscribe('UPDATE_MOUSEOVER_UNIT', function() capture('mouseover','mouseover') end, { namespace='CaptureService' }); if s2 then self._tokens[#self._tokens+1] = s2 end
        local t3 = b:RegisterWoWEvent('NAME_PLATE_UNIT_ADDED'); if t3 then self._tokens[#self._tokens+1] = t3.token end
        local s3 = b:Subscribe('NAME_PLATE_UNIT_ADDED', function(_,unit) capture(unit,'nameplate') end, { namespace='CaptureService' }); if s3 then self._tokens[#self._tokens+1] = s3 end
    end
    if log and log.Info then log:Info('CaptureService started') end
end

function CaptureService:Stop()
    local b=bus()
    if b and self._tokens then
        for _,t in ipairs(self._tokens) do pcall(function() b:Unsubscribe(t) end) end
        b:UnsubscribeNamespace('CaptureService')
    end
    self._tokens=nil; self._started=false
end

local function RegisterCaptureService()
    if not Addon.provide then return end
    if not (Addon.IsProvided and Addon.IsProvided('CaptureService')) then
        Addon.provide('CaptureService', function() return setmetatable({}, { __index=CaptureService }) end, { lifetime='SingleInstance', meta={ layer='Infrastructure', area='capture' } })
    end
end
RegisterCaptureService(); Addon._RegisterCaptureService = RegisterCaptureService
return CaptureService
