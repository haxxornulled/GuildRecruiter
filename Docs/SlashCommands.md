# Slash Commands (Guild Prospector)

Legacy aliases: /gr (old), /guildrecruiter (old). New shorthand: /gp.
# Slash Commands

Primary aliases
- /gr
- /guildrecruiter
- /guildrec

Quick usage
- /gr ui | /gr toggle — Open the main UI
- /gr settings | /gr options — Open the addon settings
- /gr log [toggle|show|hide|clear] — Toggle or control the log console
- /gr overlay [toggle|show|hide] — Toggle the floating chat overlay
- /gr messages [add <n> | remove <n> | list] — Manage rotation messages
- /gr devmode [on|off|toggle] — Toggle developer mode (shows Debug tab)
- /gr prune prospects <N> — Keep newest N prospects
- /gr prune blacklist <N> — Keep newest N blacklist entries
- /gr queue dedupe — Remove duplicate entries from the invite queue
- /gr stats — Show quick counts (prospects/active/blacklist/queue)
- /gr diag | /gr diag layers — List DI registrations grouped by layer
- /gr help — Print brief help to chat

Notes
- Extended help: /gr-help (if available) prints a more verbose summary from UI helpers.
- Dev harness: /grh is available in developer mode for internal testing hooks.

Implementation references
- Registration: Application/Commands.lua
- Handler and behaviors: Application/SlashCommandHandler.lua
- Extended help/aliases: tools/UIHelpers.lua
