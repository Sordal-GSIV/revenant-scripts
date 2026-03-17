--- @revenant-script
--- name: raelok
--- version: 1.0
--- author: Raelok
--- game: dr
--- description: Broadcast a message to LNet channels (joke/novelty script)
--- tags: lnet, chat, broadcast

local msg = "RAELOK IS KING! LONG LIVE KING RAELOK!"

LNet.send_message({type = "channel", channel = "drprime"}, msg)
LNet.send_message({type = "channel", channel = "drscripts"}, msg)
LNet.send_message({type = "channel", channel = "drprime"}, msg)
