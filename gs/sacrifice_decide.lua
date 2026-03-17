--- @revenant-script
--- name: sacrifice_decide
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Detect target readiness for Sorcerer Sacrifice and cast appropriate spells
--- tags: sorcerer, sacrifice, 706, 711, shadow essence
---
--- Usage:
---   ;sacrifice_decide <targetid> <spell>
---   Example bigshot line: script sacrifice_decide target 719

local target   = Script.vars[1] or ""
local spell_id = Script.vars[2] or ""

local function do_sacrifice(tgt)
    waitrt()
    waitcastrt()
    fput("sacrifice " .. tgt)
    pause(0.1)
    waitrt()
end

local function do_tether(tgt)
    waitrt()
    waitcastrt()
    Spell[706].cast(tgt)
    do_sacrifice(tgt)
end

local function do_pain(tgt)
    waitrt()
    waitcastrt()
    Spell[711].cast(tgt)
end

local function do_appraise(tgt)
    local result = quiet_command("appraise " .. tgt, "^The .+? is %w+ in size")
    local status = result and result[#result] or ""

    if status:find("enticingly frail") then
        do_sacrifice(tgt)
    elseif status:find("susceptible to manipulation") then
        do_tether(tgt)
    elseif status:find("soul is stalwart and formidable")
        or status:find("firmly bound")
        or status:find("indomitable") then
        do_pain(tgt)
    end
end

-- Main
echo("Finding: " .. target)

local shadow_essence = Resources.shadow_essence or 0
local search = target:gsub("^#", "")

local find = nil
local npcs = GameObj.npcs() or {}
for _, n in ipairs(npcs) do
    if tostring(n.id) == search then
        find = n
        break
    end
end

if not find then
    echo("Target not found.")
    return
end

local is_alive = not (find.status or ""):match("dead") and not (find.status or ""):match("gone")

if tonumber(shadow_essence) < 5 and find.id and is_alive then
    do_appraise("#" .. find.id)
elseif find.id and is_alive and spell_id == "717" then
    waitcastrt()
    waitrt()
    fput("release")
    if mana() > 17 then
        fput("incant 717")
    end
elseif find.id and is_alive then
    Spell[tonumber(spell_id)].cast("#" .. find.id)
end
