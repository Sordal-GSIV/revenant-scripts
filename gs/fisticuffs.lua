--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: fisticuffs
--- version: 1.32
--- author: Bhuryn
--- game: gs
--- description: UCS (Unarmed Combat System) auto-combat script with tiering, PSM management, and follow-up attacks
--- tags: UCS, Unarmed, Combo, Brawling, combat
---
--- Spiritual Guide: Combo.lic
---
--- Changelog (from original):
---   v0.1        - Initial Release
---   v0.2-v1.25  - Buncha changes, supports fury, clash and spin kick
---   v1.26       - Followups now only come from normal UCS swings, clear on target changes,
---                 stale target positioning falls back to tierup
---   v1.27       - Added optional Twin Hammerfists setup usage before normal UCS swings
---   v1.28       - Adjusted tiering so only excellent positioning uses tier3;
---                 decent and good use tierup unless a followup overrides
---   v1.29       - Twin Hammerfists setup is now only attempted once as an opening action
---                 instead of repeating during combat
---   v1.30       - Opening Twin Hammerfists now triggers when live hostiles are present even
---                 if GS has not populated an explicit current target yet
---   v1.31       - Opening Twin Hammerfists now always schedules followup combat so a miss
---                 does not stall the script
---   v1.32       - Simplified return stance handling to wait out RT and send the stance
---                 directly at combat end
---
--- Known issues: Spin kick isn't always fired. Sometimes it likes to jab too much when it
---   shouldn't, not sure if room move works to stop it yet. Needs more testing.
---
--- Usage:
---   ;fisticuffs              - Start auto-combat
---   ;fisticuffs settings     - Show current settings
---   ;fisticuffs tierup <jab|punch|grapple|kick>
---   ;fisticuffs tier3 <punch|grapple|kick>
---   ;fisticuffs stance <offensive|advance|forward|neutral|guarded|defensive>
---   ;fisticuffs aim <bodypart|off>
---   ;fisticuffs kick <on|off>
---   ;fisticuffs single <on|off>
---   ;fisticuffs roomstop <on|off>
---   ;fisticuffs fury <on|off>
---   ;fisticuffs clash <on|off>
---   ;fisticuffs clashmin <number>
---   ;fisticuffs spinkick <on|off>
---   ;fisticuffs setup <on|off>
---   ;fisticuffs help

---------------------------------------------------------------------------
-- Settings defaults
---------------------------------------------------------------------------

if not CharSettings.fisticuffs_tierup then
    CharSettings.fisticuffs_tierup = "jab"
end
if not CharSettings.fisticuffs_tier3 then
    CharSettings.fisticuffs_tier3 = "punch"
end
if not CharSettings.fisticuffs_stance then
    CharSettings.fisticuffs_stance = "defensive"
end
-- fisticuffs_aim defaults to nil (no aiming)
if CharSettings.fisticuffs_allow_kick == nil then
    CharSettings.fisticuffs_allow_kick = "true"
end
if CharSettings.fisticuffs_single == nil then
    CharSettings.fisticuffs_single = "false"
end
if CharSettings.fisticuffs_roomstop == nil then
    CharSettings.fisticuffs_roomstop = "false"
end
if CharSettings.fisticuffs_use_fury == nil then
    CharSettings.fisticuffs_use_fury = "false"
end
if CharSettings.fisticuffs_use_clash == nil then
    CharSettings.fisticuffs_use_clash = "false"
end
if not CharSettings.fisticuffs_clash_min then
    CharSettings.fisticuffs_clash_min = "3"
end
if CharSettings.fisticuffs_use_spinkick == nil then
    CharSettings.fisticuffs_use_spinkick = "false"
end
if CharSettings.fisticuffs_use_setup == nil then
    CharSettings.fisticuffs_use_setup = "false"
end

---------------------------------------------------------------------------
-- Settings helpers (CharSettings stores strings, so we need bool converters)
---------------------------------------------------------------------------

local function setting_bool(key)
    return CharSettings[key] == "true"
end

local function setting_set_bool(key, val)
    CharSettings[key] = val and "true" or "false"
end

local function setting_int(key)
    return tonumber(CharSettings[key]) or 0
end

---------------------------------------------------------------------------
-- Positioning / target tracking state
---------------------------------------------------------------------------

local fist_position = "decent"
local fist_position_target_id = nil
local fist_position_target_name = nil
local fist_sticky_excellent = false
local fist_expected_target_id = nil
local fist_expected_target_name = nil
local fist_last_action_source = nil  -- "attack", "weapon_skill", "spinkick", "setup"
local fist_setup_attempted = false

---------------------------------------------------------------------------
-- Regex patterns (compiled once)
---------------------------------------------------------------------------

local NO_TARGET_PATTERNS = {
    "You currently have no valid target",
    "^You do not have a target%.",
    "^What were you referring to%?$",
    "^It looks like somebody already did the job for you%.$",
    "^Could not find a valid target%.",
    "^There are no other valid targets%.$",
}

local UNREACHABLE_PATTERN = "You can't reach .* from here%."

---------------------------------------------------------------------------
-- Utility: string helpers
---------------------------------------------------------------------------

local function str_strip(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function str_lower(s)
    if not s then return "" end
    return string.lower(s)
end

local function str_empty(s)
    return s == nil or str_strip(s) == ""
end

---------------------------------------------------------------------------
-- Target name normalization
---------------------------------------------------------------------------

local function normalize_target_name(text)
    if not text then return "" end
    local s = str_lower(str_strip(text))
    -- Remove leading "a " or "an "
    s = s:gsub("^an?%s+", "")
    return str_strip(s)
end

---------------------------------------------------------------------------
-- Target matching: does a positioning line name match our current target?
---------------------------------------------------------------------------

local function matches_line(line_text, pattern)
    if not line_text then return false end
    return string.find(line_text, pattern) ~= nil
end

local function matches_no_target(text)
    if not text then return false end
    for _, pat in ipairs(NO_TARGET_PATTERNS) do
        if string.find(text, pat) then return true end
    end
    return false
end

local function matches_unreachable(text)
    if not text then return false end
    return string.find(text, UNREACHABLE_PATTERN) ~= nil
end

---------------------------------------------------------------------------
-- GameObj wrappers (safe access)
---------------------------------------------------------------------------

local function hostile_targets()
    local ok, result = pcall(function() return GameObj.targets() end)
    if ok and result then return result end
    return {}
end

local function dead_targets()
    local ok, result = pcall(function() return GameObj.dead() end)
    if ok and result then return result end
    return {}
end

local function current_target_obj()
    local ok, result = pcall(function() return GameObj.target() end)
    if ok then return result end
    return nil
end

local function current_target_id()
    local tgt = current_target_obj()
    if tgt then return tgt.id end
    return nil
end

local function current_attack_target_name()
    local ok, tgt = pcall(current_target_obj)
    if not ok or not tgt then return nil end
    return normalize_target_name(tgt.name or tgt.noun)
end

---------------------------------------------------------------------------
-- Target alive/dead checks
---------------------------------------------------------------------------

local function target_in_dead_list(npc)
    if not npc then return false end
    local ok, dead = pcall(dead_targets)
    if not ok or not dead then return false end
    for _, d in ipairs(dead) do
        if d.id == npc.id then return true end
    end
    return false
end

local function dead_npc(npc)
    if npc == nil then return true end
    local ok, status = pcall(function() return npc.status end)
    if ok and status then
        local s = str_lower(tostring(status))
        if s:find("dead") or s:find("corpse") or s:find("gone") then
            return true
        end
    end
    if target_in_dead_list(npc) then return true end
    return false
end

local function live_hostile_targets()
    local targets = hostile_targets()
    local live = {}
    for _, npc in ipairs(targets) do
        if not dead_npc(npc) then
            table.insert(live, npc)
        end
    end
    return live
end

local function living_target_count()
    return #live_hostile_targets()
end

local function current_target_alive()
    local tgt = current_target_obj()
    if tgt == nil then return false end
    return not dead_npc(tgt)
end

local function refresh_combat_state()
    -- In Revenant, game state is maintained automatically via XML stream.
    -- This is a no-op placeholder matching the Ruby original's status_tags call.
end

local function no_targets_left()
    refresh_combat_state()
    if current_target_alive() then return false end
    return #live_hostile_targets() == 0
end

---------------------------------------------------------------------------
-- Target memory
---------------------------------------------------------------------------

local function remembered_attack_target_id()
    return current_target_id() or fist_expected_target_id
end

local function remember_attack_target(target_obj)
    local tgt = target_obj or current_target_obj()
    if not tgt then return end
    local ok, _ = pcall(function()
        fist_expected_target_id = tgt.id
        fist_expected_target_name = normalize_target_name(tgt.name or tgt.noun)
    end)
end

local function reset_sticky_excellent()
    fist_sticky_excellent = false
    fist_position_target_id = nil
    fist_position_target_name = nil
    fist_expected_target_id = nil
    fist_expected_target_name = nil
end

---------------------------------------------------------------------------
-- Positioning state updates
---------------------------------------------------------------------------

local function positioning_line_matches_current_target(line_target_name)
    local ok, result = pcall(function()
        local normalized_line = normalize_target_name(line_target_name)
        local candidates = {}

        local tgt = current_target_obj()
        if tgt then
            if tgt.name then table.insert(candidates, normalize_target_name(tgt.name)) end
            if tgt.noun then table.insert(candidates, normalize_target_name(tgt.noun)) end
        end

        if fist_expected_target_name then table.insert(candidates, fist_expected_target_name) end
        if fist_position_target_name then table.insert(candidates, fist_position_target_name) end

        -- Remove empty entries
        local filtered = {}
        for _, c in ipairs(candidates) do
            if c and c ~= "" then table.insert(filtered, c) end
        end

        if #filtered == 0 then return true end

        -- Deduplicate and check
        local seen = {}
        for _, c in ipairs(filtered) do
            if not seen[c] then
                seen[c] = true
                if c == normalized_line then return true end
            end
        end
        return false
    end)
    if not ok then return true end
    return result
end

local function update_position_state_from_text(new_position, line_target_name)
    local target_id = remembered_attack_target_id()
    local target_name = normalize_target_name(line_target_name)

    if str_empty(target_name) then
        target_name = current_attack_target_name() or fist_expected_target_name or fist_position_target_name
    end

    if target_id == nil then
        fist_position = new_position
        if new_position ~= "excellent" then
            fist_sticky_excellent = false
        end
        return
    end

    if fist_position_target_id ~= target_id then
        fist_sticky_excellent = false
    end

    fist_position = new_position
    fist_position_target_id = target_id
    if target_name and target_name ~= "" then
        fist_position_target_name = target_name
    end

    if new_position == "excellent" then
        fist_sticky_excellent = true
    else
        fist_sticky_excellent = false
    end
end

---------------------------------------------------------------------------
-- Stance helpers
---------------------------------------------------------------------------

local function desired_return_stance()
    return CharSettings.fisticuffs_stance or "defensive"
end

local function send_return_stance()
    local ok, _ = pcall(function()
        waitrt()
        fput("stance " .. desired_return_stance())
    end)
    return ok
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

local function cleanup_and_exit(message)
    message = message or "Combat ended."
    send_return_stance()
    echo(message)
    -- exit() will trigger before_dying hooks
    error("__fisticuffs_exit__")
end

---------------------------------------------------------------------------
-- Attack helpers
---------------------------------------------------------------------------

local function kick_substitute_attack()
    local sub = str_lower(str_strip(CharSettings.fisticuffs_tier3 or ""))
    if sub == "" or sub == "kick" then return "punch" end
    return sub
end

local function sanitize_attack(attack)
    attack = str_lower(str_strip(tostring(attack or "")))
    if attack == "kick" and not setting_bool("fisticuffs_allow_kick") then
        return kick_substitute_attack()
    end
    return attack
end

local function single_target_done(locked_target_id)
    if not setting_bool("fisticuffs_single") then return false end
    if locked_target_id == nil then return false end
    local live = live_hostile_targets()
    for _, npc in ipairs(live) do
        if npc.id == locked_target_id then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Choose attack based on positioning
---------------------------------------------------------------------------

local function choose_attack(position, followup_attack)
    if followup_attack and not str_empty(followup_attack) then
        return sanitize_attack(followup_attack)
    end

    local current_id = current_target_id()
    if current_id == nil then
        return sanitize_attack(CharSettings.fisticuffs_tierup)
    end

    local effective_position = "decent"

    if current_id ~= nil
       and fist_position_target_id ~= nil
       and current_id ~= fist_position_target_id then
        reset_sticky_excellent()
        fist_position = "decent"
    elseif current_id ~= nil
       and fist_position_target_id == current_id
       and not str_empty(fist_position) then
        effective_position = fist_position
    end

    if fist_sticky_excellent
       and current_id ~= nil
       and fist_position_target_id == current_id then
        return sanitize_attack(CharSettings.fisticuffs_tier3)
    end

    local attack
    if effective_position:find("excellent") then
        attack = CharSettings.fisticuffs_tier3
    else
        attack = CharSettings.fisticuffs_tierup
    end

    return sanitize_attack(attack)
end

---------------------------------------------------------------------------
-- Send attack command
---------------------------------------------------------------------------

local function send_attack_command(cmd)
    if not standing() then fput("stand") end
    if not (GameState.stance_value == 0) then fput("stance offensive") end
    remember_attack_target()
    put(cmd)
    return "ok"
end

---------------------------------------------------------------------------
-- Do attack
---------------------------------------------------------------------------

local function do_attack(position, followup_attack, use_aim)
    if use_aim == nil then use_aim = true end
    local attack_type = choose_attack(position, followup_attack)
    local aimed = use_aim and CharSettings.fisticuffs_aim and not attack_type:find("jab")
    fist_last_action_source = "attack"

    if aimed then
        send_attack_command(attack_type .. " " .. CharSettings.fisticuffs_aim)
    else
        send_attack_command(attack_type)
    end

    return {
        status = "ok",
        position = position,
        attack_type = attack_type,
        aimed = aimed,
        followup_attack = followup_attack,
    }
end

---------------------------------------------------------------------------
-- PSM / Weapon skill helpers
---------------------------------------------------------------------------

local function psm_ready(skill_name)
    local ok, result = pcall(function()
        if not Weapon.known(skill_name) then return false end
        if not Weapon.available(skill_name) then return false end
        if not PSMS.assess(skill_name, "Weapon", true) then return false end
        return true
    end)
    if not ok then return false end
    return result
end

local function weapon_skill_command(skill_name)
    local tgt = current_target_obj()
    if tgt then
        return "weapon " .. skill_name .. " #" .. tgt.id
    else
        return "weapon " .. skill_name
    end
end

local function wait_seconds_from_result(result_text)
    local text = tostring(result_text or "")
    local n

    n = text:match("^%.%.%.wait (%d+) seconds?%.$")
    if n then return tonumber(n) end

    n = text:match("^[Ww]ait (%d+) sec")
    if n then return tonumber(n) end

    n = text:match("^Roundtime:%s*(%d+) sec")
    if n then return tonumber(n) end

    return nil
end

local function run_weapon_skill(skill_name)
    local ok, result = pcall(function()
        local cmd = weapon_skill_command(skill_name)
        fist_last_action_source = "weapon_skill"
        remember_attack_target()

        local raw = dothistimeout(cmd, 4,
            "^You ",
            "^Your mind clouds",
            "^And give yourself away",
            "^But your hands are full",
            "attempting to .+ would be a rather awkward proposition",
            "%.%.%.wait %d+ sec",
            "^[Ww]ait %d+ sec",
            "^Roundtime:",
            "You currently have no valid target",
            "^You do not have a target%.",
            "^What were you referring to%?",
            "^It looks like somebody already did the job for you%.",
            "^Could not find a valid target%.",
            "^There are no other valid targets%.",
            "You can't reach .* from here%.")

        if not raw then return false end

        if matches_no_target(raw) then return "no_target" end
        if matches_unreachable(raw) then return "unreachable" end

        local wait_secs = wait_seconds_from_result(raw)
        if wait_secs then return { "wait", wait_secs } end

        -- Check for PSM failure messages (e.g. "You are unable to do that right now.")
        if PSMS and PSMS.is_failure(raw) then return false end

        return true
    end)
    if not ok then return false end
    return result
end

local function run_reaction_skill(cmd)
    local ok, result = pcall(function()
        local raw = dothistimeout(cmd, 4,
            "^You ",
            "%.%.%.wait %d+ sec",
            "^[Ww]ait %d+ sec",
            "^Roundtime:",
            "You currently have no valid target",
            "^You do not have a target%.",
            "^What were you referring to%?",
            "^It looks like somebody already did the job for you%.",
            "^Could not find a valid target%.",
            "^There are no other valid targets%.",
            "You can't reach .* from here%.")

        if not raw then return false end
        if matches_no_target(raw) then return "no_target" end
        if matches_unreachable(raw) then return "unreachable" end
        return true
    end)
    if not ok then return false end
    return result
end

---------------------------------------------------------------------------
-- PSM attempts: Clash, Fury, Spin Kick, Twin Hammerfists setup
---------------------------------------------------------------------------

local function try_clash()
    if not setting_bool("fisticuffs_use_clash") then return false end
    if living_target_count() < setting_int("fisticuffs_clash_min") then return false end
    if not psm_ready("Clash") then return false end
    return run_weapon_skill("clash")
end

local function try_fury()
    if not setting_bool("fisticuffs_use_fury") then return false end
    if not psm_ready("Fury") then return false end
    if not current_target_alive() then return false end
    return run_weapon_skill("fury")
end

local function try_spinkick()
    if not setting_bool("fisticuffs_use_spinkick") then return false end
    fist_last_action_source = "spinkick"
    local ok, _ = pcall(function() put("weapon spin kick") end)
    return ok
end

local function twinhammer_known()
    local ok, result = pcall(function()
        return Weapon.known("Twin Hammerfists") or Weapon.known("twinhammer")
    end)
    if not ok then return false end
    return result
end

local function twinhammer_available()
    local ok, result = pcall(function()
        return Weapon.available("Twin Hammerfists") or Weapon.available("twinhammer")
    end)
    if not ok then return false end
    return result
end

local function try_setup()
    if not setting_bool("fisticuffs_use_setup") then return false end
    if not current_target_alive() and living_target_count() <= 0 then return false end
    if not twinhammer_known() then return false end
    if not twinhammer_available() then return false end
    fist_last_action_source = "setup"
    return run_reaction_skill("weapon twinhammer")
end

---------------------------------------------------------------------------
-- Line reading with timeout
---------------------------------------------------------------------------

local function next_line_or_nil(timeout_seconds)
    timeout_seconds = timeout_seconds or 0.15
    -- Use get_noblock or a brief timed wait
    -- In Revenant, we use matchtimeout with a very short timeout to simulate
    local line = get_noblock()
    if line then return line end
    -- Small pause to avoid tight-looping, then try once more
    pause(timeout_seconds)
    return get_noblock()
end

---------------------------------------------------------------------------
-- Room change detection
---------------------------------------------------------------------------

local function room_changed(start_room_id)
    if not setting_bool("fisticuffs_roomstop") then return false end
    return Room.id ~= start_room_id
end

---------------------------------------------------------------------------
-- Target cycling
---------------------------------------------------------------------------

local function try_target_next()
    local ok, result = pcall(function()
        local raw = dothistimeout("target next", 2,
            "^You are now targeting ",
            "^Could not find a valid target%.$",
            "^There are no other valid targets%.$",
            "^You do not have a target%.$",
            "^What were you referring to%?$")

        if not raw then return false end
        if raw:find("Could not find a valid target") then return false end
        if raw:find("There are no other valid targets") then return false end
        if raw:find("You do not have a target") then return false end
        if raw:find("What were you referring to") then return false end

        reset_sticky_excellent()
        return true
    end)
    if not ok then return false end
    return result
end

---------------------------------------------------------------------------
-- Unreachable target handling
---------------------------------------------------------------------------

local function handle_unreachable_target(position, pending_followup)
    refresh_combat_state()
    if living_target_count() <= 1 then return "wait", nil end
    if not try_target_next() then return "wait", nil end
    return "attack_sent", do_attack(position, nil)
end

---------------------------------------------------------------------------
-- Recover failed attack (e.g. aim too high, unreachable)
---------------------------------------------------------------------------

local function recover_failed_attack(last_attack_context)
    local position = last_attack_context.position
    local followup_attack = last_attack_context.followup_attack

    if last_attack_context.aimed then
        return "attack_sent", do_attack(position, followup_attack, false)
    end

    return handle_unreachable_target(position, followup_attack)
end

---------------------------------------------------------------------------
-- Main action performer
---------------------------------------------------------------------------

local function perform_next_action(position, single_target_id, pending_followup)
    if single_target_done(single_target_id) then
        return "break", pending_followup, nil, nil
    end
    if no_targets_left() then
        return "break", pending_followup, nil, nil
    end

    -- Try Clash
    local clash_result = try_clash()
    if clash_result == "no_target" then
        return "break", pending_followup, nil, nil
    elseif clash_result == "unreachable" then
        local us, ar = handle_unreachable_target(position, pending_followup)
        if us == "wait" then
            return "wait", pending_followup, nil, 0.25
        end
        return "continue", pending_followup, ar, nil
    elseif type(clash_result) == "table" and clash_result[1] == "wait" then
        return "wait", pending_followup, nil, clash_result[2]
    elseif clash_result == true then
        return "continue", pending_followup, nil, nil
    end

    -- Try Fury
    local fury_result = try_fury()
    if fury_result == "no_target" then
        return "break", pending_followup, nil, nil
    elseif fury_result == "unreachable" then
        local us, ar = handle_unreachable_target(position, pending_followup)
        if us == "wait" then
            return "wait", pending_followup, nil, 0.25
        end
        return "continue", pending_followup, ar, nil
    elseif type(fury_result) == "table" and fury_result[1] == "wait" then
        return "wait", pending_followup, nil, fury_result[2]
    elseif fury_result == true then
        return "continue", pending_followup, nil, nil
    end

    -- Normal attack
    return "ok", pending_followup, do_attack(position, pending_followup), nil
end

---------------------------------------------------------------------------
-- Settings display
---------------------------------------------------------------------------

local function echo_settings()
    respond("fisticuffs settings:")
    respond("  tierup: " .. (CharSettings.fisticuffs_tierup or "jab"))
    respond("  tier3: " .. (CharSettings.fisticuffs_tier3 or "punch"))
    respond("  stance: " .. (CharSettings.fisticuffs_stance or "defensive"))
    respond("  aim: " .. (CharSettings.fisticuffs_aim or "off"))
    respond("  kick: " .. (setting_bool("fisticuffs_allow_kick") and "on" or "off"))
    respond("  single: " .. (setting_bool("fisticuffs_single") and "on" or "off"))
    respond("  roomstop: " .. (setting_bool("fisticuffs_roomstop") and "on" or "off"))
    respond("  fury: " .. (setting_bool("fisticuffs_use_fury") and "on" or "off"))
    respond("  clash: " .. (setting_bool("fisticuffs_use_clash") and "on" or "off"))
    respond("  clashmin: " .. (CharSettings.fisticuffs_clash_min or "3"))
    respond("  spinkick: " .. (setting_bool("fisticuffs_use_spinkick") and "on" or "off"))
    respond("  setup: " .. (setting_bool("fisticuffs_use_setup") and "on" or "off"))
end

---------------------------------------------------------------------------
-- CLI command handling
---------------------------------------------------------------------------

local cmd = str_lower(str_strip(Script.vars[1] or ""))

if cmd ~= "" then

    if cmd == "tierup" then
        if Script.vars[2] then
            CharSettings.fisticuffs_tierup = str_lower(Script.vars[2])
            respond("Tierup attack set to " .. CharSettings.fisticuffs_tierup)
        else
            respond("Usage: ;fisticuffs tierup <jab|punch|grapple|kick>")
            respond("Current: " .. (CharSettings.fisticuffs_tierup or "jab"))
            respond("Used to build positioning.")
        end
        return

    elseif cmd == "tier3" then
        if Script.vars[2] then
            CharSettings.fisticuffs_tier3 = str_lower(Script.vars[2])
            respond("Tier3 attack set to " .. CharSettings.fisticuffs_tier3)
        else
            respond("Usage: ;fisticuffs tier3 <punch|grapple|kick>")
            respond("Current: " .. (CharSettings.fisticuffs_tier3 or "punch"))
            respond("Used when positioning is excellent.")
        end
        return

    elseif cmd == "stance" then
        local valid_stances = {
            offensive = true, advance = true, forward = true,
            neutral = true, guarded = true, defensive = true,
        }
        if Script.vars[2] then
            local stance_value = str_lower(Script.vars[2])
            if valid_stances[stance_value] then
                CharSettings.fisticuffs_stance = stance_value
                respond("Return stance set to " .. CharSettings.fisticuffs_stance)
            else
                respond("Invalid stance: " .. Script.vars[2])
                respond("Valid stances: offensive, advance, forward, neutral, guarded, defensive")
            end
        else
            respond("Usage: ;fisticuffs stance <offensive|advance|forward|neutral|guarded|defensive>")
            respond("Current: " .. (CharSettings.fisticuffs_stance or "defensive"))
            respond("Stance you return to after combat.")
        end
        return

    elseif cmd == "aim" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs aim <bodypart>")
            respond("       ;fisticuffs aim off")
            respond("Current: " .. (CharSettings.fisticuffs_aim or "off"))
        elseif str_lower(Script.vars[2]) == "off" then
            CharSettings.fisticuffs_aim = nil
            respond("Aiming disabled.")
        else
            -- Join remaining args for multi-word body parts like "right leg"
            local parts = {}
            local i = 2
            while Script.vars[i] do
                table.insert(parts, Script.vars[i])
                i = i + 1
            end
            CharSettings.fisticuffs_aim = table.concat(parts, " ")
            respond("Aiming at " .. CharSettings.fisticuffs_aim)
        end
        return

    elseif cmd == "kick" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs kick <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_allow_kick") and "on" or "off"))
            respond("If off, kick attacks are replaced with your tier3 attack, unless tier3 is kick, then punch.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_allow_kick", true)
            respond("Kick enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_allow_kick", false)
            respond("Kick disabled -- substituted with tier3 attack, or punch if tier3 is kick.")
        else
            respond("Usage: ;fisticuffs kick <on|off>")
        end
        return

    elseif cmd == "single" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs single <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_single") and "on" or "off"))
            respond("Stops after the current target dies.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_single", true)
            respond("Single-target mode enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_single", false)
            respond("Single-target mode disabled.")
        else
            respond("Usage: ;fisticuffs single <on|off>")
        end
        return

    elseif cmd == "roomstop" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs roomstop <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_roomstop") and "on" or "off"))
            respond("Stops script if you move rooms.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_roomstop", true)
            respond("Room-stop enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_roomstop", false)
            respond("Room-stop disabled.")
        else
            respond("Usage: ;fisticuffs roomstop <on|off>")
        end
        return

    elseif cmd == "fury" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs fury <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_use_fury") and "on" or "off"))
            respond("Uses Fury when available and stamina allows.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_use_fury", true)
            respond("Fury enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_use_fury", false)
            respond("Fury disabled.")
        else
            respond("Usage: ;fisticuffs fury <on|off>")
        end
        return

    elseif cmd == "clash" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs clash <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_use_clash") and "on" or "off"))
            respond("Uses Clash when enough hostile targets are in the room.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_use_clash", true)
            respond("Clash enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_use_clash", false)
            respond("Clash disabled.")
        else
            respond("Usage: ;fisticuffs clash <on|off>")
        end
        return

    elseif cmd == "clashmin" then
        if Script.vars[2] and tonumber(Script.vars[2]) and tonumber(Script.vars[2]) > 0 then
            CharSettings.fisticuffs_clash_min = tostring(math.floor(tonumber(Script.vars[2])))
            respond("Clash minimum targets set to " .. CharSettings.fisticuffs_clash_min)
        else
            respond("Usage: ;fisticuffs clashmin <number>")
            respond("Current: " .. (CharSettings.fisticuffs_clash_min or "3"))
            respond("Minimum living hostile targets before Clash is used.")
        end
        return

    elseif cmd == "spinkick" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs spinkick <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_use_spinkick") and "on" or "off"))
            respond("Uses weapon spinkick immediately when the game says: You could use this opportunity to Spin Kick!")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_use_spinkick", true)
            respond("Spin Kick enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_use_spinkick", false)
            respond("Spin Kick disabled.")
        else
            respond("Usage: ;fisticuffs spinkick <on|off>")
        end
        return

    elseif cmd == "setup" then
        if not Script.vars[2] then
            respond("Usage: ;fisticuffs setup <on|off>")
            respond("Current: " .. (setting_bool("fisticuffs_use_setup") and "on" or "off"))
            respond("Uses Twin Hammerfists when it is available before a normal UCS swing.")
        elseif str_lower(Script.vars[2]) == "on" then
            setting_set_bool("fisticuffs_use_setup", true)
            respond("Setup enabled.")
        elseif str_lower(Script.vars[2]) == "off" then
            setting_set_bool("fisticuffs_use_setup", false)
            respond("Setup disabled.")
        else
            respond("Usage: ;fisticuffs setup <on|off>")
        end
        return

    elseif cmd == "settings" then
        echo_settings()
        return

    elseif cmd == "help" then
        respond("FISTICUFFS -- UCS combat helper")
        respond("")
        respond(";fisticuffs")
        respond(";fisticuffs settings")
        respond(";fisticuffs tierup <jab|punch|grapple|kick>")
        respond(";fisticuffs tier3 <punch|grapple|kick>")
        respond(";fisticuffs stance <offensive|advance|forward|neutral|guarded|defensive>")
        respond(";fisticuffs aim <bodypart>")
        respond(";fisticuffs aim off")
        respond(";fisticuffs kick <on|off>")
        respond(";fisticuffs single <on|off>")
        respond(";fisticuffs roomstop <on|off>")
        respond(";fisticuffs fury <on|off>")
        respond(";fisticuffs clash <on|off>")
        respond(";fisticuffs clashmin <number>")
        respond(";fisticuffs spinkick <on|off>")
        respond(";fisticuffs setup <on|off>")
        return
    end
end

---------------------------------------------------------------------------
-- Register cleanup hook
---------------------------------------------------------------------------

before_dying(function()
    send_return_stance()
end)

---------------------------------------------------------------------------
-- MAIN COMBAT LOOP
---------------------------------------------------------------------------

local start_room_id = Room.id
fput("stance offensive")

local position = "decent"
local position_updated_at = os.clock()
local single_target_id = nil
local next_action_at = nil
local last_attack_at = nil
local awaiting_position_refresh = false
local pending_followup = nil
local pending_followup_target_id = nil
local active_followup_attack = nil
local last_attack_context = nil

fist_position = "decent"
fist_position_target_id = current_target_id()
fist_position_target_name = current_attack_target_name()
fist_sticky_excellent = false
fist_expected_target_id = current_target_id()
fist_expected_target_name = current_attack_target_name()

-- Check for immediate exit if no targets
if no_targets_left() then
    reset_sticky_excellent()
    send_return_stance()
    echo("Combat ended.")
    return
end

-- Opening Twin Hammerfists setup attempt
fist_setup_attempted = false
local attack_result = nil

if setting_bool("fisticuffs_use_setup") and (current_target_alive() or living_target_count() > 0) then
    fist_setup_attempted = true
    local setup_result = try_setup()

    if setup_result == "no_target" then
        reset_sticky_excellent()
        send_return_stance()
        echo("Combat ended.")
        return
    elseif setup_result == "unreachable" then
        next_action_at = os.clock() + 0.25
        attack_result = nil
    elseif type(setup_result) == "table" and setup_result[1] == "wait" then
        next_action_at = os.clock() + (tonumber(setup_result[2]) or 0)
        attack_result = nil
    elseif setup_result == true then
        next_action_at = os.clock() + 0.25
        attack_result = nil
    else
        attack_result = do_attack(position)
    end
else
    attack_result = do_attack(position)
end

last_attack_context = attack_result
if attack_result or fist_setup_attempted then
    last_attack_at = os.clock()
end
if attack_result or fist_setup_attempted then
    awaiting_position_refresh = true
end

---------------------------------------------------------------------------
-- Process due action (lambda equivalent)
---------------------------------------------------------------------------

local function process_due_action()
    if not next_action_at or os.clock() < next_action_at then
        return "idle"
    end

    local current_id = current_target_id()
    if pending_followup
       and (current_id == nil or pending_followup_target_id == nil or current_id ~= pending_followup_target_id) then
        pending_followup = nil
        pending_followup_target_id = nil
    end

    if awaiting_position_refresh then
        awaiting_position_refresh = false
    end
    if position_updated_at and (os.clock() - position_updated_at) < 0.15 then
        return "idle"
    end

    next_action_at = nil

    local action_state, pf, ar, retry_delay = perform_next_action(position, single_target_id, pending_followup)
    pending_followup = pf

    if action_state == "break" then return "break" end

    if ar then
        last_attack_context = ar
        active_followup_attack = ar.followup_attack
        if ar.followup_attack then
            pending_followup = nil
            pending_followup_target_id = nil
        end
        last_attack_at = os.clock()
        awaiting_position_refresh = true
    elseif action_state == "wait" then
        next_action_at = os.clock() + (retry_delay or 0.25)
    end

    return "acted"
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------

local function main_loop()
    while true do
        -- Room change check
        if room_changed(start_room_id) then
            reset_sticky_excellent()
            send_return_stance()
            echo("Room changed -- stopping fisticuffs.")
            return
        end

        local line = next_line_or_nil(0.15)

        -- Room change check again after read
        if room_changed(start_room_id) then
            reset_sticky_excellent()
            send_return_stance()
            echo("Room changed -- stopping fisticuffs.")
            return
        end

        if line == nil then
            local due_result = process_due_action()
            if due_result == "break" then
                break
            elseif due_result == "acted" then
                -- continue to next iteration
            else
                -- idle: check if we should exit
                if no_targets_left() and (not last_attack_at or os.clock() - last_attack_at > 0.6) then
                    break
                end
            end
        else
            -- Process line

            -- Spin kick opportunity
            if setting_bool("fisticuffs_use_spinkick")
               and line:find("[Yy]ou could use this opportunity to Spin Kick") then
                local spin_result = try_spinkick()
                if spin_result == true then
                    next_action_at = nil
                    last_attack_at = os.clock()
                    awaiting_position_refresh = true
                end
                if spin_result == "no_target" then break end
                if spin_result == "unreachable" then
                    local us, ar = handle_unreachable_target(position, active_followup_attack)
                    if ar then
                        last_attack_context = ar
                        active_followup_attack = ar.followup_attack
                        if ar.followup_attack then
                            pending_followup = nil
                            pending_followup_target_id = nil
                        end
                        last_attack_at = os.clock()
                        awaiting_position_refresh = true
                    elseif us == "wait" then
                        next_action_at = os.clock() + 0.25
                    end
                end
                goto continue
            end

            -- Roundtime
            local rt_secs = line:match("^Roundtime:%s*(%d+) sec")
            if rt_secs then
                next_action_at = os.clock() + tonumber(rt_secs)
                goto continue
            end

            -- Wait messages
            local wait_secs = line:match("^%.%.%.wait (%d+) seconds?%.$")
                           or line:match("^[Ww]ait (%d+) sec")
            if wait_secs then
                wait_secs = tonumber(wait_secs)
                local target_time = os.clock() + wait_secs
                if next_action_at then
                    next_action_at = math.max(next_action_at, target_time)
                else
                    next_action_at = target_time
                end
                goto continue
            end

            -- Attack attempt line
            if line:find("^You attempt to jab")
               or line:find("^You attempt to punch")
               or line:find("^You attempt to grapple")
               or line:find("^You attempt to kick") then
                last_attack_at = os.clock()
                awaiting_position_refresh = true
                active_followup_attack = nil
                if setting_bool("fisticuffs_single") and single_target_id == nil then
                    single_target_id = current_target_id()
                end
                goto continue
            end

            -- Positioning with target name
            local pos_tier, pos_target = line:match("You have (decent|good|excellent) positioning against (.+)%.")
            if pos_tier and pos_target then
                -- Lua patterns don't support alternation in captures directly
                -- so we handle it with a broader match below
            end
            -- Re-check with explicit patterns for positioning
            local pos_tier_named, pos_target_named
            if line:find("You have decent positioning against ") then
                pos_tier_named = "decent"
                pos_target_named = line:match("You have decent positioning against (.+)%.")
            elseif line:find("You have good positioning against ") then
                pos_tier_named = "good"
                pos_target_named = line:match("You have good positioning against (.+)%.")
            elseif line:find("You have excellent positioning against ") then
                pos_tier_named = "excellent"
                pos_target_named = line:match("You have excellent positioning against (.+)%.")
            end

            if pos_tier_named and pos_target_named then
                if positioning_line_matches_current_target(pos_target_named) then
                    position = pos_tier_named
                    position_updated_at = os.clock()
                    awaiting_position_refresh = false
                    update_position_state_from_text(position, pos_target_named)
                end
                goto continue
            end

            -- Positioning without target name
            local pos_tier_generic
            if line:find("You have decent positioning") then
                pos_tier_generic = "decent"
            elseif line:find("You have good positioning") then
                pos_tier_generic = "good"
            elseif line:find("You have excellent positioning") then
                pos_tier_generic = "excellent"
            end

            -- Only apply generic positioning if we didn't already match a named one
            if pos_tier_generic and not pos_tier_named then
                position = pos_tier_generic
                position_updated_at = os.clock()
                awaiting_position_refresh = false
                update_position_state_from_text(position)
                goto continue
            end

            -- Follow-up attack opportunity
            local followup_type = line:match("Strike leaves foe vulnerable to a followup (.*) attack!")
            if followup_type then
                if fist_last_action_source == "attack" then
                    pending_followup = str_lower(str_strip(followup_type))
                    pending_followup_target_id = current_target_id() or fist_expected_target_id
                end
                goto continue
            end

            -- Generic "You " line (target tracking)
            if line:find("^You ") then
                local current_id = current_target_id()

                if setting_bool("fisticuffs_single") and single_target_id == nil and current_id then
                    single_target_id = current_id
                end

                if pending_followup
                   and current_id
                   and pending_followup_target_id
                   and current_id ~= pending_followup_target_id then
                    pending_followup = nil
                    pending_followup_target_id = nil
                end
                goto continue
            end

            -- No target messages
            if matches_no_target(line) then
                awaiting_position_refresh = false
                pending_followup = nil
                pending_followup_target_id = nil
                reset_sticky_excellent()
                break
            end

            -- Need to stand
            if line:find("^Try standing up first%.$")
               or line:find("You cannot do that while lying down") then
                fput("stand")
                goto continue
            end

            -- Failed to find opening
            if line:find("You fail to find an opening") then
                awaiting_position_refresh = false
                next_action_at = os.clock()
                goto continue
            end

            -- Cannot aim that high
            if line:find("You cannot aim that high") then
                awaiting_position_refresh = false
                local ctx = last_attack_context or {
                    position = position,
                    followup_attack = active_followup_attack,
                    aimed = true,
                }
                local retry_state, ar = recover_failed_attack(ctx)

                if ar then
                    last_attack_context = ar
                    active_followup_attack = ar.followup_attack
                    if ar.followup_attack then
                        pending_followup = nil
                        pending_followup_target_id = nil
                    end
                    last_attack_at = os.clock()
                    awaiting_position_refresh = true
                    next_action_at = nil
                elseif retry_state == "wait" then
                    next_action_at = os.clock() + 0.25
                end
                goto continue
            end

            -- Can't reach target
            if line:find("You can't reach .* from here%.") then
                awaiting_position_refresh = false
                local ctx = last_attack_context or {
                    position = position,
                    followup_attack = active_followup_attack,
                    aimed = false,
                }
                local retry_state, ar = recover_failed_attack(ctx)

                if ar then
                    last_attack_context = ar
                    active_followup_attack = ar.followup_attack
                    if ar.followup_attack then
                        pending_followup = nil
                        pending_followup_target_id = nil
                    end
                    last_attack_at = os.clock()
                    awaiting_position_refresh = true
                    next_action_at = nil
                elseif retry_state == "wait" then
                    next_action_at = os.clock() + 0.25
                end
                goto continue
            end

            -- Stunned / unable / webbed
            if line:find("You are still stunned")
               or line:find("unable to muster the will to attack")
               or line:find("entangled in a web") then
                echo("Combat halted.")
                reset_sticky_excellent()
                break
            end

            ::continue::

            -- Process due actions after each line
            local due_result = process_due_action()
            if due_result == "break" then
                break
            end
            -- "acted" or "idle" - continue loop
        end
    end
end

-- Run the main loop, catching our exit sentinel
local ok, err = pcall(main_loop)
if not ok and err and type(err) == "string" and err:find("__fisticuffs_exit__") then
    -- Normal exit via cleanup_and_exit
else
    -- Normal loop exit
    reset_sticky_excellent()
    send_return_stance()
    echo("Combat ended.")
end
