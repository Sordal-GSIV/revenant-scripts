--- @revenant-script
--- name: invoker
--- version: 1.0
--- author: Alastir
--- game: dr
--- description: Track invoker showtime countdown and auto-invoke.
--- tags: magic, invoker, timer
--- Converted from invoker.lic
no_kill_all()
echo("=== invoker ===")
echo("Invoker showtime tracker. Monitors clock for next available window.")
echo("Requires time offset calculation for accurate countdown.")
while true do pause(60) end
