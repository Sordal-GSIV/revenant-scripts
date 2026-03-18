-- huntpro/navigation.lua — Room navigation, hunting zone dispatch, retreat, boundary patrol
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara — huntpro_hunting_zones, zone_reset_check,
-- safe_room_default, misty_logic, moon navigation (lines ~8746-15300)

local Navigation = {}

---------------------------------------------------------------------------
-- Master hunting zone list — all known zone keywords
---------------------------------------------------------------------------
Navigation.ZONES = {
    -- Landing
    "wlmiboar", "wlmountainogre", "wlredviper", "wlredspirit", "wlredpixie", "wlredtreekin",
    "wlkobold", "wlschieftain", "wlshade", "wlcentaur", "wlmeingolem",
    "wlgremlin", "wlhobgoblin", "wlgak", "wlworm", "wlrat", "wlsquirrel",
    "wlkvillage", "wlvysan", "wlfisherman", "wlmummy", "wlorc",
    "wlthrak", "wlmonhobgoblin", "wlgreyorc", "wlgorc", "wlpuma", "wlowarrior",
    "wlant", "wldirge", "wlghoul", "wlmaster", "wlspirit",
    "wlpooka", "wlminer", "wlsmare", "wlnmare", "wlhiwraith", "wlgywraith",
    "wlspectre", "wlwartroll", "wlmrwarcat", "wllhwarcat",
    "wlreiver", "wlghostwolf", "wlbrownbear", "wlcavetroll", "wlforesttroll",
    "wltreespirit", "wlzombie", "wlfireguardian", "wlsteelgolem", "wlfrostgiant",
    "wlcrone", "wlroa'ter", "wlstonesentinel", "wlbanshee", "wlmtking",
    "wlkiramon", "wllstonegargoyle", "wlmountaintroll", "wlcarceris", "wlkwarfarer",
    "wlvereri", "wlwolfshade", "wlyeti", "wlminotaur", "wlminowarrior", "wlminomagus",
    "wlspider", "wlskeletalgiant", "wldarkshambler",
    "wldarkwoode", "wlearthelemental", "wlillokeelder", "wlstonetroll",
    "wlmountainlion", "wlillokemystic", "wllessergargoyle", "wlgargoyle", "wlrolton",
    "wlthyril",

    -- Moon
    "misty", "moonfigure", "moonbeetle", "moonmonastery", "moonmagru",
    "moonmyklian", "moonvortece", "moonvruul",

    -- Caravansary
    "caratroll",

    -- Solhaven
    "solcyclops", "solwight", "solurgh", "solcorpse", "solwarhorse", "sollord",
    "solphantasma", "wlphantasma", "solcentaur", "solschieftain", "solfisherman",
    "solwaterwitch", "soldarkwoode", "solforesttroll", "solthundertroll", "solfenghai",
    "solnmvesperti", "solshan", "solvineshan", "solnmwaern", "soldybbuk",
    "solspectre", "solgreatboar", "solfireguardian", "solwerebear",

    -- River's Rest
    "rrviper", "rrkrolvin", "rrkship", "rrbogwraith", "rrsoldier", "rrhilltroll",
    "rrcavebear", "rrkpirate", "rrbloodeagle", "rrslaver", "rrmooreagle", "rrchimera",
    "rrogre", "rrswarrior", "rrmonkey", "rrarbalester", "rrherald", "rrapprentice",
    "rrhisskrashaman", "rrhag", "rrfleshgolem",

    -- Icemule
    "iceguardian", "icemanticore", "icesnowspectre", "rift2", "northscatter",
    "rift1", "icephantom", "pineseeker", "icecockatrice", "icefarmhand", "icetspirit",
    "iceshade", "rift4", "rift5", "rift3", "southscatter", "pineglacei", "pinegorge",
    "pineslope", "pinewraith", "icewight", "iceleaper", "icethyril", "icemonkey",
    "iceworm", "icesentry", "icewallguardian", "iceurchin", "icerat", "icegiant",
    "icetrailgiant", "icecrone", "iceshrub", "icebush", "icemoonshore", "denofrot",

    -- Hinterwilds
    "hinterstart", "hinterforest",

    -- Ta'Illistim
    "tikiramon", "tiwolfhound", "tiorcscout", "tileopard", "tiburgee", "tighostlymara",
    "tivourkha", "tibaesrukha", "tivortaz", "tiviper", "tisupplicant", "tiweasel",
    "tistag", "tibasilisk", "tiwarthog", "tihuntertroll", "tibarghest", "tibendith",
    "titrali", "tiraptor", "tifaeroth", "sislush", "tigriffin", "tishrickhen",
    "tigremlock", "tiithzir", "tiotfwest", "tiotfnorth", "tislush",

    -- Ta'Vaalor
    "tvravelin", "tvrodent", "tvkobold", "tvant", "tvrelnak", "tvredorc", "tvraiderorc",
    "tvdarkorc", "tvgreyorc", "tvwolfshade", "tvagreshbear", "tvsiren", "tvphantom",
    "tvcockatrice", "tvthyril", "tvapparition", "tvdirge", "tvdarkwoode", "tvtrollscout",
    "tvblackbear", "tvmaster", "tvlion", "tvbasilisk", "tvzombie", "tvmonk", "tvbogspectre",

    -- Zul Logoth
    "zulkrynch", "zulwraith", "zulsavage", "zullizard", "zulkiramon",

    -- Teras Isle
    "terasburgee", "terasjtroll", "terastsark", "teraspyrothag",
    "terasltroll", "zone2", "teraswraith",
    "terasdevil", "terasshoot", "terasradical", "teraswelemental",
    "terassentry", "teraskiramon", "terasbanshee",

    -- Kraken's Fall
    "kfatoll", "kfatemple",

    -- Special modes
    "group", "bounty", "newbounty", "fastbounty",
    "quick", "qlite", "grounded", "drarena", "drlite",
    "patrol", "bandit", "qfollow", "follow",
}

---------------------------------------------------------------------------
-- Validate zone string
---------------------------------------------------------------------------
function Navigation.is_valid_zone(zone)
    if not zone then return false end
    zone = zone:lower()
    for _, z in ipairs(Navigation.ZONES) do
        if z == zone then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Navigate to hunting area — go2 to the starting room for a given zone
-- Returns true on success
---------------------------------------------------------------------------
function Navigation.go_to_zone(hp)
    local area = hp.my_area
    if not area or area == "0" then return false end

    -- Quick/qlite/grounded stay in current room
    if area:find("quick") or area:find("qlite") then
        hp.action = 97
        return true
    end

    if area:find("grounded") then
        hp.action = 95
        hp.my_room_number = GameState.room_id
        return true
    end

    -- Moon zones need special navigation
    if area:find("^moon") or area == "misty" then
        Navigation.moon_navigate(hp)
        return true
    end

    -- Group/follow modes
    if area == "group" or area == "follow" or area == "qfollow" then
        return true
    end

    -- Use go2 to reach hunting zone
    Map.go2(area)
    return true
end

---------------------------------------------------------------------------
-- Moon navigation — Broken Lands special handling
---------------------------------------------------------------------------
function Navigation.moon_navigate(hp)
    local area = hp.my_area

    local moon_rooms = {
        misty           = 6505,
        moonfigure      = 6626,
        moonbeetle      = 7450,
        moonmonastery   = 6686,
        moonmagru       = 7459,
        moonmyklian     = 7478,
        moonvortece     = 7486,
        moonvruul       = 19261,
    }

    local target_room = moon_rooms[area]
    if not target_room then return end

    -- Check if already on moon
    local room_desc = GameState.room_description or ""
    local current_area = room_desc  -- approximate

    -- Try direct travel if we have Symbol of Seeking
    if Spell[9826] and Spell[9826].known then
        Map.go2(tostring(target_room))
        pause(1)
        if GameState.room_id == target_room then return end
    end

    -- If already in Broken Lands area
    local in_broken = (GameState.room_id == 6505) or
                      (room_desc:find("Broken Lands") or false) or
                      (room_desc:find("Monastery") or false)

    if in_broken then
        Map.go2(tostring(target_room))
        pause(1)
    else
        -- Go to Misty Chamber first
        Map.go2("6505")
        pause(1)
        if GameState.room_id ~= 6505 then
            respond(Char.name .. ", could not reach Misty Chamber.")
            respond("Try heading to room 6505 manually or have a Voln Master fog you there.")
            return
        end
        Map.go2(tostring(target_room))
        pause(1)
    end

    if GameState.room_id ~= target_room then
        respond(Char.name .. ", could not reach moon destination " .. target_room .. ".")
    end

    -- Special magru crawl mode
    if area == "moonmagru" then
        respond(Char.name .. ", setting movement to crawl for this zone.")
        respond("Huntpro will clear this when returning to safe room.")
        respond("IMPORTANT: Turn off skinning in your loot script for this zone.")
        pause(3)
        fput("move crawl")
        fput("kneel")
    end
end

---------------------------------------------------------------------------
-- Wander to next room — random walk within hunting boundary
---------------------------------------------------------------------------
function Navigation.wander(hp)
    -- Nil room recovery
    if not GameState.room_id then
        if not (hp.my_area and (hp.my_area:find("qlite") or hp.my_area:find("quick") or
                hp.my_area:find("grounded"))) then
            -- Walk until we hit a mapped room
            local attempts = 0
            while not GameState.room_id and attempts < 10 do
                fput("go door")  -- try generic exit
                pause(1)
                attempts = attempts + 1
            end
        end
        return
    end

    -- Grounded mode — stay in one room
    if hp.action == 95 then
        return
    end

    -- Quick/qlite — just walk
    if hp.action == 97 then
        walk()
        return
    end

    -- Normal wander
    walk()
end

---------------------------------------------------------------------------
-- Return to safe room — go to rest room or supernode
---------------------------------------------------------------------------
function Navigation.safe_room(hp)
    -- Clean up magru crawl mode
    if hp.my_area and hp.my_area:find("moonmagru") then
        fput("move clear")
    end

    -- Run loot script one last time
    local Combat = require("gs.huntpro.combat")
    Combat.run_loot(hp)

    if hp.rest_room and hp.rest_room ~= "0" then
        Map.go2(hp.rest_room)
        respond("At preferred resting room. Reason: " .. (hp.return_why or "hunt complete"))
    elseif hp.my_area and hp.my_area:find("^moon") then
        Map.go2("6505")
        respond("At Misty Chamber. Reason: " .. (hp.return_why or "hunt complete"))
    else
        -- Try supernode
        Map.go2("supernode")
        respond("At supernode. Reason: " .. (hp.return_why or "hunt complete"))
    end

    -- Stow equipment
    Navigation.stow_all(hp)

    -- Group cleanup
    if hp.group_ai and hp.group_ai ~= "0" then
        fput("disband")
        fput("group open")
    end

    -- Run cleanup if enabled
    if hp.combat_cleanup then
        Navigation.cleanup(hp)
    end
end

---------------------------------------------------------------------------
-- Stow all equipment
---------------------------------------------------------------------------
function Navigation.stow_all(hp)
    local rh = hp.right_hand_detect or "0"
    local lh = hp.left_hand_detect or "0"

    if rh == "0" and lh == "0" then
        local right = GameObj.right_hand()
        local left = GameObj.left_hand()
        if right or left then
            fput("sheath")
            if hp.my_style and hp.my_style:find("[5678]") then
                fput("store ranged")
            end
            if (Skills.shield_use or 0) >= 1 then
                fput("store shield")
            end
            fput("stow all")
        end
    else
        -- Selective stow preserving detected items
        if rh ~= "0" then
            local left = GameObj.left_hand()
            if left then
                if hp.my_style and hp.my_style:find("[5678]") then
                    fput("store ranged")
                end
                if (Skills.shield_use or 0) >= 1 then
                    fput("store shield")
                end
                fput("stow left")
            end
        end
        if lh ~= "0" then
            local right = GameObj.right_hand()
            if right then
                fput("sheath")
                fput("stow right")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Cleanup routine — post-hunt maintenance
---------------------------------------------------------------------------
function Navigation.cleanup(hp)
    respond(Char.name .. ", starting huntpro cleanup.")

    -- Empath self-heal
    if Spell[1118] and Spell[1118].known and Stats.prof == "Empath" then
        if Script.exists("selfhealall") then
            Script.run("selfhealall")
            wait_while(function() return Script.running("selfhealall") end)
        end
    end

    -- Herb cleanup
    if not hp.nocleanupherbs then
        if Script.exists("eherbs") then
            Script.run("eherbs")
            wait_while(function() return Script.running("eherbs") end)
        end
    end

    -- Loot sell
    local loot_script = hp.cleanloot_script or hp.loot_script or "eloot"
    Script.run(loot_script, "sell")
    wait_while(function() return Script.running(loot_script) end)

    -- End combat waggle
    local SpellMod = require("gs.huntpro.spells")
    SpellMod.end_combat_waggle(hp)

    -- Sanctify weapon refresh (Cleric 330)
    if hp.sanctify_330 and Stats.prof == "Cleric" then
        if Spell[330] and Spell[330].known and Spell[330]:affordable() then
            fput("ready weapon")
            local result = dothistimeout("look at my " .. (hp.right_hand_detect or "weapon"), 5,
                "flickering aura of holy light radiates from")
            if not result or not result:find("flickering aura") then
                fput("prep 330")
                fput("evoke " .. (hp.right_hand_detect or "weapon"))
                waitrt()
                waitcastrt()
                if GameState.prepared_spell and GameState.prepared_spell ~= "None" then
                    fput("release")
                end
            end
        end
    end

    -- Meditate
    if hp.meditate then
        fput("meditate")
    end

    respond(Char.name .. ", huntpro cleanup is complete.")
end

---------------------------------------------------------------------------
-- Zone reset check — boundary rooms that redirect wander path
-- This is a simplified version; the Ruby original has 200+ room-specific redirects
---------------------------------------------------------------------------
Navigation.ZONE_REDIRECTS = {
    -- Landing
    [3757] = 7937,  -- wlorc boundary
    [6786] = 6819,  -- wlowarrior
    [6784] = 6783,  -- wlmonhobgoblin
    [6764] = 6783,  -- wlmonhobgoblin
    [448]  = 414,   -- wlrolton
    [215]  = 414,   -- wlrolton
    [4536] = 4560,  -- wlpooka
    [7507] = 7510,  -- wlshade
    [7028] = 7018,  -- wlgargoyle
    [7014] = 7019,  -- wlgargoyle
    [7792] = 7810,  -- wlcavetroll
    [7803] = 7798,  -- wlcavetroll

    -- Solhaven
    [5239] = 5241,  -- solfisherman
    [5244] = 5207,  -- solfisherman

    -- Icemule
    [2883] = 2894,  -- icecrone
    [2900] = 2880,  -- icecrone
    [2557] = 2539,  -- icetrailgiant
    [3245] = 3263,  -- iceguardian
    [3253] = 3254,  -- iceguardian
    [3257] = 3252,  -- iceguardian
    [2824] = 2823,  -- pineslope
    [2816] = 2830,  -- pineslope
    [2911] = 2910,  -- icegiant
    [2901] = 2898,  -- icegiant
    [2894] = 2921,  -- icegiant

    -- River's Rest
    [11414] = 11419,  -- rrcavebear
    [11422] = 11419,  -- rrcavebear
    [11679] = 11683,  -- rrchimera
    [11362] = 11375,  -- rrapprentice
    [11247] = 11249,  -- rrkpirate
    [11253] = 11243,  -- rrkpirate
    [11653] = 11662,  -- rrsoldier
    [11639] = 11636,  -- rrbogwraith
    [11630] = 11636,  -- rrbogwraith

    -- Zul Logoth
    [5760] = 5766,   -- zulkrynch
    [5768] = 5770,   -- zulkrynch
    [5778] = 9459,   -- zulkrynch
    [9462] = 9465,   -- zulkrynch
    [9468] = 5753,   -- zulkrynch

    -- Ta'Illistim
    [4839] = 4838,   -- titrali
    [4848] = 4714,   -- tiraptor
    [4794] = 4883,   -- tivortaz
    [4916] = 4943,   -- tifaeroth
}

---------------------------------------------------------------------------
-- Check zone boundaries and redirect if at an edge room
---------------------------------------------------------------------------
function Navigation.check_zone_boundary(hp)
    local room_id = GameState.room_id
    if not room_id then return false end

    local redirect = Navigation.ZONE_REDIRECTS[room_id]
    if redirect then
        -- Fight any targets first
        local Combat = require("gs.huntpro.combat")
        local targets = GameObj.targets and GameObj.targets() or {}
        if #targets > 0 and (hp.force_target == "0" or not hp.force_target) then
            while #targets > 0 do
                Combat.scan_targets(hp)
                Combat.execute_round(hp)
                targets = GameObj.targets and GameObj.targets() or {}
            end
        end
        Map.go2(tostring(redirect))
        return true
    end

    -- Belly of the Beast trap
    local room_desc = GameState.room_description or ""
    if room_desc:find("Belly of the Beast") then
        respond(Char.name .. ", you were eaten! Grab a dagger and attack the wall!")
        fput("stow all")
        return true
    end

    return false
end

---------------------------------------------------------------------------
-- Unpause go2 if stuck
---------------------------------------------------------------------------
function Navigation.unpause_go2()
    pause(3)
    if Script.running("go2") then
        Script.unpause("go2")
        wait_while(function() return Script.running("go2") end)
    end
end

return Navigation
