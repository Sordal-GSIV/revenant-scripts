--- @revenant-script
--- name: healme
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Self-healing with Heal Wounds and Heal Scars.
--- tags: empath, healing, self
--- Converted from healme.lic

-- User config
local my_spells = {
    HW = {abbrev = "HW", mana = 5, cambrinth = {5, 5}},
    HS = {abbrev = "HS", mana = 10, cambrinth = {7, 7}},
}
local cambrinth = UserVars.worn_cambrinth or "armband"

Flags.add("hm-spellcast", "You feel fully prepared to cast your spell")
Flags.add("hm-partial-heal", "appear.*improved", "but it is ineffective", "appear.*better")

local function cast_spell(data, part, internal)
    while checkmana() < 25 do pause(1) end
    Flags.reset("hm-spellcast")
    DRC.bput("prepare " .. data.abbrev .. " " .. data.mana, "With tense movements")
    if data.cambrinth then
        for _, mana in ipairs(data.cambrinth) do
            DRC.bput("charge my " .. cambrinth .. " " .. mana, "You harness")
            waitrt()
        end
        DRC.bput("invoke my " .. cambrinth, "You reach for its center")
    end
    while not Flags["hm-spellcast"] do pause(0.5) end
    Flags.reset("hm-partial-heal")
    local cmd = internal and ("cast " .. part .. " internal") or ("cast " .. part)
    DRC.bput(cmd, "You gesture")
    pause(0.5)
    return Flags["hm-partial-heal"]
end

DRC.bput("perc heal self", "Roundtime")
waitrt()
echo("Healing self...")
-- Simplified healing loop
local parts = {"head", "neck", "chest", "abdomen", "back", "left arm", "right arm",
    "left hand", "right hand", "left leg", "right leg"}
for _, part in ipairs(parts) do
    while cast_spell(my_spells.HW, part, false) do pause(0.5) end
    cast_spell(my_spells.HS, part, false)
end
