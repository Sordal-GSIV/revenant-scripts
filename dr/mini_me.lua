--- @revenant-script
--- name: mini_me
--- version: 2.0.0
--- author: Dreaven
--- game: dr
--- tags: warrior, armor, mini dreavening, GUI
--- description: GUI for setting Mini-Dreavening armor options and protection fittings
---
--- Original Lich5 authors: Dreaven
--- Ported to Revenant Lua from mini-me.lic v2
---
--- Usage: ;mini_me (opens configuration GUI)

local armor_option = CharSettings.get("mini_me_armor_option") or "Armor Support"

local ARMOR_OPTIONS = {
    "Armor Blessing", "Armored Casting", "Armored Evasion",
    "Armored Fluidity", "Armor Reinforcement", "Armored Stealth", "Armor Support",
}

local ARMOR_PROTECTION = {
    "Cloth Crush (13751)", "Cloth Puncture (13752)", "Cloth Slash (13753)",
    "Leather Crush (15001)", "Leather Puncture (15002)", "Leather Slash (15003)",
    "Scale Crush (16251)", "Scale Puncture (16252)", "Scale Slash (16253)",
    "Chain Crush (17501)", "Chain Puncture (17502)", "Chain Slash (17503)",
    "Plate Crush (18751)", "Plate Puncture (18752)", "Plate Slash (18753)",
}

-- Display current settings and options
respond("Mini-Me - Armor Options for " .. GameState.character_name)
respond("Current Armor Option: " .. armor_option)
respond("")
respond("To change armor option, whisper Dreaven in-game:")
for _, opt in ipairs(ARMOR_OPTIONS) do
    respond("  whisper Dreaven " .. opt)
end
respond("")
respond("Armor Protection options (give Iteno the spell number):")
for _, opt in ipairs(ARMOR_PROTECTION) do
    local num = opt:match("%((%d+)%)")
    if num then
        respond("  give Iteno " .. num .. " -- " .. opt)
    end
end

before_dying(function()
    CharSettings.set("mini_me_armor_option", armor_option)
end)

-- Watch for Dreaven's response
while true do
    local line = get()
    if line then
        local new_opt = line:match('^Dreaven whispers, "Got it! You want (.-)!"')
        if new_opt then
            armor_option = new_opt
            echo("Armor Option updated to: " .. armor_option)
        end
    end
end
