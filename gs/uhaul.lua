--- @revenant-script
--- name: uhaul
--- version: 2.0.2
--- author: Ondreian
--- contributors: Xanlin
--- game: gs
--- description: Automated locker moving between towns
--- tags: lockers,movers,move,utility
---
--- Usage:
---   ;uhaul <from> <to> [speed]
---   ;uhaul landing teras immediate
---   ;uhaul help
---
--- Speed options: immediate (default, premium), express, standard

local SPEEDS = {
    immediate = 5000,
    express   = 10000,
    standard  = 1000,
}

local ROOMS = {
    landing     = "u72032",
    icemule     = "u4043357",
    fwi         = "u3204302",
    teras       = "u3001048",
    vaalor      = "u14103425",
    illistim    = "u13103100",
    solhaven    = "u2120207",
    riversrest  = "u5001202",
    krakensfall = "u7121028",
}

local LOOKUP = {
    ["wehnimer's landing"] = "landing|wehn|wl",
    ["solhaven"]           = "sol",
    ["teras"]              = "ter",
    ["ta'vaalor"]          = "vaalor",
    ["four winds"]         = "mist|fwi|four|ifw",
    ["ta'illistim"]        = "illi",
    ["river's rest"]       = "rr|rest|river",
    ["icemule"]            = "mule|imt",
    ["zul logoth"]         = "zul|logoth",
    ["cysaegir"]           = "cysaegir|cys",
    ["kraken's fall"]      = "kraken|fall|kf",
}

local function lookup_town(arg)
    if not arg then return arg end
    arg = arg:lower()
    for name, pattern in pairs(LOOKUP) do
        for alt in pattern:gmatch("[^|]+") do
            if arg:match("^" .. alt) then return name end
        end
    end
    return arg
end

local function find_closest_mover()
    local room_ids = {}
    for _, uid in pairs(ROOMS) do
        local ids = Map.ids_from_uid(tonumber(uid:match("(%d+)")))
        if ids and ids[1] then
            room_ids[#room_ids + 1] = ids[1]
        end
    end
    local cur = Map.current_room()
    if not cur then return nil end
    return Map.find_nearest(cur, room_ids)
end

local function check_wealth()
    local result = dothistimeout("wealth quiet", 3, "You have")
    if not result then return 0 end
    local coins_str = result:match("(%d[%d,]*) silver")
    if not coins_str then
        if result:match("but one silver") then return 1 end
        return 0
    end
    return tonumber(coins_str:gsub(",", "")) or 0
end

local function show_help()
    respond("")
    respond("  ;uhaul <from> <to> [speed=immediate]")
    respond("  ;uhaul help")
    respond("")
    respond("  Speeds: immediate, express, standard")
    respond("")
end

local function do_error(msg)
    respond("")
    respond("  ERROR: " .. msg)
    respond("")
    show_help()
end

local function swap(from, to, speed)
    speed = speed or "immediate"
    local cost = SPEEDS[speed:lower()]
    if not cost then
        do_error("unrecognized speed: " .. speed .. " (valid: immediate, express, standard)")
        return
    end

    local starting_room = Map.current_room()

    if GameState.hidden then fput("unhide") end

    -- Check if we need to visit the bank
    local coins = check_wealth()
    if coins < cost then
        Script.run("go2", "bank")
        fput("withdraw " .. (cost - coins))
    end

    local mover = find_closest_mover()
    if not mover then
        do_error("could not find a mover room")
        return
    end

    Script.run("go2", tostring(mover))
    sleep(0.2)

    if Map.current_room() == mover then
        -- Find the clerk NPC
        local npcs = GameObj.npcs()
        local clerk_id = nil
        if npcs then
            for _, npc in ipairs(npcs) do
                if npc.name:match("clerk") then
                    clerk_id = npc.id
                    break
                end
            end
        end
        if clerk_id then
            fput("ask #" .. clerk_id .. " for move")
        else
            fput("ask clerk for move")
        end
        fput("say yes")
        fput("say " .. from)
        fput("say " .. to)
        fput("say " .. speed)
    end

    if starting_room and starting_room ~= Map.current_room() then
        Script.run("go2", tostring(starting_room))
    end
end

-- Main
local raw_args = {}
for i = 1, 10 do
    if Script.vars[i] and Script.vars[i] ~= "" then
        raw_args[#raw_args + 1] = Script.vars[i]:lower()
    end
end

if #raw_args == 0 or raw_args[1] == "help" then
    show_help()
    return
end

if #raw_args > 3 then
    do_error("at most 3 arguments are allowed")
    return
end

if #raw_args < 2 then
    do_error("<from> and <to> are required options")
    return
end

local from = lookup_town(raw_args[1])
local to = lookup_town(raw_args[2])
local speed = raw_args[3] and lookup_town(raw_args[3]) or "immediate"

swap(from, to, speed)
