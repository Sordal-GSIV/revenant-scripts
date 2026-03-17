--- @revenant-script
--- name: gem_loadouts
--- version: 0.1.1
--- author: Lucullan
--- game: gs
--- description: Manage gemstone loadouts for the GEM system
--- tags: gems, loadouts, utility
---
--- Usage:
---   ;gem_loadouts setup       - Open configuration (text-based)
---   ;gem_loadouts set <name>  - Switch to specified loadout
---   ;gem_loadouts help        - Display help

CharSettings["gem_loadouts"] = CharSettings["gem_loadouts"] or {}

if script.vars[1] == "help" or script.vars[0] == "help" then
    respond("gem_loadouts by Lucullan")
    respond("Usage:")
    respond("  ;gem_loadouts setup       - Configure loadouts")
    respond("  ;gem_loadouts set <name>  - Switch to specified loadout")
    respond("  ;gem_loadouts help        - Display this message")
    exit()
end

if script.vars[1] == "set" and script.vars[2] then
    local key = script.vars[2]:lower():gsub(" ", "_")
    local loadouts = CharSettings["gem_loadouts"]
    local loadout = loadouts[key]
    if not loadout then
        echo("Loadout not found: " .. key)
        exit()
    end
    -- Get current gem state
    local result = quiet_command("gem list all", "Gemstone 1")
    -- Simple equip/unequip based on stored gem numbers
    if loadout.gems then
        for _, gem_id in ipairs(loadout.gems) do
            fput("gem equip " .. gem_id)
        end
    end
    echo("Switched to loadout: " .. (loadout.name or key))
    exit()
end

echo("Use ;gem_loadouts help for usage information.")
echo("Note: GUI setup requires Revenant GUI support. Use ;gem_loadouts set <name> to switch loadouts.")
