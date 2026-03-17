--- @revenant-script
--- name: apwatch
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Monitor for astral pool disruptions and flag bad status
--- tags: astral, moonmage, monitor

no_kill_all()
no_pause_all()

while true do
    waitfor("A wave of rippling air sweeps through the conduit!  The streams of mana writhe violently before settling into new patterns.")
    UserVars.apstatus = "bad"
end
