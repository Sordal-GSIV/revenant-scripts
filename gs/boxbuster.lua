--- @revenant-script
--- name: boxbuster
--- version: 0.4.1
--- author: nishima
--- game: gs
--- tags: locksmith, boxes, automation
--- description: Manage boxes at locksmith pools - get, give, list operations
---
--- Original Lich5 authors: nishima
--- Ported to Revenant Lua from boxbuster.lic v0.4.1
---
--- Usage:
---   ;boxbuster get           - get one box
---   ;boxbuster get all       - get all boxes
---   ;boxbuster give          - give box in right hand
---   ;boxbuster give all      - give all boxes
---   ;boxbuster list          - look at boxes in queue
---   ;boxbuster tip <amount>  - set tip amount

local tip = UserVars.get("boxbuster_tip") or "500"

local function bold(msg)
    put('<output class="mono"/>\n\n<pushBold/>' .. msg .. '<popBold/>\n\n<output class=""/>')
end

if not UserVars.get("boxbuster_tip") then
    UserVars.set("boxbuster_tip", "500")
    respond("First time setup.")
    bold("Default tip set to 500 silver.")
    return
end

local user_command = Script.current.vars[0] or ""
local count = 0

before_dying(function()
    if count > 0 then bold("Boxes Busted: " .. count) end
end)

local container = UserVars.get("container")
if not container then
    respond("You must first set your containers:")
    respond(";vars set container=MAIN")
    return
end

-- Check for tip command
local new_tip = user_command:match("tip (.+)")
if new_tip then
    UserVars.set("boxbuster_tip", new_tip)
    bold("Tip set to " .. new_tip)
    return
end

-- Pool NPC and garbage bin by room
local POOL_ROOMS = {
    [2400]  = { npc = "trickster",  bin = "barrel" },
    [17589] = { npc = "attendant",  bin = "barrel" },
    [3807]  = { npc = "worker",     bin = "wastebasket" },
    [18687] = { npc = "gnome",      bin = "barrel" },
    [28717] = { npc = "woman",      bin = "wooden crate" },
    [28719] = { npc = "jahck",      bin = "barrel" },
    [28718] = { npc = "woman",      bin = "canister" },
    [5751]  = { npc = "dwarf",      bin = "barrel" },
}

local room_info = POOL_ROOMS[Room.current.id]
if not room_info then
    respond("Not at known locksmith pool.")
    return
end

local pool_npc = room_info.npc
local garbage_bin = room_info.bin
tip = UserVars.get("boxbuster_tip")

local function get_box()
    fput("ask " .. pool_npc .. " to return")
    local line = matchtimeout(1, "Alright, here's your")
    if not line or not line:find("Alright") then
        respond("No boxes left or wrong place.")
        return false
    end
    count = count + 1
    local material, box_type = line:match("Alright, here's your (%w+) (%w+) back")
    if not material then return false end
    local my_box = material .. " " .. box_type

    fput("open my " .. my_box)
    fput("get coins")
    fput("look in my " .. my_box)
    waitrt()
    wait(0.5)
    fput("empty my " .. my_box .. " into my " .. container)

    local result = waitfor("You try to empty|There is nothing|is closed")
    if result and (result:find("falls in quite nicely") or result:find("nothing comes out") or result:find("There is nothing")) then
        waitrt()
        fput("glance my " .. my_box)
        local glance = waitfor("You glance at")
        if glance and Regex.test(glance, "mithril|gold|silver") then
            wait(0.3)
            fput("stow my " .. my_box)
        else
            wait(0.3)
            fput("put my " .. my_box .. " in " .. garbage_bin)
        end
    else
        echo("You might be full or check the box...")
        return false
    end
    return true
end

local function give_box()
    if not checkright() then
        respond("No box in right hand to offer.")
        return
    end
    fput("give " .. pool_npc .. " " .. tip)
    fput("give " .. pool_npc .. " " .. tip)
    count = count + 1
end

if user_command == "get" then
    get_box()
elseif user_command == "get all" then
    while true do
        if not get_box() then break end
        waitfor("As you place|You put|As you toss")
    end
elseif user_command == "give" then
    give_box()
elseif user_command == "give all" then
    local boxlist = { "box", "coffer", "chest", "trunk", "strongbox" }
    local function is_box(noun)
        for _, b in ipairs(boxlist) do if noun == b then return true end end
        return false
    end
    if checkright() and is_box(checkright()) then give_box() end
    if checkleft() and is_box(checkleft()) then fput("swap"); give_box() end
    -- Check containers for boxes
    echo("Check your containers for remaining boxes to give.")
elseif user_command == "list" then
    fput("ask " .. pool_npc .. " for list")
else
    respond("USAGE:")
    respond(";boxbuster get / get all / give / give all / list")
    respond(";boxbuster tip <amount>")
    bold("Tip is currently set to " .. tip)
end
