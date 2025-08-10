-- Commands.lua — central slash/command registry
local ADDON_NAME, Addon = ...

local function println(msg)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[%s]|r %s"):format(ADDON_NAME, tostring(msg)))
end

-- Show main UI
local function toggleMainUI()
    if Addon.UI and Addon.UI.Show then
        Addon.UI:Show()
        return
    end
    local mf = _G["GuildRecruiterFrame"]
    if mf then
        if mf:IsShown() then mf:Hide() else mf:Show() end
    else
        println("Main UI not ready yet.")
    end
end

-- Open settings
local function openSettings()
    local id = Addon._OptionsCategoryID or "Guild Recruiter"
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(id)
    else
        println("Settings not available.")
    end
end

-- Parse command args
local function parseArgs(msg)
    local t = {}
    for w in msg:gmatch("%S+") do table.insert(t, w) end
    return t
end

local function handleSlash(msg)
    msg = msg and msg:trim() or ""
    if msg == "" or msg == "ui" or msg == "toggle" then
        toggleMainUI()
        return
    elseif msg == "settings" or msg == "options" then
        openSettings()
        return
    elseif msg:match("^messages") then
        -- Subcommands: /gr messages add <n>, /gr messages remove <n>, /gr messages list
        local parts = { strsplit(" ", msg) }
        local sub = parts[2]
        if not sub or sub == "help" then
            println("Messages: add <n>, remove <n>, list")
            return
        end
        local settingsMod = Addon.require and Addon.require("UI.Settings")
        if not settingsMod then
            println("Settings UI not loaded yet")
            return
        end
        if sub == "add" and parts[3] then
            local ok, msgOrErr = pcall(settingsMod.AddMessage, settingsMod, tonumber(parts[3]))
            println(ok and msgOrErr or ("Error: "..tostring(msgOrErr)))
        elseif sub == "remove" and parts[3] then
            local ok, msgOrErr = pcall(settingsMod.RemoveMessage, settingsMod, tonumber(parts[3]))
            println(ok and msgOrErr or ("Error: "..tostring(msgOrErr)))
        elseif sub == "list" then
            local ok, list = pcall(settingsMod.ListMessages, settingsMod)
            if ok and type(list)=="table" then
                println("Messages: "..table.concat(list, ", "))
            else
                println("No messages.")
            end
        else
            println("Usage: /gr messages [add <n>|remove <n>|list]")
        end
        return
    elseif msg:match("^devmode") then
        local cfg = Addon.require and Addon.require("Config")
        if not cfg then println("Config not ready.") return end
        local parts = { strsplit(" ", msg) }
        local mode = parts[2]
        if mode == "on" then
            cfg:Set("devMode", true); println("Dev mode: ON")
        elseif mode == "off" then
            cfg:Set("devMode", false); println("Dev mode: OFF")
        elseif mode == "toggle" or not mode then
            local new = not cfg:Get("devMode", false)
            cfg:Set("devMode", new); println("Dev mode toggled: "..(new and "ON" or "OFF"))
        else
            println("Usage: /gr devmode [on|off|toggle]")
            return
        end
        -- Rebuild sidebar if UI loaded to reflect debug tab visibility
        if Addon.UI and Addon.UI.Main and Addon.UI.Main.RefreshCategories then
            pcall(Addon.UI.Main.RefreshCategories, Addon.UI.Main)
            local toast = Addon.UI.Main.ShowToast and Addon.UI.Main
            if toast then
                local state = cfg:Get("devMode", false) and "Dev Mode ENABLED" or "Dev Mode DISABLED"
                pcall(Addon.UI.Main.ShowToast, Addon.UI.Main, state)
            end
        elseif Addon.UI and Addon.UI.Show then
            -- fallback: reopen UI to refresh visibility
            local mf = _G["GuildRecruiterFrame"]
            if mf and mf.IsShown and mf:IsShown() then
                mf:Hide(); C_Timer.After(0, function() if mf.Show then mf:Show() end end)
            end
        end
        return
    elseif msg == "diag" or msg == "diagnostics" then
        local function stateline(label, value)
            println(string.format("%s: %s", label, tostring(value)))
        end
        println("Diagnostics ----------")
        -- Container stats
        if not Core then
            println("Core not available")
            return
        end
        -- Attempt to list known keys we care about (can't enumerate container without internal access)
        local keys = {
            "Core","Logger","EventBus","Scheduler","Config","Recruiter","InviteService","Options",
            "ChatChannelHelper","RoleHelper","UI.Main","UI.SidePanel","UI.Style","Theme_Dragonfly"
        }
        for _, k in ipairs(keys) do
            local ok, inst = pcall(Core.Resolve, k)
            if ok and inst then
                local typ = type(inst)
                local extra = ""
                if typ == "table" then
                    if inst.Start and inst.Stop then extra = " service" end
                end
                println(string.format(" - %s: ok (%s%s)", k, typ, extra))
            else
                println(string.format(" - %s: missing", k))
            end
        end
        -- Simple health events/state
        if Addon.EventBus and Addon.EventBus.Publish then
            println("EventBus: ok (Publish available)")
        else
            println("EventBus: missing facade")
        end
        if Addon.UI and Addon.UI.Show then println("UI: main module loaded") end
        println("Diagnostics complete.")
        return
    end

    -- Dispatch to Options handler if it exists (safe resolution)
    local Core = Addon.require and Addon.require("Core")
    if Core then
        local ok, opt = pcall(Core.TryResolve or Core.Resolve, "Options")
        if ok and opt and opt.HandleSlash then
            opt:HandleSlash(msg)
            return
        end
    end

    println("Unknown command. Try /gr settings or /gr ui.")
end

-- Slash aliases
SLASH_GUILDRECRUITER1 = "/gr"
SLASH_GUILDRECRUITER2 = "/guildrecruiter"
SLASH_GUILDRECRUITER3 = "/guildrec"
SlashCmdList.GUILDRECRUITER = handleSlash
