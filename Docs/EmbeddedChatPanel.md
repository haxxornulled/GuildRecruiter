# Embedded Chat Panel (Design Note)

Status: MVP implemented (dockable mini with toggle); further enhancements planned
Owner: UI/Presentation; Infrastructure (ChatRouting) for adapters
Updated: 2025-08-12

## Why
Users shouldn’t have to leave the addon to reply to whispers or guild chats while recruiting. An embedded chat view respects flow and reduces context switching.

Goals
- Show a live, scrollable view of selected chat streams (e.g., WHISPER, GUILD, SAY, system).
- Allow quick reply/input without switching to the global chat frame.
- Fit Clean Architecture: UI consumes an Application-level chat feed; Infrastructure bridges WoW events.
- Be optional and lightweight; collapsible or dockable within our main UI.

Non-goals
- Re-implement the full Blizzard ChatFrame. We embed a minimal, skinned chat view focused on recruiting.

## UX Concepts
- Docked panel: Right or bottom dock in `UI_MainFrame` with collapse/expand and adjustable height.
- Ever-present mini-view: A thin bar or small floating frame that shows the latest N messages; expands on focus.
- Contextual reply: Clicking a whisper populates the input with `/w <name>`; Enter sends and keeps focus inside the addon.
- Filters: Toggle chips for GUILD / WHISPER / SYSTEM; persisted via SavedVars.

## Architecture
- UI: `UI_ChatPanel.lua` (new). Presents a `ScrollingMessageFrame`-like feed and an EditBox for input.
- Application: `IChatFeed` interface defines subscription to message stream and send API.
  - Methods:
    - Subscribe(handler) -> unsubscribe
    - Send(target, text, opts)
    - SetFilters(filters)
- Infrastructure: `ChatRouting` service wraps WoW events/APIs:
  - Listens: `CHAT_MSG_WHISPER`, `CHAT_MSG_GUILD`, `CHAT_MSG_SAY`, etc.
  - Emits normalized messages to Application feed (channel, author, text, timestamp, guid).
  - Sends via `SendChatMessage` (guarded; throttled via Scheduler if needed).

Data shape (message)
- channel: string ('WHISPER'|'GUILD'|'SAY'|'SYSTEM'|...)
- author: string
- text: string
- time: number (seconds since epoch)
- meta: table (guid, flags)

## Implementation Sketch (WoW-safe)
- Avoid cloning Blizzard frames with protected templates; instead, compose:
  - Feed: use `CreateFrame('ScrollingMessageFrame', nil, parent)`; set font, fade, max lines.
  - Input: `CreateFrame('EditBox', nil, parent)`; on Enter, route through Application:ChatFeed:Send.
  - Style with our Tokens/Theme; never pass template as 4th arg.
- DI
  - Provide `Infrastructure/Chat/ChatRouting.lua` implementing transport.
  - Provide `Application/Chat/ChatFeed.lua` implementing IChatFeed over the router.
  - UI resolves `IChatFeed` and binds/unbinds on Show/Hide.

## Risks / Constraints
- Some chat APIs are restricted in combat; input may be blocked—handle gracefully.
- Throttle/anti-spam: respect Blizzard chat throttling; consider a simple rate limiter.
- Security: don’t echo sensitive whispers to guild by accident; preserve channels on Send.
- Locales and escape codes: strip/escape WoW color codes when needed.

## Minimal Milestone (MVP)
Delivered:
1. Infra: `Infrastructure/Chat/ChatRouting.lua` normalizes events and provides Send.
2. UI: Chat mini dock embedded in `UI_MainFrame` with collapse/expand toggle.
3. Persistence: Collapsed state is saved; toggle icon reflects state.

Planned next (post-MVP):
- Application-level `ChatFeed` to manage filters and subscribers.
- Inline filter chips and input for quick replies.

## Future
- Mention templates for quick canned responses.
- Inline actions on messages (invite, add note/blacklist).
- Search across recent messages.

## Backlog / Next Steps (Implementation Notes)

1) Filter chips in the panel UI
- Add a small row of segmented buttons (chips) above the feed: [WHISPER] [GUILD] [SYSTEM] [SAY].
- On toggle, call `ChatFeed:SetFilters({ ... })` and persist via SavedVars (already handled by ChatFeed).
- Visual: reuse button style from UI helpers; keep height low to avoid crowding.
- Acceptance: Toggling chips immediately changes messages shown; state is restored after reload.

2) Inline actions on messages (invite, blacklist, templates)
- ScrollingMessageFrame cannot host per-line buttons, but it supports hyperlinks.
- Strategy: append action tokens like `[Invite] [Blacklist] [Templates]` as custom hyperlinks using WoW link syntax (`|Hgr:action:payload|h[Invite]|h`).
- Enable links with `feed:SetHyperlinksEnabled(true)` and handle via `feed:SetScript('OnHyperlinkClick', handler)`.
- Handler parses `linkType` and payload, then dispatches to InviteService/ProspectsService/templates UI.
- Acceptance: Clicking [Invite] invites the author (if eligible); [Blacklist] opens/adds; [Templates] opens a small menu to insert canned reply into input.

3) Quick templates
- Store user-defined templates in SavedVars (e.g., `ui.chatTemplates = { ... }`).
- Provide a mini dropdown/button next to the input that inserts the selected template into the EditBox.
- Acceptance: Selecting a template inserts text at cursor; persists across sessions.

4) Mini-view toggle placement and icon semantics
- Current: A chat-bubble icon toggles the mini chat dock. When collapsed, the icon is desaturated and semi-transparent.
- Possible: Move the toggle near the sidebar chevron for a unified control area.
- Acceptance: Toggle works reliably; state persists in `ui.chatMiniCollapsed`.

## Notes on "Cloning" ChatFrame
While you can parent a new `ScrollingMessageFrame` and copy font/colors from ChatFrame1, avoid cloning secure/protected Blizzard UI templates or reusing their exact named frames. Build a parallel, lightweight frame tree that mimics the behavior we need. This sidesteps taint and template restrictions.

References:
- Toggle/icon behavior implemented in `UI/UI_MainFrame.lua`.
- Event normalization in `Infrastructure/Chat/ChatRouting.lua`.
