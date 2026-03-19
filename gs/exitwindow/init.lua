--- @revenant-script
--- name: exitwindow
--- version: 1.1.3
--- author: Phocosoen
--- contributors: ChatGPT
--- game: gs
--- tags: wrayth, frontend, mod, window, paths, navigation, wizard, avalon
--- description: Real-time room exit display window with clickable exits, Lich exits, and trash containers
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Phocosoen, ChatGPT
--- Ported to Revenant Lua from exitwindow.lic v1.1.3
---
--- Changelog (from Lich5):
---   v1.1.3 — Run GTK main asynchronously so startup hooks/loop initialize reliably at logon.
---   v1.1.0 — New GTK Window for Avalon and Wizard FEs.
---   v1.0.0 — Original Wrayth FE Window.
---
--- Features:
---   - Continuously updates with the current room exits.
---   - Displays clickable exits for both standard and Lich exits.
---   - Supports ;go2 navigation for Lich exits.
---   - Displays trash containers.
---   - Displays Lich room ID and room UID.
---
--- Usage:
---   ;exitwindow              - Start exit window
---
--- In-game Commands (while running):
---   *ewgtk                   - Toggle exit window open/closed (Lich5 compat)
---   *ewcol                   - Toggle single/double column layout (Revenant enhancement)

no_kill_all()

local exits = require("exits")
local gui = require("gui")

-- Create the GUI window
gui.create()

-- Hook IDs
local upstream_hook_id = Script.name .. "_upstream"

-- Remove stale hooks
UpstreamHook.remove(upstream_hook_id)

-- Upstream hook: handle in-game toggle commands
UpstreamHook.add(upstream_hook_id, function(command)
    if not command then return command end
    local cmd_lower = command:lower():match("^%s*(.-)%s*$")

    if cmd_lower:find("^%*ewcol") then
        gui.toggle_single_column()
        return nil
    end

    if cmd_lower:find("^%*ewgtk") then
        if gui.is_open() then
            respond("Exit window closed.")
            gui.close()
        else
            respond("Exit window opened.")
            gui.create()
        end
        return nil
    end

    return command
end)

-- Cleanup on exit
before_dying(function()
    UpstreamHook.remove(upstream_hook_id)
    gui.close()
end)

echo("Exitwindow is active.")

-- Main loop: poll for room changes
local last_room_id = nil

while gui.is_open() do
    local current_room_id = Map.current_room()
    if current_room_id and current_room_id ~= last_room_id then
        local room = Map.find_room(current_room_id)
        if room then
            local std = exits.extract_standard(room)
            local lich = exits.extract_lich(room)
            local trash = exits.extract_trash(room)
            gui.update(room, std, lich, trash)
        end
        last_room_id = current_room_id
    end
    pause(0.1)
end
