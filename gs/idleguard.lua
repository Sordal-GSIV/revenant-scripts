--- @revenant-script
--- name: idleguard
--- version: 1.0.0
--- author: Witfog
--- game: gs
--- description: Keeps session alive by issuing periodic TIME commands with suppressed output
--- tags: disconnect, protect, idle, keepalive, timeout
---
--- Usage:
---   ;idleguard
---
--- Tip: ;autostart add idleguard

toggle_unique()
hide_me()
silence_me()
setpriority(-2)

local HOOK_NAME = Script.name .. "_idleguard"
local guard_active = false

DownstreamHook.add(HOOK_NAME, function(server_string)
    if guard_active then
        if server_string and server_string:find("^Today is ") then
            guard_active = false
            return nil  -- suppress the TIME response
        else
            return server_string
        end
    else
        return server_string
    end
end)

local function guard_me()
    guard_active = true
    fput("time")
    pause(3)
end

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    echo(Script.name .. "'s watch has ended.")
end)

echo(Script.name .. " is guarding your idles!")

while true do
    guard_me()
    pause(295)
end
