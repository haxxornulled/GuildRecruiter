# Guild Prospector Architecture

> Note: The addon was previously titled "Guild Recruiter"; references in code or historical documents may still use the legacy name.
# Clean Architecture Refactor (Phase 1)

This addon is being migrated toward a Clean Architecture style segmentation:

Layers:
1. Core (Domain): Pure business entities and interfaces (no WoW API). Example: `Core/Entities/Prospect.lua`, `Core/Interfaces/ProspectRepository.lua`.
2. Application (Use Cases): Orchestrates domain logic, coordinates repositories & publishes domain events. Example: `Application/Services/ProspectService.lua`.
3. Infrastructure (Adapters): Implements interfaces using WoW SavedVariables, EventBus, Scheduler, etc. Example: `Infrastructure/Repositories/SavedVarsProspectRepository.lua`.
4. UI (Presentation): Frames, panels, XML/Lua UI logic consuming Application services only (avoid direct infra access over time).

Phase 1 Goals:
- Introduce folder structure & initial abstractions without breaking existing functionality.
- Provide a `ProspectRepository` + `ProspectService` that wrap existing DB schema progressively.
- Keep legacy `Recruiter` service operational while UI migrates.

Next Steps (Future Phases):
- Extract blacklist logic fully into repository & service (remove duplication in `GuildRecruiter.lua`).
- Refactor UI controllers to call `ProspectService` instead of `Recruiter` / `ProspectsManager`.
- Introduce dedicated event definitions (domain events) and reduce direct WoW API usage in domain/application layers.
- Add automated tests for repository and service behaviors (mock SavedVariables table).

Guidelines:
- Core layer must not require `Addon` or call WoW APIs.
- Application can depend on Core interfaces and simple platform abstractions (EventBus interface in future).
- Infrastructure wires concrete implementations with DI (`Addon.provide`).
- UI depends on Application (and maybe Core for read-only types) but not on Infrastructure.

Temporary Coexistence:
- `GuildRecruiter.lua` (legacy) still manages capture & queue; treat it as Infrastructure until its logic migrates.
- `ProspectsManager` acts as an adapter for older UI code; mark it deprecated and plan removal.

Migration Path:
1. Replace UI reads of prospects with `ProspectService:GetAll()`.
2. Replace blacklist calls with `ProspectService:Blacklist/Unblacklist`.
3. Remove direct DB table mutations from UI.
4. Shrink `GuildRecruiter.lua` to capture-only, then move capture into an Application orchestrator.

This document will evolve as refactor progresses.

See also: Docs/EmbeddedChatPanel.md for the embedded chat panel concept and architecture sketch; Docs/SlashCommands.md for user-facing command usage.

## 2025-08 Update Highlights

- Introduced `IPanelFactory` contract (Core/Interfaces) and default implementation (`Infrastructure/UI/PanelFactory.lua`). UI panels are now registered centrally (`UI/UI_PanelRegistry.lua`) and created lazily on demand by `UI_MainFrame`.
- Moved `ProspectsManager` to `Infrastructure/Services` and export it as `IProspectManager` for consumers; UI should prefer the interface alias.
- Consolidated interface stubs under `Core/Interfaces` (keys are provided for DI inspection); see `Docs/Interfaces.md`.
- Fixed DI diagnostics by building the container post-registrations in bootstrap, so `/gr diag` shows accurate counts.
- UI refinements: sidebar icons have no hover effects; the chat mini toggle uses a chat-bubble icon whose desaturation/alpha reflects collapsed state.
- Unified prospect mutation events: all adds/updates/removals/blacklist/prune actions now publish a single canonical `Prospects.Changed` event (action, guid|count). Removed legacy granular events (`ProspectAdded`, etc.) to simplify the reactive surface and reduce subscriber churn.
- Added structured constants module `Core/Events.lua` (DI key `Events`) eliminating magic event strings and enforcing compile-time discoverability in tests & UI.
- Expanded diagnostics surface: `/gr diag` aggregates EventBus publishes/errors, Scheduler queue stats (tasks, peak, ran), DI scope counts (services, singletons), and prospect read model counts. `/gr di` now dumps container registrations and scope diagnostics.
- Added `ProspectStatus` constants & predicates (IsNew/IsActive/IsBlacklisted/List) for consistent filtering & UI coloring.
- Added `AutoPruneService` (config-driven background pruning) that emits a `Prospects.Changed` action `pruned` summarizing removals.
- Hardened DI with circular dependency detection (emits full resolution path on error) and scope diagnostics (`scope:Diagnostics()`).
- Headless test harness extended: deterministic Scheduler & EventBus, plus new specs for EventBus Once, Scheduler debounce/throttle/coalesce, AutoPrune pruning publish, status helpers, and DI cycle detection.

## OOP + DI (Constructor Injection)

We now have a lightweight `Class` helper (`Core/OOP/Class.lua`) and the Autofac-style DI container (`Core/Core.lua`). To combine the two cleanly we follow these patterns:

1. Define a class with an `init` accepting its dependencies explicitly.
```
local Class = Addon.require('Class')
local MyService = Class('MyService', {
	init = function(self, logger, clock)
		self.logger = logger
		self.clock = clock
	end,
	Tick = function(self)
		self.logger:Debug('Tick at {T}', { T = self.clock:Now() })
	end
})
```
2. Register a factory that resolves dependencies first, then constructs the class instance:
```
Addon.provide('MyService', function(scope)
	local logger = scope:Resolve('Logger'):ForContext('MyService')
	local clock = scope:Resolve('Clock')
	return MyService(logger, clock) -- ctor injection
end, { lifetime = 'SingleInstance' })
```
3. Optional syntactic sugar (future): a helper that inspects a static `__deps` array on the class and injects automatically. (Planned.)

Rationale: Keep the DI container uninvolved with reflection/meta; constructor injection stays explicit and discoverable, mirroring C# Autofac style without magic strings sprinkled across code.

Planned Improvement: introduce `Addon.ClassProvide(name, class, opts)` that:
```
-- class.__deps = { 'Logger', 'Clock' }
-- Builds: local deps = map(scope:Resolve(dep) ...); return class(unpack(deps))
```
This will reduce boilerplate for simple service registrations.

## Layer rules (Separation of Concerns)

We align with Clean Architecture and WoW’s runtime model. Each layer has clear responsibilities and allowed APIs:

- UI (Presentation + Composition)
	- Owns Composition Root (UI/CompositionRoot.lua) and screens/pages.
	- May use frame/presentation APIs: CreateFrame, templates, textures, fonts, dropdown helpers, basic input helpers, portrait helpers.
	- Must not call platform/system APIs directly (chat/addon messaging, timers, saved variables, event registration) — instead, call services from Infrastructure via DI (EventBus, Scheduler, ChatRouting, SavedVarsService, RuntimeCaps).

- Application (Use Cases)
	- Orchestrates domain logic; depends on service contracts only.
	- No direct WoW API usage; no frame creation.

- Core (Domain)
	- Pure Lua: entities, contracts, collections, small utilities.
	- Absolutely no WoW API usage.

- Infrastructure (Adapters)
	- Master of WoW APIs: implements services that wrap platform concerns (EventBus bridge, Scheduler/C_Timer, SavedVars, ChatRouting, RuntimeCaps, etc.).
	- No UI code; expose capabilities via DI keys/interfaces consumed by Application/UI.

Practical effects
- UI wires services and consumes them; Infrastructure implements them. Application/Core stay platform-agnostic.
- New API touchpoints should be added as Infrastructure services, then injected via DI into callers.

## WoW addonTable as a shared state container

Why we use it:
- Deterministic lifecycle: The WoW client executes every file listed in your `.toc` as a function call with two arguments: `(addonName, addonTable)`. The same `addonTable` instance is passed to every file of the addon, acting as a built‑in module/state container.
- No globals required: By relying on `addonTable`, files share state and APIs without polluting `_G` or assuming global symbols are available early in load order.
- Cheap and safe: Passing/receiving two locals is trivial overhead in Lua 5.1; it’s more efficient and reliable than searching in `_G` or creating extra module wrappers.
- Interop with our DI: We attach DI helpers (`provide`, `require`, etc.) onto this table once (in `Core/Core.lua`) so any file can register/resolve services via the same container.

What we do in files:
- Always start with: `local ADDON_NAME, Addon = ...` (or an analyzer‑friendly variant) and then use `Addon` for shared state and DI.
- Avoid fallbacks like `rawget(_G, 'GuildRecruiter')`; if `Addon` isn’t a table, that indicates a load‑order or packaging problem that should be fixed, not masked.

Interface with DI:
- `Core/Core.lua` exports the container to the addon namespace, so `Addon.provide/require` work anywhere once Core is loaded.
- Our `ClassProvide` reads `class.__deps` and resolves dependencies from the container, then constructs the class—clean constructor injection with minimal boilerplate.

Runtime guarantees (WoW):
- The same `addonTable` is passed to each addon file exactly once at load time.
- Return values from addon files are ignored by the WoW loader; side effects (registrations) are how modules integrate.
- WoW API globals (e.g., `time`, `CreateFrame`) exist at runtime; we declare them in `.luacheckrc` to keep linters quiet without changing runtime logic.

Bottom line: Treat `addonTable` as the addon’s shared state/DI surface. It’s the most direct, efficient, and idiomatic way to coordinate modules in a WoW addon.

## Unified Event Model

The addon intentionally collapsed multiple fine-grained prospect mutation events into a single high-signal channel:

`Prospects.Changed`  (action, arg)

Actions currently emitted:
- `added` (guid)
- `updated` (guid)
- `removed` (guid)
- `blacklisted` (guid)
- `unblacklisted` (guid)
- `pruned` (countRemoved)

Rationale:
- Fewer subscriptions and frame script closures → lower GC churn.
- Simplified test assertions (one event constant everywhere) and less brittle UI refresh logic.
- Extensible: new actions can be appended without creating more global string keys or subscription fan-out.

Consumers pattern match on the first arg (`action`) and branch accordingly. Where high-volume UI sections need optimized diffs, they can batch or throttle using the Scheduler's debounce/coalesce helpers.

## Diagnostics Surface

Diagnostics are first-class to aid iterative refactors:
- EventBus: `bus:Diagnostics({ withHandlers=true })` reports publishes, errors, and handlers per event. `/gr diag` reads this.
- Scheduler: `Scheduler:Diagnostics()` returns `{ tasks, peak, ran }` used for performance tuning of coalesced or throttled workloads.
- DI Scope: every scope exposes `scope:Diagnostics()` with counts (services, decorators, singletons, scopedInstances, chainDepth). The root scope is inspected in slash diagnostics.
- Prospects Read Model: service & data provider expose counts consumed by `/gr diag` for quick inventory sanity checks.

Headless specs assert shape & sanity of these diagnostics to prevent silent regressions when optimizing internals.

## Testing Infrastructure

Location: `tools/tests/` executed via `run_all.lua` (auto-discovers `*spec.lua`). Key pieces:
- `HeadlessHarness.lua`: lightweight Addon + deterministic Scheduler & EventBus; assertion helpers (`AssertEquals`, `AssertEventPublished`, etc.).
- Domain & infra specs: prospects CRUD, blacklist, pruning, EventBus Once, Scheduler utilities, status predicate correctness, AutoPrune publish, DI cycle detection.
- In-game specs (`ingame_*.lua`): executed only when inside WoW with `Addon.RegisterInGameTest` present; validate integration points (queue, invite, broadcast flows, in-game events).

Guidelines for new specs:
- Prefer resolving the `Events` constant table instead of hard-coded strings.
- Use `Harness.ClearEvents()` before event-publish assertions to avoid cross-test noise.
- Keep tests deterministic (no reliance on wall-clock; use `Harness.Advance(dt)` for scheduler time travel).

Planned future additions:
- Namespace unsubscribe & cancel coverage (EventBus:UnsubscribeNamespace, Scheduler:CancelNamespace) — partial tests pending.
- Extended performance smoke tests measuring publish latency under synthetic load.



## Startup policy (no warm-up)

- Services are registered at load time, but instances are resolved lazily.
- The bootstrap has three phases: Register, Optional Eager Resolve (disabled by default), and Start.
- We do not use a "WarmUp" phase. Setups that need initialization should implement `Start()` and will be invoked in Phase 3.
- Eager resolves are discouraged; the composition root passes `skipResolve = true` to enforce lazy behavior.
- Logging is an Infrastructure concern. The `Logger` is registered as a factory and exported via a lazy proxy (`Addon.Logger`) to avoid accidental boot-time resolution.

