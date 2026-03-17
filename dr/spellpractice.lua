--- @revenant-script
--- name: spellpractice
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Continuously cast aug/utility/warding spells for training.
--- tags: magic, training, spells
--- Usage: ;spellpractice <aug_spell> <mana> <util_spell> <mana> <ward_spell> <mana>

no_kill_all()
local aug, augm = Script.vars[1], Script.vars[2]
local uti, utim = Script.vars[3], Script.vars[4]
local war, warm = Script.vars[5], Script.vars[6]
if not aug then echo("Usage: ;spellpractice <aug> <mana> <util> <mana> <ward> <mana>") return end

local function cast_and_check(spell, mana, skill)
    while checkmana() < 50 do pause(1) end
    waitrt(); fput("prepare " .. spell .. " " .. mana)
    waitcastrt(); waitrt(); fput("cast")
    put("exp " .. skill:sub(1,3))
    local line = get()
    return line and line:find("34/34")
end

while true do
    if not cast_and_check(aug, augm, "aug") then goto aug_again end
    ::util:: if not cast_and_check(uti, utim, "uti") then goto util end
    ::ward:: if not cast_and_check(war, warm, "war") then goto ward end
    ::aug_again::
end
