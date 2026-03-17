--- @revenant-script
--- name: title
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Display available titles in a clickable window.
--- tags: titles, display, UI
---
--- Converted from title.lic

local title_pre = {
    "Blunt", "Ranged", "Brawling", "GenEdged", "SpecEdged", "Thrown",
    "Pole", "Shield", "Slings", "Weapons", "WeaponMaster", "Performer",
    "PrimaryMagic", "Magic", "Money", "Ownership", "Survival1", "Survival2",
    "Survival3", "Lore", "Criminal", "Generic", "Racial", "Premium",
    "Order", "Religion", "Novice", "Practitioner", "Dilettante", "Aficionado",
    "Adept", "Expert", "Professional", "Authority", "Genius", "Savant",
    "Master", "GrandMaster", "Guru", "Legend", "Custom"
}

if DRStats.guild then
    table.insert(title_pre, DRStats.guild)
end

echo("=== Available Titles ===")
for _, category in ipairs(title_pre) do
    local result = DRC.bput("title pre list " .. category,
        "you:", "There are no titles you may choose from that category")
    if result and result:find("you:") then
        echo("  " .. category .. ": (titles available)")
    end
end
echo("=== End Titles ===")
