--- @revenant-script
--- name: ghoul
--- version: 2.0.0
--- author: Alastir
--- contributors: Drafix
--- description: Auto-daub bingo numbers for Ghoul game (Caligos/Naidem)
--- tags: ghoul, bingo, daub, caligos, naidem
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;ghoul             - auto-daub numbers as called
---   ;ghoul catchup     - daub all previously called numbers
---   ;ghoul <letter> <number> - yell GHOUL! when that number is called
---
--- Example: ;ghoul o 37

local first_daub = true

local arg1 = Script.vars[1]
local arg2 = Script.vars[2]

if not arg1 then
    -- Standard auto-daub mode
    -- last_called persists across get() iterations (mirrors Ruby $ghoul_number global)
    local last_called = nil
    while true do
        local line = get()
        if line then
            if line:find("The period of time for making the first mark on your game card has started.") then
                fput("daub my card O free")
                fput("daub my card O free")
            end

            local called = line:match('An ethereal voice calls out, "(.+)" before the ball drifts back into')
            if called then
                last_called = called
                if first_daub then
                    fput("daub my card O free")
                    fput("daub my card O free")
                    fput("daub my card " .. called)
                    first_daub = false
                else
                    fput("daub my card " .. called)
                end
            end

            if line:find("Using your .+ dauber, you daub a space on your card.") then
                fput("look my card")
            end

            if line:find("If you wish to continue and daub your card for the first time, repeat your daubing attempt within the next 30 seconds.") then
                if last_called then
                    fput("daub my card " .. last_called)
                end
            end

            if line:find("Tselise pushes something on the cabinet") and line:find("tumble back into the main hopper") then
                first_daub = true
            end
        end
    end

elseif arg1:match("catchup") then
    -- Catch-up mode: read callboard and daub all called numbers
    status_tags()
    put("look case")
    local count = 0
    while true do
        local line = get()
        if line then
            local letter, rest = line:match("^| ([GHOUL]) |~| (.+)$")
            if letter and rest then
                -- Extract bolded (called) numbers
                for num in rest:gmatch("<pushBold/>(%d%d) <popBold/>") do
                    put("daub my card " .. letter .. " " .. num)
                    pause(0.2)
                end
                count = count + 1
                if count >= 5 then break end
            end
        end
    end

elseif arg1:match("^[GHOULghoul]$") and arg2 and arg2:match("^%d+$") then
    -- Watch for specific number
    local watch_letter = arg1:upper()
    local watch_number = arg2
    echo("Waiting for \"" .. watch_letter .. " " .. watch_number .. "\" before yelling GHOUL!")

    while true do
        local line = get()
        if line then
            if line:find('An ethereal voice calls out, "' .. watch_letter .. " " .. watch_number .. '"') and line:find("before the ball drifts back into") then
                put("say GHOUL!")
                break
            end
        end
    end
else
    echo("Usage: ;ghoul | ;ghoul catchup | ;ghoul <letter> <number>")
end
