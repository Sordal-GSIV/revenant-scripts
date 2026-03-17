--- @revenant-script
--- name: titlecheck
--- version: 1.0
--- author: Crannach
--- game: dr
--- description: Check for new titles in a category since last check.
--- tags: titles, tracking, utility
--- Usage: ;titlecheck <title_set>

local title_set = Script.vars[1]
if not title_set then echo("Usage: ;titlecheck <title_set>") return end

UserVars.titles = UserVars.titles or {}
local result = DRC.bput("title pre list " .. title_set,
    "The following", "There are no titles", "I could not find")
if not result or result:find("no titles") or result:find("could not find") then
    respond("No titles available in that category.") return
end

respond("-------------------")
respond("Title Check: " .. title_set)
respond("-------------------")
echo("Check the game window for title listings.")
respond("-------------------")
