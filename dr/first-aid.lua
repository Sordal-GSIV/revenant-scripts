--- @revenant-script
--- name: first-aid
--- version: 1.0.0
--- author: Lich5 community (dr-scripts); Revenant port by Sordal
--- game: dr
--- description: Trains First Aid skill (and optionally Scholarship) by studying anatomy chart compendiums or textbooks.
--- tags: first-aid, scholarship, training, anatomy
--- @lic-certified: complete 2026-03-18
---
--- Ported from first-aid.lic (Lich5/dr-scripts) to Revenant Lua.
--- Original: https://elanthipedia.play.net/Lich_script_repository#first-aid
--- Advanced Options: https://github.com/elanthia-online/dr-scripts/wiki/First-Aid-Strategy
---
--- Usage:
---   ;first-aid               - Train First Aid skill (default)
---   ;first-aid scholarship   - Focus Scholarship training (stop at XP cap)
---   ;first-aid both          - Train both First Aid and Scholarship equally
---
--- Settings (in your character YAML/setup):
---   bleed_bot: "NPC name"                 - Use bleed-bot mode: walk to bleed_bot_room, tendother that NPC
---   bleed_bot_room: 1234                  - Room ID to walk to for bleed-bot mode
---   textbook: true/false                  - Use textbook mode (default false = compendium mode)
---   textbook_type: "anatomy textbook"     - Name of the textbook item to study
---   compendium_type: "anatomy compendium" - Name of the compendium item to study
---   performance_pause: 3                  - Seconds to pause before starting performance script
---   number_of_firstaid_charts: 3          - Maximum charts to study per session
---   instrument: "lute"                    - If set, skip starting the performance script
---   firstaid_scholarship_modifier: 0      - Subtracted from Scholarship rank when selecting charts

-- ============================================================
-- Arg parsing
-- ============================================================

local skill_focus_raw = Script.vars[1]
local skill_focus

if skill_focus_raw and skill_focus_raw:lower() == "scholarship" then
    skill_focus = "Scholarship"
elseif skill_focus_raw and skill_focus_raw:lower() == "both" then
    skill_focus = "both"
else
    skill_focus = "First Aid"
end

echo("Skill focus is: " .. skill_focus)

-- ============================================================
-- Settings & data
-- ============================================================

local settings    = get_settings()
local chart_data  = get_data("anatomy-charts").first_aid_charts or {}

local performance_pause = settings.performance_pause or 3
local num_charts        = settings.number_of_firstaid_charts or 3

-- ============================================================
-- Helpers
-- ============================================================

--- Effective scholarship rank used to determine which charts are readable.
-- Applies firstaid_scholarship_modifier or the standard rank / 1.6 cap above 100.
local function effective_scholarship()
    local rank = DRSkill.getrank("Scholarship")
    if settings.firstaid_scholarship_modifier then
        return rank - (settings.firstaid_scholarship_modifier or 0)
    elseif rank <= 100 then
        return rank
    else
        return rank / 1.6
    end
end

--- Returns true when the target skill(s) have reached the XP cap (18/19 on
-- Revenant's 0–19 scale, equivalent to 32/34 in Lich5's 0–34 scale).
local function xp_capped()
    if skill_focus == "both" then
        return DRSkill.getxp("First Aid") >= 18 and DRSkill.getxp("Scholarship") >= 18
    else
        return DRSkill.getxp(skill_focus) >= 18
    end
end

--- Start the performance script if the character does not play an instrument.
local function ensure_performance()
    if not settings.instrument then
        pause(performance_pause)
        if not running("performance") then
            Script.run("performance", "noclean")
        end
    end
end

-- ============================================================
-- Core: study a filtered/sorted list of charts
-- ============================================================

--- @param charts table   Subset of chart_data: { [display_name] = {index, scholarship} }
--- @param booktype string Name of the book item (compendium or textbook)
local function study_charts(charts, booktype)
    local eff_schol = effective_scholarship()

    -- Build a flat list of eligible entries, sorted by scholarship descending.
    local eligible = {}
    for _, info in pairs(charts) do
        if info.scholarship <= eff_schol then
            eligible[#eligible + 1] = info
        end
    end
    table.sort(eligible, function(a, b) return a.scholarship > b.scholarship end)

    local studied = 0
    for _, info in ipairs(eligible) do
        if studied >= num_charts then break end
        if xp_capped() then break end

        local turn_result = DRC.bput(
            "turn my " .. booktype .. " to " .. info.index,
            "You turn", "That section does not exist", "Turn what?", "almost impossible to do"
        )

        if turn_result:find("You turn") then
            local study_result = DRC.bput(
                "study my " .. booktype,
                "You attempt to study",
                "find it almost impossible to do",
                "gradually absorbing",
                "difficult time comprehending the advanced text",
                "suddenly makes sense to you",
                "^Why ",
                "You need to be holding",
                "discerned all you can"
            )

            if study_result:find("gradually absorbing") then
                -- Keep studying up to 3 more times until comprehension or exhaustion.
                for _ = 1, 3 do
                    local r = DRC.bput(
                        "study my " .. booktype,
                        "Roundtime", "makes sense", "discerned all you can"
                    )
                    if r:find("makes sense") or r:find("discerned all you can") then break end
                end
            elseif study_result:find("You need to be holding") then
                DRC.bput("get my " .. booktype, "You get", "You are already holding")
            end

            waitrt()
            studied = studied + 1
        end
    end
end

-- ============================================================
-- Compendium mode
-- ============================================================

--- Get the book, look at it to see which charts are currently visible,
-- then study only those charts.
local function compendium_charts()
    ensure_performance()

    local booktype = settings.compendium_type
    if not DRCI.get_item_if_not_held(booktype) then
        DRC.message("Could not get " .. tostring(booktype) .. ", exiting.")
        return
    end

    -- Looking at the open compendium prints the current section and all chart names.
    DRC.bput("look my " .. booktype, "The %w+ lies open to the section on .+ physiology")
    pause(0.5)   -- let remaining output arrive before reget

    -- Parse indented lines from the look output (3-space indent = chart names).
    local recent = reget(40)
    local visible = {}
    for _, line in ipairs(recent) do
        if line:match("^   %S") then
            -- Strip leading/trailing whitespace to get the bare chart name.
            local name = line:match("^%s+(.-)%s*$")
            if name and name ~= "" then
                visible[name] = true
            end
        end
    end

    -- Keep only charts the compendium currently shows.
    local charts_to_read = {}
    for name, info in pairs(chart_data) do
        if visible[name] then
            charts_to_read[name] = info
        end
    end

    study_charts(charts_to_read, booktype)
end

-- ============================================================
-- Textbook mode
-- ============================================================

--- Get and open the textbook, then study all charts.
local function textbook_charts()
    ensure_performance()

    local booktype = settings.textbook_type
    if not DRCI.get_item_if_not_held(booktype) then
        DRC.message("Could not get " .. tostring(booktype) .. ", exiting.")
        return
    end

    DRC.bput("open my " .. booktype, "You open your", "That is already open")
    study_charts(chart_data, booktype)
end

-- ============================================================
-- Cleanup
-- ============================================================

before_dying(function()
    DRCI.stow_hands()
    if running("performance") then
        Script.kill("performance")
    end
end)

-- ============================================================
-- Entry point
-- ============================================================

if settings.bleed_bot then
    -- Bleed-bot mode: walk to the assigned room and let tendother handle the NPC.
    DRCT.walk_to(settings.bleed_bot_room)
    Script.run("tendother", settings.bleed_bot)
    pause(10)
    Script.kill("tendother")
elseif settings.textbook then
    textbook_charts()
else
    compendium_charts()
end
