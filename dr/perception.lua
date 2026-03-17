--- @revenant-script
--- name: perception
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Check perception XP and hunt if not locked (for use with levelup)
--- tags: perception, hunting, training
---
--- Usage: ;perception <parent_script>

local parent = Script.vars[1]
if not parent then
    echo("Usage: ;perception <parent_script_name>")
    return
end

pause_script(parent)
fput("exp perc")

local line = waitfor("34/34", "33/34", "32/34", "EXP HELP")
if line:match("34/34") or line:match("33/34") or line:match("32/34") then
    unpause_script(parent)
    return
end

-- Not locked, go hunt
fput("hunt")
pause(8)
unpause_script(parent)
pause(80)
