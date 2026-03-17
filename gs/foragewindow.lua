--- @revenant-script
--- name: foragewindow
--- version: 1.0.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Dedicated window displaying forageable items in the current room
--- tags: wrayth, frontend, mod, window, forage, herbs, ingredients

hide_me()
no_kill_all()
setpriority(-1)

put("<closeDialog id='ForageWindow'/><openDialog type='dynamic' id='ForageWindow' title='Forageables' target='ForageWindow' scroll='auto' location='main' justify='3' height='300' resident='true'><dialogData id='ForageWindow'></dialogData></openDialog>")

local WINDOW_ID = "ForageWindow"

local function render_forage_window()
    local room = Room.current()
    local tags = (room and room.tags) or {}

    local forageables = {}
    local no_forage = false
    for _, t in ipairs(tags) do
        if t == "no forageables" then
            no_forage = true
            break
        end
    end

    if not no_forage then
        local seen = {}
        for _, t in ipairs(tags) do
            if t:match("^[%a%-%s']+$") and not t:find("meta:") and t ~= "no forageables" then
                local lower = t:lower()
                if not seen[lower] then
                    seen[lower] = true
                    table.insert(forageables, t)
                end
            end
        end
        table.sort(forageables)
    end

    local output = "<dialogData id='" .. WINDOW_ID .. "' clear='t'>"
    local top = 0

    output = output .. "<label id='header1' value='Click on item to forage.' justify='left' left='0' top='" .. top .. "' />"
    top = top + 20

    if #forageables == 0 then
        output = output .. "<label id='none' value='No forageables detected.' justify='left' left='0' top='" .. top .. "' />"
    else
        for i, item in ipairs(forageables) do
            output = output .. "<link id='item_" .. (i - 1) .. "' value='" .. item .. "' cmd=';e empty_hands(); fput(\"forage " .. item .. "\")' echo='foraging " .. item .. "' justify='left' left='0' top='" .. top .. "' />"
            top = top + 20
        end
    end

    output = output .. "</dialogData>"
    put(output)
end

-- Initial render
render_forage_window()

-- Update on room change
local last_room = Room.current() and Room.current().id
while true do
    local current = Room.current()
    local current_id = current and current.id
    if current_id ~= last_room then
        last_room = current_id
        render_forage_window()
    end
    pause(0.2)
end
