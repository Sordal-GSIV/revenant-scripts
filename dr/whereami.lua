--- @revenant-script
--- name: whereami
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Display your current room ID
--- tags: navigation, room, debug

echo("Current room id: " .. tostring(Room.id))
