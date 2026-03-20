--- @revenant-script
--- name: masscomm
--- version: 2025.09.06.02
--- author: Vailan
--- original-author: Vailan (Vailan#0875 on discord)
--- game: gs
--- description: Mass spell casting coordinator with announcements (blurs 911, guards 419, colors 611)
--- tags: spellup, mass, blur, guard, color
---
--- This script auto-detects which mass spells you can cast (611, 919, 419) and
--- advertises accordingly.  Based upon massies.lic 1.0 by Stonmel.
---
--- Usage:
---   ;masscomm                        - Show this help dialog
---   ;masscomm help                   - Show this help dialog
---   ;masscomm now                    - Cast immediately (no announcements or timer)
---   ;masscomm here                   - Announce in current room, wait ~2 min, cast
---   ;masscomm spell=<blurs|guards|colors>     - Restrict to one spell
---   ;masscomm espchannel=<channel>   - Announce on amunet/ESP channel
---   ;masscomm lnetchannel=<channel>  - Announce on LNet channel
---
--- Examples:
---   ;masscomm here espchannel=Help lnetchannel=help
---   ;masscomm here spell=guards
---
--- changelog:
---   2025.09.06.02 - Revenant Lua port (full feature parity)
---   2025.09.06.01 - Initial release (Lich5 Ruby original by Vailan)
--- @lic-certified: complete 2026-03-20

-- ---------------------------------------------------------------------------
-- Argument parsing
-- ---------------------------------------------------------------------------

local blur_planned    = true
local guard_planned   = true
local color_planned   = true
local announce_room   = false
local block_announce  = false
local esp_channel     = nil
local lnet_channel    = nil

local function show_help()
    respond("This script auto-detects which mass spells you can cast (611, 911, 419) and")
    respond("advertises accordingly.")
    respond("")
    respond("CLI: ;masscomm           -- show this help dialog")
    respond("CLI: ;masscomm help      -- show this help dialog")
    respond("")
    respond("CLI: ;masscomm [now]")
    respond(" -- cast spells immediately, override announcements and timer")
    respond("CLI: ;masscomm [here]")
    respond(" -- announce in current room, wait ~2 minutes, then cast")
    respond("CLI: ;masscomm [spell=<blurs|guards|colors>]")
    respond(" -- restrict casting to only the specified spell")
    respond("CLI: ;masscomm [espchannel=<esp channel name>]")
    respond(" -- announce intention on the specified amunet/ESP channel")
    respond("CLI: ;masscomm [lnetchannel=<lnet channel name>]")
    respond(" -- announce intention on the specified LNet channel")
    respond("")
    respond("Examples:")
    respond(";masscomm here espchannel=Help lnetchannel=help")
    respond(" -- announce in room and on both nets in 2 minutes")
    respond(";masscomm here spell=guards")
    respond(" -- announce guards-only, 2 minute countdown in room")
    exit()
end

if not Script.vars[1] then
    show_help()
end

for _, arg in ipairs(Script.vars) do
    local a = arg:lower()
    if a == "help" then
        show_help()
    elseif a == "now" then
        block_announce = true
        announce_room  = false
    elseif a == "here" then
        announce_room = true
    elseif a:match("^spell=") then
        local spell = a:gsub("^spell=", "")
        if spell:match("blur") or spell:match("911") then
            guard_planned = false
            color_planned = false
        elseif spell:match("guard") or spell:match("brill") or spell:match("419") then
            blur_planned  = false
            color_planned = false
        elseif spell:match("color") or spell:match("611") then
            blur_planned  = false
            guard_planned = false
        else
            echo("Selecting spell of [" .. spell .. "] failed to match")
        end
    elseif a:match("^espchannel=") then
        esp_channel = arg:gsub("^[Ee][Ss][Pp][Cc][Hh][Aa][Nn][Nn][Ee][Ll]=", "")
    elseif a:match("^lnetchannel=") then
        lnet_channel = arg:gsub("^[Ll][Nn][Ee][Tt][Cc][Hh][Aa][Nn][Nn][Ee][Ll]=", "")
    end
end

-- ---------------------------------------------------------------------------
-- Room info (for announcements)
-- ---------------------------------------------------------------------------

local room        = Room.current()
local room_title  = GameState.room_name or ""
local room_loc    = (room and room.location) or nil

-- Strip [ ] brackets from room title (matches Lich5 original)
room_title = room_title:gsub("%[", ""):gsub("%]", "")

-- ---------------------------------------------------------------------------
-- Determine spells to cast
-- ---------------------------------------------------------------------------

local blur_cycle  = nil
local guard_cycle = nil
local color_cycle = nil

if Spell[911].known and blur_planned then
    blur_cycle  = math.floor(250 / (20 + (Spells.wizard or 0))) + 1
    echo("Casting Blurs " .. blur_cycle .. " times!")
end
if Spell[419].known and guard_planned then
    guard_cycle = math.floor(250 / (20 + (Spells.minorelemental or 0))) + 1
    echo("Casting Guards " .. guard_cycle .. " times!")
end
if Spell[611].known and color_planned then
    color_cycle = math.floor(250 / (20 + (Spells.ranger or 0))) + 1
    echo("Casting Colors " .. color_cycle .. " times!")
end

if not blur_cycle and not guard_cycle and not color_cycle then
    echo("You do not appear to know any mass cast spells (611, 911, 419).  If this is not")
    echo("the case, please check that infomon is running, type skill and spell all, then run again.")
    exit()
end

-- Open group so others can join
fput("group open")

-- ---------------------------------------------------------------------------
-- Build announce text based on what is/isn't being cast
-- ---------------------------------------------------------------------------

local function build_what_msg(time_str)
    if blur_cycle and not guard_cycle and not color_cycle then
        return "Casting Blurs " .. time_str .. "! Please add Guards or Colors if you can!"
    elseif guard_cycle and not blur_cycle and not color_cycle then
        return "Casting Guards " .. time_str .. "! Please add Blurs or Colors if you can!"
    elseif blur_cycle and guard_cycle and not color_cycle then
        return "Casting Blurs and Guards " .. time_str .. "! Please add Colors if you can!"
    elseif color_cycle and not blur_cycle and not guard_cycle then
        return "Casting Colors " .. time_str .. "! Please add Blurs or Guards if you can!"
    elseif blur_cycle and color_cycle and not guard_cycle then
        return "Casting Blurs and Colors " .. time_str .. "! Please add Guards if you can!"
    elseif guard_cycle and color_cycle and not blur_cycle then
        return "Casting Guards and Colors " .. time_str .. "! Please add Blurs if you can!"
    else
        return "Casting all mass spells " .. time_str .. "!"
    end
end

-- ---------------------------------------------------------------------------
-- Announce casting
-- ---------------------------------------------------------------------------

if block_announce then
    echo("Skipping announcements due to [now] parameter")
else
    local msg_2min = build_what_msg("in two minutes")
    local msg_30sec = build_what_msg("in 30 seconds")

    pause(1)

    -- 2-minute announcements: room + LNet + ESP
    if announce_room then
        fput("'=pronounce :loud " .. msg_2min)
    end
    if lnet_channel and room_loc and room_title ~= "" then
        local lnet_msg = msg_2min:gsub("in two minutes", "in two minutes in " .. room_loc .. " at " .. room_title)
        if LNet then
            LNet.send_message({ type = "channel", channel = lnet_channel }, lnet_msg)
        end
    end
    if esp_channel and room_loc and room_title ~= "" then
        local esp_msg = msg_2min:gsub("in two minutes", "in two minutes in " .. room_loc .. " at " .. room_title)
        fput("think on #[" .. esp_channel .. "] " .. esp_msg)
    end

    -- Countdown echoes
    pause(30)
    echo("90 seconds")
    pause(30)
    echo("60 seconds")
    pause(30)
    echo("30 seconds")

    -- 30-second room announcement
    if announce_room then
        fput("'=inform :loud " .. msg_30sec)
    end

    -- 10-second final warning
    pause(20)
    if announce_room then
        fput("recite Casting in 10 seconds, be joined!  Last call!")
    end

    pause(10)
end

-- ---------------------------------------------------------------------------
-- Cast spells
-- ---------------------------------------------------------------------------

if blur_cycle then
    local remaining = blur_cycle
    while remaining > 0 do
        if Spell[911]:affordable() then
            Spell[911]:cast()
            remaining = remaining - 1
            waitcastrt()
        else
            echo("You need more mana to continue, ask for it or use an ability!")
            pause(3)
        end
    end
end

if guard_cycle then
    local remaining = guard_cycle
    while remaining > 0 do
        if Spell[419]:affordable() then
            Spell[419]:cast()
            remaining = remaining - 1
            waitcastrt()
        else
            echo("You need more mana to continue, ask for it or use an ability!")
            pause(3)
        end
    end
end

if color_cycle then
    local remaining = color_cycle
    while remaining > 0 do
        if Spell[611]:affordable() then
            Spell[611]:cast()
            remaining = remaining - 1
            waitcastrt()
        else
            echo("You need more mana to continue, ask for it or use an ability!")
            pause(3)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Report completion and wait for group to finish before disbanding
-- ---------------------------------------------------------------------------

if announce_room then
    fput("recite that should be four hours!  Stay safe!")
    echo("You are done casting.  Use ;u masscomm to unpause this script when everyone")
    echo("else is done casting and you are ready to disband the group!")
    pause_script(Script.name)
    pause(1)
    fput("disband")
    fput("group open")
end
