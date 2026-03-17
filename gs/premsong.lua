--- @revenant-script
--- name: premsong
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Sing a premium song with an optional tone. Usage: ;premsong [tone]

local tone = Script.vars[0] or ""

fput("song " .. tone)
fput("sing Ember bound in molten deep,;Seal your dream, return to sleep.;We hold the hush, the tethered flame,;Let none now wake your ancient name.")
fput("song none")
