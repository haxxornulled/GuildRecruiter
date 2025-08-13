# GuildRecruiter Addon Framework – Namespace & DI Pattern

## Project Structure

```
GuildRecruiter/
├── Core/
│   ├── Core.lua
│   ├── Class.lua
│   ├── Interface.lua
│   ├── TypeCheck.lua
│   ├── TryCatch.lua
│
├── Features/
│   ├── RecruitmentService.lua
│   └── (other features...)
│
├── GuildRecruiter.lua
├── GuildRecruiter.toc
├── README.md
└── ...
```

---

## Namespace Pattern

- All modules must register themselves to the `GuildRecruiter` namespace using:
  ```lua
  GuildRecruiter = GuildRecruiter or {}
  GuildRecruiter.provide("ServiceName", ServiceImpl)
  ```

- Modules are imported using:
  ```lua
  local ServiceImpl = GuildRecruiter.require("ServiceName")
  ```

- `provide` and `require` must be defined (usually in GuildRecruiter.lua):
  ```lua
  -- In GuildRecruiter.lua (executed first)
  GuildRecruiter = GuildRecruiter or {}

  function GuildRecruiter.provide(name, value)
      GuildRecruiter[name] = value
  end

  function GuildRecruiter.require(name)
      local v = GuildRecruiter[name]
      assert(v, "Module not found: " .. tostring(name))
      return v
  end
  ```

## Dependency Injection Usage

Register DI services with the Core container:
```lua
local Core = GuildRecruiter.require("Core")
Core.Register("Logger", GuildRecruiter.require("Logger"), {singleton = true})
Core.Register("RecruitmentService", GuildRecruiter.require("RecruitmentService"), {
    singleton = true,
    deps = {"Logger", "MessageTemplateService", ...}
})
```

Resolve and use services:
```lua
local RecruitmentService = Core.Resolve("RecruitmentService")
RecruitmentService:doRecruitment(...)
```

## Service/Feature Module Template

```lua
-- Features/RecruitmentService.lua
local Class = GuildRecruiter.require("Class")

local RecruitmentService = Class("RecruitmentService", {
    init = function(self, logger, messageTemplateService, ...)
        self.logger = logger
        self.messageTemplateService = messageTemplateService
        -- ...
    end,
    doRecruitment = function(self, ...)
        self.logger:log("Recruitment process started!")
        -- ...
    end
})

GuildRecruiter.provide("RecruitmentService", function(logger, messageTemplateService, ...)
    return RecruitmentService(logger, messageTemplateService, ...)
end)
```

## .toc Load Order Example

```
## Interface: 100007
## Title: GuildRecruiter
## Notes: Modular Addon Example
Core/Core.lua
Core/Class.lua
Core/Interface.lua
Core/TypeCheck.lua
Core/TryCatch.lua
Features/RecruitmentService.lua
GuildRecruiter.lua
```

## Conventions Summary

- Always use `GuildRecruiter` as your namespace.
- All modules use `GuildRecruiter.provide` and `GuildRecruiter.require`.
- Core DI (Core.lua) manages all dependencies via constructor injection.
- No accidental globals—single namespace only.

**End of conventions for GuildRecruiter framework.**

---

## 🚀 **Ready to Start Development**

Would you like me to:
1. **Set up the initial GuildRecruiter project structure**
2. **Create the main GuildRecruiter.lua with namespace setup**
3. **Build the first RecruitmentService feature**
4. **Help migrate your existing GuildRecruiter code to this pattern**

Just let me know what you'd like to tackle first!
