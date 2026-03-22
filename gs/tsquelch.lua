--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: tsquelch
--- version: 2.3
--- author: Tysong (horibu on PC)
--- original: https://github.com/elanthia-online/scripts/
--- game: gs
--- description: Event squelching for EG fishing/digging, Duskruin, pawnshop, Reim, and more
--- tags: EG,digging,ebon gate,squelching,squelch,fishing
---
--- Changelog (from Lich5):
---   v2.3 (2025-11-03) - wrap into TSquelch namespace
---   v2.2 (2022-10-05) - EG 2022 update
---   v2.1 (2021-02-16) - Added Duskruin arena/scripmaster
---   v2.0 (2018-10-13) - Rewrote regex for less greedy matching
---   v1.4 (2018-10-06) - Added extra fish pits, tide pools, and eel bed rooms
---   v1.3 (2017-10-12) - Added EG Game - Tidepools, Eel Beds, Fish Pits
---   v1.2 (2017-10-11) - Corrected a few regex matches
---   v1.1 (2017-10-08) - Code/Regex cleanup
---   v1.0 (2017-10-08) - Initial Release

--------------------------------------------------------------------------------
-- Room lists
--------------------------------------------------------------------------------

local Rooms_Fishing      = { 32116, 32117, 32118, 32123, 32124, 32125, 32126, 32127, 32128, 32120, 32121, 32122 }
local Rooms_Digging      = { 26583, 26585, 26584, 26579, 26577, 26576, 26575, 26574, 26573, 26572, 26439, 26578, 26580, 26581, 26586, 26587, 26588, 26582, 25577, 25573, 25574, 25578, 25562, 25563, 25564, 25565, 25551, 25552, 25550, 25549, 25553, 25569, 25570, 25572, 25555, 25575, 25561, 25567, 25566, 25568, 25554, 25571, 25576 }
local Rooms_Tidepools    = { 26531, 27558, 27559, 27557 }
local Rooms_Eelbeds      = { 26593, 27564, 27565, 27566 }
local Rooms_Fishpits     = { 26591, 27572, 27573, 27571 }
local Rooms_Duskruin     = { 26387, 23780, 23798 }
local Rooms_Pawnshop     = { 408, 12306 }
local Rooms_Balloons     = { 27560, 27561, 27562, 27563 }
local Rooms_WaterCannons = { 27574, 27577, 27575, 27576 }
local Rooms_WhackyEels   = { 27567, 27569, 27568, 27570 }

-- Reim rooms (defined for completeness; squelch support TBD per original author's TODO)
local Reim_Village   = { 24888, 24900, 24904, 24909, 24935, 24936, 24912, 24919, 24946, 24945, 24952, 24964, 24971, 24972, 24958, 24959, 24931, 24932, 24966, 24953, 25300, 24901, 24930, 23484, 24941, 23650 }
local Reim_Road      = { 24977, 24978, 24989, 24990, 24991, 24994, 24995, 24996, 24998, 25003, 25004, 25020, 25019, 25021, 24997, 25022, 25029, 25030, 25035, 25042, 25047, 25046, 25043, 25041, 25048, 25049, 25050, 25051, 25052, 25053, 25054, 25056, 25057, 25058, 25059, 25064, 25055, 25060, 25061, 25062, 25063 }
local Reim_Courtyard = { 25104, 25103, 25101, 25100, 25105, 25102, 25106, 25107, 25108, 25099, 25098, 25097, 25069, 25068, 25070, 25071, 25072, 25082, 25084, 25083, 25081, 25078, 25085, 25086, 25087, 25088, 25096, 25095, 25094, 25093, 25092, 25091, 25090, 25089, 25080, 25079, 25077, 25075, 25073, 25076, 25074, 25067, 25066, 25065 }
local Reim_Servant   = { 25113, 25114, 25115, 25119, 25118, 25117, 25116, 25112, 25111, 25110, 25109 }
local Reim_Visitor   = { 25125, 25124, 25123, 25129, 25128, 25127, 25126, 25122, 25121, 25120 }
local Reim_Royal     = { 25141, 25140, 25132, 25134, 25136, 25135, 25137, 25138, 25139, 25133, 25131, 25130 }
local Reim_MiscAreas = { 24965 }

-- Combined squelch room set (Reim not included until NPC patterns are finalized)
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
-- Debug support (mirrors Lich5 UserVars.tsquelch[:debug_my_script])
--------------------------------------------------------------------------------

UserVars.tsquelch = UserVars.tsquelch or {}
if UserVars.tsquelch.debug_my_script == nil then
    UserVars.tsquelch.debug_my_script = false
end

local function dbg(msg)
    if UserVars.tsquelch.debug_my_script then echo(msg) end
end

--------------------------------------------------------------------------------
-- General squelch patterns (other players' common actions)
-- Mirrors Lich5 TSquelch::General_Squelch
--------------------------------------------------------------------------------

local GENERAL_RX = Regex.new(table.concat({
    -- Rummaging / inventory handling
    [[<a exist="-\d+" noun="\w+">\w+</a> rummages through <a exist="-\d+" noun="\w+">\w+</a> things before tucking some seashells into <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="bucket">seashell bucket</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> rummages through <a exist="-\d+" noun="\w+">\w+</a> things\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> rummages around in <a exist="-\d+" noun="\w+">\w+</a> pockets\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tucks <a exist="\d+" noun="seashells">some indigo-black seashells</a> into <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="bucket">seashell bucket</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> removes <a exist="\d+" noun="[\w\-]+">[\w\s\-']+</a> from in <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="[\w\-]+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> removes \w+ <a exist="\d+" noun="[\w\-]+">[\w\s\-']+</a> [\w\s\-']*from in <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="[\w\-]+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> put <a exist="\d+" noun="\w+">[\w\s\-']+</a> in <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> put \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> in <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[With great effort <a exist="-\d+" noun="\w+">\w+</a> combines the value of <a exist="-\d+" noun="\w+">\w+</a> seashells\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gathers the remaining coins from inside <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gathers the remaining coins\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> grabs <a exist="\d+" noun="\w+">[\w\s\-']+</a> from inside the <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> grabs \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> from inside the <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> grabs \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> from inside <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> grabs \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> from one of the small[\w\s\-']*pouches lining the inside of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> draws \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> from one of the weapon loops sewn inside of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> slips \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> into one of the weapon loops sewn inside of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tucks \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> into a small pocket inside of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tucks \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> into one of the [\w\s\-']+ lining the inside of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> absent-mindedly drops \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> into <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> drops \w+ <a exist="\d+" noun="\w+">[\\w\s\-]+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> slings \w+ <a exist="\d+" noun="\w+">[\\w\s\-]+</a> over <a exist="-\d+" noun="\w+">\w+</a> shoulder\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> brushes <a exist="-\d+" noun="\w+">(?:himself|herself)</a> off\.]],
    -- Movement
    [[<a exist="-\d+" noun="\w+">\w+</a> just arrived\.]],
    [[<a exist="-\d+" noun="\w+">\w+'s</a> group just arrived\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just went <d cmd='go \w+'>\w+</d>\.]],
    [[<a exist="-\d+" noun="\w+">\w+'s</a> group just went <d cmd='go \w+'>\w+</d>]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just climbed up a <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just handed <a exist="-\d+" noun="\w+">\w+</a> some coins\.]],
    [[You notice <a exist="-\d+" noun="\w+">\w+</a> moving stealthily \w+\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just moved quietly <d cmd='go \w+'>\w+</d>, with <a exist="-\d+" noun="\w+">\w+</a> group following closely]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just moved quietly into the room, <a exist="-\d+" noun="\w+">\w+</a> group following closely\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> strides away moving <d cmd='go \w+'>\w+</d>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> strides away moving <d cmd='go \w+'>\w+</d>, <a exist="-\d+" noun="\w+">\w+</a> group following close behind\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just strode in, <a exist="-\d+" noun="\w+">\w+</a> group following close behind\.]],
    -- Social / grouping
    [[<a exist="-\d+" noun="\w+">\w+</a> joins <a exist="-\d+" noun="\w+">\w+'s</a> group\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> adds <a exist="-\d+" noun="\w+">\w+</a> to <a exist="-\d+" noun="\w+">\w+</a> group\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> offers <a exist="-\d+" noun="\w+">\w+</a> \w+ <a exist="\d+" noun="\w+">[\\w\s\-]+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> accepts <a exist="-\d+" noun="\w+">\w+'s</a> <a exist="\d+" noun="\w+">[\\w\s\-]+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> stands up\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> reaches out and holds <a exist="-\d+" noun="\w+">\w+'s</a> hand\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> clasps <a exist="-\d+" noun="\w+">\w+'s</a> hand tenderly\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gently takes hold of <a exist="-\d+" noun="\w+">\w+'s</a> hand\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gobbles down a big bite of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\\w\s\-]+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gobbles down <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\\w\s\-]+</a> in one enormous bite\.]],
    [[You hear very soft footsteps\.]],
}, "|"))

--------------------------------------------------------------------------------
-- Spell squelch patterns (other players' spell casting and buff effects)
-- Mirrors Lich5 TSquelch::Spells_Squelch
--------------------------------------------------------------------------------

local SPELLS_RX = Regex.new(table.concat({
    -- Casting actions
    [[<a exist="-\d+" noun="\w+">\w+</a> gestures\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gestures at <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> makes a complex gesture at <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gestures crisply and utters a practiced phrase as raw elemental energies issue forth from <a exist="-\d+" noun="\w+">\w+</a> dimly glowing eyes\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> gestures while calling upon the lesser spirits for aid\.\.\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> traces a sign while petitioning the spirits for cognition\.\.\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> traces a simple symbol as <a exist="-\d+" noun="\w+">\w+</a> reverently calls upon the power of <a exist="-\d+" noun="\w+">\w+</a> patron\.\.\.]],
    [[With an indolent gesture, <a exist="-\d+" noun="\w+">\w+</a> languidly traces a rune in the air\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> whispers the words to <a exist="-\d+" noun="\w+">\w+</a> spell, tracing <a exist="-\d+" noun="\w+">\w+</a> fingers across the sky\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> speaks a quiet phrase in flowing elven\.\.\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> recites a series of mystical phrases while raising <a exist="-\d+" noun="\w+">\w+</a> hands\.\.\.]],
    [[<a exist="-\d+" noun="\w+">\w+'s</a> face is bathed in a serene countenance as <a exist="-\d+" noun="\w+">\w+</a> recites\.\.\.]],
    [[A haze of black mist gathers around <a exist="-\d+" noun="\w+">\w+</a> as <a exist="-\d+" noun="\w+">\w+</a> prepares a spell\.\.\.]],
    [[Tiny colorful twinkling motes gather in the palm of <a exist="-\d+" noun="\w+">\w+'s</a> hand as <a exist="-\d+" noun="\w+">\w+</a> prepares a spell\.\.\.]],
    [[Reciting the mystical phrases of <a exist="-\d+" noun="\w+">\w+</a> elemental spell, a rime of frost suddenly encircles <a exist="-\d+" noun="\w+">\w+'s</a> blue eyes]],
    -- Bard skills
    [[<a exist="-\d+" noun="\w+">\w+</a> renews <a exist="-\d+" noun="\w+">\w+</a> songs\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> skillfully begins to weave another verse into <a exist="-\d+" noun="\w+">\w+</a> harmony\.]],
    [[<a exist="-\d+" noun="\w+">\w+'s</a> <a exist="\d+" noun="\w+">sonic [\w\-]+</a> dissipates\.]],
    [[With great skill, <a exist="-\d+" noun="\w+">\w+</a> removes one of the chords from <a exist="-\w+" noun="\w+">\w+</a> harmony while maintaining the symmetry of those that remain\.]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> sings, a squall of wind briefly swirls about <a exist="-\d+" noun="\w+">\w+</a>\.]],
    -- Spell abjurations
    [[<a exist="-\d+" noun="\w+">\w+</a> summons a torrent of \w+ and \w+ mana and releases upon <a exist="-\d+" noun="\w+">\w+</a> a flurry of abjurations\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> summons a torrent of elemental mana and releases upon <a exist="-\d+" noun="\w+">\w+</a> a flurry of abjurations\.]],
    -- Buff/debuff effects on others
    [[Dark red droplets coalesce upon <a exist="-\d+" noun="\w+">\w+'s</a> skin and upon others in <a exist="-\d+" noun="\w+">\w+</a> group\.]],
    [[Dark red droplets seep out of <a exist="-\d+" noun="\w+">\w+'s</a> skin and evaporate\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> and <a exist="-\d+" noun="\w+">\w+</a> group appear more confident\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> becomes solid again\.]],
    [[A brilliant aura surrounds <a exist="-\d+" noun="\w+">\w+'s</a> group\.]],
    [[The brilliant aura fades away from <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> looks less calm and refreshed than a moment ago\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> looks much more calm and refreshed\.]],
    [[<a exist="-\d+" noun="\w+">\w+'s</a> movements no longer appear to be influenced by a divine power as the spiritual force fades from around \w+ arms\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> suddenly stops moving light-footedly\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> suddenly appears less powerful]],
    [[<a exist="-\d+" noun="\w+">\w+</a> suddenly looks more powerful\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> suddenly disappears\.]],
    [[The mote of white light next to <a exist="-\d+" noun="\w+">\w+</a> disappears]],
    [[The brilliant green veins within <a exist="-\d+" noun="\w+">\w+'s</a> eyes fade as <a exist="-\d+" noun="\w+">\w+</a> posture becomes noticeably more relaxed\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> looks considerably more imposing\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> appears considerably more powerful\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> appears less confident\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> seems a bit weaker than before\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> seems less resolute\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> seems slightly different\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> seems hesitant, looking unsure of <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> seems to slow down and become a bit less nimble\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> and <a exist="-\d+" noun="\w+">\w+</a> group seem to slow down and become a bit less nimble\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> begins to breathe more deeply\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> begins to breathe less deeply\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> stands taller, as if bolstered with a sense of confidence\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> relaxes and no longer maintains the Whirling Dervish Stance\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> settles into the Whirling Dervish stance\.]],
    -- Auras and visual effects
    [[A light blue glow surrounds <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[A deep blue glow surrounds <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[A misty halo surrounds <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[A dim aura surrounds <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> body is surrounded by a dim dancing aura\.]],
    [[The mirror images surrounding <a exist="-\d+" noun="\w+">\w+</a> undulate and grow stronger\.]],
    [[The translucent sphere fades from around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The shimmering aura fades from around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The brilliant luminescence fades from around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The silvery luminescence fades from around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The bright luminescence fades from around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The mana around <a exist="-\d+" noun="\w+">\w+</a> continues to gracefully swirl and move\.]],
    [[Eyes widening momentarily, <a exist="-\d+" noun="\w+">\w+</a> gazes into the distance before adopting a thoughtful expression\.]],
    [[A cankerous ripple of vesicles temporarily disfigures <a exist="-\d+" noun="\w+">\w+'s</a> face and travels down]],
    [[A series of hazel lines spirals outward from the center of <a exist="-\d+" noun="\w+">\w+'s</a> forehead, but quickly fade away\.]],
}, "|"))

--------------------------------------------------------------------------------
-- Fishing-specific squelch patterns
-- Mirrors Lich5 TSquelch::Fishing_Squelch (beyond General)
--------------------------------------------------------------------------------

local FISHING_RX = Regex.new(table.concat({
    [[The tip of <a exist=".*" noun=".*">.*</a> <a exist=".*">.*</a> suddenly bends alarmingly as \w+ fights to bring \w+ catch in!]],
    [[<a exist=".*" noun=".*">.*</a> takes in some of the slack from <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a>\.]],
    [[<a exist=".*" noun=".*">.*</a> leans back and (?:let|lets) the line of <a exist=".*" noun=".*">.*</a> <a exist=".*" noun=".*">.*</a> go with a sharp \*WHOOSH!\*]],
    [[<a exist=".*" noun=".*">.*</a> tugs sharply on <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a> and it]],
    [[<a exist=".*" noun=".*">.*</a> gives <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a> one final tug and (?:a|an) <a exist=".*" noun=".*">.*</a> comes wriggling to the surface!]],
    [[<a exist=".*" noun=".*">.*</a> <a exist=".*" noun=".*">.*</a> shakes and twitches as (?:its|it's) tip bends down quite far!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> zigzags back and forth wildly]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> bends sharply several times]],
    [[<a exist=".*" noun=".*">.*'s</a> line suddenly twists and then breaks with a sharp, poignant \*SNAP\*!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> weaves wildly and bends a bit!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> whips back and forth wildly!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> dips down a bit and proceeds to twitch visibly!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> wavers frantically and makes sharp zigzag motions!]],
    [[<a exist=".*" noun=".*">.*'s</a> <a exist=".*" noun=".*">.*</a> dips visibly in a sharp curve as the catch on the end frantically]],
    [[<a exist=".*" noun=".*">.*</a> uncoils a bit of (?:line|wire) from <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a> and snaps it off swiftly\.]],
    [[<a exist=".*" noun=".*">.*</a> strings <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a> on <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a>\.]],
    [[<a exist=".*" noun=".*">.*</a> swiftly re-strings <a exist=".*" noun=".*">\w+</a> <a exist=".*" noun=".*">.*</a>]],
    [[<a exist=".*" noun=".*">.*</a> reels <a exist=".*" noun=".*">(?:her|his)</a> <a exist=".*" noun=".*">.*</a> in completely]],
    [[A thick indigo mist bubbles up from the <a exist=".*" noun=".*">.*</a> and slithers rapidly toward <a exist=".*" noun=".*">.*</a>]],
    [[The tip of <a exist=".*" noun=".*">.*</a> <a exist=".*" noun=".*">.*</a> suddenly dips slightly and <a exist=".*" noun=".*">\w+</a> swiftly gives it a tug to set the hook!]],
    -- Bait/rod storage in fishing areas
    [[<a exist=".*" noun=".*">.*</a> put a <a exist=".*" noun="(?:rod|pole|wire|line|weight|squid|bait|lure|maggot|minnow|lyretail|knife|ragworm|ballyhoo|nightcrawler)">.*</a> in <a exist=".*" noun=".*">\w+</a>]],
    [[<a exist=".*" noun=".*">.*</a> removes a <a exist=".*" noun="(?:rod|pole|wire|line|weight|squid|bait|lure|maggot|minnow|lyretail|knife|ragworm|ballyhoo|nightcrawler)">.*</a>.*from in <a exist=".*" noun=".*">\w+</a>]],
}, "|"))

--------------------------------------------------------------------------------
-- Digging-specific squelch patterns (ambient + player actions)
-- Mirrors Lich5 TSquelch::Digging_Squelch (beyond General)
--------------------------------------------------------------------------------

local DIGGING_RX = Regex.new(table.concat({
    -- Atmospheric/ambient descriptions unique to EG black sand beach
    [[For a moment, you think you see the black sands at your feet form into dozens of hands]],
    [[Massive, dark shapes rise up from the depths offshore, releasing plumes of droplets upwards in a powerful spray\.]],
    [[Waves crash against the black sands\.]],
    [[A pod of orcas surfaces just offshore, calling out plaintively in high-pitched tones]],
    [[A large orca, flanked by his mate, rushes headlong through the surf]],
    [[A wave crashes across the black sands and then washes back into the sea, leaving behind a stark set of footprints]],
    [[Sudden silence fills the air weighing thick and heavy on you as if with a great pressure]],
    [[Mists swirl across the black sands of the shoreline creating intricate patterns]],
    [[Tendrils of mist creep from the cold, damp ground, slowly cooking off in the midafternoon sun\.]],
    [[Seawater rushes up the beach from a nearby crashing wave\.]],
    [[A tiny hermit crab scuttles across the black sands as if fleeing some unseen foe\.]],
    -- Smell/residue effects on other players
    [[The foul smell lingering on <a exist="-\d+" noun="\w+">\w+</a> fades away\.]],
    [[The scent of a freshly plucked flower lingers around <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[A putrid smell lingers on <a exist="-\d+" noun="\w+">\w+</a>\.]],
    [[The rancid smell coming from <a exist="-\d+" noun="\w+">\w+</a> taints the air\.]],
    [[The remaining amount of slime on <a exist="-\d+" noun="\w+">[\w']+</a> hand drips off\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> wrings <a exist="-\d+" noun="\w+">\w+</a> hands and wipes them off\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> picks bits of flesh out from between <a exist="-\d+" noun="\w+">\w+</a> fingers\.]],
    -- Digging actions
    [[<a exist="-\d+" noun="\w+">\w+</a> digs in with <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="shovel">shovel</a>, flinging the sand aside\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> begins to dig with <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="shovel">shovel</a>, tossing the sand aside\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> hits something hard in the sand with <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="shovel">shovel</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> hits something hard in the sand, causing <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="shovel">shovel</a> to break\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> reaches down to see what <a exist="-\d+" noun="\w+">\w+</a> found]],
    [[<a exist="-\d+" noun="\w+">\w+</a> reaches down to see what destroyed]],
    [[<a exist="-\d+" noun="\w+">\w+</a> pulls \w+ <a exist="\d+" noun="\w+">[\w\s\-']+</a> from the sand\.]],
    -- Breaking apart objects (excrement, flesh, sandstone, charcoal, rose, rock, muck, etc.)
    [[As <a exist="-\d+" noun="\w+">\w+</a> breaks apart <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, something falls to the ground\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> breaks apart <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, causing whatever they were encrusting to fall to the ground\.]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> busts apart <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, something falls to the ground\.]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> plucks the petals on <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="rose">black rose</a>, something from inside the]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> brushes off <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="charcoal">lump of charcoal</a>, it falls apart]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> reaches inside <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a> and breaks it apart]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> reaches inside <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, <a exist="-\d+" noun="\w+">\w+</a> is able to dislodge something]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> rips apart <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, something falls to the ground\.]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> picks through <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, something falls to the ground]],
    [[As <a exist="-\d+" noun="\w+">\w+</a> picks through <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, it falls apart]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tosses <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a> to the ground, causing it to shatter, freeing whatever was inside\.]],
    -- Shovel/container management
    [[<a exist="-\d+" noun="\w+">\w+</a> tries to empty the contents of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">\w+</a> into <a exist="-\d+" noun="\w+">\w+</a>]],
    [[<a exist="-\d+" noun="\w+">\w+</a> opens the lid on <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a>, its hinges creaking noisily\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> lifts the lid on <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a> and sets it aside\.]],
    -- Bone-rattle sack (Duskruin carry-over)
    [[<a exist="-\d+" noun="\w+">\w+</a> slips a hand into the depths of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s]+</a> and places a]],
    [[<a exist="-\d+" noun="\w+">\w+</a> reaches into the depths of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s]+</a> and pulls out a]],
}, "|"))

--------------------------------------------------------------------------------
-- Tidepools-specific squelch patterns (NPC + fluff)
-- Mirrors Lich5 TSquelch::Tidepools_Squelch (beyond General)
--------------------------------------------------------------------------------

local TIDEPOOLS_RX = Regex.new(table.concat({
    [[.*hands over some coins to a barefoot pale human child and eagerly reaches into a jagged-edged dark crevasse]],
    [[A barefoot pale human child has a short word with <a exist=".*" noun=".*">.*</a>\.]],
    [[A barefoot pale human child heads over to <a exist=".*" noun=".*">.*</a> and speaks with <a exist=".*" noun=".*">(?:him|her)</a> briefly before handing <a exist=".*" noun=".*">(?:him|her)</a>]],
    [[Silver grey mist suddenly rolls through the cavern as it moves across the aggressively lapping water towards the sand\.]],
    [[A small hermit crab skitters out from the confines of a <a exist=".*" noun="crevasse">jagged-edged dark crevasse</a>]],
    [[Sniffing, .*the <a exist=".*" noun="child">child</a>.*runs the back of]],
    [["Come on up and try your hand at the Dank Crevasse of the Tidepools!"]],
    [[.*A <a exist=".*" noun="child">barefoot pale human child</a>.*whistles an out-of-tune ditty\.]],
    [[<a exist=".*" noun=".*">.*</a> approaches the <a exist=".*" noun="crevasse">dark crevasse</a> and then turns around, walking away from it\.]],
    [["Twenty, twenty-one, twenty-two," .*the <a exist=".*" noun="child">child</a>.*counts in an excited]],
    [[Hopping onto an <a exist=".*" noun="chest">iron-bound warped oak chest</a>, .*a <a exist=".*" noun="child">barefoot pale human child</a>]],
    [[Pushing around at the sand with .*his.*toes, .*a <a exist=".*" noun="child">barefoot pale human child</a>]],
    [[.*A <a exist=".*" noun="child">barefoot pale human child</a>.*walks over to the edge of a <a exist=".*" noun="crevasse">jagged-edged dark crevasse</a>]],
    [[Digging deep into .*his.*pocket, .*a <a exist=".*" noun="child">barefoot pale human child</a>.*pulls out a tiny pebble]],
}, "|"))

--------------------------------------------------------------------------------
-- Eel beds-specific squelch patterns (NPC + fluff)
-- Mirrors Lich5 TSquelch::Eelbeds_Squelch (beyond General)
--------------------------------------------------------------------------------

local EELBEDS_RX = Regex.new(table.concat({
    [[.*a plump-faced gnome child.*takes .*'s coins and grabs a slippery greyish green eel]],
    [[A plump-faced gnome child heads over to <a exist=".*" noun=".*">.*</a> and speaks with <a exist=".*" noun=".*">(?:him|her)</a> briefly before handing <a exist=".*" noun=".*">(?:him|her)</a>]],
    [[A plump-faced gnome child has a short word with <a exist=".*" noun=".*">.*</a>\.]],
    [[.*a <a exist=".*" noun="child">plump-faced gnome child</a>.*yells, "Come play with Morty for a chance at a prize!"]],
    [[<a exist=".*" noun=".*">.*</a> approaches the <a exist=".*" noun="bucket">oak-slatted bucket</a> and then turns around, walking away from it\.]],
    [[Whistling happily, .*a <a exist=".*" noun="child">plump-faced gnome child</a>]],
    [[Silvery grey mist tumbles out of the opening in the wall and travels with seeking fingers down a <a exist=".*" noun="rope">knotted hemp rope</a>]],
    [[Wiggling up the side of the <a exist=".*" noun="aquarium">aquarium</a>, a <a exist=".*" noun="eel">slippery greyish green eel</a>]],
    [[Using a small little skimmer, .*a <a exist=".*" noun="child">plump-faced gnome child</a>.*cleans the water that fills the <a exist=".*" noun="aquarium">aquarium</a>]],
}, "|"))

--------------------------------------------------------------------------------
-- Fish pits-specific squelch patterns (NPC + fluff)
-- Mirrors Lich5 TSquelch::Fishpits_Squelch (beyond General)
--------------------------------------------------------------------------------

local FISHPITS_RX = Regex.new(table.concat({
    [[Grinning from upon his crate, a scrawny half-krolvin lad takes .*'s coins, and they exchange a few words\.]],
    [[A scrawny half-krolvin lad heads over to <a exist=".*" noun=".*">.*</a> and speaks with <a exist=".*" noun=".*">(?:him|her)</a> briefly before handing <a exist=".*" noun=".*">(?:him|her)</a>]],
    [[A scrawny half-krolvin lad has a short word with <a exist=".*" noun=".*">.*</a>\.]],
    [[Rolling grey mist begins to flood the area, and .*a <a exist=".*" noun="lad">scrawny half-krolvin lad</a>.*watches it warily]],
    [[Drawing a deep breath, .*a <a exist=".*" noun="lad">scrawny half-krolvin lad</a>.*stands upon an .*iron-bound warped oak chest.*and begins to call out]],
    [["Step right up!" the .*half-krolvin lad.*yells]],
    [[Feigning boredom, .*a <a exist=".*" noun="lad">scrawny half-krolvin lad</a>.*lies on .*his.*back on top of an .*iron-bound warped oak chest]],
    [[Digging deep into .*his.*pocket, .*a <a exist=".*" noun="lad">scrawny half-krolvin lad</a>.*pulls out a tiny pebble and tosses it into a <a exist=".*" noun="pit">white stone-encircled pit</a>]],
}, "|"))

--------------------------------------------------------------------------------
-- Whacky Eels-specific squelch patterns
-- Mirrors Lich5 TSquelch::WhackyEels_Squelch (beyond General)
--------------------------------------------------------------------------------

local WHACKYEELS_RX = Regex.new(table.concat({
    [[Handing .* a cloth-wrapped wooden stick, a small gap-toothed kid moves to the edge of nine holes and dangles some meat over them\..*he yells, "WHACK THEM!"]],
    [[A small gap-toothed kid heads over to <a exist=".*" noun=".*">.*</a> and speaks with <a exist=".*" noun=".*">(?:him|her)</a> briefly before handing <a exist=".*" noun=".*">(?:him|her)</a>]],
    [[A small gap-toothed kid has a short word with <a exist=".*" noun=".*">.*</a>\.]],
}, "|"))

--------------------------------------------------------------------------------
-- Pawnshop-specific squelch patterns (beyond General + Spells)
-- Mirrors Lich5 TSquelch::Pawnshop_Squelch (beyond General + Spells_Squelch)
--------------------------------------------------------------------------------

local PAWNSHOP_RX = Regex.new(table.concat({
    [[<a exist="-\d+" noun="\w+">\w+</a> just entered \w+ <a exist="-\d+" noun="door">glass-centered door</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just went through \w+ <a exist="-\d+" noun="\w+">[\\w\s\-]+</a>]],
    [[Rising from his seat behind the rosewood desk, .*Cendadric.*greets an elegantly dressed elven gentleman\.]],
    [[.*Cendadric.*greets an elegantly dressed elven gentleman\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> steps aside to talk with \w+ about <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="[\\w\-]+">[\\w\s\-]+</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> steps aside to talk with the pawnbroker about <a exist="-\d+" noun="\w+">\w+</a>]],
    [[\w+ takes <a exist="-\d+" noun="\w+">\w+'s</a> <a exist="\d+" noun="[\\w\-]+">[\\w\s\-]+</a>, glances at it briefly, then hands <a exist="-\d+" noun="\w+">\w+</a> some silver coins\.]],
    [[\w+ scribbles out a <a exist="\d+" noun="note">[\\w'\s]+ promissory note</a> and hands it to <a exist="-\d+" noun="\w+">\w+</a>]],
    [[The pawnbroker takes <a exist="-\d+" noun="\w+">\w+'s</a> <a exist="\d+" noun="[\\w\-]+">[\w\-]+</a>, examines it, and quickly returns it to <a exist="-\d+" noun="\w+">\w+</a> with a shrug\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> touches <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="\w+">[\w\s\-']+</a> as <a exist="-\d+" noun="\w+">\w+</a> asks the pawnbroker a question\.]],
}, "|"))

--------------------------------------------------------------------------------
-- Duskruin-specific squelch patterns (beyond General + Spells)
-- Mirrors Lich5 TSquelch::Duskruin_Squelch (beyond General + Spells_Squelch)
--------------------------------------------------------------------------------

local DUSKRUIN_RX = Regex.new(table.concat({
    [[<a exist="-\d+" noun="\w+">\w+</a> is escorted in from the dueling sands by .*an <a exist="-\d+" noun="guard">arena guard</a>]],
    [[<a exist="-\d+" noun="\w+">\w+</a> and <a exist="-\d+" noun="\w+">\w+</a> group are escorted in from the dueling sands by .*an <a exist="-\d+" noun="guard">arena guard</a>]],
    [[<a exist="-\d+" noun="\w+">\w+</a> throws away <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="package">package</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> just opened an <a exist="\d+" noun="package">arena winnings package</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tosses aside <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="package">package</a>\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> picks up an <a exist="\d+" noun="package">arena winnings package</a>\.]],
    [[An announcer shouts, "<a exist="-\d+" noun="\w+">\w+</a> just surrendered to]],
    [[<a exist="-\d+" noun="\w+">\w+</a> tries to empty the contents of <a exist="-\d+" noun="\w+">\w+</a> <a exist="\d+" noun="package">package</a> into]],
    [[<a exist="-\d+" noun="\w+">\w+</a> (?:grabs|collects) a <a exist="\d+" noun="booklet">\w+ stamped voucher booklet</a>]],
    [[<a exist="-\d+" noun="\w+">\w+</a> has an exchange with .*an <a exist="-\d+" noun="guard">arena guard</a>.*and is escorted into one of the arenas\.]],
    [[<a exist="-\d+" noun="\w+">\w+</a> and <a exist="-\d+" noun="\w+">\w+</a> group are escorted into the arena\.]],
}, "|"))

--------------------------------------------------------------------------------
-- Hook
--------------------------------------------------------------------------------

local HOOK_NAME = "tsquelch_silence"

local function install_hook()
    DownstreamHook.add(HOOK_NAME, function(line)
        if not line then return line end

        if room_in(Rooms_Fishing) then
            if GENERAL_RX:test(line) or FISHING_RX:test(line) then return nil end
        elseif room_in(Rooms_Digging) then
            if GENERAL_RX:test(line) or DIGGING_RX:test(line) then return nil end
        elseif room_in(Rooms_Tidepools) then
            if GENERAL_RX:test(line) or TIDEPOOLS_RX:test(line) then return nil end
        elseif room_in(Rooms_Eelbeds) then
            if GENERAL_RX:test(line) or EELBEDS_RX:test(line) then return nil end
        elseif room_in(Rooms_Fishpits) then
            if GENERAL_RX:test(line) or FISHPITS_RX:test(line) then return nil end
        elseif room_in(Rooms_Balloons) then
            if GENERAL_RX:test(line) then return nil end
        elseif room_in(Rooms_WaterCannons) then
            if GENERAL_RX:test(line) then return nil end
        elseif room_in(Rooms_WhackyEels) then
            if GENERAL_RX:test(line) or WHACKYEELS_RX:test(line) then return nil end
        elseif room_in(Rooms_Duskruin) then
            if GENERAL_RX:test(line) or SPELLS_RX:test(line) or DUSKRUIN_RX:test(line) then return nil end
        elseif room_in(Rooms_Pawnshop) then
            if GENERAL_RX:test(line) or SPELLS_RX:test(line) or PAWNSHOP_RX:test(line) then return nil end
        end

        return line
    end)
end

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

--------------------------------------------------------------------------------
-- Main loop: install/remove hook based on squelch zone membership
--------------------------------------------------------------------------------

echo("TSquelch active. Squelching enabled in event areas.")

local hook_active = false

while true do
    if in_squelch_zone() then
        if not hook_active then
            dbg("Now Squelching!")
            install_hook()
            hook_active = true
        end
        -- Wait until we leave the squelch zone
        while in_squelch_zone() do pause(1) end
        DownstreamHook.remove(HOOK_NAME)
        hook_active = false
        dbg("End Squelching!")
    end
    pause(1)
end
