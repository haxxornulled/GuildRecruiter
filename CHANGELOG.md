# Changelog

## alpha-v1 (Initial modular rewrite)

Massive refactor introducing a cleaner core architecture and extensive tooling.

### Added
- Modular Dependency Injection split into `Core/DI/Registration.lua`, `Scope.lua`, `Container.lua` (cycle detection, diagnostics).
- Unified event constants in `Core/Events.lua` and prospect status constants in `Core/ProspectStatus.lua`.
- New infrastructure services:
  - `AutoPruneService` (automatic pruning with unified Prospects.Changed 'pruned' action)
  - `BroadcastService` (templated channel rotation + cooldown & skip reasons)
  - `CaptureService` (passive prospect capture via target / mouseover / nameplates)
  - `QueueService` (runtime queue façade with stats & repair)
- UI components:
  - `VerticalTabs` generic component
  - `MainTabsHost` wiring CategoryManager to tabbed content
  - `ToastService` lightweight notification queue
- Expanded interfaces (`IBroadcastService`, `IToastService`).
- Localization scaffold (`Localization.lua`).
- Extensive headless + in‑game test harnesses (`tools/tests`, `InGameTestRunner.lua`, `TestContext.lua`).
- Performance micro-bench harness (`tools/perf_bench.lua`).
- Diagnostics improvements & slash command enhancements (bench history, snapshot encoding).

### Changed
- Removed legacy multi-file framework reference `FrameworkRef/lua-typeclass-lib` and migrated to lean internal constructs.
- Replaced scattered event strings with centralized constants; unified multiple prospect events into single `Prospects.Changed` with action argument.
- Core DI no longer uses Lua `require` at runtime (WoW safe); falls back gracefully if split modules not yet present.
- Root scope initialization fixed to prevent `_root` nil errors.

### Fixed
- Circular dependency reporting now accurate (no mislabeling activation errors as cycles).
- Event subscription timing race in `UI_CategoryDecorators` (soft fallback to raw string when constants not yet registered).
- Potential crash on missing Events constants in early UI load.

### Diagnostics & Instrumentation
- `/gr diag` extended snapshot encoder for stable golden test.
- `/gr bench` now persists rolling history (SavedVariables ring buffer).
- Golden snapshot tests ensure diagnostics contract stability.

### Testing
- Added specs covering: EventBus once, namespace unsubscribe, scheduler debounce/throttle/coalesce, DI cycle detection, prospect status predicates, pruning (prospects + blacklist), auto prune service, broadcast skip/sent, queue & invite integration, in-game prospect operations, diagnostics snapshot.

### Removed / Deprecated
- Legacy dynamic event flattening & obsolete multi-event emissions.
- External typeclass library and unused migration artifacts.

### Notes
This is an alpha cut; APIs and file layout may change rapidly. Use for evaluation & feedback, not production deployment.

---
Next targets (post-alpha):
- Full indentation / lint normalization (`Core/Core.lua`, `Core/DebugCommands.lua`).
- Additional UI polish & panel migrations.
- Config persistence refinements and broadcast template variables.
- More granular performance benchmarks & memory profiling.
