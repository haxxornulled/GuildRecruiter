local ExportService = {}

function ExportService:Save(record)
    -- Record must be a table, add to global for SavedVariables
    _G.GuildRecruiter_ExportData = _G.GuildRecruiter_ExportData or {}
    table.insert(_G.GuildRecruiter_ExportData, record)
    print("DEBUG: Exported record", record and record.name, "Total now:", #_G.GuildRecruiter_ExportData)
end


_G.GuildRecruiter = _G.GuildRecruiter or {}
_G.GuildRecruiter.ExportService = ExportService

return ExportService