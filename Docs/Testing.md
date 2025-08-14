# Testing Infrastructure

This addon includes headless and in-game test layers to validate core logic, diagnostics, and integration.

## Layout
- `tools/tests/*.lua` — headless specs (executed outside WoW via Lua 5.1/JIT environment) using `HeadlessHarness`.
- `tools/tests/ingame_*.lua` — in-game specs only run when `Addon.RegisterInGameTest` is present (skipped headless).
- `tools/tests/run_all.lua` — auto-discovers every `*spec.lua` file in the directory and executes them.

## Headless Harness
File: `tools/HeadlessHarness.lua`
Features:
- Minimal Addon table with `provide/require` DI mimic.
- Deterministic scheduler (manual time via `Harness.Advance(dt)`).
- Pure EventBus with publish capture (`Addon.TestEvents`).
- Assertion helpers: `AssertEquals/True/False/AssertEventPublished`.
- Logger buffer sink for visibility without WoW chat frame.

## Specs Coverage (Key Areas)
- Prospects CRUD / blacklist / pruning events.
- Unified `Prospects.Changed` actions (added/updated/removed/blacklisted/unblacklisted/pruned).
- EventBus `Once` and diagnostics shape.
- Scheduler debounce, throttle, coalesce, diagnostics.
- ProspectStatus constants & helper predicates.
- AutoPruneService pruning publish.
- DI circular dependency detection (real Registration + Scope).

## Writing New Specs
1. Require the harness: `local Harness = require('tools.HeadlessHarness')`.
2. Resolve or register dependencies; load production files with `dofile` if necessary.
3. Use `Harness.AddTest(name, fn)`.
4. For event tests: call `Harness.ClearEvents()` before the action and `AssertEventPublished()` after.
5. For time-based logic: call `Harness.Advance(seconds)` to trigger scheduler execution.

## Event Constant Usage
Always resolve `Events` (DI key) instead of embedding raw strings:
```
local E = Addon.ResolveOptional and Addon.ResolveOptional('Events')
local EV = (E and E.Prospects and E.Prospects.Changed) or 'Prospects.Changed'
```

## In-Game Tests
- Provide higher confidence around Invite/Queue/Broadcast flows under real WoW APIs.
- Guarded early: if `RegisterInGameTest` missing, spec returns immediately.
- Avoid heavy loops; keep execution fast to prevent UI hitching.

## Running Tests (Headless)
From addon root (PowerShell example):
```
lua tools/tests/run_all.lua
```
(Adjust path / interpreter name depending on local Lua installation.)

## Adding Diagnostics Assertions
Diagnostics are stable contracts; shape changes should be deliberate. Example:
```
local bus = Addon.require('EventBus')
local d = bus:Diagnostics()
Addon.AssertTrue(d.publishes >= 0)
```

## Flakiness Avoidance
- No reliance on wall-clock; pure logical advancement.
- Single event channel simplifies ordering guarantees.
- Avoid randomization; explicit sequences only.

## Future Enhancements
- Performance micro-bench harness (publish throughput, scheduler task insertion cost).
- Golden snapshot tests for diagnostics JSON.
- CI script to run `run_all.lua` automatically.
