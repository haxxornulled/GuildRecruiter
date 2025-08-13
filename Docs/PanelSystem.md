# Panel System

Status: Adopted

We use a central, injectable panel factory to create UI panels lazily and decouple panel keys from concrete modules.

Components
- Contract: `Core/Interfaces/IPanelFactory.lua` (key: `IPanelFactory`)
- Implementation: `Infrastructure/UI/PanelFactory.lua`
- Registry: `UI/UI_PanelRegistry.lua` (registers built-in panels)
- Consumer: `UI/UI_MainFrame.lua` (calls `GetPanel(key)` to attach frames)

Lifecycle
- Registration: `UI/UI_PanelRegistry` queues panel definitions until the factory is available, then flushes (on `ServicesReady` or timer retry).
- Resolution: `UI_MainFrame` requests panels by key; the factory invokes the registered builder on first use and caches the frame.
- Diagnostics: You can list known panel keys via the factory (List/TryGet) for menus or debug.

Keys (built-in)
- `Summary`, `Prospects`, `Blacklist`, `Settings`, `Debug`

Behavioral notes
- Panels are created on demand. Avoid heavy work in panel module top-level; prefer constructing on first `GetPanel`.
- The registry defers registration to avoid ordering issues with `.toc` load order.
- Panels are regular frames parented under the main container; builders should return a frame and not self-parent.

Usage example
- `UI_MainFrame` sidebar click → `pf:GetPanel('Prospects')` → factory builds and returns frame → frame is shown/attached.

Extending
- To add a panel, register a builder in `UI/UI_PanelRegistry.lua`:
  - Key: unique string (e.g., `Help`)
  - Builder: function(scope) -> Frame
- Optionally expose `Help` in the sidebar; the factory will create it only when selected.

Related
- See `Docs/EmbeddedChatPanel.md` for the chat mini dock and toggle behavior.
- DI/container details are in `Core/README.md`.
