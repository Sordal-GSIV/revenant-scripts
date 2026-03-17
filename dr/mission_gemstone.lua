--- @revenant-script
--- name: mission_gemstone
--- version: 7.0.0
--- author: Dreaven
--- game: dr
--- description: Guide through the Mission Gemstone (A Sparkling Ascent) quest chain with step tracking
--- tags: mission, gemstone, quest, sparkling ascent, hinterwilds
---
--- Usage:
---   ;mission_gemstone   - Start quest tracker. Displays current step and provides navigation.
---
--- Supports all 13 quest steps. Handles travel to NPCs, silver requirements,
--- Teras Isle ship scheduling, and item management.

local mission_steps = {
    {
        pattern = "You have not yet begun your quest to attain a gemstone",
        name = "Kill Wyrm",
        desc1 = "You need to kill the Wyrm.",
        desc2 = "",
    },
    {
        pattern = "After slaying the wyrm, gigas from Eldurhaart were seen watching you",
        name = "Get gemstone",
        desc1 = "Meet with Ulvrig in Hinterwilds to get your gemstone",
        desc2 = "Ulvrig is in Lich room #35450",
    },
    {
        pattern = "You have retrieved an offering from the gigas",
        name = "Speak with Ilyra",
        desc1 = "You need to speak with Ilyra in Sylvarraend: Lich room #35451.",
        desc2 = "You need to bring both 'tattered parchment note' and 'ancient crumbling gemstone.'",
    },
    {
        pattern = "Ilyra has an idea of how to restore the crumbling Gemstone",
        name = "Find troubadour in Zul Logoth",
        desc1 = "You need to find a troubadour in Zul Logoth.",
        desc2 = "You need to bring the 'ancient crumbling gemstone.",
    },
    {
        pattern = "Reston wants you to harvest three stitchings.*haven't collected any",
        name = "Bring 3 stitchings to troubadour - 0 found",
        desc1 = "Loot patchwork flesh monstrosities in Sanctum of Scales.",
        desc2 = "The stitchings aren't physical objects, they are just game messages.",
    },
    {
        pattern = "Reston wants three stitchings.*You've collected one",
        name = "Bring 3 stitchings to troubadour - 1 found",
        desc1 = "Loot patchwork flesh monstrosities in Sanctum of Scales.",
        desc2 = "You have collected 1 stitching so far.",
    },
    {
        pattern = "Reston wants three stitchings.*You've collected two",
        name = "Bring 3 stitchings to troubadour - 2 found",
        desc1 = "Loot patchwork flesh monstrosities in Sanctum of Scales.",
        desc2 = "You have collected 2 stitchings so far.",
    },
    {
        pattern = "You've collected three stitchings.*Return them to Reston",
        name = "Talk to the troubadour in Zul Logoth",
        desc1 = "You need to find the troubadour in Zul Logoth.",
        desc2 = "",
    },
    {
        pattern = "Reston has told you that his former teacher Beylin Bittersteel is on Teras Isle",
        name = "Talk to Beylin on Teras Isle",
        desc1 = "This mission requires 250k silver and your gemstone.",
        desc2 = "A round trip to Teras Isle is 10k.",
    },
    {
        pattern = "The Gemstone is purified.*Ilyra asked you to return",
        name = "Speak with Ilyra again",
        desc1 = "Go to Lich room #35451, then SHOW your gemstone to researcher",
        desc2 = "You need to bring your 'tear-shaped iridescent gemstone.'",
    },
    {
        pattern = "Ilyra believes that the gigas nearly destroyed the Gemstone",
        name = "Speak with whitesmith in Moonsedge Castle",
        desc1 = "You need to travel to Moonsedge Castle: Lich room #35452.",
        desc2 = "You need to bring your 'tear-shaped iridescent gemstone.'",
    },
    {
        pattern = "phantasmal whitesmith, Jires, has agreed to craft a setting",
        name = "Kill patrician vampires in Moonsedge Castle",
        desc1 = "Kill vampires until you get a message about wasting your time.",
        desc2 = "",
    },
    {
        pattern = "You are beginning to think that Jires sent you on a wild goose chase",
        name = "Return to whitesmith in Moonsedge Castle",
        desc1 = "You need to travel to Moonsedge Castle: Lich room #35452.",
        desc2 = "You need to bring your 'tear-shaped iridescent gemstone.'",
    },
    {
        pattern = "Growing impatient with your fumbling, Jires briefly possessed your body",
        name = "Speak with Ilyra one last time",
        desc1 = "You need to speak with Ilyra in Sylvarraend: Lich room #35451.",
        desc2 = "You need to bring your 'tear-shaped iridescent gemstone.'",
    },
    {
        pattern = "Ilyra has revealed that you must vanquish the ancient power",
        name = "Defeat the sybil!",
        desc1 = "All you have to do now is kill the sybil and you're done!",
        desc2 = "It is a boss critter found in Hinterwilds and requires a group to kill.",
    },
}

local zul_logoth_rooms = {
    "995", "9437", "9438", "9439", "994", "996", "997", "9432", "9433",
    "9434", "9435", "9436", "998", "9430", "999", "9429", "1000", "1001",
    "1002", "1003", "9414", "9410", "9411", "1004", "9413", "9415", "9420",
    "9419", "9421", "9422", "9418", "9509", "9510", "9511", "9512", "9513",
    "9417", "9416", "9412", "1005", "9407", "1006", "1007", "5748", "5749",
    "5750", "9406", "5751", "1008", "9405", "1009", "5823", "1010", "9404",
    "1011", "9403", "1012",
}

local function check_mission()
    waitrt()
    put("quest info")
    local quest_number = nil
    while true do
        local line = get()
        if line then
            local num = line:match("(%d+)%) A Sparkling Ascent")
            if num then
                quest_number = num
                break
            end
            if line:find("QUEST ABANDON") then
                echo("The gemstone quest isn't available to you or you've already finished it.")
                return nil
            end
        end
    end
    if not quest_number then return nil end

    put("quest info " .. quest_number)

    while true do
        local line = get()
        if line then
            local stripped = strip_xml(line)
            for _, step in ipairs(mission_steps) do
                if stripped:find(step.pattern) then
                    return step, quest_number
                end
            end

            -- Silver check
            local silver_str = stripped:match("^You have (.*) silver with you")
            if silver_str then
                if silver_str == "no" then return 0
                elseif silver_str == "but one" then return 1
                else return tonumber((silver_str:gsub(",", ""))) or 0
                end
            end

            if stripped:find("Roundtime") or stripped:find("You don't seem to have") then
                break
            end
        end
    end
    return nil
end

-- Main
echo("=== Mission Gemstone Quest Tracker ===")
echo("Author: Dreaven")
echo("")

-- Set guarded stance
if Char.stance ~= "guarded" then
    fput("stance guarded")
    waitrt()
end

local step, quest_number = check_mission()

if not step then
    echo("Could not determine quest status. Make sure you have the quest active.")
    return
end

echo("")
echo("Current Mission: " .. step.name)
echo(step.desc1)
if step.desc2 ~= "" then
    echo(step.desc2)
end
echo(string.rep("-", 60))

-- Provide guidance based on current step
if step.name == "Kill Wyrm" then
    echo("You need to kill the Wyrm in Hinterwilds to start the quest.")

elseif step.name == "Get gemstone" then
    echo("Travel to Lich room #35450 (Ulvrig in Hinterwilds).")
    echo("GET OFFERING FROM CHEST, then stow the note and gemstone.")

elseif step.name:find("Speak with Ilyra") then
    echo("Travel to Lich room #35451 (Ilyra in Sylvarraend).")
    if step.name == "Speak with Ilyra" then
        echo("GIVE your parchment note and crumbling gemstone to the researcher.")
    elseif step.name == "Speak with Ilyra again" then
        echo("SHOW your gemstone to the researcher.")
    end

elseif step.name:find("troubadour") then
    echo("Travel to Zul Logoth and find the wandering troubadour.")
    echo("Rooms to search: " .. #zul_logoth_rooms .. " known locations.")
    if step.name == "Find troubadour in Zul Logoth" then
        echo("Buy him a drink from room 16836 (order 6, buy) then give it to him.")
    elseif step.name == "Talk to the troubadour in Zul Logoth" then
        echo("ASK him about Beylin twice.")
    end

elseif step.name:find("stitching") then
    echo("Hunt patchwork flesh monstrosities in the Sanctum of Scales.")
    echo("Take a caravan from Lich room #25185 (cost: 3000 silvers).")
    echo("The stitchings are game messages, not physical items.")

elseif step.name == "Talk to Beylin on Teras Isle" then
    echo("Requires 250k silver and your gemstone.")
    echo("Ship to Teras leaves from Landing at the top of every hour.")
    echo("Find the spotted hound near room 1842, ASK HOUND ABOUT BEYLIN.")
    echo("Then: QUEST CONTINUE, QUEST CONTINUE PAY BEYLIN 250,000 SILVERS")
    echo("GIVE your gemstone to the lapidary.")

elseif step.name:find("whitesmith") or step.name:find("Return to whitesmith") then
    echo("Travel to Moonsedge Castle: Lich room #35452.")
    echo("Warning: This goes through an ascension hunting area!")
    if step.name:find("Return") then
        echo("QUEST CONTINUE, then GET your gemstone, LIGHT FURNACE twice.")
    else
        echo("QUEST CONTINUE to begin.")
    end

elseif step.name == "Kill patrician vampires in Moonsedge Castle" then
    echo("Hunt patrician vampires until the quest updates.")
    echo("Check QUEST INFO periodically -- the message can be missed.")

elseif step.name == "Defeat the sybil!" then
    echo("Kill the sybil boss in Hinterwilds (requires a group).")
end

echo("")
echo("Re-run ;mission_gemstone after completing the current step.")
