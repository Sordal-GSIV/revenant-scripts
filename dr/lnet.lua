--- @revenant-script
--- name: lnet
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: LNet chat/communication network client for DR (original version)
--- tags: chat, communication, network, lnet
---
--- Ported from lnet.lic (Lich5) to Revenant Lua
---
--- Note: LNet relies on Lich's TCP networking between game instances.
--- Revenant handles multi-character differently. This is a compatibility stub.
---
--- Usage:
---   ;lnet   - Start LNet communication client

echo("=== LNet ===")
echo("LNet is the original DR community chat network.")
echo("See ;lnet2 for the updated version.")
echo("")
echo("Revenant multi-character communication will be handled through")
echo("the engine's built-in IPC system when available.")
