--- @revenant-script
--- name: gateway
--- version: 1.0.0
--- author: Alastir
--- game: gs
--- description: Sybil gateway dispel tool - peer for gateways and dispel them
--- tags: gateway,sybil,dispel
---
--- Peers in all directions looking for a gold-haloed stygian gateway,
--- moves to it, and casts a dispel spell (119, 417, or 1218).

local function check_gateway()
    local loot = GameObj.loot()
    local found = false
    for _, obj in ipairs(loot) do
        if obj.name and obj.name:find("gateway") then
            found = true
            break
        end
    end

    if not found then
        echo("No gateway found!")
        return
    end

    if Spell[119] and Spell[119].known and Spell[119]:affordable() then
        fput("prepare 119")
        fput("cast gateway")
    elseif Spell[417] and Spell[417].known and Spell[417]:affordable() then
        fput("prepare 417")
        fput("cast gateway")
    elseif Spell[1218] and Spell[1218].known and Spell[1218]:affordable() then
        fput("prepare 1218")
        fput("cast gateway")
    else
        echo("No suitable dispel spell known or affordable!")
    end
end

local function peercheck()
    local directions = {
        "north", "south", "northeast", "southwest",
        "east", "west", "southeast", "northwest",
        "south", "north", "southwest", "northeast",
        "west", "east", "northwest", "southeast",
    }

    for _, direction in ipairs(directions) do
        local result = dothistimeout("peer " .. direction, 5,
            { "a gold%-haloed stygian gateway", "Obvious paths", "Obvious exits" })
        if result and result:find("gold%-haloed stygian gateway") then
            move(direction)
            check_gateway()
            local home_ids = Map.ids_from_uid(7503501)
            if home_ids and home_ids[1] then
                Script.run("go2", tostring(home_ids[1]))
                wait_while(function() return running("go2") end)
            end
            return
        end
        pause(0.1)
    end
end

peercheck()
