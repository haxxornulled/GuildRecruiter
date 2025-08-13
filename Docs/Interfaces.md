# Interface Contracts (Documentation Only)

These interface descriptions were previously Lua stub files under `Core/Interfaces`. They have been removed to keep `Core` free of non-domain executable artifacts. The contracts are retained here for architectural reference. Concrete implementations live under `Infrastructure`.

---
## ProspectRepository
Responsibilities:
- Save(prospect)
- Get(guid) -> Prospect|nil
- GetAll() -> array<Prospect>
- Remove(guid)
- Blacklist(guid, reason)
- IsBlacklisted(guid)
- GetBlacklist() -> table<guid, entry>
- Unblacklist(guid)
- PruneProspects(max) -> removedCount
- PruneBlacklist(max) -> removedCount

Notes: In current implementation, blacklist operations are handled by dedicated `BlacklistRepository` (SavedVariables backed). Prospect persistence is in `Infrastructure/Repositories/SavedVarsProspectRepository.lua`.

## BlacklistRepository
Responsibilities:
- Add(guid, reason?) / Blacklist(guid, reason?)
- Remove(guid) / Unblacklist(guid)
- Contains(guid) / IsBlacklisted(guid)
- GetAll() -> table<guid, { reason, timestamp }>
- GetReason(guid)
- Prune(maxKeep) -> removedCount

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

## EventBus (port)
Methods:
- Publish(event, ...)
- Subscribe(event, handler(ev, ...), opts? { namespace }) -> token
- Unsubscribe(token) -> bool
- UnsubscribeNamespace(ns) -> countRemoved
- Diagnostics(opts?) -> table (publishes, errors, events[])

## Clock (port)
Methods:
- Now() -> high resolution seconds (float)
- Epoch() -> integer seconds (time())

Implementation: `Infrastructure/Time/Clock.lua` (GetTime/time adapters) and headless harness deterministic clock for tests.

---
Generated relocation to satisfy Clean Architecture (Core == pure domain + primitives).
