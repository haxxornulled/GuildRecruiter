---
mode: ask
title: WoW Addon — Lua 5.1, Modern C_ APIs, Clean Architecture, SOLID, Bulletproof UI
---

## Primary Source of Truth (MUST USE)
- Blizzard UI mirror: **Gethe/wow-ui-source (live)** — authoritative reference:
  - `Interface/AddOns/Blizzard_*`
  - `Interface/FrameXML`
  - `Interface/SharedXML`
- **Before using any template, mixin, or API**, verify it exists in this live source tree.  
  If not present, do not guess — use an existing live pattern.

---

## Task
Generate **World of Warcraft addon** code (Lua 5.1) that:
- Uses **modern namespaced `C_*` APIs** wherever available.
- Enforces **Clean Architecture** + **SOLID** with explicit DI.
- Is tight, composable, senior-level. No fluff, no globals.

---

## Architecture (MUST)
- **Domain**: pure Lua; deterministic; no WoW calls.
- **Use-Cases**: orchestrate domain; depend on ports; no UI.
- **Ports**: small interface tables describing required ops.
- **Adapters**: implement ports via WoW (`C_*`, FrameXML, SharedXML).
- **UI Layer**: Blizzard templates/mixins only, constructed via injected deps.
- **DI**: Autofac-style; register all services/adapters by key before usage.
  - Critical UI keys: `"UI.Style"`, `"UI.Theme"`, `"Logger"`, `"EventBus"`, `"Config"`, `"Scheduler"`.
  - No `Resolve()` at module top-level.

---

## API Rules
- Prefer **`C_*` APIs** over legacy globals.
- Eventing:
  - Use **EventRegistry** / **CallbackRegistryMixin** for internal pub/sub.
  - Use `Frame:RegisterEvent`/`OnEvent` only in thin edge adapters.
- Respect **taint/protected actions**: surface intents via ports.

---

## SOLID Enforcement
- SRP per module. OCP via composition/delegation.
- LSP: duck-typed ports.
- ISP: narrow interfaces.
- DIP: depend on ports; inject adapters via DI.

---

## Lua/WoW Style
- Lua 5.1: no `require`, no `goto`. Return a public API table only.
- Localize globals; upvalue hot paths; avoid allocations in handlers.
- Use closures/tables over faux classes; mixins only for reuse.
- `table.concat` for strings; reuse cleared tables.
- No dead code/unused locals.

---

## Output Contract
Always output in this order:
1. **Port** (interface table)
2. **Adapter** (WoW `C_*` / FrameXML / SharedXML usage)
3. **Use-Case** (pure domain composition)
4. **Wire** (composition root)
5. **Minimal usage snippet**

---

## Allowed Patterns
Strategy, Adapter, EventBus/Observer (via EventRegistry), Factory, Decorator, Command.

---

## Banned
God-modules, hidden globals, domain calling WoW APIs, ad-hoc event plumbing.

---

## Bulletproof UI Pattern (Constructor Injection)
**Goal:** No globals, no frame field injection; UI composable/testable.  
All dependencies come through constructor. WoW APIs only inside methods.

**Contract**
- **Inputs:** `deps` table, `parent` frame.  
  `deps`: `{ Config, EventBus, Logger, ButtonLib, Theme, RuntimeCaps, SavedVarsService, ... }`
- **Output:** object with:
  - `Create(parent)`
  - `Render()`
  - `Dispose()`

**Rules**
- No `Resolve` in UI files.
- Keep all frame refs in `self.ui`.
- Use `RuntimeCaps` for `_G` safety.
- Prefer injected helper factories (`ButtonLib`, `UIHelpers`).
- Access config via `deps.Config`.
- Contextualize logger in `Create`:
  ```lua
  local log = deps.Logger and deps.Logger:ForContext("UI.Settings") or nil


