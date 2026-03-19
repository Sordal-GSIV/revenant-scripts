--- @revenant-script
--- name: asclearn
--- version: 1.1.0
--- author: Tysong
--- game: gs
--- tags: ascension, training
--- description: Learn all ascension skills automatically
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Tysong, elanthia-online
--- Ported to Revenant Lua from asclearn.lic v1.1.0
---
--- Changelog:
---   v1.1.0 (2025-10-01)
---     bake in levelup as a command option
---   v1.0.0 (2022-04-14)
---     initial release
---
--- Usage:
---   ;asclearn                            - learn all ascension skills
---   ;asclearn <mnemonic>                 - learn only given mnemonic
---   ;asclearn resist|stat|skill|regen|other - learn all in category
---   ;asclearn levelup                    - level up first, then train

silence_me()

local script_args = Script.vars[1]

if script_args and script_args:match("levelup") then
    if Stats.level < 20 then
        for _ = 1, (20 - Stats.level) do
            put("level up")
            pause(0.1)
            if Stats.level >= 19 then break end
        end

        pause(5)
        fput("info")
        fput("levelup")

        if Stats.level == 19 then
            fput("skills confirm")
            fput("skills confirm")
        end
    end

    while true do
        put("level up")
        pause(0.1)
        if Stats.exp > 90000000 then break end
    end
    script_args = nil
end

local results = quiet_command("asc list", "the following Ascension Abilities are available")
local asc_skills = {}

for _, line in ipairs(results or {}) do
    local mnemonic, ranks_current, ranks_max, subcategory =
        line:match("(%w+)</d>%s+(%d+)/(%d+).-(%a+)$")
    if mnemonic then
        -- Only accept valid subcategories
        local sub_lower = subcategory:lower()
        if sub_lower == "resist" or sub_lower == "stat" or sub_lower == "skill"
            or sub_lower == "other" or sub_lower == "regen" then
            asc_skills[#asc_skills + 1] = {
                mnemonic = mnemonic,
                ranks_current = tonumber(ranks_current),
                ranks_max = tonumber(ranks_max),
                subcategory = sub_lower,
            }
        end
    end
end

local function learn_skill(skill)
    for _ = 1, (skill.ranks_max - skill.ranks_current) do
        local result = dothistimeout("asc learn " .. skill.mnemonic, 3,
            "You do not have enough points available",
            "You have chosen to learn rank")
        if result and result:match("You do not have enough points available") then
            return true -- out of points, stop
        end
        fput("asc learn confirm")
    end
    return false
end

if script_args and script_args:lower():match("^(resist|stat|skill|other|regen)$") then
    local cat = script_args:lower()
    for _, skill in ipairs(asc_skills) do
        if skill.subcategory == cat then
            if learn_skill(skill) then return end
        end
    end
elseif script_args then
    local target = script_args:lower()
    for _, skill in ipairs(asc_skills) do
        if skill.mnemonic:lower() == target then
            if learn_skill(skill) then return end
        end
    end
else
    for _, skill in ipairs(asc_skills) do
        if learn_skill(skill) then return end
    end
end
