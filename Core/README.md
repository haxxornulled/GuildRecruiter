# Core: DI container, entities, collections

This folder contains the lightweight Autofac-style DI container and foundational types used across the addon. It’s WoW-safe (Lua 5.1), has no external deps, and is designed for Clean Architecture layering.

## Concepts
- Registration: map a key (string) to a factory or constant via `Addon.provide(key, factoryOrValue, { lifetime })`.
- Lifetimes: `SingleInstance` (singleton), `InstancePerLifetimeScope` (scoped), `InstancePerDependency` (transient). Most services are singletons.
- Resolution: `Addon.require(key)` (strict) or `Addon.Get(key)` (safe optional). You can also use `Core.Builder()` and `scope:Resolve(key)` directly.
- Decorators: Wrap an existing registration using `AsDecorator(key)`. Decorators are applied outermost = last-registered.
- Parameters: Factories can accept `params` evaluated per-resolution via `WithParameter(name, constOrFunc)` or override at resolve-time.
- Lifecycle: If an instance implements `Start()`/`Stop()`, they’re called automatically when created/disposed by the container.

## Quick start
Register a singleton service

```
-- MyService.lua
local _, Addon = ...
local function CreateMyService(scope)
  local logger = scope:Resolve("Logger"):ForContext("MyService")
  local self = {}
  function self:Start() logger:Info("Started") end
  function self:DoThing(x) logger:Debug("Doing {X}",{ X=x }) end
  return self
end
if Addon.provide then
  Addon.provide("MyService", CreateMyService, { lifetime = "SingleInstance" })
end
return CreateMyService
```

Resolve and use it elsewhere

```
local _, Addon = ...
local svc = Addon.require("MyService")
svc:DoThing(42)
```

Provide a constant value

```
Addon.provide("MyConfig", { threshold = 5 }, { lifetime = "SingleInstance" })
```

Register safely (idempotent) during migration

```
Addon.safeProvide("Foo", FooFactory, { lifetime = "SingleInstance" })
```

## Decorators

```
-- Add timing around Logger
local _, Addon = ...
local function TimingDecorator(scope, params)
  local inner = params.inner -- function returning the wrapped instance
  local base = inner()
  local logger = scope:Resolve("Logger"):ForContext("Logger.Timing")
  local proxy = {}
  function proxy:Info(t,p)
    local t0=GetTime(); base:Info(t,p); logger:Debug("Info took {ms}ms",{ ms=(GetTime()-t0)*1000 })
  end
  return setmetatable(proxy, { __index = base })
end
-- Register as a decorator of the existing key
Core.Builder():Register(TimingDecorator):AsDecorator("Logger") -- when manually composing
```

Note: When using the global `Addon.provide`, register decorators by building a module that receives the builder; or adapt using the container’s `Register` API in a central wiring point. The project primarily uses regular singletons and avoids decorators unless needed.

## Factory signature & hooks
Factories receive `(scope, params)` and may use lifecycle hooks via the builder API (used internally by the container):
- OnPreparing(scope, ctx) — edit `ctx.Parameters` before construction
- OnActivating(scope, instance, ctx)
- OnActivated(scope, instance, ctx)
- OnRelease(instance) — called on disposal before `Stop()`

Error mode: any error during `Start()`/hook execution is surfaced with a readable activation trace and cycle detection like `A -> B -> C -> A`.

## Diagnostics & debugging
- List registered keys: `Addon.ListRegistered()` (returns sorted array of keys)
- Dispose container: `Addon.DisposeContainer()` (via namespace export `_G["GuildRecruiter"]` ns)
- Slash diagnostics: `/gr diag`, `/gr diag regs`, `/gr diag events`
- Boot trace: `Init.lua` publishes `GuildRecruiter.ServicesReady` and `GuildRecruiter.Ready` on EventBus.
- Optional dev: in chat, `/run Core and GuildRecruiter_Addon and print("ok")` to sanity check scope globals.

## Edge cases & tips
- Boot phase: `Addon._booting` prevents using facades early; resolve services inside `Init.lua` after registration.
- Duplicate registrations: throws unless `devMode` is true. Use `Config.devMode = true` to allow overrides while iterating.
- Circular dependencies: container reports a full resolution chain, only when an actual cycle occurs.
- Parameter overrides: resolve like `Addon.require("Foo", { Parameters = { bar = 123 } })` to override a factory parameter.

## Collections recap
Exposed via both short and namespaced keys; also assigned on `Addon.*` for convenience:
- `List` / `Collections.List` — LINQ-style arrays
- `Queue` / `Collections.Queue` — FIFO
- `Dictionary` / `Collections.Dictionary` — key-value store with LINQ helpers
- `AccordionSections` / `Collections.AccordionSections` — small UI helper wrapper

## Interface notes
- `Core/Interfaces/*.lua` are documentation stubs to describe contracts used by application services. Implementations live under `Infrastructure/*` and register their concrete types into DI with the interface’s well-known key (e.g., `ProspectRepository`).

## User commands
See `Docs/SlashCommands.md` for all `/gr` aliases and usage.
