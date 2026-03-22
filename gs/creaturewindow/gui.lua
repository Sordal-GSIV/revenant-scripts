--- CreatureWindow GUI using Revenant's native Gui widget system.

local state = require("state")
local status_mod = require("status")
local metrics = require("metrics")
local bounty_display = require("bounty_display")

local M = {}

-- GUI references
local win = nil
local root = nil
local metrics_box = nil
local bounty_box = nil
local target_box = nil
local creatures_box = nil
local dead_box = nil
local count_label = nil

-- Callback for workflow commands
M.on_workflow_cmd = nil
-- Callback for target commands
M.on_target_cmd = nil

--- Create the main creature window.
function M.create()
    if win then return end

    win = Gui.window("Creature Window", { width = 420, height = 370, resizable = true })

    root = Gui.vbox()

    -- Metrics section
    metrics_box = Gui.vbox()
    root:add(metrics_box)

    -- Bounty section
    bounty_box = Gui.vbox()
    root:add(bounty_box)

    -- Separator
    root:add(Gui.separator())

    -- Creature count
    count_label = Gui.label("Creatures: 0")
    root:add(count_label)

    -- Current target section
    target_box = Gui.vbox()
    root:add(target_box)

    -- Other creatures
    creatures_box = Gui.vbox()
    root:add(creatures_box)

    -- Separator before dead
    root:add(Gui.separator())

    -- Dead creatures
    dead_box = Gui.vbox()
    root:add(dead_box)

    win:set_root(Gui.scroll(root))
    win:show()

    win:on_close(function()
        win = nil
    end)
end

--- Check if the window is open.
function M.is_open()
    return win ~= nil
end

--- Close the window.
function M.close()
    if win then
        win:close()
        win = nil
    end
end

--- Build a creature label string with status.
local function creature_label(creature)
    local st = status_mod.creature_status_fix(creature.status, creature.name, creature.id)
    if st then
        return creature.noun .. " (" .. st .. ")"
    end
    return creature.noun or ""
end

--- Update the entire window display.
function M.update(targets)
    if not win then return end

    -- Clear dynamic sections
    -- We rebuild all widgets each update for simplicity (Gui handles this efficiently)

    -- === Metrics ===
    metrics_box = Gui.vbox()

    if state.display_avg_ttk then
        metrics_box:add(Gui.label("Avg TTK: " .. metrics.avg_ttk()))
    end
    if state.display_last_ttk then
        local txt = "Last TTK: " .. metrics.last_ttk()
        if metrics.last_kill() then
            txt = txt .. " (" .. metrics.last_kill() .. ")"
        end
        metrics_box:add(Gui.label(txt))
    end
    if state.display_kpm then
        metrics_box:add(Gui.label("Kills/Min: " .. metrics.kpm()))
    end

    -- === Bounty ===
    bounty_box = Gui.vbox()

    if state.display_bounty then
        bounty_box:add(Gui.label(bounty_display.task_line()))
        local sl = bounty_display.status_line()
        if sl ~= "" then
            bounty_box:add(Gui.label(sl))
        end

        local action = bounty_display.action_line()
        if action then
            local btn = Gui.button(action)
            btn:on_click(function()
                local cmd = bounty_display.action_cmd()
                if cmd and M.on_workflow_cmd then
                    M.on_workflow_cmd(cmd)
                end
            end)
            bounty_box:add(btn)
        end
    end

    -- === Creature count ===
    count_label = Gui.label("Creatures: " .. #targets)

    -- === Current target ===
    target_box = Gui.vbox()
    local current_target = GameObj.target()
    if current_target then
        local lbl = Gui.label(">> " .. creature_label(current_target) .. " <<")
        target_box:add(lbl)
    end

    -- === Other living creatures ===
    creatures_box = Gui.vbox()

    -- Build two-column layout using hbox pairs
    local other_creatures = {}
    for _, t in ipairs(targets) do
        if not current_target or t.id ~= current_target.id then
            other_creatures[#other_creatures + 1] = t
        end
    end

    if state.single_column then
        for _, creature in ipairs(other_creatures) do
            local btn = Gui.button(creature_label(creature))
            btn:on_click(function()
                if M.on_target_cmd then
                    M.on_target_cmd("target #" .. creature.id)
                end
            end)
            creatures_box:add(btn)
        end
    else
        -- Two-column layout
        for i = 1, #other_creatures, 2 do
            local row = Gui.hbox()
            local c1 = other_creatures[i]
            local btn1 = Gui.button(creature_label(c1))
            btn1:on_click(function()
                if M.on_target_cmd then
                    M.on_target_cmd("target #" .. c1.id)
                end
            end)
            row:add(btn1)

            if other_creatures[i + 1] then
                local c2 = other_creatures[i + 1]
                local btn2 = Gui.button(creature_label(c2))
                btn2:on_click(function()
                    if M.on_target_cmd then
                        M.on_target_cmd("target #" .. c2.id)
                    end
                end)
                row:add(btn2)
            end
            creatures_box:add(row)
        end
    end

    -- === Dead creatures ===
    dead_box = Gui.vbox()
    local dead = GameObj.dead()

    dead_box:add(Gui.label("Dead Creatures: " .. #dead))

    if state.single_column then
        for _, d in ipairs(dead) do
            local btn = Gui.button(d.noun or "")
            btn:on_click(function()
                if M.on_target_cmd then
                    M.on_target_cmd("loot #" .. d.id)
                end
            end)
            dead_box:add(btn)
        end
    else
        for i = 1, #dead, 2 do
            local row = Gui.hbox()
            local d1 = dead[i]
            local btn1 = Gui.button(d1.noun or "")
            btn1:on_click(function()
                if M.on_target_cmd then
                    M.on_target_cmd("loot #" .. d1.id)
                end
            end)
            row:add(btn1)

            if dead[i + 1] then
                local d2 = dead[i + 1]
                local btn2 = Gui.button(d2.noun or "")
                btn2:on_click(function()
                    if M.on_target_cmd then
                        M.on_target_cmd("loot #" .. d2.id)
                    end
                end)
                row:add(btn2)
            end
            dead_box:add(row)
        end
    end

    -- === Rebuild root ===
    root = Gui.vbox()
    root:add(metrics_box)
    root:add(bounty_box)
    root:add(Gui.separator())
    root:add(count_label)
    root:add(target_box)
    root:add(creatures_box)
    root:add(Gui.separator())
    root:add(dead_box)

    win:set_root(Gui.scroll(root))
end

--- Wait for window close (blocks).
function M.wait_close()
    if win then
        Gui.wait(win, "close")
    end
end

return M
