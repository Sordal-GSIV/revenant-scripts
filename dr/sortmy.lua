--- @revenant-script
--- name: sortmy
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Restart sorter script and rummage through a container
--- tags: sorting, inventory, alias
---
--- Usage: ;sortmy <container>
--- Tip: alias as ;alias add st=;sortmy

local container = Script.vars[1]
if not container then
    echo("Must enter container name")
    return
end

if Script.running("sorter") then
    stop_script("sorter")
end
start_script("sorter")
pause(1)
DRC.bput("rummage my " .. container, "You rummage", "That would accomplish nothing")
