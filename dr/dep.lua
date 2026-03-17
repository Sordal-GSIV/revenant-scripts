--- @revenant-script
--- name: dep
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Exchange currency to kronars and deposit at bank
--- tags: money, bank, deposit

DRC.walk_to(1902)

fput("exchange all lirums for kronars")
fput("exchange all dokoras for kronars")

DRC.walk_to(1900)

fput("deposit all")
fput("withdraw 7 silver")
