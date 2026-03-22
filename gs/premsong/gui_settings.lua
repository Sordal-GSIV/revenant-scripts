local settings = require("settings")

local M = {}

function M.open(state)
    local win = Gui.window("PremSong Settings", { width = 460, height = 540 })
    local root = Gui.vbox()

    -- Tone section
    root:add(Gui.section_header("Song Tone"))

    local tone_bar = Gui.hbox()
    tone_bar:add(Gui.label("Tone (blank = no tone):"))
    local tone_input = Gui.input({ text = state.tone or "" })
    tone_bar:add(tone_input)
    root:add(tone_bar)

    local reset_chk = Gui.checkbox("Reset tone to 'none' after singing", state.reset_tone)
    root:add(reset_chk)

    root:add(Gui.separator())

    -- Delay section
    root:add(Gui.section_header("Timing"))
    local delay_bar = Gui.hbox()
    delay_bar:add(Gui.label("Delay between commands (seconds):"))
    local delay_input = Gui.input({ text = tostring(state.delay or 0.5) })
    delay_bar:add(delay_input)
    root:add(delay_bar)

    root:add(Gui.separator())

    -- Lyrics section
    root:add(Gui.section_header("Lyrics Lines"))
    root:add(Gui.label("One line per entry. Lines are joined with ';' when sung."))

    -- Lyrics list display
    local lyrics_box = Gui.vbox()
    local line_inputs = {}

    local function rebuild_lyrics_ui()
        lyrics_box:clear()
        line_inputs = {}
        for i, line in ipairs(state.lyrics) do
            local row = Gui.hbox()
            local inp = Gui.input({ text = line })
            line_inputs[i] = inp
            row:add(Gui.label(string.format("%2d.", i)))
            row:add(inp)
            local del_btn = Gui.button("X")
            local idx = i
            del_btn:on_click(function()
                -- flush current text before removing
                for j, li in ipairs(line_inputs) do
                    state.lyrics[j] = li:get_text() or ""
                end
                table.remove(state.lyrics, idx)
                rebuild_lyrics_ui()
            end)
            row:add(del_btn)
            lyrics_box:add(row)
        end
    end

    rebuild_lyrics_ui()
    root:add(Gui.scroll(lyrics_box, { height = 200 }))

    local add_row = Gui.hbox()
    local new_line_input = Gui.input({ text = "", placeholder = "New lyric line..." })
    add_row:add(new_line_input)
    local add_btn = Gui.button("Add Line")
    add_btn:on_click(function()
        -- flush existing inputs first
        for j, li in ipairs(line_inputs) do
            state.lyrics[j] = li:get_text() or ""
        end
        local txt = new_line_input:get_text() or ""
        if txt ~= "" then
            table.insert(state.lyrics, txt)
            new_line_input:set_text("")
            rebuild_lyrics_ui()
        end
    end)
    add_row:add(add_btn)
    root:add(add_row)

    root:add(Gui.separator())

    -- Save button
    local save_btn = Gui.button("Save & Close")
    root:add(save_btn)

    win:set_root(Gui.scroll(root))

    -- Callbacks
    reset_chk:on_change(function(v) state.reset_tone = v end)

    save_btn:on_click(function()
        state.tone       = tone_input:get_text() or ""
        state.delay      = tonumber(delay_input:get_text()) or 0.5
        state.reset_tone = reset_chk:get_value()
        -- flush lyric inputs
        for j, li in ipairs(line_inputs) do
            state.lyrics[j] = li:get_text() or ""
        end
        -- strip blank lines
        local cleaned = {}
        for _, l in ipairs(state.lyrics) do
            if l ~= "" then table.insert(cleaned, l) end
        end
        state.lyrics = cleaned
        settings.save(state)
        respond("[premsong] Settings saved")
        win:close()
    end)

    win:show()
    Gui.wait(win, "close")
end

return M
