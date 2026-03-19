--- @revenant-script
--- name: almanac
--- version: 2.0
--- author: Ported from dr-scripts (original authors: Elanthipedia community)
--- game: dr
--- description: Passively use almanac for skill training during downtime.
--- tags: training, almanac, lore
--- @lic-certified: complete 2026-03-18
---
--- Settings (in your character YAML):
---   almanac_noun: "almanac"          -- item noun to get/use (required, must be in gear:)
---   almanac_skills: []               -- skills to target; empty = pick by mindstate
---   almanac_priority_skills: []      -- try these first before almanac_skills
---   almanac_no_use_scripts: []       -- skip if any of these scripts are running
---   almanac_no_use_rooms: []         -- skip if in these rooms (int=room ID, str=regex vs title)
---   almanac_report_details: false    -- echo which skill was trained and exp gained
---   almanac_startup_delay: 0         -- seconds to wait before first loop
---
--- Changes vs lich_repo_mirror version (now based on dr-scripts canonical):
---   - Configurable almanac noun (almanac_noun setting)
---   - All-skills-capped early exit
---   - Gear validation check at startup
---   - Safe script pause/unpause coordination (DRC.safe_pause_list)
---   - Configurable no-use room list (almanac_no_use_rooms)
---   - Priority skill list (almanac_priority_skills)
---   - Skill selection by rate-then-rank (not just rate)
---   - Fallback to skill_with_lowest_mindstate when no almanac_skills match
---   - Full study response handling: gleaned, worn pages, premium, closed almanac
---   - Report details mode (almanac_report_details)
---   - Correct cooldown: gleaned/worn → 60s retry, successful study → full 600s

local settings = get_settings()

-------------------------------------------------------------------------------
-- All-skills-capped check
-------------------------------------------------------------------------------

local function all_skills_capped()
    if not DRSkill then return false end
    local skill_list = DRSkill.list()
    if #skill_list == 0 then return false end  -- not parsed yet, don't exit
    for _, skill in ipairs(skill_list) do
        if skill.rank < 1750 then return false end
    end
    return true
end

if all_skills_capped() then
    DRC.message("All skills are capped, exiting")
    Script.exit()
end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local no_use_scripts   = settings.almanac_no_use_scripts or {}
local no_use_rooms     = settings.almanac_no_use_rooms or {}
local almanac_skills   = settings.almanac_skills or {}
local almanac_noun     = settings.almanac_noun or "almanac"
local priority_skills  = settings.almanac_priority_skills or {}
local report_details   = settings.almanac_report_details or false
local startup_delay    = settings.almanac_startup_delay or 0

-------------------------------------------------------------------------------
-- UserVars: last use timestamp (stored as string, read as number)
-------------------------------------------------------------------------------

local function get_last_use()
    return tonumber(UserVars.almanac_last_use) or (os.time() - 600)
end

local function set_last_use(t)
    UserVars.almanac_last_use = tostring(t)
end

if not UserVars.almanac_last_use then
    set_last_use(os.time() - 600)
end

-------------------------------------------------------------------------------
-- Gear validation: ensure almanac is listed in gear settings
-------------------------------------------------------------------------------

if settings.gear then
    local found = false
    for _, item in ipairs(settings.gear) do
        local item_name = type(item) == "table" and (item.name or "") or tostring(item)
        local adjective = type(item) == "table" and (item.adjective or "") or ""
        local pattern
        if adjective ~= "" then
            pattern = adjective:lower() .. "%s*" .. item_name:lower()
        else
            pattern = item_name:lower()
        end
        if pattern ~= "" and almanac_noun:lower():find(pattern, 1, true) then
            found = true
            break
        end
    end
    if not found then
        DRC.message("To minimize the possibility that items held in your hands could be lost,")
        DRC.message("they should be listed in your gear:. Your almanac (" .. almanac_noun .. ") is not listed.")
        DRC.message("Add it to gear: in your settings YAML. The script will now abort.")
        Script.exit()
    end
end

if startup_delay and startup_delay > 0 then
    pause(startup_delay)
end

-------------------------------------------------------------------------------
-- Skill selection helpers
-------------------------------------------------------------------------------

--- Select the skill with lowest learning rate (then lowest rank) from a list.
-- Only considers skills with xp < 18 (not near mind lock).
-- @param skill_list table Array of skill name strings
-- @return string|nil Skill name or nil if none eligible
local function almanac_sort_by_rate_then_rank(skill_list)
    if not skill_list or #skill_list == 0 then return nil end
    local eligible = {}
    for _, skill in ipairs(skill_list) do
        local xp = DRSkill.getxp(skill)
        if xp < 18 then
            eligible[#eligible + 1] = { name = skill, xp = xp, rank = DRSkill.getrank(skill) }
        end
    end
    if #eligible == 0 then return nil end
    table.sort(eligible, function(a, b)
        if a.xp ~= b.xp then return a.xp < b.xp end
        return a.rank < b.rank
    end)
    return eligible[1].name
end

--- Fallback: find the skill with the lowest mindstate across all tracked skills.
-- Excludes maxed (1750) and unranked (0) skills and Mechanical Lore.
-- Strips magic school prefixes (Lunar, Life, Arcane, Holy, Elemental) from result.
-- @return string|nil Skill name (stripped of school prefix) or nil
local function skill_with_lowest_mindstate()
    local skill_list = DRSkill.list()
    local eligible = {}
    for _, skill in ipairs(skill_list) do
        if skill.rank > 0 and skill.rank < 1750 and skill.name ~= "Mechanical Lore" then
            eligible[#eligible + 1] = skill
        end
    end
    if #eligible == 0 then return nil end
    table.sort(eligible, function(a, b) return a.exp < b.exp end)
    local name = eligible[1].name
    -- Strip guild magic school prefixes used as almanac turn targets
    name = name:gsub("^Lunar%s+", "")
               :gsub("^Life%s+", "")
               :gsub("^Arcane%s+", "")
               :gsub("^Holy%s+", "")
               :gsub("^Elemental%s+", "")
    return name
end

-------------------------------------------------------------------------------
-- Guard conditions
-------------------------------------------------------------------------------

local function should_not_use_almanac()
    -- Hidden or invisible
    if hidden and hidden() then return true end
    if invisible and invisible() then return true end

    -- Cooldown: 600 seconds between uses
    if (os.time() - get_last_use()) < 600 then return true end

    -- Blocking scripts
    for _, name in ipairs(no_use_scripts) do
        if running(name) then return true end
    end

    -- Blocking rooms (integer = map room ID, string = regex vs room title)
    local room_id = Map and Map.current_room and Map.current_room()
    local room_title = (GameState and GameState.room_name) or ""
    -- Strip outer brackets from DR title format "[Location, Area]" → "Location, Area"
    local room_title_inner = room_title:match("^%[(.-)%]$") or room_title
    for _, room in ipairs(no_use_rooms) do
        if type(room) == "number" then
            if room_id and room_id == room then return true end
        else
            if Regex.test(room, room_title_inner) then return true end
        end
    end

    -- Both hands full and almanac not already in hand
    local rh = DRC.right_hand()
    local lh = DRC.left_hand()
    if rh and lh and not DRCI.in_hands(almanac_noun) then return true end

    return false
end

-------------------------------------------------------------------------------
-- Study almanac (inner: send command and handle all responses)
-------------------------------------------------------------------------------

local function study_almanac()
    -- Snapshot skill baselines for reporting before we study
    if report_details and not running("exp-monitor") then
        DRSkill.reset_baselines()
    end

    local result = DRC.bput(
        "study my " .. almanac_noun,
        "You believe you've learned something significant about",
        "You've gleaned all the insight you can",
        "Study what",
        "interrupt your research",
        "The pages of the .* seem worn",
        "is only usable by a character with a Premium subscription",
        "STUDY its contents"
    )

    if result:find("STUDY its contents") then
        -- Almanac is closed — open it and retry
        DRC.bput("open my " .. almanac_noun, "You open")
        study_almanac()
        return
    end

    if result:find("You've gleaned all the insight you can") or result:find("The pages of the") then
        -- Short retry: gleaned all / worn pages resets cooldown to ~60s
        set_last_use(os.time() - 540)

    elseif result:find("is only usable by a character with a Premium subscription") then
        DRC.message("Premium almanac detected in a non-premium account. Exiting.")
        DRCI.put_away_item(almanac_noun)
        Script.exit()

    elseif result:find("You believe you've learned something significant about") then
        set_last_use(os.time())

        if report_details and not running("exp-monitor") then
            local gained_skill_name = result:match(
                "You believe you've learned something significant about ([^!]+)!"
            )
            if gained_skill_name then
                gained_skill_name = gained_skill_name:match("^%s*(.-)%s*$")
                local gained = DRSkill.gained_skills()
                local entry = gained[gained_skill_name]
                if entry then
                    local change = (entry.rank + entry.percent / 100.0) - entry.baseline
                    if change > 0 then
                        DRC.message(string.format(
                            "Almanac picked skill: %s, exp: %d/19",
                            gained_skill_name, DRSkill.getxp(gained_skill_name)
                        ), false)
                    end
                end
            end
        end
    end

    waitrt()
end

-------------------------------------------------------------------------------
-- Main almanac use (outer: select skill, pause scripts, get item, study, restore)
-------------------------------------------------------------------------------

local function use_almanac()
    -- Determine training skill
    local training_skill = nil
    if almanac_skills and #almanac_skills > 0 then
        training_skill = almanac_sort_by_rate_then_rank(priority_skills)
                      or almanac_sort_by_rate_then_rank(almanac_skills)
                      or skill_with_lowest_mindstate()
        echo("training skill is " .. tostring(training_skill))
        if not training_skill then return end
    end

    -- Safe-pause other scripts to prevent interference
    local scripts_to_unpause = DRC.safe_pause_list()

    waitrt()

    -- Brief pause + buffer clear so any last output from paused scripts settles
    pause(1)
    clear()

    -- Get the almanac (already held counts as success)
    if not (DRCI.get_item_if_not_held(almanac_noun) and DRCI.in_hands(almanac_noun)) then
        if DRCI.exists(almanac_noun) then
            DRC.message("Hands full, will try again later")
            DRC.safe_unpause_list(scripts_to_unpause)
            return
        else
            DRC.message("Almanac not found, exiting")
            DRC.safe_unpause_list(scripts_to_unpause)
            Script.exit()
        end
    end

    -- Turn to target skill if one was selected
    if training_skill then
        DRC.bput(
            "turn " .. almanac_noun .. " to " .. training_skill,
            "You turn", "You attempt to turn", "What topic"
        )
    end

    study_almanac()

    DRCI.put_away_item(almanac_noun)

    DRC.safe_unpause_list(scripts_to_unpause)
end

-------------------------------------------------------------------------------
-- Main loop
-------------------------------------------------------------------------------

while true do
    if not should_not_use_almanac() then
        use_almanac()
    end
    pause(1)
end
