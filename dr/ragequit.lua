--- @revenant-script
--- name: ragequit
--- version: 1.0
--- author: Zadrix
--- game: dr
--- description: Quit the game when you die
--- tags: death, quit, safety

no_kill_all()
no_pause_all()
silence_me()

waitfor("You are a ghost!  You must wait until someone resurrects you, or you decay.")
fput("quit")
