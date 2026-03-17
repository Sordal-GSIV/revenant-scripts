--- @revenant-script
--- name: under
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Set up gondola navigation overrides using uncoiled rope
--- tags: navigation, map, climbing, gondola
---
--- Requires 460+ Athletics. Similar to gondola.lua but uses uncoil/coil rope commands.

pause(10)

-- Room 19459 -> 2245 via rope climb (uncoil variant)
Room[19459].wayto["2245"] = function()
    fput("get my heavy rope")
    fput("uncoil my rope")
    pause(1)
    waitrt()
    move("climb branch with my rope")
    pause(1)
    waitrt()
    fput("coil my rope")
    fput("stow my rope")
end
Room[19459].wayto["19461"] = "climb niche with my rope"

-- Room 2245
Room[2245].wayto["2244"] = "northeast"
Room[2245].wayto["2246"] = "south"
Room[2245].wayto["19459"] = function()
    fput("get my heavy rope")
    fput("uncoil my rope")
    pause(1)
    waitrt()
    move("climb branch with my rope")
    pause(1)
    waitrt()
end

-- Room 19461
Room[19461].wayto["19459"] = "climb niche with my rope"
Room[19461].wayto["19472"] = "climb ledge with my rope"

-- Room 19472
Room[19472].wayto["19461"] = "climb ledge with my rope"
Room[19472].wayto["19460"] = function()
    fput("get my heavy rope")
    fput("uncoil my rope")
    pause(1)
    waitrt()
    move("climb wall with my rope")
    pause(1)
    waitrt()
    fput("coil my rope")
    fput("stow my rope")
end

-- Room 19460
Room[19460].wayto["19472"] = function()
    fput("get my heavy rope")
    fput("uncoil my rope")
    pause(1)
    waitrt()
    move("climb wall with my rope")
    pause(1)
    waitrt()
end
Room[19460].wayto["9597"] = "down"
Room[19460].wayto["19462"] = "up"

-- Timeto overrides (require 460+ Athletics)
Room[19459].timeto["2245"] = function()
    if UserVars.athletics and UserVars.athletics >= 460 then
        return 0.2
    end
    return nil
end
Room[19459].timeto["19461"] = 0.2

Room[2245].timeto["2244"] = 0.2
Room[2245].timeto["19459"] = function()
    if UserVars.athletics and UserVars.athletics >= 460 then
        return 0.2
    end
    return nil
end

echo("Under navigation overrides installed (requires 460+ Athletics).")
