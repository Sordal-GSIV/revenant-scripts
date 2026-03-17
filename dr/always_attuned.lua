--- @revenant-script
--- name: always_attuned
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Keep attunement active by periodically perceiving mana
--- tags: attunement, magic, training

while true do
    waitrt()
    fput("blink")
    fput("twitch")
    fput("perce mana")
    pause(60)
end
