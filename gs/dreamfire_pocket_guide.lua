--- @revenant-script
--- name: dreamfire_pocket_guide
--- version: 1.1.0
--- author: Luxelle
--- game: gs
--- tags: dreamfire, illusion, bracelet, guide
--- description: Quick reference guide for Dreamfire Bracelet commands based on tier/attachments
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Luxelle
--- Ported to Revenant Lua from dreamfire-pocket-guide.lic v1.1
---
--- Usage:
---   ;dreamfire_pocket_guide help
---   ;dreamfire_pocket_guide <bracelet name>

if Script.vars[0] == "help" or not Script.vars[1] then
    respond("Usage: ;dreamfire_pocket_guide <bracelet name>")
    respond("IE: ;dreamfire_pocket_guide raxiara")
    respond("Or: ;dreamfire_pocket_guide pearl bracelet")
    respond(" ")
    return
end

local dreamfire = Script.vars[0]

fput("analyze my " .. dreamfire)

local tier = 0
local attach = 0

while true do
    local line = get()
    local t = line:match("Unlock Tier: (%d+)")
    if t then tier = tonumber(t) end
    local a = line:match("Attachments: (%d+)")
    if a then attach = tonumber(a) end
    if line:find("Mana Stored:", 1, true) then break end
end

respond("Dreamfire Illusions Pocket Guide")
respond(" ")

if tier > 0 then
    respond("T1: WEAR/REMOVE")
    respond("    PUSH/PULL (attach/remove panels)")
    respond("    PEER (see all panels, you peering at it is invisible to others)")
    respond("    RUB (create illusion of selected panel)")
    respond("    LOOK/SHOW (appends attachment count and current panel info)")
end
if tier > 1 then
    respond("T2: INFUSE (adds mana)")
    respond("    GAZE (quietly preview current panel, both illusions)")
    respond("    WAVE (create concealed illusion of current panel)")
    respond("    SNAP (fluff - current panel illusion appears briefly above your palm)")
end
if tier > 2 then
    respond("T3: FLIP (Toggles Fluff designated verbs to use other side of panel)")
    respond("    TILT (fluff - attention to current panel)")
    respond("    WAGGLE (fluff - waggles current selection to appear briefly in the air)")
end
if tier > 3 then
    respond("T4: TICKLE (fluff - brush fingers, illusion appears briefly)")
    respond("    POINT (at illusion to extend by 1 min per tier, 10min max)")
    respond("    DISMISS (dismiss all illusions even if not in room with you)")
end
if tier > 4 then
    respond("T5: NUDGE (fluff - sweeping gesture and color/material appear)")
    respond("    PINCH (Toggle between creating dissipating and static illusions)")
end

if attach > 1 then
    respond(" ")
    respond("Attachment Points Verb Additions:")
    respond(" 2+ TURN (cycle through selection panel in the bracelet)")
end
if attach > 2 then
    respond(" 3+ TWIST (silently cycle panels in bracelet)")
    respond("    TURN/TWIST bracelet to # (choose specific active panel by number)")
end
if attach > 4 then
    respond(" 5+ FIDGET (randomly select from one of main panels, displays panel selection to others)")
end
if attach > 7 then
    respond(" 8+ SPIN (randomly select panel and reveal illusion, can select concealed illusions via FLIP)")
end
if attach > 9 then
    respond("10+ EMPTY (transfer panels to storage case)")
end
if attach > 11 then
    respond("12+ FLICK (find empty attachment)")
end
if attach > 14 then
    respond("15+ LOWER (random multi image spread, number selected in PROD setting) *Can target at someone!")
    respond("    PROD (toggle image count for LOWER command, range is 3-5)")
end

respond(" ")
respond("All the specific details are at the wiki: https://gswiki.play.net/Dreamfire_Panel_Bracelet")
respond(" ")
