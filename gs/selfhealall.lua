--- @revenant-script
--- name: selfhealall
--- version: 1.0.0
--- author: Jara
--- game: gs
--- description: Empath self-heal all wounds, scars, and health using spell 1118
--- tags: empath, healing, self-heal
---
--- As an Empath, heals yourself completely. Must know spell 1118.
--- Usage: ;selfhealall

local BODY_PARTS = {
    "head", "neck", "left eye", "right eye", "abdomen",
    "left hand", "right hand", "left arm", "right arm",
    "chest", "back", "right leg", "left leg", "nerves"
}

local WOUND_KEYS = {
    "head", "neck", "leye", "reye", "abs",
    "lhand", "rhand", "larm", "rarm",
    "chest", "back", "rleg", "lleg", "nerves"
}

local function empath_check()
    if not (Spell[1118].known and Char.prof == "Empath") then
        respond("")
        respond("You do not know Organ Scar Repair or you're not an empath.")
        respond("")
        exit()
    end
end

local function mana_check()
    while checkmana() < 25 do
        respond("")
        respond("Self Heal All - Pausing 10 for mana.")
        respond("")
        pause(10)
    end
end

local function health_check()
    if percenthealth() <= 99 then
        mana_check()
        fput("cure")
        waitrt()
    end
end

local function wound_check()
    for i, key in ipairs(WOUND_KEYS) do
        if Wounds[key] >= 1 then
            mana_check()
            waitrt()
            fput("cure " .. BODY_PARTS[i])
            waitrt()
            return
        end
    end
end

local function scar_check()
    for i, key in ipairs(WOUND_KEYS) do
        if Scars[key] >= 1 then
            mana_check()
            waitrt()
            fput("cure " .. BODY_PARTS[i])
            waitrt()
            return
        end
    end
end

local function has_wounds()
    for _, key in ipairs(WOUND_KEYS) do
        if Wounds[key] >= 1 then return true end
    end
    return false
end

local function has_scars()
    for _, key in ipairs(WOUND_KEYS) do
        if Scars[key] >= 1 then return true end
    end
    return false
end

-- Start of Script
empath_check()

while true do
    waitcastrt()
    pause(0.5)
    if percenthealth() <= 99 then
        health_check()
    elseif has_wounds() then
        wound_check()
    elseif has_scars() then
        scar_check()
    else
        respond("No wounds or scars found. Exiting.")
        exit()
    end
end
