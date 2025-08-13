# Copilot Instructions for GuildRecruiter Addon

## Project Overview
GuildRecruiter is a modular World of Warcraft addon for automated guild recruitment, built with a clean, layered architecture inspired by .NET best practices. The codebase is organized for maintainability, extensibility, and robust in-game configuration.

## Architecture & Key Patterns
- **Domain Layer**: Pure business logic (e.g., `Domain/RecruitScoring.lua`).
- **Application Layer**: Orchestrates workflows (e.g., `Application/RecruitmentService.lua`, `MessageTemplateService.lua`).
- **Infrastructure Layer**: Handles WoW API calls and event/callback registration (e.g., `Infrastructure/WoWApiAdapter.lua`).
- **Events**: Event dispatching and handling (`Events/EventHandler.lua`).
- **UI Layer**: All configuration UI logic (`UI/ConfigWindow.lua`).
- **Core**: Entry point, composition root, and dependency injection (`Core.lua`, `GuildRecruiter.lua`).
- **Utils**: Centralized logging (`Utils/Logger.lua`), help system, and shared utilities.

## Logging & Debugging
- All logs must go through `GuildRecruiter.Logger` (see `Utils/Logger.lua`).
- If the logger/UI is not ready, logs are buffered in `_G.__GuildRecruiterLogBuffer` and flushed to the debug panel when available.
- The debug/status pane in the config UI (Options tab) displays all logs live.
- Use `GuildRecruiter.Logger.Debug`, `.Info`, `.Warn`, `.Error` for log levels.

## Slash Commands & Events
- Register slash commands via `WoWApiAdapter.RegisterSlash(cmd, handler)`.
- Register for WoW events using `WoWApiAdapter.On(event, callback)`.
- All slash/event handlers should log via the logger, not `print`.

## UI/UX
- The config UI is tabbed, scrollable, and styled for clarity (see `UI/ConfigWindow.lua`).
- All user-facing actions (e.g., clear log, JSON dump) are buttons in the Options tab.
- UI updates and log refreshes are event-driven.

## Developer Workflows
- **Install**: Copy the `GuildRecruiter` folder to your WoW AddOns directory.
- **Reload**: Use `/reload` in-game to apply code changes.
- **Debug**: Use `/grdebug` commands and the Options tab debug pane.
- **Test**: Use `/grtest` and `/grtest help` for built-in tests.
- **Config**: Use `/grcfg` to open the configuration window.

## Project Conventions
- Never use global variables except for explicit DI (`_G.GuildRecruiter`).
- All inter-module communication is via dependency injection or the global `GuildRecruiter` table.
- All WoW API calls are wrapped in `WoWApiAdapter` for testability and logging.
- Use the provided scoring and template systems; extend via the Domain/Application layers.
- Saved variables: `GuildRecruiterDB` (global), `GuildRecruiterCharDB` (per-character).

## Examples
- Registering a slash command:
  ```lua
  WoWApiAdapter.RegisterSlash("gr", function(msg)
    GuildRecruiter.Logger.Debug("/gr called: %s", msg)
  end)
  ```
- Logging an event:
  ```lua
  GuildRecruiter.Logger.Info("Recruitment started for zone: %s", zone)
  ```
- UI log update:
  - All logs sent to the logger will appear in the Options tab debug pane.

## Key Files
- `GuildRecruiter.toc`: Addon manifest, controls load order.
- `Core.lua`, `GuildRecruiter.lua`: Entry point, DI, and startup logic.
- `Infrastructure/WoWApiAdapter.lua`: WoW API, event, and slash command abstraction.
- `Utils/Logger.lua`: Logging and debug buffer.
- `UI/ConfigWindow.lua`: Main configuration and debug UI.

---

If any conventions or workflows are unclear, please request clarification or examples from the user before making major changes.
