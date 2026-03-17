--- @revenant-script
--- name: isigils_with_bandages
--- version: 1.0.0
--- author: unknown
--- game: gs
--- tags: guardians, sunfist, sigils, automation
--- description: Maintain active Guardians of Sunfist sigils automatically
---
--- Original Lich5 authors: unknown
--- Ported to Revenant Lua from isigils_with_bandages.lic
---
--- Usage:
---   ;isigils_with_bandages          - run with current settings
---   ;isigils_with_bandages setup    - configure which sigils to maintain
---   ;isigils_with_bandages help     - show help

local SIGILS = {
    ["9703"] = "Sigil of Contact: Activates ESP Net",
    ["9704"] = "Sigil of Resolve: Climbing, Swimming, and Survival",
    ["9705"] = "Sigil of Minor Bane: HDW and +5 AS",
    ["9716"] = "Sigil of Bandages: Attack without breaking tended bandages",
    ["9707"] = "Sigil of Defense: +1 DS per rank - 5 minutes",
    ["9708"] = "Sigil of Offense: +1 AS per rank - 5 minutes",
    ["9710"] = "Sigil of Minor Protection: +5 DS and HDP - 1 minute",
    ["9711"] = "Sigil of Focus: +1 TD per rank - 1 minute",
    ["9713"] = "Sigil of Mending: Increases HP recovery by 15 - 10 minutes",
    ["9714"] = "Sigil of Concentration: +5 mana regeneration - 10 minutes",
    ["9715"] = "Sigil of Major Bane: Adds +10 AS, HCW - 1 minute",
    ["9719"] = "Sigil of Major Protection: Adds +10 DS, HCP - 1 minute",
}

local EXCLUSIVE_PAIRS = {
    { "9705", "9715" },
    { "9710", "9719" },
}

local function load_settings()
    local s = {}
    for num, _ in pairs(SIGILS) do
        s[num] = CharSettings.get("isigils_" .. num) or false
    end
    return s
end

local function save_settings(s)
    for num, val in pairs(s) do
        CharSettings.set("isigils_" .. num, val)
    end
end

local arg1 = Script.current.vars[1]

if arg1 and arg1:lower() == "help" then
    respond("")
    respond("Usage:")
    respond("   ;isigils_with_bandages          run with current settings")
    respond("   ;isigils_with_bandages setup    configure sigils (terminal)")
    respond("   ;isigils_with_bandages help     show this message")
    respond("")
    return
elseif arg1 and arg1:lower() == "setup" then
    local settings = load_settings()
    respond("Current sigil settings:")
    local nums = {}
    for num, _ in pairs(SIGILS) do nums[#nums + 1] = num end
    table.sort(nums)
    for _, num in ipairs(nums) do
        local status = settings[num] and "ON" or "OFF"
        respond("  " .. num .. " [" .. status .. "] " .. SIGILS[num])
    end
    respond("")
    respond("To toggle a sigil: ;send <sigil number>")
    respond("To save and exit: ;send done")

    while true do
        local input = get()
        if input then
            input = input:match("^%s*(.-)%s*$")
            if input == "done" then break end
            if SIGILS[input] then
                settings[input] = not settings[input]
                local status = settings[input] and "ON" or "OFF"
                -- Handle exclusions
                for _, pair in ipairs(EXCLUSIVE_PAIRS) do
                    if input == pair[1] and settings[input] then settings[pair[2]] = false end
                    if input == pair[2] and settings[input] then settings[pair[1]] = false end
                end
                respond("  " .. input .. " [" .. status .. "] " .. SIGILS[input])
            end
        end
    end

    save_settings(settings)
    echo("Settings saved")
    return
end

-- Main loop
local settings = load_settings()

while true do
    if checkdead() then return end
    for num, active in pairs(settings) do
        if active then
            local spell = Spell[tonumber(num)]
            if spell.known() and spell.affordable() and not spell.active() then
                spell.cast()
                waitrt()
                waitcastrt()
            end
        end
    end
    wait(1)
end
