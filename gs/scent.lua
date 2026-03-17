--- @revenant-script
--- name: scent
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Manage perfume organizer - apply, auto-reapply, or randomize scents
--- tags: perfume, scent, organizer, cosmetic
---
--- Usage:
---   ;scent apply [number]   - apply scent (default perfume 1)
---   ;scent auto             - auto-reapply when scent fades
---   ;scent random           - apply a random scent
---
--- Settings (Vars):
---   ;vars set organizer = <name>
---   ;vars set scent_container = <container>

no_kill_all()
no_pause_all()

local organizer       = Vars.organizer
local scent_container = Vars.scent_container

if not organizer then
    respond("You have not set the name of the scent organizer, please do so now.")
    respond("Enter ;vars set organizer = organizername")
    return
else
    respond("Organizer set to " .. organizer)
end

if not scent_container then
    respond("You have not set where the scent organizer is stored, please do so now.")
    respond("Enter ;vars set scent_container = containername")
    return
else
    respond("Scent container set to " .. scent_container)
end

local function apply_scent(number)
    number = number or 1
    empty_hands()
    fput("get my " .. organizer .. " from my " .. scent_container)
    fput("whisper " .. organizer .. " perfume " .. number)
    fput("pull my " .. organizer)
    fput("pour my bottle on " .. Char.name)
    fput("put my bottle in my " .. organizer)
    fput("put my " .. organizer .. " in my " .. scent_container)
    fill_hands()
end

local function auto_application()
    while true do
        local line = get()
        if line and line:find("The subtle scent which had been clinging to you dissipates.") then
            if running("bigshot") then
                Script.pause("scent")
                wait_while(function() return running("bigshot") end)
            end
            apply_scent(1)
        end
    end
end

local arg1 = Script.vars[1]
local arg2 = Script.vars[2]

if arg1 and arg1:match("apply") then
    local number = tonumber(arg2) or 1
    apply_scent(number)
elseif arg1 and arg1:match("auto") then
    auto_application()
elseif arg1 and arg1:match("random") then
    local number = math.random(1, 10)
    apply_scent(number)
else
    echo("What do you want to do?  Apply or Auto?")
    echo(";scent apply or ;scent auto")
end
