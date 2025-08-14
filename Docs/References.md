# Guild Prospector References

Legacy name: Guild Recruiter.
# WoW API References

Authoritative references for in-game APIs we touch. Use these when extending services or UI.

- API Index (canonical): https://warcraft.wiki.gg/wiki/World_of_Warcraft_API

Core APIs we rely on
- Frame/UI
  - CreateFrame: https://warcraft.wiki.gg/wiki/API_CreateFrame
  - DEFAULT_CHAT_FRAME: https://warcraft.wiki.gg/wiki/Using_the_Default_Chat_Frame
- Events / Build Info
  - GetBuildInfo: https://warcraft.wiki.gg/wiki/API_GetBuildInfo
- Timers / Time
  - C_Timer.After: https://warcraft.wiki.gg/wiki/API_C_Timer.After
  - GetTime: https://warcraft.wiki.gg/wiki/API_GetTime
  - time(): https://warcraft.wiki.gg/wiki/API_time
- Chat / Addon Messaging
  - C_ChatInfo.SendAddonMessage: https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage
  - SendAddonMessage (Classic): https://warcraft.wiki.gg/wiki/API_SendAddonMessage
  - C_ChatInfo.RegisterAddonMessagePrefix: https://warcraft.wiki.gg/wiki/API_C_ChatInfo.RegisterAddonMessagePrefix
  - RegisterAddonMessagePrefix (Classic): https://warcraft.wiki.gg/wiki/API_RegisterAddonMessagePrefix
- Units / Player
  - UnitName: https://warcraft.wiki.gg/wiki/API_UnitName
  - UnitGUID: https://warcraft.wiki.gg/wiki/API_UnitGUID
- Secure State
  - InCombatLockdown: https://warcraft.wiki.gg/wiki/API_InCombatLockdown
- Slash commands
  - SlashCmdList: https://warcraft.wiki.gg/wiki/Creating_slash_commands

Notes
- Retail vs. Classic variants: prefer C_ChatInfo APIs when available; fall back to legacy functions otherwise (see ChatRouting service).
- Payload limits and channel availability can differ by project/build; probe with RuntimeCaps when behavior is uncertain.
- WoW’s addon loader passes (addonName, addonTable) varargs to each file in the .toc—use addonTable as the shared state/DI surface (see ARCHITECTURE.md).
