--- @revenant-script
--- name: gemstones
--- version: 1.0.0
--- author: Alastir
--- game: gs
--- description: Gemstone quest progression tracker and automation
--- tags: gemstone, quest, hinterwilds
---
--- Usage: ;gemstones (checks mission status and guides you through steps)

no_pause_all()
no_kill_all()

local function step_check()
    local result = dothistimeout("mission gemstone", 5, "You have not yet begun|Ulvrig|retrieved an offering|Ilyra has an idea|Reston wants|collected the three|Reston has told|charm is purified|Ilyra believes|phantasmal whitesmith|starting to think|Growing impatient|must vanquish")

    if not result then
        echo("Could not determine quest step.")
        return
    end

    if result:match("not yet begun") then
        echo("Step 1: Travel to Hinterwilds and defeat the wyrm!")
    elseif result:match("Ulvrig") then
        echo("Step 1.5: Go to Eldurhaart to get your gemstone!")
        echo("Unpause to travel there.")
        pause_script()
        Script.run("go2", "shrine")
    elseif result:match("retrieved an offering") then
        echo("Step 2: Travel to Sylvarraend and talk to the researcher!")
    elseif result:match("Ilyra has an idea") then
        echo("Step 3: Go to Zul Logoth and find the troubadour!")
    elseif result:match("Reston wants") then
        echo("Step 4: Hunt monstrosity in Sanctum of Scales for stitchings!")
    elseif result:match("collected the three") then
        echo("Step 4.5: Return to Zul Logoth troubadour!")
    elseif result:match("Reston has told") then
        echo("Step 5: Go to Teras Isle and pay 250k!")
    elseif result:match("charm is purified") then
        echo("Step 6: Return to Sylvarraend!")
    elseif result:match("Ilyra believes") then
        echo("Step 7: Go to Moonsedge for kroderine!")
    elseif result:match("phantasmal whitesmith") then
        echo("Step 7.1: Kill patrician vampires for stickpin!")
    elseif result:match("starting to think") then
        echo("Step 7.2: Return to Jires!")
    elseif result:match("Growing impatient") then
        echo("Step 8: Return to Sylvarraend!")
    elseif result:match("must vanquish") then
        echo("Step 9: Fight the Sybil in Hinterwilds!")
    end
end

step_check()
