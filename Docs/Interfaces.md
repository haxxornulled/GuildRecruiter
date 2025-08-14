# Interface Contracts (Current)

These contracts live under `Core/Interfaces` as lightweight Lua descriptors and are registered into the DI container as well-known keys. Concrete implementations live under `Infrastructure` and are provided with the same keys (aliases where applicable).

Active interfaces (non-exhaustive):
- `IConfiguration` — read-only config surface (flags like `devMode`).
- `IServiceProvider` — DI scope surface for resolving registered services.
- `IScheduler` — timers, debounce/throttle, namespaces.
- `IEventBus` — pub/sub with diagnostics.
- `ISlashCommandHandler` — register and handle `/gr ...` commands.
- `IProspectsService` — use-cases over prospects and blacklist.
- `IProspectManager` — main controlling service (single entry point for mutations: blacklist/unblacklist/remove/prune/invite).
- `IInviteService` — safe invitation flows and decline detection.
- `IPanelFactory` — UI panel creation/resolution by key with lazy construction.
- `IProspectsReadModel` — read-only query surface implemented by `ProspectsDataProvider`. Consumers MUST resolve this interface; never resolve the concrete provider.

Notes:
- Interfaces are pure contracts; they should not call WoW APIs directly.
- Implementations reside in `Infrastructure/*` and are registered with metadata indicating layer/role for diagnostics.

---
## PanelFactory (UI contract)
Key: `IPanelFactory`

Responsibilities:
- GetPanel(key) -> Frame (creates on first request; caches thereafter)
- List() -> string[] (optional, for diagnostics/menus)
- RegisterPanel(key, builderFn) (implementation-side registry)

Default implementation: `Infrastructure/UI/PanelFactory.lua`. Panels are registered centrally in `UI/UI_PanelRegistry.lua` and created lazily when requested by `UI_MainFrame`.

---
## Prospects stack (current)
- IProspectManager: controlling service for mutations and orchestration.
- ProspectsService (Application): pure use-cases over SavedVarsService (no WoW APIs).
- ProspectsDataProvider (Infrastructure): implements IProspectsReadModel; read-only cache for UI (filter/sort/page/stats); subscribes to `Prospects.Changed`.
- SavedVarsService (Infrastructure): namespaced SavedVariables adapter (Get/Set/Assign/Prune/Sync).

### Read/Write flow overview
- Writes: UI/Slash/Services → IProspectManager → ProspectsService → SavedVarsService → publishes `Prospects.Changed`
- Reads: IProspectsReadModel (implemented by ProspectsDataProvider) → SavedVarsService; subscribes to `Prospects.Changed`; exposes GetAll/GetFiltered/GetPage/GetByGuid/GetStats/GetVersion

Notes:
- UI must call IProspectManager for actions. The read side is accessed via IProspectsReadModel only.
- No concrete fallbacks: if DI wiring breaks, fix registration/order; do not resolve `ProspectsDataProvider` directly from consumers.
- Invite flows go through InviteService; IProspectManager exposes InviteProspect for UI convenience.

### Read-only interface: IProspectsReadModel
Purpose: make the read side explicit and enforce that consumers cannot mutate prospects directly. Implemented by `Infrastructure/Providers/ProspectsDataProvider.lua` and provided as `IProspectsReadModel`.

Suggested surface:
- GetAll() -> table[]
- GetFiltered(filterFn | predicateTable?) -> table[]
- GetPage(opts { pageSize, page, sort? { key, dir }, filter? }) -> { items = table[], total = number, page = number, pageSize = number }
- GetByGuid(guid) -> table? (O(1) via internal byGuid map)
- GetStats() -> table (counts, by-role, by-level, blacklist size, etc.)
- GetVersion() -> number (monotonic increment on changes; useful for UI memoization)

Why this interface helps:
- Enforces CQRS split: UIs/services can depend on a read-only contract, preventing accidental writes outside IProspectManager.
- Increases testability: easy to swap a fake read model in headless harnesses or unit tests.
- Future-proofing: allows alternative read models (e.g., remote source, pre-filtered indices) without changing consumers.
- Smaller surface area: keeps UI dependencies stable and simple.

---
## UI/UX principles for Recruitment

1) Principles We Keep
- Frames via Lua only — no XML, no legacy art.
- Use NineSlice only when we want seamless reskinning for future patches.
- Use UIPanelLayout rules only if integrating with the Escape menu stack.

2) Principles We Ditch
- Default ChatFrame tab visuals and filtering — we own our tab visuals and filtering logic.
- Massive empty frame padding — every pixel has a purpose; minimal chrome.
- 2004-era nested scroll templates — replace with lean scrolling logic that doesn’t overdraw.

3) UI Psychology for Recruitment
- Always-Accessible but Never Cluttered: Sidebar collapsed state ≈ 40px with iconic glyphs (guild crest, +invite, settings). Hover expansion or click-to-lock open.
- Context-Driven Controls: Show “Invite” only when eligible and not already invited. Show “Blacklist” only after interaction/decline.
- Fluid Chat: Recruitment chat behaves like a Discord-style overlay; resizable & draggable with a corner grip; optional auto-close on combat.

4) Addon UX Flow (New Prospect)
- Sidebar glows subtly (no full-screen alerts).
- Hover → player card (name, ilvl, roles, mutuals, note field).
- Click → opens slim recruitment chat docked bottom-left.
- On conversation end or invite sent → chat auto-collapses; sidebar remains.

5) Why This Beats Blizzard’s Layout
- Shorter eye travel: no hunting across the screen.
- Less mode switching: one sidebar handles scanning, chatting, inviting.
- High signal-to-noise: avoids “always-on” giant windows.

Implementation hints
- Resizing: prefer a simple corner grip (no Blizzard ResizeButton) and SetResizable/StartSizing/StopMovingOrSizing handlers.
- Overlay chat: use a dedicated frame strata/layer, fade-in/out on show/hide, throttle updates to avoid overdraw.
- Escape stack: opt-in only when a panel must participate; otherwise keep custom close semantics.

## Logger (port)
Methods:
- Trace/Debug/Info/Warn/Error/Fatal(template, props?, ex?)
- ForContext(key, value) -> Logger (adds single key/value)
- With(propsTable) -> Logger (adds multiple properties)
Semantics: Structured template rendering replacing `{Property}` tokens with values from merged context.

## Scheduler (port)
Methods:
- Start()/Stop()
- NextTick(fn)
- After(delay, fn, opts?)
- Every(interval, fn, opts?)
- Cancel(token)
- CancelNamespace(namespace) -> count
- Debounce(key, window, fn, opts?)
- Throttle(key, window, fn, opts?)
- Coalesce(bus, event, window, reducerFn, publishAs?, opts?) -> handle { unsubscribe() }
 - Diagnostics() -> { tasks, peak, ran }

Notes:
- Always supply a `namespace` in opts for recurring or grouped tasks you might cancel later via `CancelNamespace`.
- Debounce/Throttle are test-covered; Coalesce enables batching high-frequency events into one publish.

## EventBus (port)
Methods:
- Publish(event, ...)
- Subscribe(event, handler(ev, ...), opts? { namespace }) -> token
- Unsubscribe(token) -> bool
- UnsubscribeNamespace(ns) -> countRemoved
- Diagnostics(opts?) -> table (publishes, errors, events[])
 - Once(event, fn, opts?) -> token (fires only once)

Notes:
- Use the `Events` constants module (`Core/Events.lua`) rather than raw strings for addon-defined events (e.g. `Events.Prospects.Changed`).
- Always namespace UI subscriptions (e.g. `{ namespace='UI.Prospects' }`) for bulk teardown.
- `Once` is preferred for bootstrap or readiness events to avoid manual unsubscribe.

## Clock (port)
Methods:
- Now() -> high resolution seconds (float)
- Epoch() -> integer seconds (time())

Implementation: `Infrastructure/Time/Clock.lua` (GetTime/time adapters) and headless harness deterministic clock for tests.

---
Generated relocation to satisfy Clean Architecture (Core == pure domain + primitives).

## Unified Prospect Event Contract
All prospect mutations publish a single event: `Events.Prospects.Changed` with an action as first argument. Actions include `added`, `updated`, `removed`, `blacklisted`, `unblacklisted`, `pruned`.

## Diagnostics Consumption
Slash command `/gr diag` aggregates:
- EventBus diagnostics (publishes/errors/handler counts)
- Scheduler diagnostics (tasks, peak, ran)
- DI scope/registration counts
- Prospect read model stats

Programmatic pattern:
```
local bus = Addon.ResolveOptional and Addon.ResolveOptional('EventBus')
if bus then local bdiag = bus:Diagnostics() end
```

Diagnostics are side-effect free and safe in UI contexts.
