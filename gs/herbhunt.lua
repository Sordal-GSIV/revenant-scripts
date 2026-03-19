--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: herbhunt
--- version: 1.3.2
--- author: elanthia-online
--- contributors: Tysong, Alastir
--- original: herbhunt.lic v1.3.2
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
---
--- Version Control:
---   Major_change.feature_addition.bugfix
--- v1.3.2 (2025-10-19)
---   - additional corrections
--- v1.3.1 (2025-10-14)
---   - check hands for herb sack if hunt ended early
--- v1.3.0 (2025-10-13)
---   - fix for using redeemed entries, so just go entrance now
--- v1.2.0 (2023-10-03)
---   - fix to continue foraging when no toadshade found
--- v1.1.1 (2023-10-03)
---   - fix to pause if found unknown result incase of something important found
--- v1.1.0 (2023-10-02)
---   - add option to rest till percent experience setting, see help for info!
--- v1.0.0 (2023-10-02)
---   - initial release
---   - fork of mandrake.lic by Alastir with a few minor updates and code cleanup

local Messaging = require("lib/messaging")

-- Settings (mirrors UserVars.herbhunt hash from Lich5)
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
    Script.pause(Script.name)
end

local function at_uid(uid)
    local ids = Map.ids_from_uid(uid)
    local current = Map.current_room()
    if not current then return false end
    for _, id in ipairs(ids) do
        if id == current then return true end
    end
    return false
end

local function show_help()
    if settings.first_run then
        respond("This is your first time running ;herbhunt")
        respond("Please verify the settings below.")
        respond("")
    end
    respond("The script can be paused between runs by changing the herbhunt.pause setting.")
    Messaging.monsterbold("herbhunt.pause is currently set to " .. tostring(settings.pause))
    respond("You can change this by typing the following:")
    respond("  ;e CharSettings[\"herbhunt.pause\"] = " .. tostring(not settings.pause))
    respond("")
    respond("Whether to pause after each arena run to wait for experience to fall below set percent.")
    Messaging.monsterbold("Set to FALSE to disable. Currently set to " .. tostring(settings.experience))
    respond("Example: Set to 100 to hunt once no longer at saturated. (at must rest)")
    respond("Example: Set to  90 to hunt once no longer at must rest. (at numbed)")
    respond("  ;e CharSettings[\"herbhunt.experience\"] = 90")
    respond("")
    respond("Various Container Settings Used Below.")
    local lootsack = UserVars.lootsack or ""
    Messaging.monsterbold("We use UserVars.lootsack to store your winnings. Currently set to \"" .. lootsack .. "\"")
    respond("You can change this by typing the following:")
    respond("  ;e UserVars.lootsack = \"giant cloak\"")
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
    if not rh then
        echo("Didn't find a herb sack in right hand! Report this to elanthia-online!")
        do_pause()
        return
    end
    local result = dothistimeout("look in #" .. rh.id, 5, "In the herb sack", "There is nothing in there%.")
    if result and result:find("In the herb sack") then
        local contents = rh.contents or {}
        for _, item in ipairs(contents) do
            Messaging.msg("info", "Found " .. item.name)
            fput("get #" .. item.id)
            if not known_item(item.name) then
                echo("Unknown " .. item.name .. " found, unsure what to do, placing in " .. (UserVars.lootsack or "backpack") .. "!")
                echo("Please report this to elanthia-online team!")
                do_pause()
            end
            local lootsack = UserVars.lootsack or "backpack"
            fput("put #" .. item.id .. " in my " .. lootsack)
        end
        -- Re-check if sack still has contents
        rh = GameObj.right_hand()
        if rh and rh.contents and #rh.contents > 0 then
            echo("Something still left inside herb sack! Report the contents to elanthia-online!")
            fput("look in my herb sack")
            do_pause()
        else
            if rh and rh.name and rh.name:match("herb sack") then
                fput("toss my herb sack")
            end
        end
        -- Check hands aren't still full
        rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if rh or lh then
            echo("Couldn't store item in hands, likely full container. Empty your stuff!")
            do_pause()
        end
    elseif result and result:find("There is nothing in there") then
        -- Empty sack, just toss it
        fput("toss my herb sack")
    else
        echo("Didn't find a herb sack in right hand! Report this to elanthia-online!")
        do_pause()
    end
end

local function has_herb_sack()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    return (rh and rh.name and rh.name:match("herb sack"))
        or (lh and lh.name and lh.name:match("herb sack"))
end

local function hunt_ended()
    waitrt()
    if at_uid(8086351) then
        if has_herb_sack() then loot() end
        return true
    end
    return false
end

local function search()
    if hunt_ended() then return end
    local result = dothistimeout("search", 10, "You search the area for herbs%.", "You don't find anything of interest here%.")
    if result and result:find("You search the area for herbs") then
        loot()
    end
end

local function forage()
    waitrt()
    local result = dothistimeout("forage", 5,
        "see withered burgundy flowerheads scattered throughout the area%.",
        "find no signs of toadshade in this area",
        "find several withered toadshade leaves in this area",
        "Having run out of time, you quickly search the area")
    if hunt_ended() then return end
    if result and (result:find("find no signs of toadshade") or
                   result:find("see withered burgundy flowerheads") or
                   result:find("Having run out of time")) then
        walk()
        forage()
    elseif result and result:find("find several withered toadshade leaves") then
        search()
    end
end

local function get_mind_value()
    -- Mirror Lich5: saturated = 110 (above any normal threshold)
    if checkmind("saturated") then
        return 110
    end
    return percentmind()
end

local function main()
    if settings.first_run then show_help() end

    while true do
        local room = Room.current()
        local location = (room and room.location) or ""
        if not location:match("Naidem") and not location:match("Evermore Hollow") then
            echo("This script only works within Naidem/Evermore Hollow, accessible during the Ebon Gate festival.")
            return
        end

        -- Navigate to starting room (UID 8086350) if not already there
        if not at_uid(8086350) then
            Map.go2("u8086350")
        end

        local result = move("go entry")
        if result then
            forage()
            if has_herb_sack() then loot() end
        else
            echo("Out of keys/entries or not in the right room!")
            return
        end

        if settings.pause then do_pause() end

        if settings.experience and type(settings.experience) == "number" then
            respond("Waiting until percentmind(" .. get_mind_value() .. ") <= herbhunt.experience(" .. settings.experience .. ").")
            wait_until(function()
                return get_mind_value() <= settings.experience
            end)
        end
    end
end

-- Main entry
if Script.vars[1] and Script.vars[1]:match("[Hh]elp") then
    show_help()
else
    main()
end
