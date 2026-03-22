--- @revenant-script
--- name: creaturewindow
--- version: 1.6.1
--- author: Phocosoen
--- contributors: ChatGPT
--- game: gs
--- tags: wrayth, frontend, mod, window, target, creature, mob, bounty, advguild, avalon, wizard, gtk3
--- description: Real-time creature & bounty display window with kill metrics and bounty workflow automation
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from creaturewindow.lic v1.6.1
---
--- Changelog (from Lich5):
---   v1.6.1 — Added bounty action buttons for workflow automation (guild, guard, furrier, gem, herb, skin).
---            Added gem bounty automation with inventory-aware handling and gemshop routing controls.
---            Added herb bounty automation using zzherb and automated herb turn-in flow.
---            Added skin bounty action that tracks on-hand skin progress and automates furrier turn-in.
---            Added guard-return workflow support that can prep heirloom turn-ins and run scripted return flow.
---            Added turn-in NPC targeting safeguards that avoid invalid NPC types (familiars/animates).
---            Added TTK/KPM metrics display support with toggles in the creature window.
---
--- Usage:
---   ;creaturewindow              - Start creature window
---
--- In-game Commands (while running):
---   *ttk                         - Toggle time-to-kill metrics display
---   *bty                         - Toggle bounty task display
---   *cwcol                       - Toggle single/double column layout

no_kill_all()

local state = require("state")
local status_mod = require("status")
local metrics = require("metrics")
local bounty_display = require("bounty_display")
local workflows = require("workflows")
local gui = require("gui")

-- Load settings
state.load()

-- Command queue for workflow actions
local cmd_queue = {}
local target_cmd_queue = {}

--- Push a command to the appropriate queue.
local function push_cmd(cmd)
    cmd_queue[#cmd_queue + 1] = cmd
end

local function push_target_cmd(cmd)
    target_cmd_queue[#target_cmd_queue + 1] = cmd
end

--- Pop a command from a queue.
local function pop_cmd(queue)
    if #queue == 0 then return nil end
    local cmd = queue[1]
    table.remove(queue, 1)
    return cmd
end

-- Wire GUI callbacks
gui.on_workflow_cmd = function(cmd)
    push_cmd("run_" .. cmd .. "_workflow")
end

gui.on_target_cmd = function(cmd)
    push_target_cmd(cmd)
end

-- Create the GUI window
gui.create()

-- Hook IDs
local upstream_hook_id = Script.name .. "_upstream"
local downstream_hook_id = Script.name .. "_downstream"

-- Remove stale hooks
UpstreamHook.remove(upstream_hook_id)
DownstreamHook.remove(downstream_hook_id)

-- Downstream hook: capture recent lines for custom status detection
DownstreamHook.add(downstream_hook_id, function(line)
    local ok, _ = pcall(state.push_recent_line, line or "")
    if not ok then end
    return line
end)

-- Upstream hook: handle in-game toggle commands
UpstreamHook.add(upstream_hook_id, function(command)
    if not command then return command end
    local cmd_lower = command:lower()

    if cmd_lower:find("^%*bty") then
        local new_val = state.toggle("display_bounty")
        respond("Bounty display: " .. (new_val and "ON" or "OFF"))
        push_cmd("update_window")
        return nil
    end

    if cmd_lower:find("^%*ttk") then
        local enabled = not state.display_avg_ttk
        state.display_avg_ttk = enabled
        state.display_last_ttk = enabled
        state.display_kpm = enabled
        state.save()
        respond("Average TTK display: " .. (state.display_avg_ttk and "ON" or "OFF"))
        respond("Last TTK display: " .. (state.display_last_ttk and "ON" or "OFF"))
        respond("Kills per minute display: " .. (state.display_kpm and "ON" or "OFF"))
        push_cmd("update_window")
        return nil
    end

    if cmd_lower:find("^%*cwcol") then
        local new_val = state.toggle("single_column")
        respond("Column Layout: " .. (new_val and "Single" or "Double"))
        push_cmd("update_window")
        return nil
    end

    if cmd_lower:find("^%*cwgtk") then
        respond("GTK mode is not applicable in Revenant — native Gui window is always used.")
        return nil
    end

    -- Workflow commands (from text input)
    if cmd_lower:find("^%*cwherb") then push_cmd("run_herb_workflow"); return nil end
    if cmd_lower:find("^%*cwgem") then push_cmd("run_gem_workflow"); return nil end
    if cmd_lower:find("^%*cwguild") then push_cmd("run_guild_workflow"); return nil end
    if cmd_lower:find("^%*cwguard") then push_cmd("run_guard_workflow"); return nil end
    if cmd_lower:find("^%*cwfurrier") then push_cmd("run_furrier_workflow"); return nil end
    if cmd_lower:find("^%*cwskin") then push_cmd("run_skin_workflow"); return nil end

    return command
end)

-- Cleanup on exit
before_dying(function()
    UpstreamHook.remove(upstream_hook_id)
    DownstreamHook.remove(downstream_hook_id)
    gui.close()
end)

echo("Creaturewindow is active.")

-- Initialize bounty state
bounty_display.capture_origin()
bounty_display.parse()

-- Snapshot function for change detection
local function targets_snapshot(targets)
    local current = GameObj.target()
    local parts = {}
    for _, t in ipairs(targets) do
        parts[#parts + 1] = t.id .. ":" .. (t.status or "") .. ":" .. (t.name or "")
    end
    table.sort(parts)
    return table.concat(parts, "|") .. "|current:" .. (current and current.id or "nil")
end

-- Main loop state
local last_snapshot = ""
local last_ui_time = 0
local last_bounty_check = os.time()

--- Process the refresh cycle.
local function refresh(current_targets)
    local dead = GameObj.dead()

    -- Update metrics
    metrics.reset_if_inactive(dead)
    metrics.track_owned_room_kills(dead)
    metrics.track_missing_creatures(current_targets)

    -- Track alive creatures for TTK
    for _, t in ipairs(current_targets) do
        metrics.note_creature_alive(t.id)
    end

    -- Track current target
    local current = GameObj.target()
    if current then
        metrics.note_creature_targeted(current.id)
    end

    -- Update GUI
    gui.update(current_targets)
end

-- Main loop
while gui.is_open() do
    local current_targets = GameObj.targets()
    local snapshot = targets_snapshot(current_targets)

    -- Refresh on change or heartbeat
    if snapshot ~= last_snapshot or (os.time() - last_ui_time) > 1 then
        last_snapshot = snapshot
        last_ui_time = os.time()
        refresh(current_targets)
    end

    -- Process target commands
    local tcmd = pop_cmd(target_cmd_queue)
    if tcmd then
        local ok, err = pcall(fput, tcmd)
        if not ok then
            echo("Creaturewindow target command error: " .. tostring(err))
        end
        push_cmd("update_window")
    end

    -- Process command queue
    local cmd = pop_cmd(cmd_queue)
    if cmd then
        if cmd == "update_window" then
            refresh(current_targets)
            last_snapshot = targets_snapshot(current_targets)
            last_ui_time = os.time()
        elseif cmd == "run_herb_workflow" then
            workflows.run_herb()
        elseif cmd == "run_gem_workflow" then
            workflows.run_gem()
        elseif cmd == "run_guild_workflow" then
            workflows.run_guild()
        elseif cmd == "run_guard_workflow" then
            workflows.run_guard()
        elseif cmd == "run_furrier_workflow" then
            workflows.run_furrier()
        elseif cmd == "run_skin_workflow" then
            workflows.run_skin()
        end
    end

    -- Periodic bounty refresh (every 5 seconds)
    if os.time() - last_bounty_check > 5 then
        if not bounty_display.origin_npc_id then
            bounty_display.capture_origin()
        end
        bounty_display.parse()
        push_cmd("update_window")
        last_bounty_check = os.time()
    end

    pause(0.1)
end
