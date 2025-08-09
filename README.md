# GuildRecruiter

World of Warcraft addon to streamline guild recruiting.

## Features
- Prospect management
- Blacklist / do-not-invite tracking
- Rotational broadcast messages
- Structured DI (Autofac-style) container for services
- EventBus + Scheduler + Logger subsystems
- LINQ-like collection library (List, Dictionary, Extensions)

## Install
Copy the `GuildRecruiter` folder into your WoW `Interface/AddOns` directory.

Windows Retail path example:
```
World of Warcraft/_retail_/Interface/AddOns/GuildRecruiter
```

## Slash Commands
```
/gr ui         Toggle main UI
/gr settings   Open Settings panel
/gr diag       Diagnostics snapshot
```

## Architecture Highlights
- Core DI container (lifetime scopes, decorators, circular detection)
- Phased boot: factory registration → warm resolve → service Start()
- Structured logging (multi-sink, level switch)
- EventBus bridging WoW events
- SavedVariables config with migration + change events
- LINQ-style collections for ergonomic data operations

## Development
Symlink or clone into AddOns. Use `/reload` in-game after edits.

### Package
A PowerShell packaging script is provided:
```
pwsh ./tools/package.ps1
```
Creates `release/GuildRecruiter-vX.Y.Z.zip` based on version in `GuildRecruiter.toc`.

## Testing Ideas
- `/gr diag` after reload to confirm service wiring
- Inspect log buffer (Logger ring buffer) after actions
- Trigger Config changes and observe `ConfigChanged` EventBus publications

## License
MIT
