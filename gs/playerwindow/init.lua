--- @revenant-script
--- name: playerwindow
--- version: 1.9.0
--- author: Phocosoen
--- contributors: ChatGPT
--- game: gs
--- tags: wrayth, frontend, mod, window, players, filter, spam, flare, combat, group, movement
--- description: Real-time player room display window with spam/flare/combat/animal filters and movement announcements
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from playerwindow.lic v1.9.0
---
--- Changelog (from Lich5):
---   v1.9.0 — Native Revenant Gui window replaces GTK3 PlayerWindowGtk.
---             CharSettings + JSON replace YAML-based settings persistence.
---             Pre-compiled Regex patterns replace Ruby regexp compilation.
---             Group API replaced with lib/group.lua Group.leader/Group.members.
---             Frontend.supports_streams() replaces $frontend == "stormfront".
---             os.time() replaces Ruby Time.now for join-delay tracking.
---             GameObj.inv() + .contents replaces GameObj.containers for wand scan.
---
--- Usage:
---   ;playerwindow              - Start player window
---
--- In-game Commands (while running):
---   *filterspam                - Toggle spam message filter
---   *filteranimals             - Toggle animal noise filter
---   *pwflare                   - Toggle flare message filter
---   *pwcombat                  - Toggle combat math filter
---   *pwcol                     - Toggle single/double column layout
---   *pwbuttons                 - Toggle filter toggle buttons display
---   *pwmove                    - Toggle player movement announcements
---   *pwdebug                   - Toggle filter debug mode
---   *pwgtk                     - Open/close the native GUI window

no_kill_all()

local state    = require("state")
local settings = require("settings")
local filter   = require("filter")
local display  = require("display")
local gui      = require("gui")

-- ── Settings ──────────────────────────────────────────────────────────────────

local saved = settings.load()
for k, v in pairs(saved) do state[k] = v end

-- Load user flare patterns (stored as JSON array of strings in CharSettings)
local FLARE_KEY = "playerwindow_flare_patterns"
local raw_flares = CharSettings[FLARE_KEY]
if raw_flares then
    local ok, patterns = pcall(Json.decode, raw_flares)
    if ok and type(patterns) == "table" then
        for _, pat in ipairs(patterns) do
            local ok2, re = pcall(Regex.new, pat)
            if ok2 then
                state.flare_patterns[#state.flare_patterns + 1] = re
            end
        end
    end
end

-- ── Action queue ──────────────────────────────────────────────────────────────

local action_queue = {}

local function push_action(action)
    action_queue[#action_queue + 1] = action
end

local function pop_action()
    if #action_queue == 0 then return nil end
    local a = action_queue[1]
    table.remove(action_queue, 1)
    return a
end

-- ── GUI callbacks ─────────────────────────────────────────────────────────────

gui.on_action = function(action)
    push_action(action)
end

gui.on_setting_change = function(field, val)
    state[field] = val
    settings.save(state)
    -- Wrayth dialog reflects filter button state; trigger refresh
    state.group_dirty = true
end

-- ── Hook IDs ──────────────────────────────────────────────────────────────────

local upstream_hook_id   = Script.name .. "_upstream"
local downstream_hook_id = Script.name .. "_downstream"

UpstreamHook.remove(upstream_hook_id)
DownstreamHook.remove(downstream_hook_id)

-- ── Upstream hook: toggle commands ────────────────────────────────────────────

UpstreamHook.add(upstream_hook_id, function(command)
    if not command then return command end
    local cmd = command:lower()

    if cmd:find("^%*filterspam") then
        state.filter_spam = not state.filter_spam
        settings.save(state)
        respond("Spam filter: " .. (state.filter_spam and "ON" or "OFF"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*filteranimals") then
        state.filter_animals = not state.filter_animals
        settings.save(state)
        respond("Animal filter: " .. (state.filter_animals and "ON" or "OFF"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*pwflare") then
        state.filter_flares = not state.filter_flares
        settings.save(state)
        respond("Flare filter: " .. (state.filter_flares and "ON" or "OFF"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*pwcombat") then
        state.filter_combat_math = not state.filter_combat_math
        settings.save(state)
        respond("Combat filter: " .. (state.filter_combat_math and "ON" or "OFF"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*pwcol") then
        state.single_column = not state.single_column
        settings.save(state)
        respond("Column layout: " .. (state.single_column and "Single" or "Double"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*pwbuttons") then
        state.show_filter_buttons = not state.show_filter_buttons
        settings.save(state)
        respond("Filter buttons: " .. (state.show_filter_buttons and "ON" or "OFF"))
        state.group_dirty = true
        return nil
    end

    if cmd:find("^%*pwmove") then
        state.show_movement = not state.show_movement
        settings.save(state)
        respond("Movement announcements: " .. (state.show_movement and "ON" or "OFF"))
        return nil
    end

    if cmd:find("^%*pwdebug") then
        state.debug_filter_enabled = not state.debug_filter_enabled
        respond("Filter debug: " .. (state.debug_filter_enabled and "ON" or "OFF"))
        return nil
    end

    if cmd:find("^%*pwgtk") then
        if gui.is_open() then
            gui.close()
            respond("Player window closed.")
        else
            gui.create()
            respond("Player window opened.")
        end
        return nil
    end

    return command
end)

-- ── Downstream hook: filter ────────────────────────────────────────────────────

DownstreamHook.add(downstream_hook_id, function(line)
    local ok, result = pcall(filter.filter, line)
    if not ok then return line end
    return result
end)

-- ── Window open ───────────────────────────────────────────────────────────────

-- Wrayth / Stormfront: open the XML dialog (display.lua handles it on each update)
-- Revenant GUI: open the native window
gui.create()

-- ── Cleanup ───────────────────────────────────────────────────────────────────

before_dying(function()
    UpstreamHook.remove(upstream_hook_id)
    DownstreamHook.remove(downstream_hook_id)
    gui.close()
end)

echo("Playerwindow is active.")

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Sort: dead first, then alphabetical by noun
local function sort_pcs(pcs)
    local sorted = {}
    for _, pc in ipairs(pcs) do sorted[#sorted + 1] = pc end
    table.sort(sorted, function(a, b)
        local sa = display.player_status_fix(a.status)
        local sb = display.player_status_fix(b.status)
        local da = (sa == "dead") and 0 or 1
        local db = (sb == "dead") and 0 or 1
        if da ~= db then return da < db end
        return display.extract_noun(a):lower() < display.extract_noun(b):lower()
    end)
    return sorted
end

-- Build a snapshot string for change detection
local function pcs_snapshot(pcs)
    local parts = {}
    for _, pc in ipairs(pcs) do
        parts[#parts + 1] = pc.id .. ":" .. (pc.status or "") .. ":" .. (pc.name or "")
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- Process a pending action from the GUI
local function execute_action(action)
    if not action then return end

    if action.type == "cmd" then
        local ok, err = pcall(fput, action.cmd)
        if not ok then echo("Playerwindow action error: " .. tostring(err)) end

    elseif action.type == "spell" then
        -- Prep and cast: PREP <num>; CAST <target>
        local ok1, e1 = pcall(fput, "prep " .. action.num)
        if not ok1 then echo("Playerwindow spell prep error: " .. tostring(e1)); return end
        waitfor("You(?:'re| are) ready to cast", 4)
        local ok2, e2 = pcall(fput, "cast " .. action.target_id)
        if not ok2 then echo("Playerwindow spell cast error: " .. tostring(e2)) end

    elseif action.type == "wand" then
        -- Remove wand from container, wave at target, put back
        local ok1, e1 = pcall(fput, "remove #" .. action.wand_id .. " from #" .. action.container_id)
        if not ok1 then echo("Playerwindow wand error: " .. tostring(e1)); return end
        waitfor("You remove", 3)
        local ok2, e2 = pcall(fput, "wave #" .. action.wand_id .. " at " .. action.target_id)
        if not ok2 then echo("Playerwindow wand wave error: " .. tostring(e2)); return end
        waitfor("(?:tap|wave|gesture|flicker|flare)", 4)
        local ok3, e3 = pcall(fput, "put #" .. action.wand_id .. " in #" .. action.container_id)
        if not ok3 then echo("Playerwindow wand replace error: " .. tostring(e3)) end
    end
end

-- ── Main loop ─────────────────────────────────────────────────────────────────

local last_snapshot   = ""
local last_ui_time    = 0
local last_hook_check = os.time()

while gui.is_open() do
    local pcs      = GameObj.pcs()
    local snapshot = pcs_snapshot(pcs)
    local now      = os.time()

    -- Group display update
    if state.group_dirty then
        state.group_display = display.get_group_display()
        state.group_dirty   = false
    end

    -- Refresh on PC change or heartbeat (every 1 second)
    if snapshot ~= last_snapshot or (now - last_ui_time) > 1 then
        last_snapshot = snapshot
        last_ui_time  = now

        local sorted = sort_pcs(pcs)

        -- Update native GUI
        gui.update(sorted)

        -- Update Wrayth / Stormfront dialog
        display.push_players_to_window(sorted)
    end

    -- Process action queue
    local action = pop_action()
    if action then
        local ok, err = pcall(execute_action, action)
        if not ok then echo("Playerwindow execute error: " .. tostring(err)) end
    end

    -- Periodic hook health check (every 5 seconds)
    if now - last_hook_check > 5 then
        last_hook_check = now
        if not UpstreamHook.exists(upstream_hook_id) then
            UpstreamHook.add(upstream_hook_id, function(command) return command end)
            echo("Playerwindow: upstream hook re-registered.")
        end
        if not DownstreamHook.exists(downstream_hook_id) then
            DownstreamHook.add(downstream_hook_id, function(line)
                local ok2, result = pcall(filter.filter, line)
                if not ok2 then return line end
                return result
            end)
            echo("Playerwindow: downstream hook re-registered.")
        end
    end

    pause(0.1)
end
