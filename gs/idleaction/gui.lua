--- GUI module for idleaction.
--- Creates a setup window with 10 tabs of 10 action entry fields each,
--- plus an idle timer configuration. Replicates the Lich5 GTK notebook layout.

local M = {}

--- Build the label for an action entry (1-indexed)
local function action_label(index)
    return "Action " .. index .. ":"
end

--- Open the setup window and block until it is closed.
--- @param settings table  Current settings table (message_1..message_100, seconds)
--- @return table|nil  Updated settings if window was closed normally, nil if cancelled
function M.open_setup(settings)
    settings = settings or {}

    local win = Gui.window("IdleACTion: v. (1.0.0)", { width = 500, height = 420, resizable = true })

    local root = Gui.vbox()

    -- Timer row at the top
    local timer_box = Gui.hbox()
    timer_box:add(Gui.label("Idle Timer (seconds, default 120):"))
    local timer_input = Gui.input({ text = tostring(settings.seconds or 120), placeholder = "120" })
    timer_box:add(timer_input)
    root:add(timer_box)

    root:add(Gui.separator())

    -- Build tab names: "1" through "10"
    local tab_names = {}
    for i = 1, 10 do
        tab_names[i] = tostring(i)
    end

    local tabs = Gui.tab_bar(tab_names)

    -- Store all input widgets keyed by message_N
    local inputs = {}

    for tab_idx = 1, 10 do
        local page = Gui.vbox()
        local start_num = (tab_idx - 1) * 10 + 1
        local end_num = tab_idx * 10

        for i = start_num, end_num do
            local row = Gui.hbox()
            row:add(Gui.label(action_label(i)))
            local key = "message_" .. i
            local input = Gui.input({
                text = settings[key] or "",
                placeholder = "Enter ACT command...",
            })
            inputs[key] = input
            row:add(input)
            page:add(row)
        end

        tabs:set_tab_content(tab_idx, Gui.scroll(page))
    end

    root:add(tabs)
    win:set_root(root)
    win:show()

    -- Block until window is closed
    Gui.wait(win, "close")

    -- Harvest values from all inputs
    local result = {}
    result.seconds = timer_input:get_text()
    if result.seconds == "" then result.seconds = "120" end

    for key, input in pairs(inputs) do
        local text = input:get_text()
        if text and text ~= "" then
            result[key] = text
        else
            result[key] = ""
        end
    end

    return result
end

return M
