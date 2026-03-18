--- @revenant-script
--- name: boondetector
--- version: 1.0.0
--- author: unknown
--- game: gs
--- tags: boon, creatures, hunting, detection
--- description: Detect and display boon creature adjectives with their associated effects
---
--- Original Lich5 authors: unknown
--- Ported to Revenant Lua from boondetector.lic
---
--- Usage: ;boondetector (runs in background, reports boon creatures)

local BOON_MAP = {
    adroit = "Jack of all Trades", afflicted = "Diseased", apt = "Counter-attack",
    barbed = "Damage Weighting", belligerent = "Boosted Offense", blurry = "Confuse",
    canny = "Mind Blast", combative = "Boosted Offense", dazzling = "Dispelling",
    deft = "Jack of all Trades", diseased = "Diseased", drab = "Parting Shot",
    dreary = "Parting Shot", ethereal = "Ethereal", flashy = "Dispelling",
    flexile = "Boosted Defense", flickering = "Blink", flinty = "Damage Padding",
    frenzied = "Frenzy", ghastly = "Terrifying", ghostly = "Ethereal",
    gleaming = "Crit Weighting", glittering = "Elemental Flares",
    glorious = "Cheat Death", glowing = "Extra Spells - Elemental",
    grotesque = "Terrifying", hardy = "Crit Padding", illustrious = "Cheat Death",
    indistinct = "Physical Negation", keen = "Mind Blast", lanky = "Weaken",
    luminous = "Boosted Mana", lustrous = "Boosted Mana",
    muculent = "Regeneration", nebulous = "Physical Negation",
    oozing = "Poisonous", pestilent = "Diseased",
    radiant = "Extra Spells - Spiritual", raging = "Frenzy",
    ready = "Counter-attack", resolute = "Crit Death Immune",
    robust = "Boosted HP", rune_covered = "Magic Immune",
    shadowy = "Soul Stealing", shielded = "Bolt Shield",
    shifting = "Confuse", shimmering = "Crit Weighting",
    shining = "Elemental Negation", sickly_green = "Poisonous",
    sinuous = "Boosted Defense", slimy = "Regeneration",
    sparkling = "Elemental Negation", spindly = "Weaken",
    spiny = "Damage Weighting", stalwart = "Boosted HP",
    steadfast = "Stun Immune", stout = "Crit Padding",
    tattooed = "Magic Immune", tenebrous = "Soul Stealing",
    tough = "Damage Padding", twinkling = "Extra Spells - Other",
    unflinching = "Crit Death Immune", unyielding = "Stun Immune",
    wavering = "Blink", wispy = "Ethereal",
}

local function lookup_boon(name)
    local key = name:gsub("[%s%-]", "_"):gsub("'", ""):lower()
    return BOON_MAP[key] or ("Unknown: " .. name)
end

local seen_ids = {}
local MAX_SEEN = 200

local function track_id(id)
    seen_ids[#seen_ids + 1] = id
    while #seen_ids > MAX_SEEN do
        table.remove(seen_ids, 1)
    end
end

local function already_seen(id)
    for _, v in ipairs(seen_ids) do
        if v == id then return true end
    end
    return false
end

local found_room = nil

while true do
    local targets = GameObj.targets()
    local boon_creatures = {}
    for _, t in ipairs(targets or {}) do
        if t.type and t.type:find("boon") then
            boon_creatures[#boon_creatures + 1] = t
        end
    end

    if #boon_creatures > 0 and not found_room and not GameObj.pcs() then
        found_room = Room.id
        for _, npc in ipairs(boon_creatures) do
            if not already_seen(npc.id) then
                local lines = quiet_command("appraise #" .. npc.id, "is %w+ in size and about|^Usage:")
                for _, l in ipairs(lines or {}) do
                    local adj_str = l:match("appears to be (.-)%.")
                    if adj_str then
                        adj_str = adj_str:gsub("and ", ""):gsub("sickly green", "sickly_green"):gsub(",", "")
                        local boons = {}
                        for adj in adj_str:gmatch("%S+") do
                            boons[#boons + 1] = adj .. "(" .. lookup_boon(adj) .. ")"
                        end
                        local msg = string.format("(%s) Room: %s - Name: %s - ID: %s\n          Boons: %s",
                            os.date("%H:%M:%S"), tostring(found_room), npc.name, npc.id,
                            table.concat(boons, ", "))
                        Gui.stream_window(msg)
                        track_id(npc.id)
                    end
                end
            end
        end
        while found_room == Room.id do wait(0.5) end
        found_room = nil
    end
    wait(0.5)
end
