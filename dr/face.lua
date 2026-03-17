--- @revenant-script
--- name: face
--- version: 1.0
--- author: Crannach
--- game: dr
--- description: Keep the Veiled Identity cantrip active automatically
--- tags: magic, cantrip, disguise

UserVars.face_timer = UserVars.face_timer or 200

while true do
    pause(1)
    local spells = DRSpells.active_spells or {}
    local has_veiled = false
    for _, spell in ipairs(spells) do
        if spell == "Veiled Identity" then
            has_veiled = true
            break
        end
    end

    if not has_veiled and not Script.running("combat-trainer") then
        pause(UserVars.face_timer)
        local result = DRC.bput("chant cantrip face",
            "a bit too distracted to cast",
            "You chant",
            "still under the effects",
            "You still need",
            "just recently chanted that cantrip")
        if result and result:match("recently chanted") then
            UserVars.face_timer = UserVars.face_timer + 1
            echo("Increasing wait timer to: " .. UserVars.face_timer .. " seconds")
        end
    end
end
