-- tpick/spells.lua -- Spell management: casting, preparing, stopping buff spells during lockpicking
-- Ported from tpick.lic lines 1997-2047, 5510-5619
-- Original authors: Dreaven et al.

local M = {}
local util  -- set by wire()
local modes -- set by wire()

---------------------------------------------------------------------------
-- M.wire(funcs) -- Inject cross-module dependencies.
-- Called once during init before any spell functions are used.
--
-- @param funcs  Table with keys: util, modes
---------------------------------------------------------------------------
function M.wire(funcs)
    util  = funcs.util  or require("tpick/util")
    modes = funcs.modes
end

---------------------------------------------------------------------------
-- Spell-number to buff-name mapping.
-- Used to check active status and determine spell vs buff category.
---------------------------------------------------------------------------
local SPELL_NAMES = {
    [402]  = "Presence",
    [403]  = "Lock Pick Enhancement",
    [404]  = "Disarm Enhancement",
    [506]  = "Celerity",
    [515]  = "Rapid Fire",
    [613]  = "Self Control",
    [1006] = "Song of Luck",
    [1035] = "Song of Tonis",
}

--- Spells whose active status is tracked via Effects.Buffs rather than Effects.Spells.
local BUFF_CATEGORY = {
    [402]  = true,
    [506]  = true,
    [515]  = true,
    [1035] = true,
}

---------------------------------------------------------------------------
-- M.tpick_cast_spells(number, vars, settings) -- Cast/maintain a buff spell.
-- Port of tpick_cast_spells from lines 5510-5575.
--
-- Handles:
--   - Lmaster Focus for 403/404
--   - Mana threshold check (Percent Mana To Keep)
--   - Spell-active / expiring-soon detection
--   - Song of Tonis (1035): skip if not affordable
--   - Rapid Fire (515): wait for 50 mana
--   - Armor removal before casting if configured
--   - Loop until spell is active
--
-- @param number    Spell number (402, 403, 404, 506, 515, 613, 1006, 1035)
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.tpick_cast_spells(number, vars, settings)
    local load_data = settings.load_data
    local spell_name = SPELL_NAMES[number]

    -- Flag that 403 is needed (used elsewhere for sequencing)
    if number == 403 then
        vars["Need 403"] = true
    end

    -- Lmaster Focus path for 403/404
    if load_data["Use Lmaster Focus"] == "Yes" and (number == 403 or number == 404) then
        -- Cast lmaster focus if not active or about to expire (< 10s remaining)
        if not Effects.Buffs.active("Focused") or
           (Effects.Buffs.active("Focused") and
            Effects.Buffs.remaining("Focused") and
            Effects.Buffs.remaining("Focused") < 10) then
            local successful = false
            while not successful do
                local result = dothistimeout("lmaster focus", 2,
                    "You focus intently on your picking and disarm skill%.")
                if result and string.find(result, "You focus intently") then
                    successful = true
                end
            end
        end
    elseif (load_data["Percent Mana To Keep"] or 0) > percentmana() then
        util.tpick_silent(true,
            "According to your settings your current mana is too low to cast spells.",
            settings)
    else
        -- Determine if spell needs to be (re)cast
        local needs_recast = false

        if spell_name and Spell[number].known then
            if BUFF_CATEGORY[number] then
                -- Check Effects.Buffs
                if not Effects.Buffs.active(spell_name) or
                   (Effects.Buffs.active(spell_name) and
                    Effects.Buffs.remaining(spell_name) and
                    Effects.Buffs.remaining(spell_name) < 10) then
                    needs_recast = true
                end
            else
                -- Check Effects.Spells
                if not Effects.Spells.active(spell_name) or
                   (Effects.Spells.active(spell_name) and
                    Effects.Spells.remaining(spell_name) and
                    Effects.Spells.remaining(spell_name) < 10) then
                    needs_recast = true
                end
            end
        end

        if needs_recast then
            -- Song of Tonis: skip if can't afford, don't wait
            if number == 1035 and not Spell[number].affordable then
                -- Do nothing, just skip
            else
                -- Rapid Fire (515): wait for at least 50 mana
                if number == 515 then
                    if checkmana() < 50 then
                        util.tpick_silent(true,
                            "Waiting for at least 50 mana before casting Rapid Fire (515).",
                            settings)
                        wait_until(function() return checkmana(50) end)
                    end
                elseif (Spell[number].mana_cost + 5) > checkmana() then
                    -- Wait until we have spell cost + 5 mana
                    util.tpick_silent(true, "Waiting for mana.", settings)
                    local cost = Spell[number].mana_cost + 5
                    wait_until(function() return checkmana() >= cost end)
                end

                -- Remove armor before casting if configured and not at a table
                if vars["Armor To Remove"] and not vars["Armor Removed"] then
                    local room_name = GameState.room_name or ""
                    if not string.find(string.lower(room_name), "table") then
                        vars["Armor Removed"] = true
                        waitrt()
                        fput("remove " .. vars["Armor To Remove"])
                        fput("stow " .. vars["Armor To Remove"])
                    end
                end

                -- Cast until active
                while not Spell[number].active do
                    Spell[number]:cast()
                end
                pause(0.2)
            end
        end
    end

    waitrt()
end

---------------------------------------------------------------------------
-- M.tpick_prep_spell(number, name) -- Prepare a spell for manual casting.
-- Port of tpick_prep_spell from lines 5577-5591.
--
-- Waits for mana, releases any conflicting prep, then preps the requested
-- spell. Loops until checkprep() matches the spell name.
--
-- @param number  Spell number (e.g. 407).
-- @param name    Spell name string (e.g. "Unlock").
---------------------------------------------------------------------------
function M.tpick_prep_spell(number, name)
    if not Spell[number].known then
        return
    end

    -- Wait for enough mana (cost + 5 buffer)
    if (Spell[number].mana_cost + 5) > checkmana() then
        util.tpick_silent(true, "Waiting for mana.", { load_data = {} })
        local cost = Spell[number].mana_cost + 5
        wait_until(function() return checkmana() >= cost end)
    end

    -- Loop until the correct spell is prepped
    while checkprep() ~= name do
        waitrt()
        waitcastrt()
        local current_prep = checkprep()
        if current_prep ~= "None" and string.lower(current_prep) ~= string.lower(name) then
            fput("release")
        end
        fput("prep " .. number)
        pause(0.2)
    end
end

---------------------------------------------------------------------------
-- M.tpick_stop_spell(number, vars, settings) -- Stop a spell and Lmaster Focus.
-- Port of tpick_stop_spell from lines 5609-5612.
--
-- @param number    Spell number to stop.
-- @param vars      Mutable picking state (unused but kept for uniform signature).
-- @param settings  Settings table (unused but kept for uniform signature).
---------------------------------------------------------------------------
function M.tpick_stop_spell(number, vars, settings)
    if Spell[number].active then
        fput("stop " .. number)
    end
    if Effects.Buffs.active("Focused") then
        fput("stop lmaster focus")
    end
end

---------------------------------------------------------------------------
-- M.tpick_stop_403_404(vars, settings) -- Conditionally stop 403/404 between boxes.
-- Port of tpick_stop_403_404 from lines 5614-5619.
--
-- Checks both vars cancel flags and load_data auto-cancel settings.
-- Also stops Lmaster Focus if any cancel is configured.
--
-- @param vars      Mutable picking state (Cancel 403, Cancel 404 keys).
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.tpick_stop_403_404(vars, settings)
    local load_data = settings.load_data

    waitrt()

    local cancel_403 = (vars["Cancel 403"] and string.find(string.lower(vars["Cancel 403"]), "cancel"))
        or (load_data["403"] and string.find(string.lower(load_data["403"]), "cancel"))
    local cancel_404 = (vars["Cancel 404"] and string.find(string.lower(vars["Cancel 404"]), "cancel"))
        or (load_data["404"] and string.find(string.lower(load_data["404"]), "cancel"))

    if Spell[403].active and cancel_403 then
        fput("stop 403")
    end
    if Spell[404].active and cancel_404 then
        fput("stop 404")
    end
    if Effects.Buffs.active("Focused") and (cancel_403 or cancel_404) then
        fput("stop lmaster focus")
    end
end

---------------------------------------------------------------------------
-- M.cast_407(vars, settings) -- Cast Unlock (407) on the current box.
-- Port of cast_407 from lines 1997-2047.
--
-- Validates mana threshold, box material (mithril/enruned), glyph traps,
-- and user settings before casting. Routes success/failure to the
-- appropriate mode handler (solo/other/ground/worker).
--
-- On "vibrates slightly" failure: retries recursively.
-- On success (flies open / already open): routes to open handler.
-- On material/glyph/setting blocks: stows or gives back box per mode.
--
-- @param vars      Mutable picking state table.
-- @param settings  Settings table with load_data.
---------------------------------------------------------------------------
function M.cast_407(vars, settings)
    local load_data = settings.load_data

    -- Check mana threshold setting
    if (load_data["Unlock (407) Mana"] or -1) > -1 then
        vars["Stop Using 407"] = nil
        local mana_threshold = GameState.max_mana * (load_data["Unlock (407) Mana"] / 100.0)
        if checkmana() < mana_threshold then
            util.tpick_silent(nil,
                "According to your 407 settings your mana is too low to continue trying to open this box with 407.",
                settings)
            vars["Stop Using 407"] = true
        end
    end

    -- Check disqualifying conditions
    local box_name = vars["Current Box"] and vars["Current Box"].name or ""
    local is_blocked = string.find(string.lower(box_name), "mithril")
        or string.find(string.lower(box_name), "enruned")
        or string.find(string.lower(box_name), "rune%-incised")
        or vars["Box Is Enruned/Mithril"]
        or load_data["Unlock (407)"] == "Never"
        or vars["Stop Using 407"]
        or vars["Box Has Glyph Trap"]

    if is_blocked then
        -- Explain why we can't use 407 (unless it's just mana)
        if not vars["Stop Using 407"] then
            util.tpick_silent(true,
                "Can't open this plated box because it is mithril or enruned, or has a glyph trap, "
                .. "or because your settings are set to not use 407 to open boxes.",
                settings)
        end

        -- Route based on picking mode
        if vars["Picking Mode"] == "solo" then
            util.where_to_stow_box(vars)
            util.tpick_put_stuff_away(vars, settings)
            pause(0.1)
        elseif vars["Picking Mode"] == "other" then
            util.tpick_say("Can't Open Box", settings)
            if modes and modes.open_others then
                modes.open_others(vars, settings)
            end
        elseif vars["Picking Mode"] == "ground" then
            util.tpick_drop_box(vars)
            vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
            vars["Box Opened"] = nil
        elseif vars["Picking Mode"] == "worker" then
            vars["Give Up On Box"] = true
        end
    else
        -- Cast Rapid Fire (515) if configured
        if vars["Use 515"] then
            M.tpick_cast_spells(515, vars, settings)
        end

        -- Wait for at least 20 mana
        if checkmana() < 20 then
            util.tpick_silent(true, "Waiting for mana.", settings)
            wait_until(function() return checkmana() >= 20 end)
        end

        -- Cast 403 (Lock Pick Enhancement) first if not set to "never"
        if not (load_data["403"] and string.find(string.lower(load_data["403"]), "never")) then
            M.tpick_cast_spells(403, vars, settings)
        end

        -- Prep and cast 407
        M.tpick_prep_spell(407, "Unlock")
        local box_id = vars["Current Box"] and vars["Current Box"].id or ""
        local result = dothistimeout("cast #" .. box_id, 4,
            "vibrates slightly but nothing else happens%.|suddenly flies open%.|is already open%.")

        if result and (string.find(result, "suddenly flies open") or string.find(result, "is already open")) then
            -- Success: route to appropriate open handler
            if vars["Picking Mode"] == "solo" then
                if modes and modes.open_solo then
                    modes.open_solo(vars, settings)
                end
            elseif vars["Picking Mode"] == "other" then
                if modes and modes.open_others then
                    modes.open_others(vars, settings)
                end
            elseif vars["Picking Mode"] == "ground" then
                util.tpick_drop_box(vars)
            elseif vars["Picking Mode"] == "worker" then
                -- Worker mode: box is open, return to caller
            end
        elseif (result and string.find(result, "vibrates slightly")) or not result then
            -- Failure or timeout: retry
            M.cast_407(vars, settings)
        end
    end
end

return M
