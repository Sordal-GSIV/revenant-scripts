--- @revenant-script
--- name: sailors_grief_swim_fix
--- version: 1.0.0
--- author: Tysong
--- game: gs
--- description: Hotpatch mapdb with proper swimming routes for Sailor's Grief
--- tags: map, swimming, navigation
---
--- Patches map routes between Grief, Talon, Seat, and Contempt areas.
--- Run once to add swimming routes to map database.

local TALON_ROOMS = {35620, 35622, 35623, 35624, 35625, 35626, 35627, 35628}

local DIR_MAP = {
    north = "s", south = "n", east = "w", west = "e",
    northeast = "sw", northwest = "se", southeast = "nw", southwest = "ne"
}

local function swim_route(from, to, dirs)
    if Room[from] and Room[from].wayto then
        Room[from].wayto[tostring(to)] = function()
            for _, dir in ipairs(dirs) do
                wait_until(function() return Char.stamina > 15 end)
                waitrt()
                fput(dir)
                pause(5)
            end
        end
        Room[from].timeto[tostring(to)] = function()
            return Skills.swimming >= 101 and 10 or nil
        end
    end
end

-- Grief (35608) -> Talon rooms
for _, talon in ipairs(TALON_ROOMS) do
    swim_route(35608, talon, {"swim water","ne","ne","e","e","e","e","e","swim talon"})
    swim_route(talon, 35608, {"swim water","sw","sw","w","w","w","w","w","swim sailor"})
end

-- Seat (35670) -> Talon rooms
for _, talon in ipairs(TALON_ROOMS) do
    swim_route(35670, talon, {"swim water","se","se","se","se","se","se","se","se","se","se","e","e","e","e","e","e","e","e","e","swim talon"})
    swim_route(talon, 35670, {"swim water","nw","nw","nw","nw","nw","nw","nw","nw","nw","nw","w","w","w","w","w","w","w","w","w","swim seat"})
end

-- Seat (35670) <-> Grief (35608)
swim_route(35670, 35608, {"swim water","se","se","se","se","se","se","se","se","se","se","s","s","e","e","swim sailor"})
swim_route(35608, 35670, {"swim water","nw","nw","nw","nw","nw","nw","nw","nw","nw","nw","n","n","w","w","swim seat"})

echo("Sailor's Grief swimming routes patched successfully.")
