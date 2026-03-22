--- @revenant-script
--- name: raven
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Navigate Raven's Court art gallery, studying artwork for Appraisal training.
--- tags: quest, art, appraisal, court
--- Converted from raven.lic
---
--- Usage:
---   ;raven
---
--- Travels to room 5995 (Raven's Court entrance), then walks through studying
--- each art piece. Checks AP skill for court-lock (mind lock / dazed).
--- When all art is studied, runs ;collect.

-- Navigate to Raven's Court entrance
put(";go2 5995")
waitfor("--- Lich: go2 has exited.")

-- Art sequence: each entry has optional moves and the art noun to study
local art_sequence = {
    { art = "raven" },
    { moves = {"e", "climb step"}, art = "mermaid" },
    { moves = {"climb step", "w", "n", "climb step", "climb stair", "s"}, art = "sculpture" },
    { art = "painting" },
    { art = "carving" },
    { art = "statue" },
    { art = "second painting" },
    { moves = {"w"}, art = "painting" },
    { art = "triptych" },
    { art = "statue" },
    { art = "figurine" },
    { art = "second painting" },
    { moves = {"s"}, art = "cylinder" },
    { art = "sculpture" },
    { art = "statue" },
    { art = "painting" },
    { art = "second painting" },
    { moves = {"s"}, art = "sphere" },
    { art = "panel" },
    { art = "painting" },
    { art = "canvas" },
    { art = "statue" },
    { moves = {"e"}, art = "painting" },
    { art = "diorama" },
    { art = "figure" },
    { art = "statue" },
    { art = "second painting" },
}

local exit_moves = {"w", "n", "n", "ne", "climb stair", "climb step", "s"}

local courtlocked = false

--- Study a piece of art, retrying on ...wait
local function study_art(art_name)
    while true do
        local result = DRC.bput("study " .. art_name, {
            "Roundtime",
            "%.%.%.wait",
        })
        if result and result:find("Roundtime") then
            waitrt()
            return
        elseif result and result:find("wait") then
            pause(1)
        else
            waitrt()
            return
        end
    end
end

--- Check AP skill for court-lock
local function check_courtlock()
    local result = DRC.bput("skill AP", {
        "mind lock",
        "dazed",
        "Overall state of",
    })
    if result and (result:find("mind lock") or result:find("dazed")) then
        return true
    end
    return false
end

-- Walk through all art pieces
for _, entry in ipairs(art_sequence) do
    if not courtlocked then
        courtlocked = check_courtlock()
    end

    if entry.moves then
        for _, m in ipairs(entry.moves) do
            move(m)
        end
    end

    if not courtlocked then
        study_art(entry.art)
    end
end

-- Exit the court
for _, m in ipairs(exit_moves) do
    move(m)
end

echo("")
echo("*** All done!")
echo("")

put(";collect")
