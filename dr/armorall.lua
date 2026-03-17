--- @revenant-script
--- name: armorall
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Put on or take off a set of armor pieces
--- tags: armor, equipment
---
--- Usage:
---   ;armorall on  - Get and wear all armor pieces
---   ;armorall off - Remove and stow all armor pieces

local action = Script.vars[1]
if not action then
    echo("Usage: ;armorall on|off")
    return
end

local verb, adverb
if action == "on" then
    verb = "get"
    adverb = "wear"
elseif action == "off" then
    verb = "remove"
    adverb = "stow"
else
    echo("Usage: ;armorall on|off")
    return
end

local armor_pieces = {"lorica", "targe", "knuckles", "gloves", "vamb", "greave", "bala"}
for _, armor in ipairs(armor_pieces) do
    fput(verb .. " " .. armor)
    fput(adverb .. " my " .. armor)
end
