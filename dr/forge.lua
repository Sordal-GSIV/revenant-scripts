--- @revenant-script
--- name: forge
--- version: 1.0
--- author: Seped/Mallitek
--- game: dr
--- description: Forging workflow - study book, work ingot, assemble.
--- tags: crafting, forging, weapons
--- Usage: ;forge <log|stow> <chapter> <page> <ingot_type> <item_noun> <assemble_noun>
--- Converted from forge.lic
if #Script.vars < 6 then
    echo("Usage: ;forge <log|stow> <chapter> <page> <ingot_type> <item> <assemble>")
    return
end
echo("=== forge ===")
echo("Forging workflow. Requires full crafting API integration.")
