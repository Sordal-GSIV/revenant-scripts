--- @revenant-script
--- name: sell_and_return
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Run sell-loot then return to your original room
--- tags: loot, sell, travel

local room = Room.current.id
wait_for_script_to_complete("sell_loot")
DRCT.walk_to(room)
