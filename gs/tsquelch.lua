--- @revenant-script
--- name: tsquelch
--- version: 2.3
--- author: Tysong
--- game: gs
--- description: Event squelching for EG fishing/digging, Duskruin, pawnshop, Reim
--- tags: EG,digging,ebon gate,squelching,squelch,fishing
---
--- Changelog (from Lich5):
---   v2.3 (2025-11-03) - wrap into TSquelch namespace
---   v2.2 (2022-10-05) - EG 2022 update
---   v2.1 (2021-02-16) - Added Duskruin arena/scripmaster
---   v2.0 (2018-10-13) - Rewrote regex for less greedy matching

--------------------------------------------------------------------------------
-- Room lists (Lich room IDs)
--------------------------------------------------------------------------------

local Rooms_Fishing   = { 32116, 32117, 32118, 32123, 32124, 32125, 32126, 32127, 32128, 32120, 32121, 32122 }
local Rooms_Digging   = { 26583, 26585, 26584, 26579, 26577, 26576, 26575, 26574, 26573, 26572, 26439, 26578, 26580, 26581, 26586, 26587, 26588, 26582, 25577, 25573, 25574, 25578, 25562, 25563, 25564, 25565, 25551, 25552, 25550, 25549, 25553, 25569, 25570, 25572, 25555, 25575, 25561, 25567, 25566, 25568, 25554, 25571, 25576 }
local Rooms_Tidepools = { 26531, 27558, 27559, 27557 }
local Rooms_Eelbeds   = { 26593, 27564, 27565, 27566 }
local Rooms_Fishpits  = { 26591, 27572, 27573, 27571 }
local Rooms_Duskruin  = { 26387, 23780, 23798 }
local Rooms_Pawnshop  = { 408, 12306 }
local Rooms_Balloons  = { 27560, 27561, 27562, 27563 }
local Rooms_WaterCannons = { 27574, 27577, 27575, 27576 }
local Rooms_WhackyEels = { 27567, 27569, 27568, 27570 }

-- Combine all squelchable rooms
local ALL_SQUELCH_ROOMS = {}
local function add_rooms(list)
    for _, r in ipairs(list) do ALL_SQUELCH_ROOMS[r] = true end
end
add_rooms(Rooms_Fishing)
add_rooms(Rooms_Digging)
add_rooms(Rooms_Tidepools)
add_rooms(Rooms_Eelbeds)
add_rooms(Rooms_Fishpits)
add_rooms(Rooms_Duskruin)
add_rooms(Rooms_Pawnshop)
add_rooms(Rooms_Balloons)
add_rooms(Rooms_WaterCannons)
add_rooms(Rooms_WhackyEels)

local function room_in(list)
    local room = Room.current()
    if not room then return false end
    for _, r in ipairs(list) do
        if room.id == r then return true end
    end
    return false
end

local function in_squelch_zone()
    local room = Room.current()
    return room and ALL_SQUELCH_ROOMS[room.id]
end

--------------------------------------------------------------------------------
-- Squelch patterns (simplified for Revenant -- match other players' actions)
--------------------------------------------------------------------------------

-- General patterns: other players arriving, leaving, rummaging, stowing
local GENERAL_RX = Regex.new(table.concat({
    "<a exist=\"-\\d+\".*?just arrived",
    "<a exist=\"-\\d+\".*?just went",
    "<a exist=\"-\\d+\".*?rummages",
    "<a exist=\"-\\d+\".*?removes.*?from in",
    "<a exist=\"-\\d+\".*?put.*?in",
    "<a exist=\"-\\d+\".*?brushes",
    "<a exist=\"-\\d+\".*?stands up",
    "<a exist=\"-\\d+\".*?joins",
    "<a exist=\"-\\d+\".*?gestures",
    "<a exist=\"-\\d+\".*?renews",
    "<a exist=\"-\\d+\".*?skillfully begins",
    "<a exist=\"-\\d+\".*?drops",
    "You notice <a exist=\"-\\d+\".*?moving stealthily",
    "You hear very soft footsteps",
}, "|"))

-- Fishing-specific patterns
local FISHING_RX = Regex.new(table.concat({
    "tip of <a exist=\".*?\" noun=\".*?\">.*?</a>.*?suddenly bends",
    "takes in some of the slack",
    "leans back and lets? the line",
    "tugs sharply on",
    "gives.*?one final tug",
    "zigzags back and forth wildly",
    "bends sharply several times",
    "line suddenly twists and then breaks",
    "weaves wildly and bends",
    "whips back and forth wildly",
    "dips down a bit and proceeds to twitch",
    "reels.*?completely",
    "uncoils a bit of",
    "strings.*?on",
    "swiftly re-strings",
}, "|"))

-- Digging-specific patterns
local DIGGING_RX = Regex.new(table.concat({
    "digs in with.*?shovel",
    "hits something hard in the sand",
    "begins to dig with.*?shovel",
    "reaches down to see what",
    "pulls.*?from the sand",
    "breaks apart.*?something falls",
    "busts apart.*?something falls",
    "plucks the petals",
    "brushes off.*?charcoal",
    "tosses.*?to the ground, causing it to shatter",
    "picks through.*?something falls",
    "rips apart.*?something falls",
    "reaches inside.*?breaks it apart",
    "foul smell|rancid smell|scent of a freshly plucked",
    "wrings.*?hands",
    "picks bits of flesh",
}, "|"))

-- Duskruin patterns
local DUSKRUIN_RX = Regex.new(table.concat({
    "escorted in from the dueling sands",
    "throws away.*?package",
    "opened an.*?arena winnings package",
    "tosses aside.*?package",
    "picks up an.*?arena winnings package",
    "just surrendered to",
    "empty the contents of.*?package",
    "grabs a.*?voucher booklet",
    "escorted into one of the arenas",
}, "|"))

--------------------------------------------------------------------------------
-- Hook
--------------------------------------------------------------------------------

local HOOK_NAME = "tsquelch_silence"

local function install_hook()
    DownstreamHook.add(HOOK_NAME, function(line)
        if not line then return line end

        if room_in(Rooms_Fishing) and (GENERAL_RX:test(line) or FISHING_RX:test(line)) then
            return nil
        elseif room_in(Rooms_Digging) and (GENERAL_RX:test(line) or DIGGING_RX:test(line)) then
            return nil
        elseif room_in(Rooms_Tidepools) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_Eelbeds) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_Fishpits) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_Duskruin) and (GENERAL_RX:test(line) or DUSKRUIN_RX:test(line)) then
            return nil
        elseif room_in(Rooms_Pawnshop) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_Balloons) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_WaterCannons) and GENERAL_RX:test(line) then
            return nil
        elseif room_in(Rooms_WhackyEels) and GENERAL_RX:test(line) then
            return nil
        end

        return line
    end)
end

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

--------------------------------------------------------------------------------
-- Main loop: install/remove hook based on room
--------------------------------------------------------------------------------

echo("TSquelch active. Squelching enabled in event areas.")

local hook_active = false

while true do
    if in_squelch_zone() then
        if not hook_active then
            install_hook()
            hook_active = true
        end
        -- Wait until we leave
        while in_squelch_zone() do pause(1) end
        DownstreamHook.remove(HOOK_NAME)
        hook_active = false
    end
    pause(1)
end
