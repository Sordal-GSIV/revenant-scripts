--- @revenant-script
--- name: lnet2
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: LNet2 chat/communication network client for DR
--- tags: chat, communication, network, lnet
---
--- Ported from lnet2.lic (Lich5) to Revenant Lua
---
--- Note: LNet relies on Lich's TCP networking between game instances.
--- Revenant handles multi-character differently. This is a compatibility stub.
---
--- Usage:
---   ;lnet2   - Start LNet2 communication client

echo("=== LNet2 ===")
echo("LNet2 is the DR community chat/communication network.")
echo("It relies on Lich's inter-process TCP sockets for messaging")
echo("between game instances running on the same machine.")
echo("")
echo("Revenant multi-character communication will be handled through")
echo("the engine's built-in IPC system when available.")
echo("")
echo("Chat commands (for future implementation):")
echo("  ;chat <message>     - Send to default channel")
echo("  ;chat to <name> msg - Send private message")
echo("  ;chat tune <channel> - Join a channel")
