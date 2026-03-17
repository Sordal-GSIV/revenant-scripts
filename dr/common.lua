--- @revenant-script
--- name: common
--- version: 1.0.0
--- author: rpherbig
--- game: dr
--- description: Common helper functions shared by DR scripts (DRC module)
--- tags: library, common, utility, bput
---
--- Ported from common.lic (Lich5) to Revenant Lua
---
--- Provides the DRC module with bput, wait_for_script_to_complete,
--- remove_armor, wear_armor, forage, hand_over, rummage, empty_hands, etc.
---
--- Usage:
---   Loaded automatically by scripts that require "common"

-- DRC module is provided by the Revenant engine's DR compatibility layer.
-- This script ensures it is available and adds any missing functions.

if not DRC then DRC = {} end

FAILED_COMMAND = "*FAILED*"
ORDINALS = {"first","second","third","fourth","fifth","sixth","seventh","eighth","ninth","tenth","eleventh","twelfth","thirteenth"}

--- Blocking put - sends command, waits for one of the expected responses
--- @param message string The command to send
--- @param matches table Array of string/pattern matches to look for
--- @return string The matched response line
function DRC.bput(message, matches)
    if type(matches) == "string" then matches = {matches} end
    local timer = os.time()
    clear()
    put(message)
    while os.time() - timer < 15 do
        local response = get_with_timeout(0.1)
        if response then
            -- Handle wait messages
            local wait_time = response:match("%.%.%.wait (%d+)")
                or response:match("Wait (%d+)")
            if wait_time then
                pause(tonumber(wait_time))
                put(message)
                timer = os.time()
            elseif response:find("Sorry, you may only type ahead") then
                pause(1)
                put(message)
                timer = os.time()
            elseif response:find("too busy performing") then
                put("stop play")
                put(message)
                timer = os.time()
            elseif response:find("still stunned") then
                pause(0.5)
                put(message)
                timer = os.time()
            else
                for _, match in ipairs(matches) do
                    if response:find(match) then
                        return response
                    end
                end
            end
        end
    end
    echo("*** bput: No match found after 15 seconds for: " .. message)
    return FAILED_COMMAND
end

function DRC.wait_for_script_to_complete(name, args)
    local ok = start_script(name, args or {})
    if ok then
        pause(2)
        while running(name) do pause(1) end
    end
    return ok
end

function DRC.remove_armor(armors)
    if not armors then return end
    for _, piece in ipairs(armors) do
        fput("remove my " .. piece)
        fput("stow my " .. piece)
        pause(0.25)
    end
end

function DRC.wear_armor(armors)
    if not armors then return end
    for _, piece in ipairs(armors) do
        fput("get my " .. piece)
        fput("wear my " .. piece)
        pause(0.25)
    end
end

function DRC.forage(item)
    while true do
        local r = DRC.bput("forage " .. item, {
            "Roundtime",
            "too cluttered",
            "need to have at least one hand free",
        })
        if r:find("too cluttered") then
            fput("kick pile")
        elseif r:find("hand free") then
            DRCI.stow_hands()
        else
            waitrt()
            return
        end
        waitrt()
    end
end

function DRC.message(text)
    echo(text)
end

function DRC.empty_hands()
    if checkright() then fput("stow right") end
    if checkleft() then fput("stow left") end
end

echo("DR common library loaded.")
