--- @revenant-script
--- name: checkfavors
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Check favor count and run favor quest if needed.
--- tags: favors, theurgy, quest
---
--- Converted from checkfavors.lic

local settings = get_settings()
if not settings.favor_goal then return end

local result = DRC.bput("favor", "You currently have %d+", "You are not currently")
local favor_count = 0
if result then
    local num = result:match("(%d+)")
    if num then favor_count = tonumber(num) end
end

if favor_count >= settings.favor_goal then return end

local god = settings.favor_god or "chadatru"
local tap_result = DRC.bput("tap my " .. god .. " orb", "The orb is delicate", "I could not find")

if tap_result and tap_result:find("could not") then
    if settings.use_favor_altars then
        wait_for_script_to_complete("favor", {god})
    else
        wait_for_script_to_complete("favor")
    end
    fput("stow my orb")
else
    local rub_result = DRC.bput("rub my " .. god .. " orb",
        "not yet fully prepared", "lacking in the type", "your sacrifice is properly prepared")
    if rub_result and rub_result:find("properly prepared") then
        local town_data = get_data("town")
        local hometown = town_data[settings.hometown]
        if hometown and hometown.favor_altar then
            DRCT.walk_to(hometown.favor_altar.id)
        end
        fput("get my " .. god .. " orb")
        fput("put my orb on altar")
        if favor_count + 1 < settings.favor_goal then
            if settings.use_favor_altars then
                wait_for_script_to_complete("favor", {god})
            else
                wait_for_script_to_complete("favor")
            end
            fput("stow my orb")
        end
    end
end
