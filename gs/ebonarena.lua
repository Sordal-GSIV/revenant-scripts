--- @revenant-script
--- name: ebonarena
--- version: 1.0
--- author: Fulmen
--- game: gs
--- description: Ebon Gate Arena automation script
--- tags: ebon gate, arena, combat, event
---
--- Usage: ;ebonarena
---        ;ebonarena help
---        ;ebonarena pause <seconds>

local ARENA_ROOM = 28564
local REWARD_ROOM = 28556

UserVars.ebonarena = UserVars.ebonarena or {}
UserVars.ebonarena.wave_number = 0
UserVars.ebonarena.activescripts = UserVars.ebonarena.activescripts or {"stand"}
UserVars.ebonarena.pause_timer = UserVars.ebonarena.pause_timer or 0
UserVars.ebonarena.waggle_me = (UserVars.ebonarena.waggle_me == nil) and true or UserVars.ebonarena.waggle_me

if script.vars[1] == "help" then
    respond("Ebon Gate Arena Script")
    respond("SYNTAX: ;ebonarena")
    respond("        ;ebonarena pause <seconds>")
    respond("Active scripts: " .. table.concat(UserVars.ebonarena.activescripts, ", "))
    exit()
elseif script.vars[1] == "pause" and script.vars[2] then
    UserVars.ebonarena.pause_timer = tonumber(script.vars[2]) or 0
    echo("Pause timer set to " .. UserVars.ebonarena.pause_timer .. " seconds")
    exit()
end

fput("store all")
pause(1)
fput("get my cube from my " .. (Vars.lootsack or "pack"))
pause(1)
fput("pay")

while true do
    local line = get()
    if line:match("sinister voice announces") and Room.current.id == ARENA_ROOM then
        fput("put my cube in my " .. (Vars.lootsack or "pack"))
        fput("stow all")
        UserVars.ebonarena.wave_number = 0
        echo("Arena starting!")
    elseif line:match("crimson bolt of lightning") then
        UserVars.ebonarena.wave_number = UserVars.ebonarena.wave_number + 1
        echo("Wave " .. UserVars.ebonarena.wave_number)
        -- Default combat: use bigshot
        if Script.exists("bigshot") then
            Script.start("bigshot", "quick")
        end
    elseif line:match("is triumphant") and Room.current.id == ARENA_ROOM then
        echo("Victory!")
        fput("store all")
    elseif line:match("incarnadine vathor") and Room.current.id == REWARD_ROOM then
        waitrt()
        fput("store all")
        pause(2)
        Script.run("go2", "28549")
        echo("Run complete.")
        if UserVars.ebonarena.pause_timer > 0 then
            pause(UserVars.ebonarena.pause_timer)
        else
            echo("Type ;unpause ebonarena to continue")
            pause_script()
        end
        fput("get my cube from my " .. (Vars.lootsack or "pack"))
        fput("pay")
    elseif line:match("drags you out") or dead() then
        echo("Defeated!")
        exit()
    end
end
