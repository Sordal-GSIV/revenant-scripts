--- @revenant-script
--- name: find-darkbox
--- version: 1.0
--- author: Kynevaar Maeramil (original Lich5), elanthia-online (Revenant port)
--- game: dr
--- description: Find and continuously play the Hollow Eve Darkbox - navigates rooms, handles loot, healing, and banking
--- tags: hollow-eve, darkbox, game, festival
--- @lic-certified: complete 2026-03-19
---
--- Original: find-darkbox.lic (https://elanthipedia.play.net/Lich_script_repository#find-darkbox)
--- Converted to Revenant Lua with full feature parity.
---
--- Usage: find-darkbox [override]
---   override  Use remedies instead of herbs if herbs are defined in yaml and passed to heal-remedy

-- Parse args
local override = Script.vars[1] and Script.vars[1]:lower():find("override") ~= nil

-- Load settings
local settings = get_settings()
local darkbox_stop_on_wounded  = settings.darkbox_stop_on_wounded
local he_use_herbs_remedies    = settings.he_use_herbs_remedies
local hollow_eve_loot_container = settings.hollow_eve_loot_container
local worn_trashcan            = settings.worn_trashcan
local worn_trashcan_verb       = settings.worn_trashcan_verb

-- Build compiled trash-item regex list (word-boundary, case-insensitive, mirrors Ruby /\bX\b/i)
local trash_regexes = {}
if settings.hollow_eve_junk then
    for _, x in ipairs(settings.hollow_eve_junk) do
        trash_regexes[#trash_regexes + 1] = Regex.new("(?i)\\b" .. x .. "\\b")
    end
end

local function is_trash(item_name)
    for _, re in ipairs(trash_regexes) do
        if re:test(item_name) then return true end
    end
    return false
end

-- Stop roomnumbers script if running; restart it on exit
if running("roomnumbers") then
    Script.kill("roomnumbers")
    before_dying(function()
        Script.run("roomnumbers")
    end)
end

-- Room list: all known Darkbox spawn locations at Hollow Eve festival
local rooms = {
    16150, 16153, 16154, 16276, 16277, 16278, 16290, 16291, 16292, 16293,
    16294, 16295, 16296, 16159, 16161, 16166, 16169, 16174, 16185, 16217,
    16221, 16224, 16226, 16227, 16235, 16188, 16195, 16203, 16204, 16205,
    16208, 16238, 16240, 16241, 16242, 16244, 16248, 16249, 16263,
    16264, 16267, 16268, 16318, 16256, 16257,
}

fput("stop play") -- In case you were playing a song

-- Resume from last known Darkbox room (rotate room list to start there)
local last_room = UserVars.last_darkbox and tonumber(UserVars.last_darkbox)
if last_room then
    local idx = nil
    for i, id in ipairs(rooms) do
        if id == last_room then idx = i; break end
    end
    if idx then
        local rotated = {}
        for i = idx, #rooms do rotated[#rotated + 1] = rooms[i] end
        for i = 1,   idx - 1 do rotated[#rotated + 1] = rooms[i] end
        rooms = rotated
    end
end

-- Search for the Darkbox: check current room first, then walk to each candidate room
for _, id in ipairs(rooms) do
    if reget(5, "You try, but") then pause(20) end

    local found = false
    local objs = DRRoom and DRRoom.room_objs or {}
    for _, obj in ipairs(objs) do
        if obj:find("Darkbox") then found = true; break end
    end
    if found then break end

    DRCT.walk_to(id)
end

-- Store current room as last-known Darkbox location
UserVars.last_darkbox = tostring(Map.current_room() or "")

-- Set up event flags
Flags.add("darkbox-drop",    "Your .* falls to the ground")
Flags.add("darkbox-gone",    "Without warning, the Darkbox simply vanishes")
Flags.add("darkbox-wounded", "Your injury increases the difficulty of the game, but you press on")
Flags.add("darkbox-no-money", "realize you don't have the 200 Kronars")

-- Cleanup flags on script exit
before_dying(function()
    Flags.delete("darkbox-drop")
    Flags.delete("darkbox-gone")
    Flags.delete("darkbox-wounded")
    Flags.delete("darkbox-no-money")
end)

-- Main play loop
local done = false
while not done do
    -- Check if Darkbox has vanished
    if Flags["darkbox-gone"] then
        UserVars.last_darkbox = nil
        break
    end

    Flags.reset("darkbox-drop")
    DRC.fix_standing()

    -- Optionally stop if wounded flag tripped
    if darkbox_stop_on_wounded and Flags["darkbox-wounded"] then break end

    fput("play darkbox")
    pause(1)

    -- Detect "not at a darkbox" (game asking what song instead)
    if reget(5, "What type of song did you want to play?") then
        DRC.message("*** Darkbox not found in any of the rooms! ***")
        done = true
        break
    end

    -- Handle being out of money: walk to bank, withdraw, return
    if Flags["darkbox-no-money"] then
        DRC.message("*** You are out of money. Heading to bank to get more! ***")
        DRCT.walk_to(16315)
        local bank_result = DRC.bput("withdraw 3 platinum",
            "we are not lending money at this time",
            "The clerk counts out")
        if bank_result:find("we are not lending money at this time") then
            done = true
            break
        end
        fput("balance")
        Flags.reset("darkbox-no-money")
        local return_room = UserVars.last_darkbox and tonumber(UserVars.last_darkbox)
        if return_room then DRCT.walk_to(return_room) end
    end

    -- Handle wounds making it impossible to play
    if reget(10, "your wounds make it impossible") then
        if he_use_herbs_remedies then
            if override then
                DRC.wait_for_script_to_complete("heal-remedy", {"quick", "override"})
            else
                DRC.wait_for_script_to_complete("heal-remedy", {"quick"})
            end
            if reget(3, "What were") then
                DRC.message("*** Out of herbs or remedies! Seek out more or an Empath! ***")
                done = true
                break
            end
            pause(65) -- Wait for herbs to take effect before resuming
        else
            done = true
            break
        end
    end

    -- Process items won from Darkbox: trash junk, coil rope, stow prizes
    local hands = { DRC.right_hand(), DRC.left_hand() }
    for _, in_hand in ipairs(hands) do
        if in_hand then
            if is_trash(in_hand) then
                DRCI.dispose_trash(in_hand, worn_trashcan, worn_trashcan_verb)
            else
                -- Coil rope so it can be stored
                if in_hand:find("rope") then
                    fput("coil my " .. in_hand)
                end
                if not DRCI.put_away_item(in_hand, hollow_eve_loot_container) then
                    DRC.message("*** The item is either too big to fit or no more room in the container(s)! ***")
                    DRC.beep()
                    done = true
                    break
                end
            end
        end
    end

    if not done then waitrt() end
end

-- Return to Hollow Eve entrance
DRCT.walk_to(16150)
