--- @revenant-script
--- name: roomwindow_mod_nodesc
--- version: 1.0.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Filter room descriptions from the Room window, optionally show wayto info
--- tags: filter, room, window, description, wayto
---
--- Usage:
---   ;roomwindow_mod_nodesc       - start filtering room descriptions
---   Use ;e toggle_waytos() to enable/disable wayto display in the Room window

local show_waytos = false

-- Expose toggle function globally
function toggle_waytos()
    show_waytos = not show_waytos
    echo("Room wayto info is now " .. (show_waytos and "enabled" or "disabled") .. ".")
end

local HOOK_ID = "filter_room_desc_only"

DownstreamHook.add(HOOK_ID, function(data)
    -- Remove room description content
    local new_data = data:gsub("<compDef id='room desc'>.-</compDef>", "<compDef id='room desc'></compDef>")

    -- If wayto output is enabled and this is a room update, push wayto info
    if show_waytos and new_data:find("<streamWindow id='room'") then
        -- Brief delay for Room.current to update
        pause(0.001)
        local room = Room.current()
        if room and room.wayto then
            local parts = {}
            for num, cmd in pairs(room.wayto) do
                table.insert(parts, tostring(num) .. " -> " .. tostring(cmd))
            end
            local formatted = table.concat(parts, "\n")
            if formatted ~= "" then
                stream_window(formatted, "room")
            end
        end
    end

    return new_data
end)

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
end)

echo("Room description filter active: Room descriptions are removed, and room wayto info is " .. (show_waytos and "enabled" or "disabled") .. ".")

while true do
    pause(1)
end
