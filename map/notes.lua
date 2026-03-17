-- notes.lua
local M = {}

local notes_path = nil

function M.init(game)
    notes_path = "data/" .. game .. "/map_notes.json"
end

function M.load()
    if not notes_path then return {} end
    if not File.exists(notes_path) then return {} end
    local content, err = File.read(notes_path)
    if not content then return {} end
    local ok, data = pcall(Json.decode, content)
    if ok and data then return data end
    return {}
end

function M.save(notes)
    if not notes_path then return end
    if not File.exists("data") then File.mkdir("data") end
    local game_dir = notes_path:match("^(data/[^/]+)/")
    if game_dir and not File.exists(game_dir) then File.mkdir(game_dir) end
    File.write(notes_path, Json.encode(notes))
end

function M.get(notes, room_id)
    return notes[tostring(room_id)]
end

function M.set(notes, room_id, text)
    if text and text ~= "" then
        notes[tostring(room_id)] = text
    else
        notes[tostring(room_id)] = nil
    end
end

function M.open_editor(room_id, notes, on_save)
    local note_win = Gui.window("Note — Room " .. room_id, { width = 350, height = 250 })
    local vbox = Gui.vbox()
    local room_label = Gui.label("Room " .. room_id)
    vbox:add(room_label)
    local note_input = Gui.input({
        placeholder = "Enter note...",
        text = notes[tostring(room_id)] or "",
    })
    vbox:add(note_input)
    local btn_box = Gui.hbox()
    local save_btn = Gui.button("Save")
    btn_box:add(save_btn)
    local delete_btn = Gui.button("Delete")
    btn_box:add(delete_btn)
    local cancel_btn = Gui.button("Cancel")
    btn_box:add(cancel_btn)
    vbox:add(btn_box)
    note_win:set_root(vbox)

    save_btn:on_click(function()
        local text = note_input:get_text()
        M.set(notes, room_id, text)
        M.save(notes)
        if on_save then on_save() end
        note_win:close()
    end)

    delete_btn:on_click(function()
        M.set(notes, room_id, nil)
        M.save(notes)
        if on_save then on_save() end
        note_win:close()
    end)

    cancel_btn:on_click(function()
        note_win:close()
    end)

    note_win:show()
end

return M
