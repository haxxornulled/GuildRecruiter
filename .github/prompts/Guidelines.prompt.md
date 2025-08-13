---
mode: ask
title: Tight, Law-Abiding Lua — Clean Architecture + SOLID + Patterns
---

## Task
Generate **Lua 5.1** code that is minimal, composable, and adheres to **Clean Architecture**, **SOLID principles**, and **battle-tested design patterns**.  
Target environment may include **World of Warcraft addon constraints** (no `require`, no globals, localized API calls).  

## Requirements
- Code must be **as concise and elegant as a well-defined Monad implementation**.
- Follow Clean Architecture layers:
  1. **Domain**: pure, no I/O, testable in isolation.
  2. **Application / Use-Cases**: orchestrates domain logic.
  3. **Ports / Interfaces**: abstract contracts (tables with functions).
  4. **Adapters**: implementations that talk to infra, UI, or game APIs.
- Apply SOLID:
  - SRP: one reason to change per module.
  - OCP: extend via composition, not edits.
  - LSP: behavior must be substitutable.
  - ISP: narrow, focused contracts.
  - DIP: depend on abstractions, inject concretions.
- Patterns encouraged: Strategy, Adapter, EventBus/Observer, Factory, Decorator, Command.
- Patterns banned: God-modules, needless class emulation, hidden globals.

## Constraints
- **Lua idioms**: localize everything, prefer closures/tables over faux-OOP, avoid table allocations in hot paths, use `table.concat` not string loops.
- No unused locals, imports, or dead code.
- Public API is clearly documented in 1–2 lines max.
- No trivial syntax commentary — assume senior-level reader.

## Success Criteria
- Code is **tight, law-abiding**, and composes cleanly.
- No global pollution.
- Complies with monad/functor laws where applicable.
- Domain layer runs without the runtime environment (pure Lua).

## Output Style
- Prefer: port (interface table), implementation (adapter), factory (wire), use-case (domain), small usage example.
- Reject: monolithic blobs, leaking domain into adapters, inline globals.
- If unsure, propose the smallest composable abstraction possible.

## Example Skeleton
```lua
-- Port
local ClockPort = { now = function() end }

-- Domain (pure)
local function makeIsExpired(ttlSeconds)
  return function(clock, startedAt)
    return (clock.now() - startedAt) >= ttlSeconds
  end
end

-- Adapter
local function makeOsClock()
  return { now = function() return os.time() end }
end

-- Use-case
local function makeSessionService(deps)
  local isExpired = makeIsExpired(deps.ttlSeconds)
  return { expired = function(startedAt) return isExpired(deps.clock, startedAt) end }
end

-- Usage
local clock = makeOsClock()
local svc = makeSessionService({ clock = clock, ttlSeconds = 3600 })
-- print(svc.expired(os.time() - 4000))
