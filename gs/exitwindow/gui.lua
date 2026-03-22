--- GUI module for exitwindow.
--- Creates and manages the exit display window using Revenant's Gui widget system.
--- Replaces both the Wrayth stormfront dialog XML and the GTK3 window from Lich5.

local M = {}

local win = nil
local single_column = false

function M.create()
    if win then return end

    win = Gui.window("Exit Window", { width = 400, height = 350, resizable = true })
    win:on_close(function() win = nil end)

    -- Set initial empty content
    local root = Gui.vbox()
    root:add(Gui.label("Waiting for room data..."))
    win:set_root(Gui.scroll(root))
    win:show()
end

function M.close()
    if win then
        win:close()
        win = nil
    end
end

function M.is_open()
    return win ~= nil
end

function M.toggle_single_column()
    single_column = not single_column
    respond("Exit Window column layout: " .. (single_column and "Single" or "Double"))
end

--- Format UID for display. Handles string, table, and nil types.
local function format_uid(uid)
    if not uid then return "?" end
    if type(uid) == "table" then
        local parts = {}
        for _, v in ipairs(uid) do
            parts[#parts + 1] = tostring(v)
        end
        return table.concat(parts, ", ")
    end
    return tostring(uid)
end

--- Build a clickable button for a standard exit.
local function make_exit_button(exit_name)
    local cmd = "go " .. exit_name:lower()
    local btn = Gui.button(exit_name)
    btn:on_click(function()
        put(cmd)
    end)
    return btn
end

--- Build a clickable button for a Lich exit.
local function make_lich_exit_button(lich_exit)
    local btn = Gui.button(lich_exit.label)
    btn:on_click(function()
        if lich_exit.cmd:sub(1, 1) == ";" then
            -- Script command (e.g. ";go2 123")
            local script_cmd = lich_exit.cmd:sub(2)
            local script_name, script_args = script_cmd:match("^(%S+)%s*(.*)")
            if script_name then
                Script.run(script_name, script_args ~= "" and script_args or nil)
            end
        else
            put(lich_exit.cmd)
        end
    end)
    return btn
end

--- Lay out buttons in rows (single or double column).
local function layout_buttons(container, buttons)
    if single_column or #buttons <= 1 then
        for _, btn in ipairs(buttons) do
            container:add(btn)
        end
    else
        for i = 1, #buttons, 2 do
            local row = Gui.hbox()
            row:add(buttons[i])
            if buttons[i + 1] then
                row:add(buttons[i + 1])
            end
            container:add(row)
        end
    end
end

--- Update the window with new exit data.
--- @param room table — room table from Map.find_room()
--- @param standard table — array of standard exit names
--- @param lich table — array of {label, cmd, destination} lich exit tables
--- @param trash table — array of trash container name strings
function M.update(room, standard, lich, trash)
    if not win then return end

    local root = Gui.vbox()

    -- Room info header
    local room_id_str = room.id and tostring(room.id) or "?"
    local uid_str = format_uid(room.uid)
    root:add(Gui.section_header("Room Info"))
    root:add(Gui.label("Lid#: " .. room_id_str .. "   Uid#: " .. uid_str))

    -- Standard exits section
    root:add(Gui.separator())
    root:add(Gui.section_header("Exits: " .. #standard))

    if #standard > 0 then
        local exit_buttons = {}
        for _, exit_name in ipairs(standard) do
            exit_buttons[#exit_buttons + 1] = make_exit_button(exit_name)
        end
        layout_buttons(root, exit_buttons)
    end

    -- Lich exits section
    if #lich > 0 then
        root:add(Gui.separator())
        root:add(Gui.section_header("Lich Exits: " .. #lich))

        local lich_buttons = {}
        for _, lich_exit in ipairs(lich) do
            lich_buttons[#lich_buttons + 1] = make_lich_exit_button(lich_exit)
        end
        layout_buttons(root, lich_buttons)
    end

    -- Trash containers section
    if #trash > 0 then
        root:add(Gui.separator())
        root:add(Gui.section_header("Trash: " .. #trash))

        for _, container in ipairs(trash) do
            root:add(Gui.label(container))
        end
    end

    win:set_root(Gui.scroll(root))
end

return M
