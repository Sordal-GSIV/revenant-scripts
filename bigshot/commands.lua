--- Bigshot Commands — combat command execution
-- Dispatches hunting commands to the appropriate handler based on command type.

local command_check = require("command_check")

local M = {}

-- Main command dispatcher
function M.execute(command, target, state)
    if not command_check.should_execute(command, target, state) then
        return false, "conditions not met"
    end

    local clean = command_check.strip_modifiers(command)
    if clean == "" then return false, "empty command" end

    -- Determine command type and dispatch
    local cmd_type, cmd_args = clean:match("^(%S+)%s*(.*)")
    if not cmd_type then return false, "parse error" end
    cmd_type = cmd_type:lower()

    -- Spell casting (incant, prep, cast, channel)
    if cmd_type == "incant" then
        return M.cmd_spell(cmd_args, target, state)
    elseif cmd_type == "prep" or cmd_type == "cast" or cmd_type == "channel" then
        return M.cmd_spell_manual(cmd_type, cmd_args, target, state)

    -- Combat maneuvers
    elseif cmd_type == "mstrike" then
        return M.cmd_mstrike(cmd_args, target, state)
    elseif cmd_type == "feint" or cmd_type == "punch" or cmd_type == "kick"
        or cmd_type == "grapple" or cmd_type == "jab" then
        return M.cmd_cman(cmd_type, cmd_args, target, state)

    -- Movement/positioning
    elseif cmd_type == "hide" then
        return M.cmd_hide(state)
    elseif cmd_type == "ambush" then
        return M.cmd_ambush(cmd_args, target, state)

    -- Ranged
    elseif cmd_type == "aim" or cmd_type == "fire" or cmd_type == "shoot" then
        return M.cmd_ranged(cmd_type, cmd_args, target, state)

    -- Wand
    elseif cmd_type == "wave" or cmd_type == "raise" then
        return M.cmd_wand(cmd_type, cmd_args, target, state)

    -- Script delegation
    elseif cmd_type == "run" then
        return M.cmd_run_script(cmd_args, state)

    -- Pause
    elseif cmd_type == "sleep" or cmd_type == "wait" then
        return M.cmd_sleep(cmd_args)

    -- Generic: send as-is to the game
    else
        return M.cmd_generic(clean, target, state)
    end
end

-- Spell casting via incant
function M.cmd_spell(args, target, state)
    local spell_num = args:match("^(%d+)")
    if not spell_num then
        fput("incant " .. args)
        return true
    end

    -- Check if spell is known and affordable
    local spell = Spell[tonumber(spell_num)]
    if spell and spell.known and not spell.known then
        return false, "spell not known"
    end

    -- Target the creature if it's an attack spell
    waitrt()
    waitcastrt()
    if target then
        fput("incant " .. args .. " at #" .. target.id)
    else
        fput("incant " .. args)
    end
    return true
end

-- Manual spell flow: prep → cast
function M.cmd_spell_manual(cmd_type, args, target, state)
    waitrt()
    waitcastrt()
    if target and cmd_type == "cast" then
        fput(cmd_type .. " " .. args .. " at #" .. target.id)
    else
        fput(cmd_type .. " " .. args)
    end
    return true
end

-- MStrike
function M.cmd_mstrike(args, target, state)
    waitrt()
    if target then
        fput("mstrike #" .. target.id)
    else
        fput("mstrike")
    end
    return true
end

-- Combat maneuvers (generic)
function M.cmd_cman(cman_type, args, target, state)
    waitrt()
    if target and args == "" then
        fput(cman_type .. " #" .. target.id)
    else
        fput(cman_type .. " " .. args)
    end
    return true
end

-- Hide
function M.cmd_hide(state)
    waitrt()
    fput("hide")
    pause(0.3)
    return hidden and hidden() or false
end

-- Ambush
function M.cmd_ambush(args, target, state)
    if not (hidden and hidden()) then
        M.cmd_hide(state)
    end
    waitrt()
    if target then
        fput("ambush #" .. target.id .. " " .. args)
    else
        fput("ambush " .. args)
    end
    return true
end

-- Ranged combat
function M.cmd_ranged(cmd_type, args, target, state)
    waitrt()
    if target then
        fput(cmd_type .. " #" .. target.id)
    else
        fput(cmd_type .. " " .. args)
    end
    return true
end

-- Wand usage
function M.cmd_wand(cmd_type, args, target, state)
    waitrt()
    if target then
        fput(cmd_type .. " my " .. (args ~= "" and args or "wand") .. " at #" .. target.id)
    else
        fput(cmd_type .. " my " .. (args ~= "" and args or "wand"))
    end
    return true
end

-- Run external script
function M.cmd_run_script(args, state)
    local script_name = args:match("^(%S+)")
    local script_args = args:match("^%S+%s+(.+)$") or ""
    if script_name then
        Script.run(script_name, script_args)
        pause(1)
    end
    return true
end

-- Sleep/pause during combat
function M.cmd_sleep(args)
    local secs = tonumber(args) or 1
    pause(secs)
    return true
end

-- Generic command: send as-is, optionally targeting
function M.cmd_generic(command, target, state)
    waitrt()
    -- If command ends with "target" placeholder, replace with target id
    if target and command:find("#target") then
        command = command:gsub("#target", "#" .. target.id)
    end
    fput(command)
    return true
end

-- Execute a full command routine (list of commands)
function M.execute_routine(routine, target, state)
    for _, command in ipairs(routine) do
        if dead and dead() then return false, "dead" end
        if target and (target.status == "dead" or target.status == "gone") then
            return true, "target dead"
        end
        M.execute(command, target, state)
    end
    return true
end

return M
