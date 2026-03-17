--- @revenant-script
--- name: cyclic_buddy
--- version: 1.0
--- author: Aeridal
--- game: dr
--- description: Background cyclic spell maintenance for magic training.
--- tags: magic, cyclic, training
--- Converted from cyclic-buddy.lic
no_pause_all()
local settings = get_settings()
local cycle_timer = os.time() - 251
local no_use = settings.cyclic_no_use_scripts or {}
Flags.add("cyclic_lost", "cannot maintain itself", "interferes with your spell", "concentrate on your journey", "prevents your spell")

while true do
    pause(1)
    if DRStats.concentration <= 90 then goto continue end
    for _, name in ipairs(no_use) do if running(name) then goto continue end end
    if Flags["cyclic_lost"] then cycle_timer = os.time() - 251; Flags.reset("cyclic_lost") end
    if not settings.cyclic_training_spells then goto continue end
    if os.time() - cycle_timer <= 250 then goto continue end
    local skills = settings.cyclic_cycle_skills or {}
    local best_skill, best_xp = nil, 999
    for _, s in ipairs(skills) do
        local xp = DRSkill.getxp(s)
        if xp < best_xp then best_xp = xp; best_skill = s end
    end
    if not best_skill or best_xp >= 32 then DRCA.release_cyclics(); goto continue end
    local data = settings.cyclic_training_spells[best_skill]
    if data then DRCA.release_cyclics(); DRCA.cast_spell(data, settings) end
    cycle_timer = os.time()
    ::continue::
end
