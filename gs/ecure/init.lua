--- @revenant-script
--- @lic-audit: validated 2026-03-17
--- name: ecure
--- version: 2.0.3
--- author: elanthia-online
--- contributors: Tayre, Ashraam, Talonhawke, Naijin
--- description: Enhanced empath self-healing script
--- game: gs
---
--- Originally cure.lic — a combination of Heal (by Tayre) and Healself (by Ashraam).
--- Talonhawke heavily modified it. EO updated it for GTK3/Lich5.
---
--- Changelog (from Lich5):
---   v2.0.3 (2026-03-17)
---     - add --list CLI option to display current settings
---     - add --debug toggle for verbose troubleshooting output
---     - YARD documentation throughout
---     - extract shared spell-hindrance retry logic
---     - minor Ruby best-practice cleanup
---   v2.0.2 (2025-10-17)
---     - bugfix in regex for missing hand/arm/leg extra space
---   v2.0.1 (2025-09-27)
---     - bugfix in wait_for_mana infinite stack level
---     - fix to attempt APPRAISE up to 3 times due to failure
---     - fix in regex wound array
---   v2.0.0 (2025-09-27)
---     - rewrite into proper module/class structure
---     - regex fixes for additional injury matching
---     - retry on spell hindrance
---     - condense GUI window
---     - add Exertion curing
---   v1.0.3 (2023-07-26)
---     - correct sleep/pauses for CURE usage for less than 3 second RT
---   v1.0.2 (2023-07-26)
---     - fix for NilClass comparison for @doneVerb
---     - fix for enabling use of CoL signs but not knowing Clotting or Staunching
---   v1.0.1 (2023-05-22)
---     - fixed group functionality after Naijin's return
---   v1.0.0 (2023-04-08)
---     - Rebase cure.lic to ecure.lic
---     - rubocop cleanup
---   Prior cure.lic changelog:
---     v1.2 (2021-09-20) - Modifications by EO to support aligned menus
---     v1.1 (2019-08-01) - Fixed some messaging
---     v1.0              - Initial release

local config = require("config")
local healer = require("healer")
local gui = require("gui_settings")

-- Empath-only check
if Stats.prof ~= "Empath" then
    respond("Nice try, non-empath person!")
    return
end

silence_me()
before_dying(function() DownstreamHook.remove("Appraising") end)

local settings = config.load()
local args = Script.vars
local first = (args[1] or ""):lower()

-- --debug toggle
if first == "--debug" then
    settings.debug = not settings.debug
    config.save(settings)
    respond("ECure debug mode: " .. (settings.debug and "ON" or "OFF"))
    return
end

-- --list: show current settings
if first == "--list" then
    local w = 16
    respond("=[ ECure Settings: " .. Char.name .. " ]=")
    respond(string.format("%-" .. w .. "s: %s", "Mode", settings.mode or "heal"))
    respond(string.format("%-" .. w .. "s: %s", "Done Verb", (settings.done_verb == "" and "(none)" or settings.done_verb)))
    respond(string.format("%-" .. w .. "s: %s", "Use Signs", tostring(settings.use_signs)))
    respond(string.format("%-" .. w .. "s: %s", "Troll's Blood", tostring(settings.use_trolls_blood)))
    respond(string.format("%-" .. w .. "s: %s", "Alt Behavior", tostring(settings.alternative_behavior)))
    respond(string.format("%-" .. w .. "s: %s", "Head/Nerve Pri.", tostring(settings.head_nerve_priority)))
    respond(string.format("%-" .. w .. "s: %d", "All Wounds Lvl", settings.all_wounds_level or 0))
    respond(string.format("%-" .. w .. "s: %d", "All Scars Lvl", settings.all_scars_level or 0))
    respond(string.format("%-" .. w .. "s: %s", "Debug", settings.debug and "ON" or "OFF"))
    respond("")
    respond("--- Per-Part Thresholds (" .. (settings.mode or "heal") .. " mode) ---")
    respond(string.format("%-12s  %-6s  %s", "Part", "Wounds", "Scars"))
    respond(string.rep("-", 30))
    for _, part in ipairs(config.BODY_PARTS) do
        local w_lvl = config.wound_level(settings, part)
        local s_lvl = config.scar_level(settings, part)
        respond(string.format("%-12s  %-6d  %d", part, w_lvl, s_lvl))
    end
    return
end

-- setup / options: show GUI
if first == "setup" or first == "options" then
    gui.show(settings)
    return
end

-- help
if first == "help" then
    respond("ECure - Enhanced Healing Script")
    respond("  ;ecure              - Heal yourself")
    respond("  ;ecure setup        - Open configuration GUI")
    respond("  ;ecure <names>      - Heal specific targets")
    respond("  ;ecure group        - Heal group members")
    respond("  ;ecure room         - Heal everyone in room")
    respond("  ;ecure all          - Heal completely (overrides settings)")
    respond("  ;ecure hunt/heal    - Switch active mode")
    respond("  ;ecure --list       - Show current settings")
    respond("  ;ecure --debug      - Toggle debug output")
    return
end

-- Process modifiers
local has_all = false
local targets = {}
local reserved = { hunt=true, heal=true, group=true, room=true, all=true, setup=true, options=true, help=true }

for i = 1, 20 do
    local arg = (args[i] or ""):lower()
    if arg == "" then break end
    if arg == "all" then
        has_all = true
    elseif arg == "hunt" then
        settings.mode = "hunt"
    elseif arg == "heal" then
        settings.mode = "heal"
    elseif not reserved[arg] and not arg:match("^%-%-") then
        targets[#targets + 1] = args[i]  -- preserve case for names
    end
end

if has_all then
    settings.all_wounds_level = 0
    settings.all_scars_level = 0
end

-- Determine action
if first == "room" then
    healer.heal_room(settings)
    healer.heal_self(settings)
elseif first == "group" then
    fput("group")
    pause(1)
    healer.heal_group(settings)
    healer.heal_self(settings)
elseif #targets > 0 then
    respond("Attempting to heal " .. table.concat(targets, ", "))
    -- Resolve target names to PCs in room
    local pcs = GameObj.pcs()
    for _, target_input in ipairs(targets) do
        local found = false
        for _, pc in ipairs(pcs) do
            if pc.noun:lower():find("^" .. target_input:lower()) then
                healer.heal_target(settings, pc.noun)
                found = true
                break
            end
        end
        if not found then
            respond("Could not find: " .. target_input)
        end
    end
    healer.heal_self(settings)
else
    healer.heal_self(settings)
end

-- Alt behavior: exit after any args were passed (not just named targets)
if settings.alternative_behavior and #Script.vars > 0 then
    return
end
