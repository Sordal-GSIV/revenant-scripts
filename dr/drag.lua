--- @revenant-script
--- name: drag
--- version: 0.9
--- author: Jydus
--- game: dr
--- description: Convert movement commands to drag commands.
--- tags: movement, drag, utility
--- Usage: ;drag <person|object>

local drag_obj = Script.vars[1]
if not drag_obj then
    respond("You need to set an object or person to drag.")
    return
end

UpstreamHook.add("drag_hook", function(cmd)
    local dir = cmd:match("^(north|south|east|west|northeast|northwest|southeast|southwest|up|down|out|n|ne|e|se|s|sw|w|nw)$")
    if dir then
        put("drag " .. drag_obj .. " " .. dir)
        return nil
    end
    local go_cmd = cmd:match("^(go|climb|swim)%s+(.+)$")
    if go_cmd then
        put("drag " .. drag_obj .. " " .. cmd)
        return nil
    end
    return cmd
end)

before_dying(function()
    UpstreamHook.remove("drag_hook")
end)

while true do
    pause(10)
    echo("Auto-dragging " .. drag_obj)
end
