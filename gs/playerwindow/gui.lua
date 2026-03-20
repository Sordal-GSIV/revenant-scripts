-- Player window GUI using Revenant's native Gui widget system.
-- Replaces the GTK3 PlayerWindowGtk class from playerwindow.lic v1.9.0.

local state   = require("state")
local display = require("display")

local M = {}

-- GUI reference
local win = nil

-- Callback: action descriptor table from a player button click
-- { type="cmd"|"spell"|"wand", ... }
M.on_action = nil

-- Callback: called after a filter toggle changes
-- fn(setting_name, new_value)
M.on_setting_change = nil

--- Create the player window.
function M.create()
    if win then return end

    win = Gui.window("Player Window", { width = 380, height = 460, resizable = true })

    -- Populate with an empty root so the window shows immediately
    win:set_root(Gui.scroll(Gui.vbox()))
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

--- Build and push the full window layout to the GUI.
-- pcs: array of GameObj player objects (already sorted by caller)
function M.update(pcs)
    if not win then return end

    local root = Gui.vbox()

    -- === Filter toggles (only when show_filter_buttons is on) ===
    if state.show_filter_buttons then
        local toggle_box = Gui.vbox()

        local function make_toggle(label, field)
            local t = Gui.toggle(label, state[field])
            t:on_change(function(val)
                state[field] = val
                if M.on_setting_change then
                    M.on_setting_change(field, val)
                end
            end)
            return t
        end

        if state.single_column then
            toggle_box:add(make_toggle("Spam Filter",   "filter_spam"))
            toggle_box:add(make_toggle("Flare Filter",  "filter_flares"))
            toggle_box:add(make_toggle("Combat Filter", "filter_combat_math"))
            toggle_box:add(make_toggle("Animal Filter", "filter_animals"))
        else
            -- Two-column toggle layout
            local row1 = Gui.hbox()
            row1:add(make_toggle("Spam Filter",   "filter_spam"))
            row1:add(make_toggle("Flare Filter",  "filter_flares"))
            toggle_box:add(row1)

            local row2 = Gui.hbox()
            row2:add(make_toggle("Combat Filter", "filter_combat_math"))
            row2:add(make_toggle("Animal Filter", "filter_animals"))
            toggle_box:add(row2)
        end

        root:add(toggle_box)
        root:add(Gui.separator())
    end

    -- === Group display ===
    if state.group_display then
        root:add(Gui.label(state.group_display))
    end

    -- === PC count ===
    root:add(Gui.label("PCs: " .. #pcs))

    -- === Player buttons ===
    local players_box = Gui.vbox()

    if state.single_column then
        for _, pc in ipairs(pcs) do
            local noun   = display.extract_noun(pc)
            local status = display.player_status_fix(pc.status)
            local label  = status and (noun .. " (" .. status .. ")") or noun

            local btn = Gui.button(label)
            local action = display.action_for_status_gui(status, pc)
            btn:on_click(function()
                if M.on_action then M.on_action(action) end
            end)
            players_box:add(btn)
        end
    else
        -- Two-column player layout
        for i = 1, #pcs, 2 do
            local row = Gui.hbox()

            local pc1    = pcs[i]
            local noun1  = display.extract_noun(pc1)
            local stat1  = display.player_status_fix(pc1.status)
            local lbl1   = stat1 and (noun1 .. " (" .. stat1 .. ")") or noun1
            local act1   = display.action_for_status_gui(stat1, pc1)
            local btn1   = Gui.button(lbl1)
            btn1:on_click(function()
                if M.on_action then M.on_action(act1) end
            end)
            row:add(btn1)

            if pcs[i + 1] then
                local pc2   = pcs[i + 1]
                local noun2 = display.extract_noun(pc2)
                local stat2 = display.player_status_fix(pc2.status)
                local lbl2  = stat2 and (noun2 .. " (" .. stat2 .. ")") or noun2
                local act2  = display.action_for_status_gui(stat2, pc2)
                local btn2  = Gui.button(lbl2)
                btn2:on_click(function()
                    if M.on_action then M.on_action(act2) end
                end)
                row:add(btn2)
            end

            players_box:add(row)
        end
    end

    root:add(players_box)

    win:set_root(Gui.scroll(root))
end

return M
