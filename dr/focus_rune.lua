--- @revenant-script
--- name: focus_rune
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Focus a runestone to train Sorcery until 30 XP or 90 attempts
--- tags: sorcery, runestone, training

local count = 0

EquipmentManager.new().empty_hands()
DRC.bput("get my runestone", "You get")

while DRSkill.getxp("Sorcery") < 30 and count <= 90 do
    DRC.bput("focus my runestone", "You focus")
    count = count + 1
end

EquipmentManager.new().empty_hands()
