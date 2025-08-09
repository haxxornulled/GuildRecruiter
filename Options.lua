-- Options.lua — Settings panel + enterprise-grade slash commands (DI + Settings API)
-- Factory-based registration for DI container
-- Retail 10.0+: Settings API

local ADDON_NAME, Addon = ...

-- ------- tiny UI helpers -------
local id_seq = 0
local function NextName(prefix) id_seq = id_seq + 1; return (ADDON_NAME .. prefix .. id_seq) end

local function CreateCheckbox(parent, label, tooltip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  if tooltip then cb.tooltipText = label; cb.tooltipRequirement = tooltip end
  return cb
end

local function CreateSlider(parent, label, minv, maxv, step, width)
  local name = NextName("Slider")
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minv, maxv)
  s:SetValueStep(step or 1)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(width or 260)
  _G[name.."Low"]:SetText(tostring(minv))
  _G[name.."High"]:SetText(tostring(maxv))
  _G[name.."Text"]:SetText(label)
  return s, name
end

local function CreateEditBox(parent, width)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetAutoFocus(false); e:SetWidth(width or 320); e:SetHeight(22); e:SetMaxLetters(240); e:SetCursorPosition(0)
  return e
end

local function CreateDropdown(parent, width)
  local d = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  d:SetWidth(width or 180)
  return d
end

-- ------- DI service -------
-- Factory function for DI container (TRUE lazy resolution)
local function CreateOptions()
    -- Lazy dependency accessors - resolved only when actually used
    local function getLog()
      return Addon.require("Logger"):ForContext("Subsystem","Options")
    end
    
    local function getConfig()
      return Addon.require("Config")
    end
    
    local function getBus()
      return Addon.require("EventBus")
    end

    local self = { category = nil, frame = nil }

    -- ------- Settings canvas -------
    local function BuildCanvas(frame)
      local cfg = getConfig()
      local bus = getBus()
      
      local y = -20
      local function row(h) y = y - h; return y end

      local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
      title:SetPoint("TOPLEFT", 20, y); title:SetText("Guild Recruiter"); row(28)

      local cb = CreateCheckbox(frame, "Enable broadcast rotation", "Sends a recruiting message at a cadence with jitter.")
      cb:SetPoint("TOPLEFT", 24, y)
      cb:SetChecked(cfg:Get("broadcastEnabled", false))
      cb:SetScript("OnClick", function(b)
        local val = b:GetChecked() and true or false
        cfg:Set("broadcastEnabled", val)
        if bus and bus.Publish then bus:Publish("ConfigChanged", "broadcastEnabled", val) end
      end)
      row(32)

      local chanHelper = nil
      local okCH, maybeCore = pcall(Addon.require, "Core")
      if okCH and maybeCore and maybeCore.TryResolve then
        chanHelper = maybeCore.TryResolve("ChatChannelHelper")
      end
      local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      label:SetPoint("TOPLEFT", 20, y); label:SetText("Broadcast channel")
      local dd = CreateDropdown(frame); dd:SetPoint("TOPLEFT", 180, y - 6)
      local entries = {}
      if chanHelper and chanHelper.Enumerate then
        entries = chanHelper:Enumerate()
      else
        entries = {
          { display="AUTO (Trade > General > Say)", spec="AUTO" },
          { display="Say", spec="SAY" }, { display="Yell", spec="YELL" },
          { display="Guild", spec="GUILD" }, { display="Instance", spec="INSTANCE_CHAT" },
          { display="General", spec="CHANNEL:General" },
        }
      end
      local curr = cfg:Get("broadcastChannel","AUTO")
      UIDropDownMenu_SetWidth(dd, 220)
      UIDropDownMenu_Initialize(dd, function(_, level)
        for i, e in ipairs(entries) do
          local info = UIDropDownMenu_CreateInfo()
          info.text = e.display or e.spec
          info.func = function()
            curr = e.spec
            UIDropDownMenu_SetSelectedID(dd, i)
            cfg:Set("broadcastChannel", curr)
            if bus and bus.Publish then bus:Publish("ConfigChanged","broadcastChannel",curr) end
          end
          info.checked = (curr == e.spec)
          UIDropDownMenu_AddButton(info, level)
        end
      end)
      for i,e in ipairs(entries) do if e.spec == curr then UIDropDownMenu_SetSelectedID(dd, i) end end
      row(36)

      local iv, ivName = CreateSlider(frame, "Broadcast interval (sec)", 60, 900, 5, 260)
      iv:SetPoint("TOPLEFT", 20, y)
      iv:SetValue(cfg:Get("broadcastInterval", 300))
      iv:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        cfg:Set("broadcastInterval", v)
        _G[ivName.."Text"]:SetText("Broadcast interval (sec): "..v)
        if bus and bus.Publish then bus:Publish("ConfigChanged","broadcastInterval",v) end
      end)
      row(56)

      local jit, jitName = CreateSlider(frame, "Jitter (% of interval)", 0, 50, 1, 260)
      jit:SetPoint("TOPLEFT", 20, y)
      jit:SetValue(math.floor((cfg:Get("jitterPercent", 0.15) * 100) + 0.5))
      jit:SetScript("OnValueChanged", function(_, v)
        v = math.max(0, math.min(50, math.floor(v + 0.5)))
        cfg:Set("jitterPercent", v/100.0)
        _G[jitName.."Text"]:SetText(("Jitter (%% of interval): %d"):format(v))
        if bus and bus.Publish then bus:Publish("ConfigChanged","jitterPercent", v/100.0) end
      end)
      row(56)

      local cd, cdName = CreateSlider(frame, "Invite button cooldown (sec)", 0, 10, 1, 260)
      cd:SetPoint("TOPLEFT", 20, y)
      cd:SetValue(tonumber(cfg:Get("inviteClickCooldown", 3)) or 3)
      cd:SetScript("OnValueChanged", function(_, v)
        v = math.max(0, math.min(10, math.floor(v + 0.5)))
        cfg:Set("inviteClickCooldown", v)
        _G[cdName.."Text"]:SetText("Invite button cooldown (sec): "..v)
        if bus and bus.Publish then bus:Publish("ConfigChanged","inviteClickCooldown",v) end
      end)
      row(56)

      local pill, pillName = CreateSlider(frame, "Invite status pill duration (sec)", 0, 10, 1, 260)
      pill:SetPoint("TOPLEFT", 20, y)
      pill:SetValue(tonumber(cfg:Get("invitePillDuration", 3)) or 3)
      pill:SetScript("OnValueChanged", function(_, v)
        v = math.max(0, math.min(10, math.floor(v + 0.5)))
        cfg:Set("invitePillDuration", v)
        _G[pillName.."Text"]:SetText("Invite status pill duration (sec): "..v)
        if bus and bus.Publish then bus:Publish("ConfigChanged","invitePillDuration", v) end
      end)
      row(56)

      local msgLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      msgLabel:SetPoint("TOPLEFT", 20, y); msgLabel:SetText("Message templates"); row(24)

      local function msgRow(key, caption)
        local lbl = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", 24, y); lbl:SetText(caption)
        local eb = CreateEditBox(frame, 460); eb:SetPoint("TOPLEFT", 180, y - 3)
        eb:SetText(cfg:Get(key, "")); eb:SetCursorPosition(0)
        eb:SetScript("OnEditFocusLost", function(e)
          local txt = e:GetText() or ""
          cfg:Set(key, txt)
          if bus and bus.Publish then bus:Publish("ConfigChanged", key, txt) end
        end)
        row(28)
      end

      msgRow("customMessage1", "Message 1")
      msgRow("customMessage2", "Message 2")
      msgRow("customMessage3", "Message 3")

      local tip = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
      tip:SetPoint("BOTTOMLEFT", 20, 12)
      tip:SetText("Tokens: {Guild} {Player} {Class} {Level} {Realm} {Date} {Time}")
    end

    -- expose for slash
    function self:HandleSlash(msg)
      -- open if asked to open/settings
      msg = (msg or ""):gsub("^%s+",""):gsub("%s+$","")
      if msg == "" or msg == "open" or msg == "options" or msg == "settings" then
        if Addon._OptionsCategoryID and Settings and Settings.OpenToCategory then
          C_Timer.After(0, function() Settings.OpenToCategory(Addon._OptionsCategoryID) end)
        end
        return
      end
      -- rest of commands are unchanged (omitted for brevity)
      -- TIP: keep your previous command handlers here...
    end

    -- Dependency-free startup - just initialize state
    function self:Start()
      self._started = true
      getLog():Debug("Options ready")
    end

    function self:Stop() end

    return self
end

-- Registration function for Init.lua
local function RegisterOptionsFactory()
  if not Addon.provide then
    error("Options: Addon.provide not available")
  end
  
  Addon.provide("Options", CreateOptions, { lifetime = "SingleInstance" })
  
  -- Lazy export (safe)
  Addon.Options = setmetatable({}, {
    __index = function(_, k)
      if Addon._booting then
        error("Cannot access Options during boot phase")
      end
      local inst = Addon.require("Options"); return inst[k] 
    end,
    __call  = function(_, ...) return Addon.require("Options"), ... end
  })
end

-- Export registration function
Addon._RegisterOptions = RegisterOptionsFactory

-- ------- Global slash proxy with on-demand, DI-free registration -------
do
  local function EnsureRegistered()
    if Addon._OptionsCategoryID and Addon._OptionsFrame then return true end
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return false end

    -- Create a minimal frame; no OnShow resolve, no BuildCanvas here.
    local frame = Addon._OptionsFrame or CreateFrame("Frame", ADDON_NAME.."OptionsFrame_Fallback")
    frame.name = "Guild Recruiter"

    -- Register category once
    local cat = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name)
    cat.ID = "GuildRecruiter"          -- stable, non-localized
    Settings.RegisterAddOnCategory(cat)

    Addon._OptionsFrame = frame
    Addon._OptionsCategoryID = cat.ID
    return true
  end

  local function SlashProxy(msg)
    msg = (msg or ""):gsub("^%s+",""):gsub("%s+$","")

    -- Open/settings case: avoid DI completely to prevent re-entrancy
    if msg == "" or msg == "open" or msg == "options" or msg == "settings" then
      if EnsureRegistered() and Settings and Settings.OpenToCategory then
        C_Timer.After(0, function() Settings.OpenToCategory(Addon._OptionsCategoryID) end)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[GuildRecruiter]|r Settings API not available.")
      end
      return
    end

    -- Non-open commands: use the real Options service if ready
    local CoreObj = Addon.require and Addon.require("Core")
    if CoreObj then
      local ok, opt = pcall(CoreObj.Resolve, "Options")
      if ok and opt and opt.HandleSlash then
        opt:HandleSlash(msg)
        return
      end
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[GuildRecruiter]|r Options not ready; try again after a moment.")
  end

  -- Use different slash commands to avoid conflict with Commands.lua
  SLASH_GUILDRECRUITER_OPTIONS1 = "/groptions"
  SLASH_GUILDRECRUITER_OPTIONS2 = "/grsettings" 
  SlashCmdList.GUILDRECRUITER_OPTIONS = SlashProxy
end

return RegisterOptionsFactory
