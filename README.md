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

### Collections: Queue & AccordionSections
The addon ships with lightweight collection abstractions used internally and available for features.

#### Queue (FIFO)
File: `Collections/Queue.lua`

API:
```lua
local Queue = Addon.require("Collections.Queue")
local q = Queue.new()
q:Enqueue("a"):Enqueue("b")            -- chainable
print(q:Peek())                           -- "a" (does not remove)
local first = q:Dequeue()                 -- "a"
print(q:Count(), q:IsEmpty())             -- 1, false
for item in q:Iter() do print(item) end   -- iterates remaining items ("b")
q:Clear()                                 -- empties queue

-- Optional: convert to List (only if List module loaded)
local list = q:ToList()                   -- returns List or nil
```

Notes:
- Amortized O(1) enqueue/dequeue using head/tail indices.
- Periodic compaction keeps memory bounded.
- Safe to store any Lua value (including tables / frames).

#### AccordionSections
Implemented in `Collections/AccordionSections.lua` and required by the Accordion component (`CreateAccordion`). It abstracts how accordion sections are stored (raw table vs List) so calling code gets a stable API. Narrow name reduces namespace noise.

API (methods on `frame.sections`):
```lua
local acc = UIHelpers.CreateAccordion(parent, defs, opts)
local sections = acc.sections              -- AccordionSections instance
local count = sections:Count()
for i=1,count do
	local sec = sections:Get(i)
	-- sec.key, sec.content, sec.editBox, sec._expanded
end
sections:ForEach(function(sec, index)
	print(index, sec.key)
end)
```

Usage Tips:
- Prefer the provided accordion API (`acc:Open(key)`, `acc:CloseAll()`, etc.) for behavior changes; use AccordionSections only for inspection or advanced customizations.
- Each section frame exposes: `key`, `content` (container frame), `editBox` (if auto-generated), `_expanded` (boolean state), `arrow` (fontstring), and `titleFS`.
- Dynamic APIs available: `acc:AddSection(def)`, `acc:RemoveSection(key)`, `acc:RemoveAllSections()`, `acc:GetSection(key)`.

Planned Enhancements:
- Already extracted to `Collections/AccordionSections.lua` and registered as both `AccordionSections` and `Collections.AccordionSections`.
- Public `AddSection/RemoveSection` helpers on the accordion frame.

If you interact with these abstractions externally, keep SOLID in mind: isolate queue/section logic from rendering or business rules.

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
BSD 3-Clause. Collective anonymous authorship ("Distributed Cloud of Sentient Macros"). See LICENSE.
