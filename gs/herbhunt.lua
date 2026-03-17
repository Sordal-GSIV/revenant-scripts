--- @revenant-script
--- name: herbhunt
--- version: 1.3.2
--- author: elanthia-online
--- contributors: Tysong, Alastir
--- game: gs
--- description: Play the Ebon Gate Herb Hunt mini-game
--- tags: herb hunt,ebon gate,games
---
--- Usage:
---   ;herbhunt         start herb hunting
---   ;herbhunt help    show setup instructions
---
--- Settings (via ;e):
---   UserVars.herbhunt_pause       = true/false  (pause between runs)
---   UserVars.herbhunt_experience  = false or 90  (wait for XP to drop)
---   UserVars.lootsack            = "giant cloak"

local Messaging = require("lib/messaging")

-- Settings
local settings = {
    pause      = CharSettings["herbhunt.pause"],
    first_run  = CharSettings["herbhunt.first_run"],
    experience = CharSettings["herbhunt.experience"],
}
if settings.pause == nil then settings.pause = true end
if settings.first_run == nil then settings.first_run = true end
if settings.experience == nil then settings.experience = false end

local ITEM_NAMES = {
    "pumpkin%-etched token",
    "glowing orb",
    "potent blue%-green potion",
    "Adventurer's Guild task waiver",
    "sun%-etched gold ring",
    "locker runner contract",
    "larger locker contract",
    "urchin guide contract",
    "flexing arm token",
    "Elanthian Guilds voucher pack",
    "blue feather%-shaped charm",
    "Adventurer's Guild voucher pack",
    "swirling yellow%-green potion",
}

local function known_item(name)
    for _, pat in ipairs(ITEM_NAMES) do
        if name:match(pat) then return true end
    end
    return false
end

local function do_pause()
    respond("########################################")
    respond("#         Pausing herbhunt             #")
    respond("# Please ;unpause herbhunt to continue #")
    respond("########################################")
    pause_script()
end

local function show_help()
    if settings.first_run then
        respond("This is your first time running ;herbhunt.")
        respond("Please verify the settings below.")
        respond("")
    end
    respond("Settings (change via ;e CharSettings[key] = value):")
    respond("  herbhunt.pause       = " .. tostring(settings.pause) .. "  (pause between runs)")
    respond("  herbhunt.experience  = " .. tostring(settings.experience) .. "  (false to disable, or number)")
    respond("  UserVars.lootsack    = your loot container")
    respond("")
    if settings.first_run then
        do_pause()
        settings.first_run = false
        CharSettings["herbhunt.first_run"] = false
    end
end

local function loot()
    waitrt()
    fput("open my herb sack")
    local rh = GameObj.right_hand()
    if not rh then return end
    local result = dothistimeout("look in #" .. rh.id, 5, "In the herb sack|There is nothing in there")
    if result and result:find("In the herb sack") then
        local contents = rh.contents and rh.contents() or {}
        for _, item in ipairs(contents) do
            Messaging.msg("info", "Found " .. item.name)
            fput("get #" .. item.id)
            if not known_item(item.name) then
                echo("Unknown item: " .. item.name .. " — placing in lootsack.")
                echo("Please report to elanthia-online!")
                do_pause()
            end
            local lootsack = CharSettings["lootsack"] or "backpack"
            fput("put #" .. item.id .. " in my " .. lootsack)
        end
        -- Check if sack is empty now
        local lh = GameObj.left_hand()
        rh = GameObj.right_hand()
        if rh and rh.name and rh.name:match("herb sack") then
            fput("toss my herb sack")
        end
        if (rh and rh.id) or (lh and lh.id) then
            echo("Couldn't store item — container may be full!")
            do_pause()
        end
    end
end

local function hunt_ended()
    waitrt()
    -- Check if we're back at the entrance (UID 8086351)
    local room = Map.find_room(Map.current_room())
    if room and room.uid then
        local uids = type(room.uid) == "table" and room.uid or { room.uid }
        for _, u in ipairs(uids) do
            if tonumber(u) == 8086351 then
                -- Check for herb sack in hands
                local rh = GameObj.right_hand()
                local lh = GameObj.left_hand()
                if (rh and rh.name and rh.name:match("herb sack")) or
                   (lh and lh.name and lh.name:match("herb sack")) then
                    loot()
                end
                return true
            end
        end
    end
    return false
end

local function forage()
    waitrt()
    local result = dothistimeout("forage", 5,
        "withered burgundy flowerheads|find no signs of toadshade|find several withered toadshade|Having run out of time")
    if hunt_ended() then return end
    if result and (result:find("find no signs") or result:find("withered burgundy") or result:find("Having run out of time")) then
        move("go path")
        forage()
    elseif result and result:find("find several withered toadshade") then
        search()
    end
end

local function search()
    if hunt_ended() then return end
    local result = dothistimeout("search", 10, "You search the area for herbs|You don't find anything")
    if result and result:find("You search the area for herbs") then
        loot()
    end
end

local function main()
    if settings.first_run then show_help() end

    while true do
        local location = GameState.room_location or ""
        if not location:match("Naidem") and not location:match("Evermore Hollow") then
            echo("This script only works within Naidem/Evermore Hollow (Ebon Gate festival).")
            return
        end

        local result = move("go entry")
        if result then
            forage()
            -- Check for herb sack after run
            local rh = GameObj.right_hand()
            local lh = GameObj.left_hand()
            if (rh and rh.name and rh.name:match("herb sack")) or
               (lh and lh.name and lh.name:match("herb sack")) then
                loot()
            end
        else
            echo("Out of keys/entries or not in the right room!")
            return
        end

        if settings.pause then do_pause() end

        if settings.experience and type(settings.experience) == "number" then
            respond("Waiting for experience to drop below " .. settings.experience .. "%")
            wait_until(function()
                return percentmind() <= settings.experience
            end)
        end
    end
end

-- Main entry
if Script.vars[1] and Script.vars[1]:match("help") then
    show_help()
else
    main()
end
