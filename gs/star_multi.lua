--- @revenant-script
--- name: star_multi
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: QoL wrapper - type "<number> <command>" to repeat a command N times
--- tags: multi,repeat,utility
---
--- Usage (after ;star_multi is running):
---   3 east          -> moves east 3 times
---   5 forage        -> forages 5 times
---   10 stow my sword -> stows your sword 10 times
---
--- Hooks upstream input. Numbers 1-99 supported.
--- To stop: ;kill star_multi

local HOOK_ID = Script.name .. "_upstream_hook"
local COUNT_CMD_RE = Regex.new("^(?:<c>)?\\s*(\\d{1,2})\\s+(.+)\\s*$")

UpstreamHook.add(HOOK_ID, function(command)
    local ok, count, cmd = pcall(function()
        local m = COUNT_CMD_RE:match(command)
        if m then
            local n = m:match("^(%d+)")
            local c = m:match("^%d+%s+(.+)%s*$")
            return n, c
        end
        return nil, nil
    end)

    if ok and count and cmd then
        cmd = cmd:match("^%s*(.-)%s*$")  -- trim
        Script.run("multi", count .. "," .. cmd)
        return nil
    end
    return command
end)

before_dying(function()
    UpstreamHook.remove(HOOK_ID)
end)

while true do
    pause(1)
end
