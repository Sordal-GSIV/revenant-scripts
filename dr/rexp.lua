--- @revenant-script
--- name: rexp
--- version: 1.0
--- author: Slarc
--- game: dr
--- description: Manage rested EXP by toggling sleep state.
--- tags: rexp, sleep, experience
--- Converted from rexp.lic
local settings = get_settings()
local full_rexp = (settings.rexp_hours or 4) * 60
echo("=== rexp ===")
echo("REXP manager. Full REXP pool: " .. full_rexp .. " minutes.")
echo("Monitoring rested EXP state...")
while true do
    DRC.bput("exp", "Rested EXP")
    pause(full_rexp * 120)
end
