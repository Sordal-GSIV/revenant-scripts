--- @revenant-script
--- name: wood
--- version: 1.0.0
--- author: Pukk
--- game: gs
--- description: Reference guide for magical wood types and their properties
--- tags: reference, wood, weapons, shields, staves
---
--- Usage: ;wood [wood_name]

local WOODS = {
    {name="Carmiln",   staff="Y", shield="Y", range="Y", arrow="Y", bonus="+6"},
    {name="Deringo",   staff="Y", shield="Y", range="Y", arrow="Y", bonus="+8"},
    {name="Faewood",   staff="Y", shield="Y", range="N", arrow="Y", bonus="+20"},
    {name="Fireleaf",  staff="Y", shield="Y", range="N", arrow="N", bonus="+22"},
    {name="Glowbark",  staff="Y", shield="Y", range="Y", arrow="N", bonus="+22"},
    {name="Hoarbeam",  staff="Y", shield="Y", range="Y", arrow="N", bonus="+12"},
    {name="Illthorn",  staff="Y", shield="Y", range="N", arrow="N", bonus="+25"},
    {name="Ipantor",   staff="N", shield="N", range="Y*",arrow="N", bonus="+17"},
    {name="Ironwood",  staff="Y", shield="Y", range="Y", arrow="N", bonus="+0"},
    {name="Kakore",    staff="Y", shield="Y", range="N", arrow="Y", bonus="+10"},
    {name="Lor",       staff="Y", shield="N", range="N", arrow="N", bonus="+25"},
    {name="Mesille",   staff="Y", shield="Y", range="Y", arrow="Y", bonus="+15"},
    {name="Modwir",    staff="Y", shield="N", range="Y", arrow="N", bonus="-10"},
    {name="Mossbark",  staff="Y", shield="Y", range="Y", arrow="Y", bonus="+15"},
    {name="Orase",     staff="Y", shield="Y", range="N", arrow="N", bonus="+20"},
    {name="Rowan",     staff="Y", shield="N", range="N", arrow="Y", bonus="+5"},
    {name="Ruic",      staff="N", shield="N", range="Y", arrow="N", bonus="+20"},
    {name="Sephwir",   staff="N", shield="N", range="Y*",arrow="N", bonus="+25"},
    {name="Villswood", staff="Y", shield="Y", range="Y", arrow="Y", bonus="+18"},
    {name="Witchwood", staff="Y", shield="N", range="N", arrow="N", bonus="+17"},
    {name="Wyrwood",   staff="N", shield="N", range="Y", arrow="N", bonus="+24"},
    {name="Yew",       staff="N", shield="N", range="Y*",arrow="N", bonus="+2"},
}

if not script.vars[1] or script.vars[1] == "" then
    respond(string.format("%-12s %-6s %-7s %-6s %-6s %s", "Wood", "Staff", "Shield", "Range", "Arrow", "Bonus"))
    respond(string.rep("-", 50))
    for _, w in ipairs(WOODS) do
        respond(string.format("%-12s %-6s %-7s %-6s %-6s %s", w.name, w.staff, w.shield, w.range, w.arrow, w.bonus))
    end
    respond("* denotes naturally sighted bows.")
    respond("Type ;wood <name> for detailed info.")
elseif script.vars[1] == "help" then
    respond("Usage: ;wood or ;wood <wood name>")
else
    local query = script.vars[1]:lower()
    for _, w in ipairs(WOODS) do
        if w.name:lower():match(query) then
            respond(w.name)
            respond("Staff: " .. w.staff .. " | Shield: " .. w.shield .. " | Range: " .. w.range .. " | Arrow: " .. w.arrow)
            respond("Bonus: " .. w.bonus)
            exit()
        end
    end
    respond("Wood not found: " .. script.vars[1])
end
