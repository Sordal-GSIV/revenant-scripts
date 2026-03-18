--- tpick trap detection, identification, and disarming module.
-- Ported from tpick.lic lines 2364-2409, 3132-3810, 3983-4039, 4095-4149,
-- 4235-4340, 4949-5073.
-- Contains all 17 trap type patterns with exact game message matching.
local M = {}
local data = require("tpick/data")
local util = require("tpick/util")

---------------------------------------------------------------------------
-- Forward declarations for functions that reference each other
---------------------------------------------------------------------------
-- These are set at module load via the wiring functions below.
-- External functions called by trap logic but defined in other modules:
local open_solo           -- from picking modes
local open_others         -- from picking modes
local measure_lock        -- from picking system
local wedge_lock          -- from picking system
local bash_the_box_open   -- from picking system
local cast_407            -- from spell management
local pop_open_box        -- from picking modes (pop)
local detect_plinite      -- from picking modes (plinite)
local tpick_cast_spells   -- from spell management
local tpick_prep_spell    -- from spell management
local tpick_bundle_vials  -- from loot management
local stuff_to_do         -- from main loop
local no_vaalin_picks     -- from lockpick system

--- Wire external function references so this module can call them.
-- Called once during init to break circular requires.
-- @param funcs  Table of { name = function } pairs.
function M.wire(funcs)
    open_solo          = funcs.open_solo
    open_others        = funcs.open_others
    measure_lock       = funcs.measure_lock
    wedge_lock         = funcs.wedge_lock
    bash_the_box_open  = funcs.bash_the_box_open
    cast_407           = funcs.cast_407
    pop_open_box       = funcs.pop_open_box
    detect_plinite     = funcs.detect_plinite
    tpick_cast_spells  = funcs.tpick_cast_spells
    tpick_prep_spell   = funcs.tpick_prep_spell
    tpick_bundle_vials = funcs.tpick_bundle_vials
    stuff_to_do        = funcs.stuff_to_do
    no_vaalin_picks    = funcs.no_vaalin_picks
end

---------------------------------------------------------------------------
-- All trap states that mean "trap is done, proceed to picking"
---------------------------------------------------------------------------
local TRAP_DONE_STATES = {
    ["No trap found."]                                  = true,
    ["Scarab trap has already been disarmed."]           = true,
    ["Scarab trap has already been disarmed with 408."]  = true,
    ["Scarab trap has been disarmed."]                   = true,
    ["Needle trap has been disarmed."]                   = true,
    ["Needle trap has already been disarmed."]           = true,
    ["Needle trap has already been disarmed with 408."]  = true,
    ["Jaws trap has been disarmed."]                     = true,
    ["Jaws trap has already been disarmed."]             = true,
    ["Sphere trap has been disarmed."]                   = true,
    ["Sphere trap has already been disarmed."]           = true,
    ["Sphere trap has already been disarmed with 408."]  = true,
    ["Crystal trap has been disarmed."]                  = true,
    ["Crystal trap has already been disarmed."]          = true,
    ["Crystal trap has already been disarmed with 408."] = true,
    ["Scales trap has been disarmed."]                   = true,
    ["Scales trap has already been disarmed."]           = true,
    ["Scales trap has already been disarmed with 408."]  = true,
    ["Sulphur trap has been disarmed."]                  = true,
    ["Sulphur trap has already been disarmed."]          = true,
    ["Cloud trap has been disarmed."]                    = true,
    ["Cloud trap has already been disarmed."]            = true,
    ["Cloud trap has already been disarmed with 408."]   = true,
    ["Acid vial trap has been disarmed."]                = true,
    ["Acid vial trap has already been disarmed."]        = true,
    ["Acid vial trap has already been disarmed with 408."] = true,
    ["Springs trap has been disarmed."]                  = true,
    ["Springs trap has already been disarmed with 408."] = true,
    ["Fire vial trap has been disarmed."]                = true,
    ["Fire vial trap has already been disarmed."]        = true,
    ["Fire vial trap has already been disarmed with 408."] = true,
    ["Spores trap has been disarmed."]                   = true,
    ["Spores trap has already been disarmed."]           = true,
    ["Spores trap has already been disarmed with 408."]  = true,
    ["Plate trap has been disarmed."]                    = true,
    ["Plate trap has already been disarmed."]            = true,
    ["Glyph trap has been disarmed."]                    = true,
    ["Glyph trap has already been disarmed."]            = true,
    ["Rods trap has been disarmed."]                     = true,
    ["Rods trap has already been disarmed."]             = true,
    ["Rods trap has already been disarmed with 408."]    = true,
    ["Boomer trap has been disarmed."]                   = true,
    ["Boomer trap has already been disarmed."]           = true,
    ["Boomer trap has already been disarmed with 408."]  = true,
    ["Spores trap has already been set off."]            = true,
    ["Sphere trap has already been set off."]            = true,
    ["Sulphur trap has already been set off."]           = true,
}

-- Trap names that are "standard disarm" types (not scales, plate, glyph, or no-trap)
local STANDARD_DISARM_TYPES = {
    ["Needle"] = true, ["Jaws"] = true, ["Crystal"] = true,
    ["Sulphur"] = true, ["Cloud"] = true, ["Acid Vial"] = true,
    ["Springs"] = true, ["Fire Vial"] = true, ["Spores"] = true,
    ["Glyph"] = true, ["Rods"] = true, ["Boomer"] = true,
    ["Sphere"] = true,
    ["Sphere trap found, need to use lockpick to disarm."] = true,
    ["Scarab"] = true,
}

-- All 16 base trap names for stats tracking
local ALL_TRAP_NAMES_SET = {}
for _, name in ipairs(data.TRAP_NAMES) do
    ALL_TRAP_NAMES_SET[name] = true
end

---------------------------------------------------------------------------
-- Helper: update_box_for_window wrapper
---------------------------------------------------------------------------
local function update_box_for_window(vars, settings)
    if settings.update_box_for_window then
        settings.update_box_for_window()
    end
end

---------------------------------------------------------------------------
-- Helper: tpick_silent shorthand
---------------------------------------------------------------------------
local function tsilent(flag, message, settings)
    util.tpick_silent(flag, message, settings)
end

---------------------------------------------------------------------------
-- Helper: check if item is in either hand by ID
---------------------------------------------------------------------------
local function in_either_hand(item_id)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    return (rh and rh.id == item_id) or (lh and lh.id == item_id)
end

---------------------------------------------------------------------------
-- 1. disarm_scale (lines 3132-3170)
-- Disarm a scales trap using the configured scale weapon.
---------------------------------------------------------------------------
function M.disarm_scale(vars, settings)
    local load_data = settings.load_data
    tsilent(nil, "Attempting to disarm scales trap.", settings)

    -- Try 3 times to get the scale weapon
    for _ = 1, 3 do
        waitrt()
        if not in_either_hand(vars["Scale Weapon ID"]) then
            fput("get #" .. vars["Scale Weapon ID"])
            pause(0.2)
        end
    end

    if not in_either_hand(vars["Scale Weapon ID"]) then
        tsilent(true,
            "To fix the below issues enter ;tpick setup\n"
            .. "Be sure to fill out the setting for the name of your scale trap weapon.\n"
            .. "Be sure to fill out the setting for which container your scale trap weapon is in.\n"
            .. "Also be sure you have your scale trap weapon.\n\n"
            .. "Couldn't find your " .. (load_data["Scale Trap Weapon"] or "scale weapon") .. ".",
            settings)
        error("tpick:exit")
    end

    if tpick_cast_spells then
        if vars["Need 404"] == "yes" or vars["Use 404"] then tpick_cast_spells(404) end
        if vars["Use 506"] then tpick_cast_spells(506) end
        if vars["Use 613"] then tpick_cast_spells(613) end
        if vars["Use 1006"] then tpick_cast_spells(1006) end
        if vars["Use 1035"] then tpick_cast_spells(1035) end
    end

    local result = dothistimeout("disarm #" .. vars["Current Box"].id, 3,
        { "slice through the cord" })

    if result and string.find(result, "slice through the cord") then
        waitrt()
        util.tpick_put_stuff_away(vars, settings)
        if vars["Picking Mode"] == "solo" then
            if open_solo then open_solo(vars, settings) end
        elseif vars["Picking Mode"] == "other" then
            if open_others then open_others(vars, settings) end
        elseif vars["Picking Mode"] == "ground" then
            pause(0.1)
        elseif vars["Picking Mode"] == "worker" then
            pause(0.1)
        end
    elseif result == nil then
        waitrt()
        util.tpick_put_stuff_away(vars, settings)
        if tpick_cast_spells then
            tpick_cast_spells(404)
            if vars["Use 506"] then tpick_cast_spells(506) end
        end
        M.disarm_scale(vars, settings)
    end
end

---------------------------------------------------------------------------
-- 2. plate_trap_disarm (lines 2364-2407)
-- Handle plate traps: rogues wedge task, 407 vial vs mithril, or manual disarm.
---------------------------------------------------------------------------
function M.plate_trap_disarm(vars, settings)
    local load_data = settings.load_data

    -- Rogues wedge task override
    if vars["rogue_current_task"] == "Wedge open boxes"
        and vars["rogue_automate_current_task_with_tpick"]
        and vars["Picking Mode"] == "worker"
    then
        tsilent(true, "Working on a ;rogues task to use wedges so I'm going to use a wedge on this box.", settings)
        vars["Use A Wedge"] = true
        if wedge_lock then wedge_lock(vars, settings) end
        return
    end

    -- Check if should use 407 on non-enruned/mithril plated boxes
    if load_data["Unlock (407)"] == "Vial" then
        local box_name = vars["Current Box"].name or ""
        local is_special = Regex.test("mithril|enruned|rune%-incised", box_name)
        if not is_special and not vars["Box Is Enruned/Mithril"] then
            tsilent(nil, "According to your settings you want to use 407 on non-enruned/mithril plated boxes.", settings)
            if cast_407 then cast_407(vars, settings) end
            return
        end
    end

    -- Manual plate disarm
    tsilent(nil, "Disarming trap.", settings)
    waitrt()
    if tpick_cast_spells then
        if vars["Use 1035"] then tpick_cast_spells(1035) end
        if vars["Use 506"] then tpick_cast_spells(506) end
    end

    if vars["Always Use Wedge"] then
        if wedge_lock then wedge_lock(vars, settings) end
        return
    end

    if tpick_cast_spells then
        if vars["Need 404"] then tpick_cast_spells(404) end
        if vars["Use 506"] then tpick_cast_spells(506) end
    end

    local result = dothistimeout("disarm #" .. vars["Current Box"].id, 3,
        { "You try to pour .* onto the .*, but it just won't pour",
          "the metal plate covering the lock begins to melt away",
          "but it appears to have been melted through",
          "Gonna chew through it",
          "The darn thing is built too tightly",
          "You still have a good enough picture of the trap in your mind" })

    if result and (string.find(result, "the metal plate covering the lock begins to melt away")
        or string.find(result, "but it appears to have been melted through"))
    then
        if measure_lock then measure_lock(vars, settings) end
    elseif result and string.find(result, "Gonna chew through it") then
        tsilent(nil, "No vials found bundled in your locksmith's container, going to look for loose vials in your locksmith's container.", settings)
        M.get_vials_and_stuff(vars, settings)
    elseif result and (string.find(result, "The darn thing is built too tightly")
        or string.find(result, "You still have a good enough picture of the trap in your mind"))
    then
        M.plate_trap_disarm(vars, settings)
    elseif result and string.find(result, "but it just won't pour") then
        tsilent(true, "THIS IS A BUG WITH THE GAME: IT IS TRYING TO POUR YOUR LOCKSMITH'S CONTAINER ON THE BOX. Looking for loose vials in your locksmith's container.", settings)
        M.get_vials_and_stuff(vars, settings)
    elseif result == nil then
        vars["Number Of Vial Disarm Tries"] = vars["Number Of Vial Disarm Tries"] or 0
        vars["Number Of Vial Disarm Tries"] = vars["Number Of Vial Disarm Tries"] + 1
        if vars["Number Of Vial Disarm Tries"] >= 3 then
            tsilent(true, "TRIED 3 TIMES TO DISARM THIS TRAP WITH VIALS BUNDLED IN YOUR LOCKSMITH'S CONTAINER. GIVING UP AND MOVING ON. Looking for loose vials in your locksmith's container.", settings)
            M.get_vials_and_stuff(vars, settings)
        else
            M.plate_trap_disarm(vars, settings)
        end
    end
end

---------------------------------------------------------------------------
-- get_vials_and_stuff (lines 4787-4817)
-- Get loose vials from locksmith container for plate disarm.
---------------------------------------------------------------------------
function M.get_vials_and_stuff(vars, settings)
    local load_data = settings.load_data
    waitrt()

    -- Try 3 times to get a vial
    for _ = 1, 3 do
        waitrt()
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_vial = (rh and string.find(rh.name or "", "vial"))
                      or (lh and string.find(lh.name or "", "vial"))
        if not has_vial then
            local container = vars["Locksmith's Container"]
            if container then
                fput("get vial from #" .. container.id)
            end
            pause(0.2)
        end
    end

    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local has_vial = (rh and string.find(rh.name or "", "vial"))
                  or (lh and string.find(lh.name or "", "vial"))

    if not has_vial then
        tsilent(true, "No vials found bundled in your locksmith's container and no loose vials found in your locksmith's container", settings)
        if Stats.prof == "Rogue" then
            tsilent(nil, "Going to try wedging this box open.", settings)
            if wedge_lock then wedge_lock(vars, settings) end
        elseif not Spell[407].known or not string.find(load_data["Unlock (407)"] or "", "Plate")
            and not string.find(load_data["Unlock (407)"] or "", "All")
        then
            tsilent(true, "Can't open this plated box.", settings)
            if vars["Picking Mode"] == "solo" then
                error("tpick:exit")
            elseif vars["Picking Mode"] == "other" then
                util.tpick_say("Can't Open Box", settings)
                if open_others then open_others(vars, settings) end
            elseif vars["Picking Mode"] == "ground" then
                vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
                vars["Box Opened"] = nil
            end
        elseif Spell[407].known and (string.find(load_data["Unlock (407)"] or "", "Plate")
            or string.find(load_data["Unlock (407)"] or "", "All"))
        then
            if vars["Picking Mode"] == "ground" then
                util.tpick_get_box(vars)
            end
            tsilent(nil, "Going to try popping this box.", settings)
            if cast_407 then cast_407(vars, settings) end
        end
    else
        -- Have vial, try to disarm with it
        M.plate_trap_disarm(vars, settings)
    end
end

---------------------------------------------------------------------------
-- 3. fused_lock_disarm (lines 4095-4121)
-- Handle fused/locked mechanism that requires special approach.
---------------------------------------------------------------------------
function M.fused_lock_disarm(vars, settings)
    -- Rogues wedge task override
    if vars["rogue_current_task"] == "Wedge open boxes"
        and vars["rogue_automate_current_task_with_tpick"]
        and vars["Picking Mode"] == "worker"
    then
        tsilent(true, "Working on a ;rogues task to use wedges so I'm going to use a wedge on this box.", settings)
        vars["Use A Wedge"] = true
        if wedge_lock then wedge_lock(vars, settings) end
    elseif Stats.prof == "Rogue" then
        tsilent(nil, "Going to try wedging this box open.", settings)
        if wedge_lock then wedge_lock(vars, settings) end
    elseif Stats.prof ~= "Rogue" and not Spell[407].known then
        tsilent(true, "Can't open this box.", settings)
        if vars["Picking Mode"] == "solo" then
            util.where_to_stow_box(vars)
        elseif vars["Picking Mode"] == "other" then
            util.tpick_say("Can't Open Box", settings)
            if open_others then open_others(vars, settings) end
        elseif vars["Picking Mode"] == "ground" then
            vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
            vars["Box Opened"] = nil
        end
    elseif Stats.prof ~= "Rogue" and Spell[407].known then
        if vars["Picking Mode"] == "ground" then
            util.tpick_get_box(vars)
        end
        tsilent(nil, "Going to try popping this box.", settings)
        if cast_407 then cast_407(vars, settings) end
    end
end

---------------------------------------------------------------------------
-- 4. disarm_the_trap (lines 4123-4147)
-- Use 408 (Disarm) to disarm a trap on a box.
---------------------------------------------------------------------------
function M.disarm_the_trap(vars, settings)
    local box_is_disarmed = false

    while not box_is_disarmed do
        if tpick_cast_spells then
            if vars["Use 402"] then tpick_cast_spells(402) end
            if vars["Use 404"] then tpick_cast_spells(404) end
            if vars["Use 515"] then tpick_cast_spells(515) end
        end
        if tpick_prep_spell then tpick_prep_spell(408, "Disarm") end
        fput("cast at #" .. vars["Current Box"].id)

        while true do
            local line = get()
            if not line then break end

            if Regex.test(
                "Now to isolate the offending mechanism and disable it%.%.%.The.*vibrates slightly but nothing else happens%."
                .. "|You begin to probe the.*for unusual mechanisms%.%.%.The.*vibrates slightly but nothing else happens%.",
                line)
            then
                tsilent(nil, "Couldn't disarm trap. Trying again.", settings)
                break
            elseif string.find(line, "Now to isolate the offending mechanism and disable it")
                and string.find(line, "the entire")
                and string.find(line, "explodes in a deafening")
            then
                tsilent(true, "The trap was set off! Script is now exiting.", settings)
                error("tpick:exit")
            elseif string.find(line, "Now to isolate the offending mechanism and disable it")
                and string.find(line, "pulses once with a deep crimson light")
            then
                box_is_disarmed = true
                tsilent(nil, "Box is disarmed.", settings)
                break
            end
        end
    end

    if pop_open_box then pop_open_box(vars, settings) end
end

---------------------------------------------------------------------------
-- 5. check_for_trap (lines 4235-4339)
-- Detect traps using 416 (Piercing Gaze). Used in pop mode.
---------------------------------------------------------------------------
function M.check_for_trap(vars, settings)
    local load_data = settings.load_data
    local stats_data = settings.stats_data or {}

    if tpick_cast_spells then
        if vars["Use 402"] then tpick_cast_spells(402) end
        if vars["Use 404"] then tpick_cast_spells(404) end
        if vars["Use 515"] then tpick_cast_spells(515) end
    end

    vars["Current Trap Type"] = nil
    if tpick_prep_spell then tpick_prep_spell(416, "Piercing Gaze") end
    fput("cast at #" .. vars["Current Box"].id)

    while true do
        local line = get()
        if not line then break end

        -- Scarab
        local scarab_name = string.match(line,
            "Peering closely into the lock, you spy an? [a-zA-Z]+ (.*) scarab wedged into the lock mechanism%.")
        if scarab_name then
            vars["Scarab Name"] = scarab_name
            vars["Current Trap Type"] = "Scarab"
        -- Needle
        elseif string.find(line, "You notice what appears to be a sharp sliver of metal nestled in a hole next to the lock plate") then
            vars["Current Trap Type"] = "Needle"
        -- Jaws
        elseif string.find(line, "You notice a discolored oval ring around the outside of the")
            and string.find(line, "spring%-loaded jaws pressed flush against the")
        then
            vars["Current Trap Type"] = "Jaws"
        -- Sphere
        elseif string.find(line, "You see a tiny sphere imbedded in the lock mechanism") then
            vars["Current Trap Type"] = "Sphere"
        -- Crystal
        elseif string.find(line, "You can see a small crystal imbedded in the locking mechanism") then
            vars["Current Trap Type"] = "Crystal"
        -- Scales
        elseif string.find(line, "You see a cord stretched between the lid and case") then
            vars["Current Trap Type"] = "Scales"
        -- Sulphur
        elseif string.find(line, "you notice that the lock casing is coated with a rough, grainy substance")
            and string.find(line, "a small bladder is wedged between the tumblers")
        then
            vars["Current Trap Type"] = "Sulphur"
        -- Cloud
        elseif string.find(line, "you spy a small vial of liquid and a tiny hammer device which seems poised to shatter it") then
            vars["Current Trap Type"] = "Cloud"
        -- Acid Vial
        elseif string.find(line, "You notice what appears to be a tiny vial placed just past the tumblers")
            and string.find(line, "any tampering with the lock mechanism will cause the tumblers to crush the vial")
        then
            vars["Current Trap Type"] = "Acid Vial"
        -- Springs
        elseif string.find(line, "you notice that the hinges have some springs incorporated into the design") then
            vars["Current Trap Type"] = "Springs"
        -- Fire Vial
        elseif string.find(line, "you spy a small vial of fire%-red liquid and a tiny hammer device which seems poised to shatter it") then
            vars["Current Trap Type"] = "Fire Vial"
        -- Spores
        elseif string.find(line, "The tube appears to be filled with a greenish powder") then
            vars["Current Trap Type"] = "Spores"
        -- Plate
        elseif string.find(line, "There appears to be a plate over the lock, sealing it and preventing any access to the tumblers") then
            vars["Current Trap Type"] = "Plate"
        -- Glyph
        elseif string.find(line, "Suddenly a dark splotch erupts from the lock mechanism and envelops you") then
            vars["Current Trap Type"] = "Glyph"
        -- Rods
        elseif string.find(line, "you notice a pair of small metal rods a hair's width from rubbing together") then
            vars["Current Trap Type"] = "Rods"
        -- Boomer
        elseif string.find(line, "The inside chamber is lined with some unidentifiable substance") then
            vars["Current Trap Type"] = "Boomer"
        -- Vision obscured (retry)
        elseif string.find(line, "You gaze at the") and string.find(line, "but your vision is obscured") then
            vars["Current Trap Type"] = "check again"
        -- Roundtime ends detection
        elseif string.find(line, "Roundtime") then
            if vars["Current Trap Type"] ~= "check again" and vars["Current Trap Type"] ~= nil then
                if stats_data[vars["Current Trap Type"]] then
                    stats_data[vars["Current Trap Type"]] = stats_data[vars["Current Trap Type"]] + 1
                end
            end
            break
        end
    end

    -- Report what was found
    if vars["Current Trap Type"] ~= "check again" and vars["Current Trap Type"] ~= nil then
        tsilent(nil, "Found a " .. vars["Current Trap Type"] .. " trap.", settings)
    end

    -- Route based on trap type
    if vars["Current Trap Type"] == "check again" then
        tsilent(nil, "Failed detecting a trap, trying again.", settings)
        M.check_for_trap(vars, settings)

    elseif vars["Current Trap Type"] == "Needle"
        or vars["Current Trap Type"] == "Jaws"
        or vars["Current Trap Type"] == "Plate"
    then
        tsilent(nil, "Trap is safe to skip disarming.", settings)
        if pop_open_box then pop_open_box(vars, settings) end

    elseif vars["Current Trap Type"] == "Crystal"
        or vars["Current Trap Type"] == "Springs"
    then
        tsilent(nil, "Trap is safe to use 408 on. Must be disarmed before popping.", settings)
        M.disarm_the_trap(vars, settings)

    elseif vars["Current Trap Type"] == "Scarab"
        or vars["Current Trap Type"] == "Sphere"
        or vars["Current Trap Type"] == "Scales"
        or vars["Current Trap Type"] == "Acid Vial"
        or vars["Current Trap Type"] == "Fire Vial"
        or vars["Current Trap Type"] == "Spores"
        or vars["Current Trap Type"] == "Boomer"
        or vars["Current Trap Type"] == "Cloud"
        or vars["Current Trap Type"] == "Rods"
    then
        tsilent(nil, "408 might set off trap. Must be disarmed before popping.", settings)
        if load_data["Only Disarm Safe"] == "Yes" then
            tsilent(true, "Skipping box due to tpick setting 'Only Disarm Safe' is set to yes.", settings)
            util.where_to_stow_box(vars)
            vars["Box Opened"] = nil
        else
            M.disarm_the_trap(vars, settings)
        end

    elseif vars["Current Trap Type"] == "Sulphur" then
        tsilent(true, "Skipping box because 408 will set this trap off.", settings)
        if vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        else
            util.where_to_stow_box(vars)
            vars["Box Opened"] = nil
        end

    elseif vars["Current Trap Type"] == "Glyph" then
        tsilent(true, "The box had a glyph trap on it. Taking you back to the room you started in.", settings)
        -- Navigate out of Temporal Rift if needed
        local room_name = GameState.room_name or ""
        while string.find(room_name, "Temporal Rift") do
            fput("go east")
            pause(0.1)
            room_name = GameState.room_name or ""
        end
        pause(0.5)
        -- go2 starting room
        if vars["Starting Room"] then
            start_script("go2", { vars["Starting Room"] })
            wait_while(function() return running("go2") end)
        end
        tsilent(true, "This box has a glyph trap and cannot be opened.", settings)
        if vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        else
            util.where_to_stow_box(vars)
            vars["Box Opened"] = nil
        end

    elseif vars["Current Trap Type"] == nil then
        tsilent(nil, "No trap found.", settings)
        vars["Remaining 416 Casts"] = (vars["Remaining 416 Casts"] or 1) - 1
        if vars["Remaining 416 Casts"] < 1 then
            if stats_data["No Trap"] then
                stats_data["No Trap"] = stats_data["No Trap"] + 1
            end
            if pop_open_box then pop_open_box(vars, settings) end
        else
            tsilent(nil, "416 casts remaining: " .. vars["Remaining 416 Casts"] .. ".", settings)
            M.check_for_trap(vars, settings)
        end
    end
end

---------------------------------------------------------------------------
-- 6. check_for_trap_416 (extracted from lines 4149-4205)
-- Entry point for pop mode trap checking with 416.
-- Sets up state and calls check_for_trap or cast_704_at_box.
---------------------------------------------------------------------------
function M.check_for_trap_416(vars, settings)
    local load_data = settings.load_data

    util.tpick_put_stuff_away(vars, settings)

    if vars["Picking Mode"] == "worker" then
        -- get current worker box handled externally
    else
        -- Wait for box in hand
        while true do
            local rh = GameObj.right_hand()
            if rh and rh.id then break end
            fput("get #" .. (vars["Current Box"] and vars["Current Box"].id or ""))
            pause(0.2)
        end
        local rh = GameObj.right_hand()
        if rh then
            vars["Current Box"] = rh
            update_box_for_window(vars, settings)
        end
    end

    vars["Start Time"] = os.time()
    vars["Remaining 416 Casts"] = load_data["Number Of 416 Casts"] or 1
    if stuff_to_do then stuff_to_do(vars, settings) end

    -- Check mithril/enruned status
    vars["Hand Status"] = nil
    if vars["Picking Mode"] == "worker" then
        local box_name = vars["Current Box"] and vars["Current Box"].name or ""
        if Regex.test("mithril|enruned|rune%-incised", box_name) then
            vars["Hand Status"] = "mithril or enruned"
        else
            vars["Hand Status"] = "good"
        end
    else
        vars["Check For Command"] = "glance"
        -- Mithril/enruned check callback would be called here
        vars["Hand Status"] = "good"
    end

    -- Plinite handling
    local box_name = vars["Current Box"] and vars["Current Box"].name or ""
    if string.find(string.lower(box_name), "plinite") and vars["Picking Mode"] == "worker" then
        tsilent(true, "Can't open plinites when popping.", settings)
        vars["Give Up On Box"] = true
        return
    end

    if vars["Hand Status"] == "mithril or enruned" and load_data["Pick Enruned"] == "No" then
        tsilent(true, "Can't open this box because it is mithril or enruned.", settings)
        waitrt()
        if vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
        elseif vars["Picking Mode"] == "solo" then
            util.where_to_stow_box(vars)
        elseif vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        end
        vars["Box Opened"] = nil
        return
    end

    if vars["Hand Status"] == "empty" then
        tsilent(true, "No box was found in your hands.", settings)
        error("tpick:exit")
    end

    if load_data["Phase (704)"] == "Yes" then
        M.cast_704_at_box(vars, settings)
    else
        tsilent(nil, "Checking for traps.", settings)
        if vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
        end
        M.check_for_trap(vars, settings)
    end
end

---------------------------------------------------------------------------
-- 7. cast_704_at_box (lines 4949-4976)
-- Use Phase (704) to detect glyph traps.
---------------------------------------------------------------------------
function M.cast_704_at_box(vars, settings)
    waitrt()
    waitcastrt()
    if tpick_prep_spell then tpick_prep_spell(704, "Phase") end

    local result = dothistimeout("cast at #" .. vars["Current Box"].id, 3,
        { "resists the effects of your magic",
          "appears lighter",
          "then stabilizes",
          "but quickly returns to normal",
          "Roundtime" })

    -- Update box reference after cast
    local rh = GameObj.right_hand()
    if rh then
        vars["Current Box"] = rh
        update_box_for_window(vars, settings)
    end

    if result and string.find(result, "resists the effects of your magic") then
        tsilent(true, "Box has a glyph trap and cannot be opened.", settings)
        vars["Box Has Glyph Trap"] = true
        if vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
        elseif vars["Picking Mode"] == "solo" then
            util.where_to_stow_box(vars)
        elseif vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        end
        vars["Box Opened"] = nil
    elseif result and (string.find(result, "appears lighter")
        or string.find(result, "then stabilizes")
        or string.find(result, "but quickly returns to normal")
        or string.find(result, "Roundtime"))
    then
        tsilent(nil, "Box has no glyph trap. Checking for other traps.", settings)
        if vars["Picking Mode"] ~= "worker" then
            util.tpick_drop_box(vars)
            if vars["Picking Mode"] ~= "ground" then
                util.tpick_get_box(vars)
            end
        end
        M.check_for_trap(vars, settings)
    elseif result == nil then
        M.cast_704_at_box(vars, settings)
    end
end

---------------------------------------------------------------------------
-- 8. gnomish_bracers_trap_check (lines 4028-4037)
-- Use gnomish bracer tier 2+ for trap detection.
---------------------------------------------------------------------------
function M.gnomish_bracers_trap_check(vars, settings)
    if vars["Picking Mode"] ~= "ground" and vars["Picking Mode"] ~= "worker" then
        while true do
            local rh = GameObj.right_hand()
            if rh and rh.id then break end
            pause(0.1)
        end
        vars["Current Box"] = GameObj.right_hand()
        update_box_for_window(vars, settings)
    end

    if vars["Picking Mode"] == "ground" then
        util.tpick_get_box(vars)
    end

    -- Worker box retrieval handled externally
    M.gnomish_bracers_check_result(vars, settings)
end

---------------------------------------------------------------------------
-- 9. gnomish_bracers_check_result (lines 3983-4009)
-- Parse the gnomish bracer trap check result and route to handler.
---------------------------------------------------------------------------
function M.gnomish_bracers_check_result(vars, settings)
    waitrt()
    vars["Bracers Found Trap"] = nil

    local bracers_name = vars["Gnomish Bracers"] or "bracers"
    local result = dothistimeout("rub my " .. bracers_name, 3,
        { "begins to glow with a deep red light",
          "begins to glow with a bright green light",
          "Perhaps you need to be holding a container" })

    if result and string.find(result, "begins to glow with a deep red light") then
        waitrt()
        vars["Bracers Found Trap"] = true
        M.manually_disarm_trap(vars, settings)
    elseif result and string.find(result, "begins to glow with a bright green light") then
        waitrt()
        if vars["Disarm Only"] then
            if vars["Bash Open Boxes"] then
                if bash_the_box_open then bash_the_box_open(vars, settings) end
            else
                vars["Box Math"] = nil
                util.tpick_drop_box(vars)
            end
        else
            if measure_lock then measure_lock(vars, settings) end
        end
    elseif result and string.find(result, "Perhaps you need to be holding a container") then
        waitrt()
        M.manually_disarm_trap(vars, settings)
    elseif result == nil then
        M.gnomish_bracers_check_result(vars, settings)
    end
end

---------------------------------------------------------------------------
-- 10. measure_detection (lines 4988-5071)
-- Measure lock difficulty using calipers (Rogue) or loresinging (Bard).
---------------------------------------------------------------------------
function M.measure_detection(vars, settings)
    local load_data = settings.load_data
    vars["Lock Difficulty"] = nil
    vars["Measured Lock"] = nil

    if Stats.prof == "Rogue" then
        tsilent(nil, "Measuring lock.", settings)
        -- Get calipers
        for _ = 1, 3 do
            waitrt()
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local has_calipers = (rh and string.find(rh.name or "", "calipers"))
                              or (lh and string.find(lh.name or "", "calipers"))
            if not has_calipers then
                fput("get my calipers")
                pause(0.2)
            end
        end

        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        local has_calipers = (rh and string.find(rh.name or "", "calipers"))
                          or (lh and string.find(lh.name or "", "calipers"))
        if not has_calipers then
            tsilent(true,
                "To fix the below issues enter ;tpick setup\n"
                .. "Make sure your calipers container is filled out properly and that you have calipers.\n"
                .. "If you don't want to use calipers then go to the 'Other' tab and uncheck the box for the 'Use Calipers' setting.\n\n"
                .. "Couldn't find your calipers.",
                settings)
            error("tpick:exit")
        end

        fput("lmaster measure #" .. vars["Current Box"].id)

    elseif Stats.prof == "Bard" then
        tsilent(nil, "Loresinging to box to find out lock difficulty.", settings)
        if vars["Picking Mode"] == "ground" then
            util.tpick_get_box(vars)
            -- Wait until box is in hand
            while not in_either_hand(vars["Current Box"].id) do
                pause(0.1)
            end
        end
        waitrt()
        fput("speak bard")

        local loresong_stuff
        if vars["Picking Mode"] == "worker" then
            local charname = GameState.name or ""
            local noun = vars["Current Box"].noun or "box"
            local table_name = vars["Pool Table"] or "table"
            loresong_stuff = "loresing ::" .. charname .. " " .. noun .. " on " .. table_name
                .. ":: " .. noun .. " that looks like a clock;What's the purpose of your lock?"
        else
            local rh_name = GameObj.right_hand() and GameObj.right_hand().name or "box"
            loresong_stuff = "loresing " .. rh_name .. " that I hold;let your purpose now be told"
        end

        while true do
            local result = dothistimeout(loresong_stuff, 2, { "^You sing" })
            if result and string.find(result, "You sing") then
                break
            end
        end
    end

    -- Parse the measurement result
    while true do
        local line = get()
        if not line then break end

        -- Numeric difficulty from calipers
        local difficulty = string.match(line, "%-(%d+) in thief%-lingo difficulty ranking")
        if difficulty then
            vars["Lock Difficulty"] = tonumber(difficulty)
            break
        end

        -- Loresing text match
        for text, value in pairs(data.LOCK_DIFFICULTIES) do
            if string.find(line, text, 1, true) then
                vars["Lock Difficulty"] = value
                break
            end
        end
        if vars["Lock Difficulty"] then break end

        -- Soul golem / active trap on calipers
        if string.find(string.lower(line), "you place the probe in the lock and grimace as something feels horribly wrong") then
            local critter_name = vars["Critter Name"] or ""
            if string.find(string.lower(critter_name), "soul golem") then
                vars["Lock Difficulty"] = "need vaalin"
            else
                if vars["Picking Mode"] == "worker" then
                    vars["Give Up On Box"] = true
                    vars["Lock Difficulty"] = "Soul Golem"
                else
                    vars["Lock Difficulty"] = "need vaalin"
                end
            end
            break
        end

        if string.find(line, "has already been unlocked") then
            vars["Lock Difficulty"] = "not locked"
            break
        end
        if string.find(line, "As you start to place the probe in the lock") then
            vars["Lock Difficulty"] = "can't find trap"
            break
        end
        if string.find(line, "but your song simply wasn't powerful enough") then
            vars["Lock Difficulty"] = "can't measure"
            break
        end
        if string.find(line, "^Try measuring something with a lock%.") then
            error("tpick:exit")
        end
    end

    waitrt()

    -- Store measured lock before buffer
    if type(vars["Lock Difficulty"]) == "number" then
        vars["Measured Lock"] = vars["Lock Difficulty"]
    end

    -- Apply lock buffer
    if type(vars["Lock Difficulty"]) == "number" and (load_data["Lock Buffer"] or 0) > 0 then
        vars["Lock Difficulty"] = vars["Lock Difficulty"] + load_data["Lock Buffer"]
        tsilent(nil, "You have lock buffer set to " .. load_data["Lock Buffer"]
            .. ", going to assume this lock is +" .. load_data["Lock Buffer"]
            .. " higher at -" .. vars["Lock Difficulty"], settings)
    end

    vars["Number Of Times To Measure"] = (vars["Number Of Times To Measure"] or 0) + 1

    if vars["Lock Difficulty"] == "can't measure" and vars["Number Of Times To Measure"] < 3 then
        M.measure_detection(vars, settings)
    elseif vars["Lock Difficulty"] == "IMPOSSIBLE" then
        vars["Lock Difficulty"] = "can't measure"
    end

    update_box_for_window(vars, settings)
end

---------------------------------------------------------------------------
-- 11. manually_disarm_trap (lines 3172-3807)
-- CORE FUNCTION: ~640 lines in Ruby. Detects and disarms all 17 trap types.
-- Sends DISARM IDENTIFY or DISARM, parses response, routes to handler.
---------------------------------------------------------------------------
function M.manually_disarm_trap(vars, settings)
    local load_data = settings.load_data
    local stats_data = settings.stats_data or {}

    waitrt()

    -- Plinite detection
    local box_name = vars["Current Box"] and vars["Current Box"].name or ""
    if string.find(box_name, "plinite") then
        if detect_plinite then detect_plinite(vars, settings) end
        return
    end

    -- Status message
    if vars["Time To Disarm Trap"] then
        tsilent(nil, "Attempting to disarm trap.", settings)
    else
        tsilent(nil, "Checking for traps.", settings)
        vars["403 Needed"] = nil
        vars["Need 404"] = nil
    end

    -- Sphere trap: need vaalin pick in hand
    if vars["Current Trap Type"] == "Sphere"
        or vars["Current Trap Type"] == "Sphere trap found, need to use lockpick to disarm."
    then
        if no_vaalin_picks then no_vaalin_picks(vars, settings) end
        local vaalin_ids = vars["all_pick_ids"] and vars["all_pick_ids"]["Vaalin"]
        local vaalin_id = vaalin_ids and vaalin_ids[1]
        if vaalin_id then
            for _ = 1, 3 do
                waitrt()
                if not in_either_hand(vaalin_id) then
                    fput("get #" .. vaalin_id)
                    pause(0.2)
                end
            end
            if not in_either_hand(vaalin_id) then
                tsilent(true, "Couldn't find your " .. (load_data["Vaalin"] or "vaalin lockpick") .. ".", settings)
                error("tpick:exit")
            end
        end
    end

    waitrt()

    -- 404 based on critter level
    if (load_data["Use 404 On Level"] or 200) ~= 200 then
        if vars["Critter Level"] == nil then
            tsilent(nil, "Critter level unknown, using 404 based on your settings.", settings)
            vars["Need 404"] = "yes"
        else
            if load_data["Use 404 On Level"] <= vars["Critter Level"] then
                tsilent(nil, "Critter level is " .. vars["Critter Level"] .. ", using 404 based on your settings.", settings)
                vars["Need 404"] = "yes"
            end
        end
    end

    -- Cast support spells
    if tpick_cast_spells then
        if vars["Use 402"] then tpick_cast_spells(402) end
        if vars["Use 404"] or vars["Need 404"] then tpick_cast_spells(404) end
        if vars["Use 506"] then tpick_cast_spells(506) end
        if vars["Use 613"] then tpick_cast_spells(613) end
        if vars["Use 1006"] then tpick_cast_spells(1006) end
        if vars["Use 1035"] then tpick_cast_spells(1035) end
    end

    local trap_cant_be_disarmed = false

    -- Ensure box is in hand for non-ground/worker modes
    if vars["Picking Mode"] ~= "ground" and vars["Picking Mode"] ~= "worker" then
        while true do
            local rh = GameObj.right_hand()
            if rh and rh.id then break end
            pause(0.1)
        end
        vars["Current Box"] = GameObj.right_hand()
        update_box_for_window(vars, settings)
    end

    waitrt()
    pause(1)
    waitrt()
    pause(0.3)
    waitrt()
    pause(0.1)
    waitrt()

    -- Track existing scarabs before disarm
    if vars["Current Trap Type"] == "Scarab" then
        vars["All Scarab IDs"] = {}
        local loot = GameObj.loot()
        if loot then
            for _, item in ipairs(loot) do
                if item.noun == "scarab" then
                    table.insert(vars["All Scarab IDs"], item.id)
                end
            end
        end
    end

    if vars["Current Trap Type"] == "Scarab" then
        util.tpick_say("Scarab Found", settings)
    end

    -- Handle 404/Lmaster Focus decisions for disarm attempt
    if vars["Time To Disarm Trap"] and vars["Trap Difficulty"] then
        -- Stop 404 if not needed
        if load_data["404"] and string.find(string.lower(load_data["404"]), "detect")
            and vars["Disarm Skill"] and vars["Trap Difficulty"]
            and (vars["Disarm Skill"] > vars["Trap Difficulty"])
            and not vars["Use 404/Trap Higher Than Setting"]
        then
            tsilent(nil, "According to your settings you want to stop 404 when it's not needed to disarm a trap.", settings)
            -- tpick_stop_spell(404) -- handled by spell module
        end
        if load_data["404"] and string.find(string.lower(load_data["404"]), "auto")
            and not vars["Use 404"] and not vars["Need 404"]
            and not vars["Use 404/Trap Higher Than Setting"]
        then
            -- tpick_stop_spell(404)
        end
        fput("disarm #" .. vars["Current Box"].id)
    else
        if tpick_cast_spells then
            if load_data["404"] and string.find(string.lower(load_data["404"]), "detect") then
                tpick_cast_spells(404)
            end
            if vars["Use 506"] then tpick_cast_spells(506) end
        end
        fput("detect #" .. vars["Current Box"].id)
    end

    ---------------------------------------------------------------------------
    -- Main line-reading loop: parse DISARM/DETECT output
    ---------------------------------------------------------------------------
    while true do
        local line = get()
        if not line then break end

        ---------------------------------------------------------------
        -- Trap difficulty extraction: (-NNN).
        ---------------------------------------------------------------
        local trap_diff = string.match(line, "%(.*%-(%d+)%)%.")
        if trap_diff then
            vars["Trap Difficulty"] = tonumber(trap_diff)
            local disarm_skill_plus_lore = (vars["Disarm Skill"] or 0) + (vars["Disarm Lore"] or 0)
            vars["Total Trap Skill"] = (vars["Disarm Skill"] or 0) + (vars["Disarm Lore"] or 0) + (load_data["Trap Roll"] or 0)

            if not vars["Time To Disarm Trap"] then
                tsilent(nil,
                    "Trap difficulty is: " .. vars["Trap Difficulty"] .. "\n"
                    .. "Your disarm skill is: " .. (vars["Disarm Skill"] or 0) .. "\n"
                    .. "Your total disarm skill with lore is: " .. disarm_skill_plus_lore .. "\n"
                    .. "Highest trap you are willing to try is: " .. (vars["Total Trap Skill"] or 0),
                    settings)
            end

            if vars["Trap Difficulty"] > vars["Total Trap Skill"] then
                trap_cant_be_disarmed = true
            elseif vars["404 For Trap-Difficulty"] then
                if vars["Trap Difficulty"] > vars["404 For Trap-Difficulty"] then
                    if not vars["Time To Disarm Trap"] then
                        tsilent(nil, "Trap difficulty is higher than your setting in the setup menu for when to use Disarm Enhancement (404), going to use Disarm Enhancement (404).", settings)
                    end
                    vars["Use 404/Trap Higher Than Setting"] = true
                    vars["Need 404"] = "yes"
                end
            elseif (vars["Trap Difficulty"] + 40) > (vars["Disarm Skill"] or 0)
                and (Spell[404].known or (load_data["Use Lmaster Focus"] == "Yes"))
            then
                if not vars["Time To Disarm Trap"] then
                    tsilent(nil, "This trap looks tough, going to use Disarm Enhancement (404) or Lock Mastery Focus.", settings)
                end
                vars["Need 404"] = "yes"
            elseif vars["Trap Difficulty"] > (vars["Disarm Skill"] or 0)
                and not Spell[404].known
                and load_data["Use Lmaster Focus"] ~= "Yes"
            then
                trap_cant_be_disarmed = true
            end

        ---------------------------------------------------------------
        -- Box is enruned/mithril check
        ---------------------------------------------------------------
        elseif string.find(line, "You carefully begin to examine") and string.find(line, "for traps") then
            vars["Box Is Enruned/Mithril"] = nil
            if Regex.test("mithril|enruned|rune%-incised", line) then
                vars["Box Is Enruned/Mithril"] = true
            end

        ---------------------------------------------------------------
        -- Failed to disarm
        ---------------------------------------------------------------
        elseif string.find(line, "Having discovered a trap on the")
            and string.find(line, "you begin to carefully attempt to disarm it")
        then
            vars["Current Trap Type"] = "Couldn't disarm trap, trying again."

        ---------------------------------------------------------------
        -- SCARAB detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you spy a") and string.find(line, "scarab wedged into the lock mechanism") then
            local scarab_name = string.match(line, "you spy an? [a-zA-Z]+ (.*) scarab wedged into the lock mechanism%.")
            if scarab_name then
                vars["Scarab Name"] = scarab_name
            end
            vars["Current Trap Type"] = "Scarab"

        -- Successful manual disarm
        elseif string.find(line, "You carefully nudge the scarab free of its prison")
            and string.find(line, "The scarab falls from the lock")
        then
            vars["Current Trap Type"] = "Scarab trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "The lock appears to be free of all obstructions") then
            vars["Current Trap Type"] = "Scarab trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "Looking closely at the lock")
            and string.find(line, "scarab wedged into the lock mechanism")
            and string.find(line, "The scarab is surrounded by crimson glow")
        then
            vars["Current Trap Type"] = "Scarab trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- NEEDLE detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you can see what appears to be a tiny hole next to the lock plate")
            and string.find(line, "a gleaming sliver of metal recessed in the hole")
        then
            vars["Current Trap Type"] = "Needle"

        -- Successful manual disarm
        elseif Regex.test(
            "Using a bit of putty from your.*, you manage to block the tiny hole in the lock plate"
            .. "|Using a pair of metal grips, you carefully remove .* from .* and cover the tip with a bit of putty",
            line)
        then
            vars["Current Trap Type"] = "Needle trap has been disarmed."
            vars["Putty Remaining"] = vars["Putty Remaining"] or 999
            if vars["Putty Remaining"] ~= 999 then
                vars["Putty Remaining"] = vars["Putty Remaining"] - 1
            end
            break

        -- Already manually disarmed
        elseif Regex.test(
            "You see a tiny hole next to the lock plate which has been completely plugged"
            .. "|you can see what appears to be a tiny hole next to the lock plate which doesn't seem to belong there%.  However, nothing about it seems to indicate cause for alarm"
            .. "|You spot a shiny metal needle sticking out of a small hole next to the lockplate with some sort of dark paste on it",
            line)
        then
            vars["Current Trap Type"] = "Needle trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "you can see what appears to be a tiny hole next to the lock plate which doesn't belong there")
            and string.find(line, "An occasional glint of red winks at you from within the hole")
        then
            vars["Current Trap Type"] = "Needle trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- JAWS detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "You notice a discolored oval ring around the outside of the")
            and string.find(line, "spring-loaded jaws pressed flush against the")
            and string.find(line, "walls")
        then
            vars["Current Trap Type"] = "Jaws"

        -- Successful manual disarm
        elseif Regex.test(
            "Using the pair of metal grips, you manage to pull out the two pins that hold the upper and lower jaw pieces together"
            .. "|Using your metal grips, you carefully remove a pair of small steel jaws from the",
            line)
        then
            vars["Current Trap Type"] = "Jaws trap has been disarmed."
            break

        -- Already manually disarmed
        elseif (string.find(line, "You notice a discolored oval ring around the outside of the")
            and string.find(line, "the pins that hold the jaws together have been pushed out"))
            or (string.find(line, "You notice a discolored oval ring around the outside of the")
            and string.find(line, "some vital part of whatever trap was here has been removed"))
        then
            vars["Current Trap Type"] = "Jaws trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "You see a pair of metal jaws clamped tightly before the lockplate")
            or string.find(line, "The jaws are surrounded with a reddish glow")
        then
            vars["Current Trap Type"] = "Jaws trap has already been disarmed with 408. Can't pick it."
            break

        -- Trap has already been set off
        elseif string.find(line, "You see a pair of bloody jaws clamped tightly before the lockplate") then
            vars["Current Trap Type"] = "Jaws trap has already been set off."
            break

        ---------------------------------------------------------------
        -- SPHERE detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you locate")
            and string.find(line, "sphere held in a metal bracket")
            and string.find(line, "the gem would be caught amongst them")
        then
            vars["Current Trap Type"] = "Sphere"

        -- Successful manual disarm
        elseif string.find(line, "With utmost care, you slip your")
            and (string.find(line, "you are able to poke the gem free of its metal housing")
                or string.find(line, "you knock the gem free of its metal housing"))
        then
            vars["Current Trap Type"] = "Sphere trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "A thorough search of the area inside the tumblers reveals what appears to be a metal bracket")
            and string.find(line, "it seems to be empty now")
        then
            vars["Current Trap Type"] = "Sphere trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif Regex.test("The sphere is surrounded by a.*crimson glow", string.lower(line)) then
            vars["Current Trap Type"] = "Sphere trap has already been disarmed with 408."
            break

        -- Need lockpick in hand
        elseif string.find(line, "your fingers are just too big to get back there to the gem")
            and string.find(line, "You'll need some sort of thin, rigid implement like a lockpick")
        then
            vars["Current Trap Type"] = "Sphere trap found, need to use lockpick to disarm."
            if no_vaalin_picks then no_vaalin_picks(vars, settings) end
            local vaalin_ids = vars["all_pick_ids"] and vars["all_pick_ids"]["Vaalin"]
            local vaalin_id = vaalin_ids and vaalin_ids[1]
            if vaalin_id then
                for _ = 1, 3 do
                    waitrt()
                    if not in_either_hand(vaalin_id) then
                        fput("get #" .. vaalin_id)
                        pause(0.2)
                    end
                end
                if not in_either_hand(vaalin_id) then
                    tsilent(true, "Couldn't find your " .. (load_data["Vaalin"] or "vaalin lockpick") .. ".", settings)
                    error("tpick:exit")
                end
            end

        -- Setting off trap
        elseif string.find(line, "you hear a sound like shattered crystal")
            and string.find(line, "light flashes from the lock mechanism")
        then
            vars["Current Trap Type"] = "Sphere trap has been set off."
            tsilent(true, "Sphere trap has been set off! Exiting.", settings)
            error("tpick:exit")

        -- Trap already set off
        elseif string.find(line, "a thorough and careful search of the lock mechanism indicates that the entire")
            and string.find(string.upper(line), "MANGLED")
            and string.find(line, "not trapped anymore")
        then
            vars["Current Trap Type"] = "Sphere trap has already been set off."
            break

        ---------------------------------------------------------------
        -- CRYSTAL detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you spy")
            and string.find(line, "crystal which seems imbedded in the locking mechanism")
            and string.find(line, "could shatter it")
        then
            vars["Current Trap Type"] = "Crystal"

        -- Successful manual disarm
        elseif string.find(line, "you manage to grind down parts of the lock mechanism with your metal file") then
            vars["Current Trap Type"] = "Crystal trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "crystal which seems imbedded in the locking mechanism")
            and string.find(line, "parts of the mechanism have been ground away")
        then
            vars["Current Trap Type"] = "Crystal trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "crystal imbedded in the locking mechanism")
            and string.find(line, "a slight reddish glow about it")
        then
            vars["Current Trap Type"] = "Crystal trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- SCALES detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif Regex.test(
            "appears to be covered with hundreds of tiny metal scales"
            .. "|Despite heavy scrutiny, you can see no way to pry off any of the scales",
            line)
        then
            vars["Current Trap Type"] = "Scales"

        -- Successful manual disarm
        elseif string.find(line, "you gently slide your")
            and string.find(line, "slice through the cord")
            and string.find(line, "That oughta do it")
        then
            vars["Current Trap Type"] = "Scales trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "you see what appears to be a thin cord dangling from the case")
            and string.find(line, "looks to have been sliced through")
        then
            vars["Current Trap Type"] = "Scales trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "A crimson glow seeps between the lid and the casing") then
            vars["Current Trap Type"] = "Scales trap has already been disarmed with 408."
            break

        -- Need dagger in hand
        elseif string.find(line, "You figure that if you had a dagger, you could probably cut the cord") then
            vars["Current Trap Type"] = "Scales trap found, need to use dagger to disarm."
            break

        ---------------------------------------------------------------
        -- SULPHUR detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "the casing is coated with a rough, grainy substance")
            and string.find(line, "a small bladder filled with a strange liquid wedged between the tumblers")
            and string.find(line, "faintest scent of sulphur")
        then
            vars["Current Trap Type"] = "Sulphur"

        -- Successful manual disarm
        elseif string.find(line, "you carefully use the tip of a small metal file to scrape away")
            and string.find(line, "a strange clear gel oozes forth from the hole")
            and string.find(line, "blowing away in the wind as if it never existed")
        then
            vars["Current Trap Type"] = "Sulphur trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "the casing is coated with a rough, grainy substance")
            and string.find(line, "A small section of the casing has been scraped clean")
            and string.find(line, "a deflated bladder wedged between the tumblers")
        then
            vars["Current Trap Type"] = "Sulphur trap has already been disarmed."
            break

        -- Trap already set off (shares line with sphere)
        elseif string.find(line, "a thorough and careful search of the lock mechanism indicates that the entire")
            and string.find(string.upper(line), "MANGLED")
            and not string.find(line, "not trapped anymore")
        then
            vars["Current Trap Type"] = "Sulphur trap has already been set off."
            break

        ---------------------------------------------------------------
        -- CLOUD detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you spy a small vial of liquid and a tiny hammer device which seems poised to shatter it if the lock is tampered with") then
            vars["Current Trap Type"] = "Cloud"

        -- Successful manual disarm
        elseif Regex.test(
            "you manage to reach in and grasp the post of the metal hammer, and bend the weak metal out of striking range of the vial"
            .. "|Having rendered the hammer harmless, you carefully remove a green%-tinted vial filled with thick acrid smoke",
            line)
        then
            vars["Current Trap Type"] = "Cloud trap has been disarmed."
            break

        -- Already manually disarmed
        elseif Regex.test(
            "you spy a tiny hammer device which has been bent back slightly"
            .. "|you spy a small vial of liquid and a tiny hammer device which has been bent from striking range of the vial"
            .. "|you spy a tiny hammer device and several splinters of glass",
            line)
        then
            vars["Current Trap Type"] = "Cloud trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "you spy a small vial of liquid and a tiny hammer device which has a red glow about it") then
            vars["Current Trap Type"] = "Cloud trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- ACID VIAL detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you spy a tiny vial placed just past the tumblers of the lock mechanism")
            and string.find(line, "any tampering with the lock mechanism would cause the tumblers to crush the vial")
        then
            vars["Current Trap Type"] = "Acid Vial"

        -- Successful manual disarm
        elseif Regex.test(
            "You carefully push a small ball of cotton into the lock mechanism, surrounding and protecting the small vial"
            .. "|Using a pair of metal grips, you carefully remove the padded clear glass vial",
            line)
        then
            vars["Current Trap Type"] = "Acid vial trap has been disarmed."
            vars["Cotton Remaining"] = vars["Cotton Remaining"] or 999
            if vars["Cotton Remaining"] ~= 999 then
                vars["Cotton Remaining"] = vars["Cotton Remaining"] - 1
            end
            break

        -- Already manually disarmed
        elseif Regex.test(
            "you spy a tiny vial placed just past the tumblers of the lock mechanism%.  A small ball of cotton has been pushed up against the vial"
            .. "|you spy a small metal housing set just inside the lock mechanism, but it appears empty"
            .. "|you spy a small metal housing, which appears to be empty",
            line)
        then
            vars["Current Trap Type"] = "Acid vial trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif Regex.test(
            "You notice what appears to be a tiny vial placed just past the tumblers of the lock mechanism%.  A crimson glow surrounds the vial"
            .. "|you spy a tiny vial set just inside the lock mechanism%.  The vial is surrounded by crimson glow",
            line)
        then
            vars["Current Trap Type"] = "Acid vial trap has already been disarmed with 408."
            break

        -- Setting off trap
        elseif string.find(line, "You peer inside the lock and see that the tumblers have all been fused into a lump of useless metal") then
            vars["Current Trap Type"] = "Acid vial trap has been set off."
            break

        -- Trap already set off
        elseif string.find(line, "You peer inside the lock and see that the tumblers have been fused into a lump of useless metal") then
            vars["Current Trap Type"] = "Acid vial trap has already been set off."
            break

        ---------------------------------------------------------------
        -- SPRINGS detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you notice what appears to be the ends of springs incorporated with the hinges")
            and string.find(line, "Seems rather odd to have")
        then
            vars["Current Trap Type"] = "Springs"

        -- Successful manual disarm
        elseif Regex.test(
            "With a little force applied to the springs, you manage to pop them inside.*the tinkle of breaking glass"
            .. "|With a little force applied to the springs, you manage to pop them inside.*You also hear something else rolling around in there",
            line)
        then
            vars["Current Trap Type"] = "Springs trap has been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "You spot a reddish glow about the hinges") then
            vars["Current Trap Type"] = "Springs trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- FIRE VIAL detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you spy a small vial of fire-red liquid and a tiny hammer device which seems poised to shatter it") then
            vars["Current Trap Type"] = "Fire Vial"

        -- Successful manual disarm
        elseif Regex.test(
            "you manage to reach in and grasp the post of the metal hammer, and bend the weak metal out of striking range of the vial"
            .. "|Having rendered the hammer harmless, you carefully remove a thick glass vial filled with murky red liquid",
            line)
        then
            vars["Current Trap Type"] = "Fire vial trap has been disarmed."
            break

        -- Already manually disarmed
        elseif Regex.test(
            "you spy a tiny hammer device which has been bent back slightly"
            .. "|you spy a small vial of fire%-red liquid and a tiny hammer device which has been bent from striking range of the vial"
            .. "|you spy a tiny hammer device and several splinters of glass",
            line)
        then
            vars["Current Trap Type"] = "Fire vial trap has already been disarmed."
            break

        ---------------------------------------------------------------
        -- SPORES detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you see a small tube towards the bottom of the tumbler mechanism")
            and string.find(line, "The tube is capped with a thin membrane")
        then
            vars["Current Trap Type"] = "Spores"

        -- Successful manual disarm
        elseif string.find(line, "Taking a lump of putty from your")
            and string.find(line, "you carefully apply it to the end of the small tube")
        then
            vars["Current Trap Type"] = "Spores trap has been disarmed."
            vars["Putty Remaining"] = vars["Putty Remaining"] or 999
            if vars["Putty Remaining"] ~= 999 then
                vars["Putty Remaining"] = vars["Putty Remaining"] - 1
            end
            break

        -- Already manually disarmed
        elseif string.find(line, "you see a small tube towards the bottom of the tumbler mechanism")
            and string.find(line, "the tube has been plugged with something")
        then
            vars["Current Trap Type"] = "Spores trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif Regex.test(
            "You see a thin tube extending from the lock mechanism down into the.*The end of the tube is surrounded by a crimson glow"
            .. "|you see a small tube towards the bottom of the tumbler mechanism%.  A crimson glow surrounds the mouth of the tube",
            line)
        then
            vars["Current Trap Type"] = "Spores trap has already been disarmed with 408."
            break

        -- Trap already set off
        elseif string.find(line, "you see a small tube towards the bottom of the tumbler mechanism")
            and string.find(line, "it has torn mostly away, and greyish-green powder covers the area")
        then
            vars["Current Trap Type"] = "Spores trap has already been set off."
            break

        ---------------------------------------------------------------
        -- PLATE detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "There appears to be a plate over the lock, sealing it and preventing any access to the tumblers")
            or string.find(line, "Gonna chew through it")
        then
            vars["Current Trap Type"] = "Plate"

        -- Successful manual disarm
        elseif Regex.test(
            "the metal plate covering the lock begins to melt away"
            .. "|and carefully pour the contents onto the .* where you think the keyhole ought to be",
            line)
        then
            vars["Current Trap Type"] = "Plate trap has been disarmed."
            vars["Vials Remaining"] = (vars["Vials Remaining"] or 1) - 1
            break

        -- Already manually disarmed
        elseif string.find(line, "a metal plate covering the lock plate, but it appears to have been melted through") then
            vars["Current Trap Type"] = "Plate trap has already been disarmed."
            break

        ---------------------------------------------------------------
        -- GLYPH detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "You notice some spiderweb-like scratches on the lock plate")
            and string.find(line, "it might be some type of glyph spell")
            and not string.find(line, "some of the markings have been altered")
        then
            vars["Current Trap Type"] = "Glyph"
            vars["Box Has Glyph Trap"] = true

        -- Successful manual disarm
        elseif string.find(line, "Knowing how delicate magical glyphs can be")
            and string.find(line, "you scrape some extra lines into the markings")
        then
            vars["Current Trap Type"] = "Glyph trap has been disarmed."
            vars["Box Has Glyph Trap"] = true
            break

        -- Already manually disarmed
        elseif string.find(line, "You notice some spiderweb-like scratches on the lock plate")
            and string.find(line, "some of the markings have been altered")
        then
            vars["Current Trap Type"] = "Glyph trap has already been disarmed."
            vars["Box Has Glyph Trap"] = true
            break

        ---------------------------------------------------------------
        -- RODS detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "you notice a pair of small metal rods a hair's width from touching each other")
            and string.find(line, "the lock would push the two rods together")
        then
            vars["Current Trap Type"] = "Rods"

        -- Successful manual disarm
        elseif string.find(line, "you take a pair of metal grips and bend the sensitive metal rods out of alignment") then
            vars["Current Trap Type"] = "Rods trap has been disarmed."
            break

        -- Already manually disarmed
        elseif string.find(line, "you notice a pair of small metal rods that have been bent in opposite directions") then
            vars["Current Trap Type"] = "Rods trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif Regex.test(
            "you notice a pair of small metal rods surrounded by a crimson glow"
            .. "|you notice a pair of small metal rods that have a slight reddish glow about them",
            line)
        then
            vars["Current Trap Type"] = "Rods trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- BOOMER detection and disarm messages
        ---------------------------------------------------------------
        -- Manual detection
        elseif string.find(line, "the inside chamber is coated with a strange white substance")
            and string.find(line, "detonation system for an explosive mixture")
        then
            vars["Current Trap Type"] = "Boomer"

        -- Successful manual disarm
        elseif string.find(line, "Using a bit of putty from your")
            and string.find(line, "you cake a thin layer on the lock casing")
            and string.find(line, "sufficient to prevent sparks")
        then
            vars["Current Trap Type"] = "Boomer trap has been disarmed."
            vars["Putty Remaining"] = vars["Putty Remaining"] or 999
            if vars["Putty Remaining"] ~= 999 then
                vars["Putty Remaining"] = vars["Putty Remaining"] - 1
            end
            break

        -- Already manually disarmed
        elseif string.find(line, "A thin layer of mud or putty has been dabbed on the connecting point") then
            vars["Current Trap Type"] = "Boomer trap has already been disarmed."
            break

        -- Already disarmed with 408
        elseif string.find(line, "A deep red glow surrounds the striking arm of the trap mechanism") then
            vars["Current Trap Type"] = "Boomer trap has already been disarmed with 408."
            break

        ---------------------------------------------------------------
        -- NO TRAP FOUND
        ---------------------------------------------------------------
        elseif string.find(line, "You discover no traps") then
            vars["Current Trap Type"] = "No trap found."
            break

        ---------------------------------------------------------------
        -- BOX IS ALREADY OPEN
        ---------------------------------------------------------------
        elseif Regex.test(
            "Um, but it's open"
            .. "|There is no lock on that"
            .. "|You blink in surprise as though just becoming aware of"
            .. "|What were you referring to"
            .. "|You want to pick a lock on what",
            line)
        then
            vars["Current Trap Type"] = "Box is already open."
            vars["Box Math"] = nil
            break

        ---------------------------------------------------------------
        -- NO PUTTY
        ---------------------------------------------------------------
        elseif string.find(line, "You figure that if you had some sort of putty") then
            tsilent(true, "No putty to disarm this trap. Exiting.\nBe sure to fill up your locksmith's container.\nThe script can do it for you by doing: ;tpick buy", settings)
            error("tpick:exit")

        ---------------------------------------------------------------
        -- ROUNDTIME or ...wait
        ---------------------------------------------------------------
        elseif string.find(line, "Roundtime") or string.find(line, "%.%.%.wait") then
            break
        end
    end -- end while get()

    update_box_for_window(vars, settings)

    -- Track trap stats
    if vars["Current Trap Type"] and ALL_TRAP_NAMES_SET[vars["Current Trap Type"]] then
        if stats_data[vars["Current Trap Type"]] then
            stats_data[vars["Current Trap Type"]] = stats_data[vars["Current Trap Type"]] + 1
        end
    end

    vars["Time To Disarm Trap"] = true

    ---------------------------------------------------------------------------
    -- Post-detection routing
    ---------------------------------------------------------------------------
    if TRAP_DONE_STATES[vars["Current Trap Type"]] then
        -- Trap is done (disarmed, already disarmed, or no trap)
        tsilent(nil, vars["Current Trap Type"], settings)

        if string.find(vars["Current Trap Type"], "already") then
            vars["Box Math"] = nil
        end

        vars["Manual Trap Checks Remaining"] = (vars["Manual Trap Checks Remaining"] or 1) - 1

        -- Recheck if no trap found but bracers said there was one, or checks remaining
        if vars["Current Trap Type"] == "No trap found."
            and (vars["Bracers Found Trap"] or (vars["Manual Trap Checks Remaining"] or 0) > 0)
        then
            if vars["Bracers Found Trap"] then
                tsilent(nil, "No trap found but bracers said there was a trap. Checking again.", settings)
            else
                tsilent(nil, "Number of trap checks remaining: " .. (vars["Manual Trap Checks Remaining"] or 0), settings)
            end
            vars["Time To Disarm Trap"] = nil
            M.manually_disarm_trap(vars, settings)
            return
        end

        -- Track "No Trap" stat
        if vars["Current Trap Type"] == "No trap found." then
            if stats_data["No Trap"] then
                stats_data["No Trap"] = stats_data["No Trap"] + 1
            end
        end

        waitrt()

        -- Auto bundle vials if in hand
        if load_data["Auto Bundle Vials"] == "Yes" then
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            local has_vial = (rh and string.find(rh.name or "", "vial"))
                          or (lh and string.find(lh.name or "", "vial"))
            if has_vial then
                -- Check if vial is needed for rogues task
                local need_vial_for_task = false
                if vars["rogue_automate_current_task_with_tpick"]
                    and vars["Picking Mode"] == "worker"
                    and vars["rogue_current_task"] == "Gather trap components"
                then
                    local trap_names = vars["rogue_trap_components_needed_names"] or {}
                    for _, name in ipairs(trap_names) do
                        if Regex.test("clear vial|thick vial|green vial", name) then
                            need_vial_for_task = true
                            break
                        end
                    end
                end

                if need_vial_for_task then
                    tsilent(true, "This vial is needed for your task so we are not bundling it in your locksmith's kit.", settings)
                else
                    if tpick_bundle_vials then tpick_bundle_vials(vars, settings) end
                end
            end
        end

        -- Scarab pickup after disarm
        if vars["Current Trap Type"] == "Scarab trap has been disarmed." then
            tsilent(nil, "Disarming scarab.", settings)
            waitrt()
            if tpick_cast_spells then
                if vars["Use 506"] then tpick_cast_spells(506) end
                if vars["Use 1035"] then tpick_cast_spells(1035) end
            end
            pause(1)
            waitrt()

            local scarab_object = nil
            local loot = GameObj.loot()
            if loot then
                for _, item in ipairs(loot) do
                    if item.noun == "scarab"
                        and string.find(item.name or "", vars["Scarab Name"] or "")
                        and not M._id_in_list(item.id, vars["All Scarab IDs"] or {})
                    then
                        if load_data["Disarm (408)"] == "Yes" then
                            -- Use 408 on scarab
                            while true do
                                if tpick_cast_spells then
                                    if vars["Use 515"] then tpick_cast_spells(515) end
                                end
                                if checkmana and checkmana() < 13 then
                                    tsilent(true, "Waiting for mana.", settings)
                                    wait_until(function() return checkmana(13) end)
                                end
                                waitrt()
                                waitcastrt()
                                fput("release")
                                fput("prep 408")
                                pause(0.5)

                                local result = dothistimeout("cast #" .. item.id, 3,
                                    { "The runes on the scarab go still", "Cast Roundtime" })
                                if result and string.find(result, "The runes on the scarab go still") then
                                    scarab_object = item
                                    break
                                end
                                -- Cast Roundtime means failed, try again
                            end
                        else
                            -- Manual disarm of scarab
                            waitrt()
                            local result = dothistimeout("disarm #" .. item.id, 5,
                                { "As you reach for the", "Knowing how delicate magical runes can be" })
                            if result and string.find(result, "Knowing how delicate magical runes can be") then
                                scarab_object = item
                            end
                        end

                        if scarab_object then break end
                    end
                end
            end

            if scarab_object then
                util.tpick_say("Scarab Safe", settings)
                -- Pick up scarab
                while true do
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    local rh_noun = rh and rh.noun or ""
                    local lh_noun = lh and lh.noun or ""
                    if rh_noun == "scarab" or lh_noun == "scarab" then break end
                    waitrt()
                    fput("get #" .. scarab_object.id)
                    pause(0.5)
                end

                if stats_data["Pool Scarabs Received"] and vars["Picking Mode"] == "worker" then
                    stats_data["Pool Scarabs Received"] = stats_data["Pool Scarabs Received"] + 1
                end
                if stats_data["Loot Session"] then
                    stats_data["Loot Session"]["Scarabs"] = (stats_data["Loot Session"]["Scarabs"] or 0) + 1
                end
                if stats_data["Loot Total"] and load_data["Track Loot"] == "Yes" then
                    stats_data["Loot Total"]["Scarabs"] = (stats_data["Loot Total"]["Scarabs"] or 0) + 1
                end
            end

            util.tpick_put_stuff_away(vars, settings)
        end

        util.tpick_put_stuff_away(vars, settings)

        -- Route to next step
        if vars["Disarm Only"] then
            if vars["Bash Open Boxes"] then
                if bash_the_box_open then bash_the_box_open(vars, settings) end
            else
                vars["Box Math"] = nil
            end
        else
            if vars["Always Use Wedge"] then
                if wedge_lock then wedge_lock(vars, settings) end
            else
                if measure_lock then measure_lock(vars, settings) end
            end
        end

    elseif vars["Current Trap Type"] == "Couldn't disarm trap, trying again." then
        tsilent(nil, vars["Current Trap Type"], settings)
        vars["Need 404"] = "yes"
        if tpick_cast_spells then
            tpick_cast_spells(404)
            if vars["Use 506"] then tpick_cast_spells(506) end
        end
        M.manually_disarm_trap(vars, settings)

    elseif vars["Current Trap Type"] == nil then
        tsilent(true, "Something went wrong on my end, repeating the DISARM command.", settings)
        if tpick_cast_spells then
            tpick_cast_spells(404)
            if vars["Use 506"] then tpick_cast_spells(506) end
        end
        M.manually_disarm_trap(vars, settings)

    elseif vars["Current Trap Type"] == "Acid vial trap has been set off."
        or vars["Current Trap Type"] == "Acid vial trap has already been set off."
    then
        tsilent(true, vars["Current Trap Type"] .. "\nLock has been fused.", settings)
        if vars["Disarm Only"] then
            if vars["Bash Open Boxes"] then
                if bash_the_box_open then bash_the_box_open(vars, settings) end
            else
                vars["Box Math"] = nil
            end
        else
            M.fused_lock_disarm(vars, settings)
        end

    elseif vars["Current Trap Type"] == "Box is already open." then
        tsilent(nil, vars["Current Trap Type"], settings)
        if vars["Picking Mode"] == "solo" then
            if open_solo then open_solo(vars, settings) end
        elseif vars["Picking Mode"] == "other" then
            if open_others then open_others(vars, settings) end
        end

    elseif vars["Current Trap Type"] == "Plate" then
        tsilent(nil, "Found a " .. vars["Current Trap Type"] .. " trap.", settings)
        if vars["Disarm Only"] then
            if vars["Bash Open Boxes"] then
                if bash_the_box_open then bash_the_box_open(vars, settings) end
            else
                vars["Box Math"] = nil
            end
        else
            -- Stop 404 if not needed for plate
            if load_data["404"] and string.find(string.lower(load_data["404"]), "detect")
                and vars["Disarm Skill"] and vars["Trap Difficulty"]
                and (vars["Disarm Skill"] > vars["Trap Difficulty"])
                and vars["Trap Difficulty"]
                and not vars["Use 404/Trap Higher Than Setting"]
            then
                tsilent(nil, "According to your settings you want to stop 404 when it's not needed to disarm a trap.", settings)
                -- tpick_stop_spell(404)
            end
            M.plate_trap_disarm(vars, settings)
        end

    elseif vars["Current Trap Type"] == "Jaws trap has already been disarmed with 408. Can't pick it."
        or vars["Current Trap Type"] == "Jaws trap has already been set off."
    then
        tsilent(nil, vars["Current Trap Type"], settings)
        if vars["Disarm Only"] then
            if vars["Bash Open Boxes"] then
                if bash_the_box_open then bash_the_box_open(vars, settings) end
            else
                vars["Box Math"] = nil
            end
        else
            M.fused_lock_disarm(vars, settings)
        end

    else
        -- All other trap types: standard disarm flow
        if vars["Current Trap Type"] == "Scales trap found, need to use dagger to disarm."
            or vars["Current Trap Type"] == "Sphere trap found, need to use lockpick to disarm."
        then
            tsilent(nil, vars["Current Trap Type"], settings)
        else
            tsilent(nil, "Found a " .. (vars["Current Trap Type"] or "unknown") .. " trap.", settings)
        end

        if trap_cant_be_disarmed then
            tsilent(true, "Trap difficulty is too high according to your settings. Can't open box.", settings)
            if vars["Picking Mode"] == "solo" then
                util.where_to_stow_box(vars)
            elseif vars["Picking Mode"] == "other" then
                util.tpick_say("Can't Open Box", settings)
                if open_others then open_others(vars, settings) end
            elseif vars["Picking Mode"] == "ground" then
                vars["Box Opened"] = nil
                vars["Box Was Not Locked"] = nil
                vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
            elseif vars["Picking Mode"] == "worker" then
                vars["Give Up On Box"] = true
            end
        else
            if vars["Current Trap Type"] ~= "Scales" and not vars["Time To Disarm Trap"] then
                tsilent(nil, "Attempting to disarm trap.", settings)
            end

            if vars["Current Trap Type"] == "Scales" then
                tsilent(nil, "Scales trap found, picking lock first then disarming.", settings)
                vars["Scale Trap Found"] = true
                if measure_lock then measure_lock(vars, settings) end
            elseif vars["Current Trap Type"] == "Scales trap found, need to use dagger to disarm." then
                M.disarm_scale(vars, settings)
            elseif STANDARD_DISARM_TYPES[vars["Current Trap Type"]] then
                M.manually_disarm_trap(vars, settings)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Internal helper: check if ID is in a list
---------------------------------------------------------------------------
function M._id_in_list(id, list)
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

return M
