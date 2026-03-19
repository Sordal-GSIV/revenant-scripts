--- Combat-trainer global skill category constants
-- Ported from GameState class in combat-trainer.lic
local M = {}

M.MARTIAL_SKILLS  = {"Brawling"}
M.EDGED_SKILLS    = {"Small Edged", "Large Edged", "Twohanded Edged"}
M.BLUNT_SKILLS    = {"Small Blunt", "Large Blunt", "Twohanded Blunt"}
M.STAFF_SKILLS    = {"Staves"}
M.POLEARM_SKILLS  = {"Polearms"}
M.MELEE_SKILLS    = {} -- filled in init
M.THROWN_SKILLS   = {"Heavy Thrown", "Light Thrown", "Missile Mastery"}
M.TWOHANDED_SKILLS = {"Twohanded Edged", "Twohanded Blunt"}
M.AIM_SKILLS      = {"Bow", "Slings", "Crossbow"}
M.RANGED_SKILLS   = {} -- filled in init
M.NON_DANCE_SKILLS = {} -- filled in init
M.TACTICS_ACTIONS = {"bob", "weave", "circle"}

-- Spell weapon buffs
M.WEAPON_BUFFS    = {"Ignite", "Rutilor's Edge", "Resonance"}

-- Combine melee skills
for _, s in ipairs(M.EDGED_SKILLS)   do table.insert(M.MELEE_SKILLS, s) end
for _, s in ipairs(M.BLUNT_SKILLS)   do table.insert(M.MELEE_SKILLS, s) end
for _, s in ipairs(M.STAFF_SKILLS)   do table.insert(M.MELEE_SKILLS, s) end
for _, s in ipairs(M.POLEARM_SKILLS) do table.insert(M.MELEE_SKILLS, s) end
table.insert(M.MELEE_SKILLS, "Melee Mastery")

-- Combine ranged skills
for _, s in ipairs(M.THROWN_SKILLS) do table.insert(M.RANGED_SKILLS, s) end
for _, s in ipairs(M.AIM_SKILLS)    do table.insert(M.RANGED_SKILLS, s) end
table.insert(M.RANGED_SKILLS, "Missile Mastery")

-- Non-dance skills (ranged + brawling + offhand)
for _, s in ipairs(M.RANGED_SKILLS) do table.insert(M.NON_DANCE_SKILLS, s) end
table.insert(M.NON_DANCE_SKILLS, "Brawling")
table.insert(M.NON_DANCE_SKILLS, "Offhand Weapon")

--- Check if a value is in a table
function M.tcontains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--- Remove a value from a table (first occurrence)
function M.tremove_val(t, val)
    for i, v in ipairs(t) do
        if v == val then
            table.remove(t, i)
            return
        end
    end
end

--- Merge two arrays
function M.tmerge(a, b)
    local result = {}
    for _, v in ipairs(a) do table.insert(result, v) end
    for _, v in ipairs(b) do table.insert(result, v) end
    return result
end

--- Subtract table b from table a (set difference)
function M.tdiff(a, b)
    local result = {}
    for _, v in ipairs(a) do
        if not M.tcontains(b, v) then
            table.insert(result, v)
        end
    end
    return result
end

--- Intersection of two arrays
function M.tintersect(a, b)
    local result = {}
    for _, v in ipairs(a) do
        if M.tcontains(b, v) then
            table.insert(result, v)
        end
    end
    return result
end

return M
