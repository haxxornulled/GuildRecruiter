-- Domain/RecruitScoring.lua
-- Pure scoring logic, no WoW API or UI dependencies

local RecruitScoring = {}

-- Default config table for scoring (to be updated by UI sliders)
RecruitScoring.Config = {
    classBonus = {
        Paladin = 10,
        Priest = 10,
        Druid = 10,
        Shaman = 10,
        Evoker = 10,
        Monk = 10,
        Warrior = 5,
        DeathKnight = 5,
        DemonHunter = 5,
        Mage = 5,
        Warlock = 5,
        Rogue = 5,
        Hunter = 5,
    },
    levelBonus = {
        minLevel = 60,
        bonus = 5,
    },
    ilvlBonus = {
        -- Each entry: { min = ilvl, bonus = weight }
        { min = 400, bonus = 2 },
        { min = 600, bonus = 5 },
        { min = 650, bonus = 10 },
        { min = 680, bonus = 15 },
    },
    -- Score range for UI sliders: 10-80 (UI can update these values)
}



function RecruitScoring.CalculateScore(playerClass, level, ilvl)
    local score = 0
    local cfg = RecruitScoring.Config
    -- Class bonus
    if playerClass and cfg.classBonus[playerClass] then
        score = score + cfg.classBonus[playerClass]
    end
    -- Level bonus
    if level and level >= (cfg.levelBonus.minLevel or 0) then
        score = score + (cfg.levelBonus.bonus or 0)
    end
    -- ilvl bonus (use highest matching breakpoint)
    if ilvl then
        local ilvlBonus = 0
        for _, entry in ipairs(cfg.ilvlBonus) do
            if ilvl >= entry.min and entry.bonus > ilvlBonus then
                ilvlBonus = entry.bonus
            end
        end
        score = score + ilvlBonus
    end
    return score
end


_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.RecruitScoring = RecruitScoring
return RecruitScoring
