--- @revenant-script
--- name: tattoo
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Auto-target when tattoo spell pattern forms (magic training helper)
--- tags: magic, tattoo, training

while true do
    waitfor("The saturated tunnels in the tattoo form the foundation of a spell pattern")
    waitrt()
    DRC.bput("target", "You begin to weave mana lines")
end
