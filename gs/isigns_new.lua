--- @revenant-script
--- name: isigns_new
--- version: 3.1.0
--- author: Ifor Get
--- game: gs
--- tags: council of light, signs, upkeep, automation
--- description: Council of Light Signs upkeep with GUI setup support
---
--- Original Lich5 authors: Ifor Get, Kaldonis, Doug
--- Ported to Revenant Lua from isigns_new.lic v3.1
---
--- Usage:
---   ;isigns_new          - run sign upkeep
---   ;isigns_new setup    - configure which signs to maintain
---   ;isigns_new help     - show help

local SIGNS = {
    ["9903"] = "Sign of Warding: +5 to DS",
    ["9904"] = "Sign of Striking: +5 to AS",
    ["9905"] = "Sign of Clotting: Stops all bleeding",
    ["9906"] = "Sign of Thought: Amunet",
    ["9907"] = "Sign of Defending: +10 to DS",
    ["9908"] = "Sign of Smiting: +10 to AS",
    ["9909"] = "Sign of Staunching: Stops bleeding, 2x duration",
    ["9910"] = "Sign of Deflection: +20 Bolt DS",
    ["9912"] = "Sign of Swords: +20 AS",
    ["9913"] = "Sign of Shields: +20 DS",
    ["9914"] = "Sign of Dissipation: +15 TD",
}

local settings = CharSettings.load("isigns_new") or {}

local arg1 = Script.current.vars[1]

if arg1 and arg1:lower() == "help" then
    respond("")
    respond("Usage:")
    respond("   ;isigns_new          run sign upkeep")
    respond("   ;isigns_new setup    configure signs")
    respond("   ;isigns_new help     show this message")
    respond("")
    return
elseif arg1 and arg1:lower():match("^setup$") then
    respond("Current sign settings:")
    local nums = {}
    for num, _ in pairs(SIGNS) do nums[#nums + 1] = num end
    table.sort(nums)
    for _, num in ipairs(nums) do
        local status = settings[num] and "ON" or "OFF"
        respond("  " .. num .. " [" .. status .. "] " .. SIGNS[num])
    end
    respond("")
    respond("To toggle: ;send <sign number>")
    respond("To save: ;send done")

    while true do
        local input = get()
        if input then
            input = input:match("^%s*(.-)%s*$")
            if input == "done" then break end
            if SIGNS[input] then
                settings[input] = not settings[input]
                -- Mutual exclusion: clotting vs staunching
                if input == "9905" and settings[input] then settings["9909"] = false end
                if input == "9909" and settings[input] then settings["9905"] = false end
                local status = settings[input] and "ON" or "OFF"
                respond("  " .. input .. " [" .. status .. "] " .. SIGNS[input])
            end
        end
    end

    CharSettings.save("isigns_new", settings)
    echo("Settings saved.")
    return
end

-- Main upkeep loop
while true do
    if checkdead() then return end

    if Spell[9012].active() then
        echo("The Grand Poohbah is still mad at you.")
        return
    end

    for num, active in pairs(settings) do
        if active then
            local spell = Spell[tonumber(num)]
            if spell.known() and spell.affordable() and not spell.active() then
                spell.cast()

                -- Check for anti-magic zone
                local recent = reget(10)
                local anti_magic = false
                for _, line in ipairs(recent or {}) do
                    if line:find("The power from your sign dissipates into the air") then
                        anti_magic = true
                        break
                    end
                end
                if anti_magic then
                    local room = Room.current.id
                    while room == Room.current.id do
                        echo("*** You are in an ANTI-MAGIC zone ***")
                        echo("*** " .. Script.current.name .. " will restart in 10 seconds ***")
                        echo("*** and only if you leave this room ***")
                        wait(10)
                    end
                end

                waitrt()
                waitcastrt()
            end
        end
    end

    wait(1)
end
