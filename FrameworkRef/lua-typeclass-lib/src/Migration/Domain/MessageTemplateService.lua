-- Application/MessageTemplateService.lua

-- Ensure globals
_G.GuildRecruiter = _G.GuildRecruiter or {}
GuildRecruiterDB = GuildRecruiterDB or {}

local Logger = (_G.GuildRecruiter.Logger or { Info = print })

local MessageTemplateService = {}

-- Default message templates (use lowercase keys for consistency)
local DEFAULT_TEMPLATES = {
    general = "Hi {playerName}! We're recruiting for <{guildName}>, a friendly guild looking for active players. Interested in joining us?",
    tank    = "Hey {playerName}! <{guildName}> is looking for tanks like you! We raid {raidDays} and would love to have you join our team!",
    healer  = "Hi {playerName}! <{guildName}> is in need of skilled healers. We're a {guildType} guild that values teamwork. Want to learn more?",
    dps     = "Hello {playerName}! <{guildName}> is recruiting DPS players. We have a great community and are looking to grow. Interested?",
    social  = "Hey {playerName}! Looking for a friendly social guild? <{guildName}> welcomes players of all levels. Come join our community!"
}

-- Ensure DB templates table exists on first run
GuildRecruiterDB.messageTemplates = GuildRecruiterDB.messageTemplates or {}
for k, v in pairs(DEFAULT_TEMPLATES) do
    if not GuildRecruiterDB.messageTemplates[k] then
        GuildRecruiterDB.messageTemplates[k] = v
    end
end

-- Initialization (optionally override templates)
function MessageTemplateService.Initialize(templates)
    Logger.Info("Initializing message templates...")
    if type(templates) == "table" then
        for k, v in pairs(templates) do
            GuildRecruiterDB.messageTemplates[k] = v
        end
    end
end

function MessageTemplateService.GetTemplate(name)
    name = (name or "general"):lower()
    return GuildRecruiterDB.messageTemplates[name] or DEFAULT_TEMPLATES.general
end

function MessageTemplateService.ListTemplateVariables()
    return { "playerName", "guildName", "raidDays", "guildType" }
end

-- Enterprise: robust variable replacement, no code smell!
function MessageTemplateService.RenderTemplate(name, vars)
    local template = MessageTemplateService.GetTemplate(name)
    if not template then return "" end
    return template:gsub("{(%w+)}", function(key)
        return tostring(vars[key] or ("{" .. key .. "}"))
    end)
end

-- (Optionally: add, edit, remove, list templates for future UI)
-- e.g. MessageTemplateService.SetTemplate(name, value)

-- Expose globally
_G.GuildRecruiter.MessageTemplateService = MessageTemplateService
return MessageTemplateService
