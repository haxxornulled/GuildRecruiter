-- Application/RecruitmentService.lua

local RecruitmentService = {}

-- Role enum
local VALID_ROLES = { tank = true, healer = true, dps = true }

-- Class-to-roles mapping (Retail)
local CLASS_ROLES = {
    ["warrior"]        = { "tank", "dps" },
    ["paladin"]        = { "tank", "healer", "dps" },
    ["death knight"]   = { "tank", "dps" },
    ["druid"]          = { "tank", "healer", "dps" },
    ["monk"]           = { "tank", "healer", "dps" },
    ["demon hunter"]   = { "tank", "dps" },
    ["priest"]         = { "healer", "dps" },
    ["shaman"]         = { "healer", "dps" },
    ["evoker"]         = { "healer", "dps" },
    ["hunter"]         = { "dps" },
    ["mage"]           = { "dps" },
    ["rogue"]          = { "dps" },
    ["warlock"]        = { "dps" },
}

local function GetRolesForClass(class)
    return CLASS_ROLES[(class or ""):lower()] or { "dps" }
end

local function GetMainRoleForClass(class)
    local roles = GetRolesForClass(class)
    return roles[1] or "dps"
end

function RecruitmentService.Init(services)
    RecruitmentService.Logger = services.Logger
    RecruitmentService.RecruitScoring = services.RecruitScoring
    RecruitmentService.MessageTemplateService = services.MessageTemplateService
    RecruitmentService.WoWApiAdapter = services.WoWApiAdapter
    RecruitmentService.EventHandler = services.EventHandler
    RecruitmentService.EventBus = _G.GuildRecruiter.EventBus
    RecruitmentService.Config = services.Config or {}
    return RecruitmentService
end

--- Entry point: mass or single recruit
function RecruitmentService.StartRecruitmentForPlayer(playerName, playerClass, level, ilvl, role)
    -- Defensive param correction: flip params if needed
    if CLASS_ROLES[(playerName or ""):lower()] and (not CLASS_ROLES[(playerClass or ""):lower()]) then
        role, ilvl, level, playerClass, playerName = ilvl, level, playerClass, playerName, nil
    end
    playerName  = playerName or ""
    playerClass = playerClass or "Unknown"
    level       = tonumber(level) or 0
    ilvl        = tonumber(ilvl) or 0

    local score = RecruitmentService.RecruitScoring.CalculateScore(playerClass, level, ilvl)
    RecruitmentService.Logger.Info(
        "[RecruitmentService] Player %s scored: %d (Class: %s, Level: %d, ilvl: %s, Role: %s)",
        tostring(playerName), score, tostring(playerClass), level, tostring(ilvl), tostring(role)
    )

    if RecruitmentService.EventBus then
        RecruitmentService.EventBus.Emit("PlayerScored", {
            name = playerName, class = playerClass, level = level, ilvl = ilvl, score = score, role = role
        })
    end

    local vars = {
        playerName = playerName,
        guildName  = GetGuildInfo("player") or "MyGuild",
        raidDays   = RecruitmentService.Config.raidDays or "Wed/Thu",
        guildType  = RecruitmentService.Config.guildType or "casual",
    }

    local templateRole = (role and VALID_ROLES[(role or ""):lower()]) and role:lower() or GetMainRoleForClass(playerClass)
    local whisper = RecruitmentService.MessageTemplateService.RenderTemplate(templateRole, vars)
    RecruitmentService.WoWApiAdapter.SendWhisper(playerName, whisper)
    RecruitmentService.Logger.Info("[RecruitmentService] Whisper sent to %s: %s", playerName, whisper)

    return score
end

function RecruitmentService.StartRecruitmentForRange(playerClass, minLevel, maxLevel, ilvl, role)
    local myName = UnitName("player")
    RecruitmentService.WoWApiAdapter.QueryWho(
        playerClass, minLevel, maxLevel,
        function(players)
            if not players or #players == 0 then
                RecruitmentService.Logger.Info("No players found for %s %d-%d", playerClass, minLevel, maxLevel)
                return
            end
            for _, player in ipairs(players) do
                if player.name ~= myName then
                    RecruitmentService.StartRecruitmentForPlayer(player.name, player.class, player.level, ilvl, role)
                end
            end
            RecruitmentService.Logger.Info("[RecruitmentService] Mass recruitment complete for %d players.", #players)
        end
    )
end

function RecruitmentService.OnPlayerScored(callback)
    if RecruitmentService.EventBus then
        RecruitmentService.EventBus.On("PlayerScored", callback)
    end
end

function RecruitmentService.ListenForWhisperResponses()
    local api = RecruitmentService.WoWApiAdapter
    api.OnWhisperReceived(function(msg, sender)
        local msgLower = (msg or ""):lower()
        if msgLower:find("yes") then
            api.SendGuildInvite(sender)
            RecruitmentService.Logger.Info("[RecruitmentService] Sent guild invite to %s", sender)
            if RecruitmentService.EventBus then
                RecruitmentService.EventBus.Emit("PlayerInvited", sender)
            end
        elseif msgLower:find("no") then
            RecruitmentService.Logger.Info("[RecruitmentService] Player %s declined invite (should be blacklisted)", sender)
            if RecruitmentService.EventBus then
                RecruitmentService.EventBus.Emit("PlayerDeclined", sender)
            end
        end
    end)
end

function RecruitmentService.InvitePlayer(playerName)
    if not playerName or playerName == "" then
        RecruitmentService.Logger.Warn("[RecruitmentService] InvitePlayer: No player name provided.")
        return
    end
    RecruitmentService.Logger.Info("[RecruitmentService] Attempting to invite: %s", playerName)
    RecruitmentService.WoWApiAdapter.SendGuildInvite(playerName)
end

function RecruitmentService.InitListeners()
    RecruitmentService.ListenForWhisperResponses()
end

_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.RecruitmentService = RecruitmentService

return RecruitmentService
