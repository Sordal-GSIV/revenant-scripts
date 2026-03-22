--- @revenant-script
--- name: ebonarena
--- version: 1.0
--- author: Fulmen
--- ported-by: Claude (AI conversion from ebonarena.lic)
--- game: gs
--- description: Ebon Gate Arena automation script
--- tags: ebon gate, arena, combat, event
--- @lic-certified: complete 2026-03-19
---
--- Usage: ;ebonarena
---        ;ebonarena help
---        ;ebonarena pause <seconds>

-- Configuration
local SAFE_ROOM = 28549
local ARENA_ROOM = 28564
local REWARD_ROOM = 28556

-- Initialize persistent settings
UserVars.ebonarena = UserVars.ebonarena or {}
UserVars.ebonarena.wave_number = 0
UserVars.ebonarena.activescripts = UserVars.ebonarena.activescripts or { "stand" }
UserVars.ebonarena.pause_timer = UserVars.ebonarena.pause_timer or 0
if UserVars.ebonarena.waggle_me == nil then
    UserVars.ebonarena.waggle_me = true
end
if UserVars.ebonarena.absorb_me == nil then
    UserVars.ebonarena.absorb_me = false
end

-- Combat routines

local function default_attack(npc)
    echo("Using bigshot for combat...")
    if Script.running("bigshot") then
        Script.kill("bigshot")
        wait_while(function() return Script.running("bigshot") end, 0.1)
    end
    Script.run("bigshot", "quick")
    wait_while(function()
        return npc.status ~= "dead" and npc.status ~= "gone"
            and not npc.status:find("dead") and not npc.status:find("gone")
            and not dead()
            and Script.running("bigshot")
    end, 0.1)
end

local function fulmen_attack(npc)
    fput("stance defensive")
    waitrt()
    waitcastrt()

    while not npc.status:find("dead") and not npc.status:find("gone") and not dead() do
        waitrt()
        waitcastrt()

        if checkmana(20) then
            fput("incant 1615")
        else
            fput("stance offensive")
            waitcastrt()
            waitrt()
            fput("kill")
            waitrt()
            fput("kick")
            waitrt()
        end
        pause(0.1)
    end
end

local function numindor_attack(npc)
    if not checkleft("buckler") then
        fput("stow left")
    end
    local lh = GameObj.left_hand()
    if not lh or lh.noun == nil or lh.name == "Empty" then
        fput("ready shield")
    end
    if not checkright("star") then
        fput("stow right")
    end
    local rh = GameObj.right_hand()
    if not rh or rh.noun == nil or rh.name == "Empty" then
        fput("unsheath")
    end
    waitrt()

    local berserk_active = false

    while not npc.status:find("dead") and not npc.status:find("gone") and not dead() do
        waitrt()
        if not checkstance("offensive") then
            fput("stance offensive")
        end
        waitrt()

        if not berserk_active then
            local result = dothistimeout("berserk", 3,
                "You scream with a maniacal bloodlust!",
                "You cannot do that while berserking")
            if result and result:find("You scream with a maniacal bloodlust!") then
                berserk_active = true
            end
        end

        waitrt()
        if checkstamina() <= 35 then
            fput("kill")
        end
        waitrt()
    end
end

local function attack()
    local targets = GameObj.targets()
    -- Shuffle targets
    for i = #targets, 2, -1 do
        local j = math.random(1, i)
        targets[i], targets[j] = targets[j], targets[i]
    end

    for _, npc in ipairs(targets) do
        if not npc.status:find("dead") and not npc.status:find("gone") then
            put("target #" .. npc.id)

            if Char.name:find("Fulmen") then
                fulmen_attack(npc)
            elseif Char.name:find("Numindor") then
                numindor_attack(npc)
            else
                default_attack(npc)
            end
        end
    end
end

-- Start active support scripts
local function start_active_scripts()
    for _, name in ipairs(UserVars.ebonarena.activescripts) do
        if Script.exists(name) then
            if not Script.running(name) then
                Script.run(name)
            elseif Script.is_paused(name) then
                Script.unpause(name)
            end
        end
    end
end

-- Pause active support scripts
local function pause_active_scripts()
    for _, name in ipairs(UserVars.ebonarena.activescripts) do
        if Script.running(name) and not Script.is_paused(name) then
            Script.pause(name)
        end
    end
end

-- Absorb experience if mind is saturated/fried
local function absorb_experience()
    if UserVars.ebonarena.absorb_me then
        local mind_val = percentmind()
        local mind_text = GameState.mind or ""
        if mind_val >= 100 or mind_text:find("saturated") or mind_text:find("fried") then
            waitrt()
            fput("boost absorb")
            echo("Absorbed experience - mind was full")
        end
    end
end

-- Cleanup on exit
before_dying(function()
    for _, name in ipairs(UserVars.ebonarena.activescripts) do
        if Script.running(name) then
            Script.kill(name)
        end
    end
end)

-- Handle arguments
local args = Script.vars
local arg1 = args and args[1] and args[1]:lower() or nil

if arg1 == "help" then
    respond("")
    respond("=== Ebon Gate Arena Script Help ===")
    respond("SYNTAX: ;ebonarena")
    respond("        ;ebonarena pause <seconds>")
    respond("")
    respond("This script automates the Ebon Gate Arena.")
    respond("Start the script in the safe room (28549) with cubes in your lootsack.")
    respond("")
    respond("Settings:")
    respond("  Active support scripts: " .. table.concat(UserVars.ebonarena.activescripts, ", "))
    respond("  ;e UserVars.ebonarena.activescripts = {'stand', 'script1', 'script2'}")
    respond("")
    respond("  Lootsack container: " .. (Vars.lootsack or "(not set)"))
    respond("  ;vars set lootsack=CONTAINERHERE")
    respond("")
    respond("  Pause timer (seconds): " .. tostring(UserVars.ebonarena.pause_timer))
    respond("  ;ebonarena pause 240  (or any number of seconds)")
    respond("  Set to 0 to pause indefinitely until manual unpause. Set to 240 to pause for 240 seconds before running again, etc.")
    respond("")
    respond("  Waggle between runs: " .. tostring(UserVars.ebonarena.waggle_me))
    respond("  ;e UserVars.ebonarena.waggle_me = true/false")
    respond("")
    respond("  Auto-absorb when mind full: " .. tostring(UserVars.ebonarena.absorb_me))
    respond("  ;e UserVars.ebonarena.absorb_me = true/false")
    respond("  If you have BOOST ABSORBs available, it will use them when your mind is at 100%, right before pausing at the end of a run.")
    respond("")
    respond("The script will:")
    respond("  - Pay with a cube and enter the arena")
    respond("  - Execute your character's combat routine")
    respond("  - Collect rewards")
    respond("  - Return to Arena entrance and pause")
    respond("  - Auto-unpause after timer (if set) or wait for manual unpause")
    respond("")
    respond("Support scripts are started before combat and paused after each run.")
    exit()
elseif arg1 == "pause" and args[2] and tonumber(args[2]) and tonumber(args[2]) > 0 then
    UserVars.ebonarena.pause_timer = tonumber(args[2])
    echo("Pause timer set to " .. UserVars.ebonarena.pause_timer .. " seconds")
    exit()
elseif arg1 == "pause" then
    echo("Current pause timer: " .. tostring(UserVars.ebonarena.pause_timer) .. " seconds")
    echo("Usage: ;ebonarena pause <seconds>")
    echo("Set to 0 for indefinite pause (manual unpause required)")
    exit()
end

-- Main loop: enter arena
fput("store all")
pause(1)
fput("get my cube from my " .. (Vars.lootsack or "pack"))
pause(1)
fput("pay")
wait_until(function() return Room.id == ARENA_ROOM end)

while true do
    local line = get()

    -- Arena starting
    if line:find("A sinister voice announces") and line:find("We have another living one") and Room.id == ARENA_ROOM then
        fput("put my cube in my " .. (Vars.lootsack or "pack"))
        fput("stow all")
        UserVars.ebonarena.wave_number = 0
        start_active_scripts()
        fput("beg")
        echo("Arena starting!")

    -- Enemy wave (lightning strike or live targets still in room)
    elseif line:find("A crimson bolt of lightning strikes") or
           (Room.id == ARENA_ROOM and UserVars.ebonarena.wave_number > 0 and (function()
               local t = GameObj.targets()
               return t and #t > 0
           end)()) then
        UserVars.ebonarena.wave_number = UserVars.ebonarena.wave_number + 1
        echo("Wave " .. UserVars.ebonarena.wave_number)
        attack()

    -- Victory
    elseif line:find(Char.name .. " is triumphant") and Room.id == ARENA_ROOM then
        echo("Victory!")
        fput("store all")
        fput("loot room")

    -- Reward received in reward room
    elseif line:find("a huge incarnadine vathor heals you of your injuries") and Room.id == REWARD_ROOM then
        waitrt()

        -- Store weapons first to make room for reward
        fput("store all")
        pause(1)

        -- Check if reward was dropped at your feet and capture what it was
        local reward_match = line:match("regurgitates an? (.-) at your feet")
        if reward_match then
            local reward_noun = reward_match:match("(%S+)$")
            if reward_noun then
                pause(0.5)
                fput("get " .. reward_noun)
                pause(0.5)
            end
        end

        -- Stow everything
        fput("stow all")
        pause(2)

        -- Return to safe room
        echo("Returning to safe room...")
        Script.run("go2", tostring(SAFE_ROOM))
        wait_while(function() return Script.running("go2") end)
        pause(1)

        -- Waggle if enabled
        if UserVars.ebonarena.waggle_me then
            if Script.exists("waggle") then
                Script.run("waggle")
                wait_while(function() return Script.running("waggle") end)
            end
        end

        -- Pause support scripts
        pause_active_scripts()

        -- Absorb experience if enabled and mind full
        absorb_experience()

        echo("Run complete. Pausing script.")

        if UserVars.ebonarena.pause_timer > 0 then
            echo("Auto-unpausing in " .. UserVars.ebonarena.pause_timer .. " seconds...")
            pause(UserVars.ebonarena.pause_timer)
        else
            echo("Type ;unpause ebonarena to continue")
            Script.pause(Script.name)
            pause(0) -- yield to pause-aware sleep so we block until unpaused
        end

        -- Get next cube and re-enter
        fput("get my cube from my " .. (Vars.lootsack or "pack"))
        fput("pay")
        wait_until(function() return Room.id == ARENA_ROOM end)

    -- Death
    elseif line:find("drags you out of the arena") or dead() then
        echo("Defeated!")
        exit()
    end
end
