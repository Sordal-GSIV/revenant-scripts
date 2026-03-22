--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: generate_gemstone
--- version: 10
--- author: Dreaven
--- game: dr
--- description: Random gemstone property generator - simulates gemstone drops with rarity tiers
--- tags: gemstone, random, fun, simulator
--- original-author: Dreaven (in-game) / Tgo01 (Player's Corner)
--- original-contact: LordDreaven@gmail.com
---
--- Just a fun little script that generates a random gemstone. It uses the
--- odds to generate a Legendary, Rare, Double Common, or Common based loosely
--- on the odds experienced finding in-game gemstones. Tracks how many gemstones
--- you have created as well as how many years/months/weeks it would have taken
--- to find that gemstone in game. Generate gemstones while you're looking for
--- gemstones in game! Why not double your disappointment!

math.randomseed(os.time())

-- ─────────────────────────────────────────────────────────────────────────────
-- Property tables — fully expanded (matching .lic v10 create_main_window lists)
-- ─────────────────────────────────────────────────────────────────────────────

local COMMON = {
    "Arcane Intensity", "Binding Shot", "Blood Artist", "Blood Prism",
    "Boatswain's Savvy", "Bold Brawler", "Burning Blood", "Cannoneer's Savvy",
    "Channeler's Edge", "Consummate Professional", "Cutting Corners", "Dispulsion Ward",
    "Elemental Resonance", "Elementalist's Gift", "Ephemera's Extension", "Ether Flux",
    "Flare Resonance", "Force of Will", "Geomancer's Spite", "Grand Theft Kobold",
    "Green Thumb", "High Tolerance", "Immobility Veil", "Journeyman Defender",
    "Journeyman Tactician",
    "Limit Break: Blunt Weapons", "Limit Break: Brawling", "Limit Break: Edged Weapons",
    "Limit Break: Pole Arm Weapons", "Limit Break: Ranged Weapons", "Limit Break: Spell Aiming",
    "Limit Break: Thrown Weapons", "Limit Break: Two-Handed Weapons",
    "Limit Break: Agility", "Limit Break: Aura", "Limit Break: Constitution",
    "Limit Break: Dexterity", "Limit Break: Discipline", "Limit Break: Influence",
    "Limit Break: Intuition", "Limit Break: Logic", "Limit Break: Strength", "Limit Break: Wisdom",
    "Mana Prism", "Metamorphic Shield", "Mephitic Brume", "Mystic Magnification",
    "Navigator's Savvy", "Opportunistic Sadism", "Root Veil", "Slayer's Fortitude",
    "Spirit Prism", "Stamina Prism", "Storm of Rage", "Subtle Ward",
    "Tactical Canny", "Taste of Brutality", "Twist the Knife", "Web Veil",
}

local REGIONAL = {
    "Grimswarm: Shroud Soother", "Hinterwilds: Indigestible", "Hinterwilds: Light of the Disir",
    "Hinterwilds: Warden of the Damned", "Moonsedge: Gift of Enlightement",
    "Moonsedge: Organ Enthusiast", "Temple Nelemar: Breath of the Nymph",
    "Temple Nelemar: Perfect Conduction", "Temple Nelemar: Trident of the Sunderer",
    "The Hinterwilds: Gift of Enlightement", "The Hive: Arrhythmic Gait",
    "The Hive: Astral Spark", "The Hive: Gift of Enlightement", "The Rift: Gift of the God-King",
}

local RARE = {
    "Adaptive Resistance", "Advanced Spell Shielding", "Anointed Defender", "Arcane Opus",
    "Bandit Bait", "Blood Boil", "Blood Siphon", "Blood Wellspring", "Chameleon Shroud",
    "Channeler's Epiphany", "Defensive Duelist", "Evanescent Possession",
    "Grace of the Battlecaster", "Greater Arcane Intensity", "Hunter's Afterimage",
    "Infusion of Acid", "Infusion of Cold", "Infusion of Disintegration", "Infusion of Disruption",
    "Infusion of Heat", "Infusion of Lightning", "Infusion of Plasma", "Infusion of Steam",
    "Infusion of Vacuum",
    "Innate Focus", "Lost Arcanum", "Mana Wellspring", "Martial Impulse", "Master Tactician",
    "Relentless", "Relentless Warder", "Ripe Melon", "Rock Hound", "Serendipitous Hex",
    "Spirit Wellspring", "Stamina Wellspring", "Strong Back", "Sureshot",
    "Terror's Tribute", "Tethered Strike", "Thirst for Brutality",
}

local LEGENDARY = {
    "Arcane Aegis", "Arcanist's Ascendancy", "Arcanist's Blade", "Arcanist's Will",
    "Charged Presence", "Chronomage Collusion", "Forbidden Arcanum", "Imaera's Balm",
    "Mana Shield", "Mirror Image", "Mystic Impulse", "One Shot, One Kill",
    "Pixie's Mischief", "Reckless Precision", "Spellblade's Fury", "Stolen Power",
    "Thorns of Acid", "Thorns of Cold", "Thorns of Disintegration", "Thorns of Disruption",
    "Thorns of Heat", "Thorns of Lightning", "Thorns of Plasma", "Thorns of Steam",
    "Thorns of Vacuum",
    "Trueshot", "Unearthly Chains", "Witchhunter's Ascendancy",
}

-- Sets for O(1) rarity lookup
local common_set, regional_set, rare_set, legendary_set = {}, {}, {}, {}
for _, v in ipairs(COMMON)    do common_set[v]    = true end
for _, v in ipairs(REGIONAL)  do regional_set[v]  = true end
for _, v in ipairs(RARE)      do rare_set[v]       = true end
for _, v in ipairs(LEGENDARY) do legendary_set[v]  = true end

-- ─────────────────────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────────────────────
local total        = 0
local stop_rolling = false
local last_rarity  = nil
local last_p1, last_p2, last_p3 = nil, nil, nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────
local function pick(tbl)
    return tbl[math.random(#tbl)]
end

local function pick_distinct(tbl, exclude)
    local v = pick(tbl)
    local attempts = 0
    while v == exclude and attempts < 30 do
        v = pick(tbl)
        attempts = attempts + 1
    end
    return v
end

-- 1/3 chance regional, 2/3 chance common (matches .lic rand(1..3)==1 logic)
local function pick_c_or_r()
    if math.random(3) == 1 then return pick(REGIONAL)
    else return pick(COMMON) end
end

local function prop_rarity_tag(prop)
    if     common_set[prop]    then return "Common"
    elseif regional_set[prop]  then return "Regional"
    elseif rare_set[prop]      then return "Rare"
    elseif legendary_set[prop] then return "Legendary"
    else                            return "Unknown"
    end
end

-- Approximate future date: 3 gemstones ≈ 1 month, each leftover ≈ 1 week
local function future_date_str(n)
    local total_months = math.floor(n / 3)
    local weeks_left   = n % 3
    local approx_days  = total_months * 30 + weeks_left * 7
    return os.date("%m/%d/%Y", os.time() + approx_days * 86400)
end

local function time_string(n)
    local total_months = math.floor(n / 3)
    local weeks        = n % 3
    local years        = math.floor(total_months / 12)
    local months       = total_months % 12
    return string.format("%d years, %d months, %d weeks", years, months, weeks)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Core generate
-- ─────────────────────────────────────────────────────────────────────────────

-- force_rarity: if set, skip the probability roll and force this rarity tier.
local function do_generate(force_rarity)
    total = total + 1

    local rarity
    if force_rarity then
        rarity = force_rarity
    else
        local roll = math.random(100)
        if     roll <= 2  then rarity = "Legendary"
        elseif roll <= 7  then rarity = "Rare"
        elseif roll <= 12 then rarity = "Common/Common"
        elseif roll <= 32 then rarity = "Common/Regional"
        elseif roll <= 47 then rarity = "Regional"
        else                   rarity = "Common"
        end
    end

    local p1, p2, p3

    if rarity == "Legendary" then
        p1 = pick_c_or_r()
        p2 = pick(RARE)
        p3 = pick(LEGENDARY)
    elseif rarity == "Rare" then
        p1 = pick_c_or_r()
        p2 = pick(RARE)
    elseif rarity == "Common/Common" then
        p1 = pick(COMMON)
        p2 = pick_distinct(COMMON, p1)
    elseif rarity == "Common/Regional" then
        p1 = pick(COMMON)
        p2 = pick(REGIONAL)
    elseif rarity == "Regional" then
        p1 = pick(REGIONAL)
    else -- "Common"
        p1 = pick(COMMON)
    end

    last_rarity = rarity
    last_p1, last_p2, last_p3 = p1, p2, p3
    return p1, p2, p3, rarity
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GUI construction
-- ─────────────────────────────────────────────────────────────────────────────

local win  = Gui.window("Generate Gemstone", { width = 700, height = 520 })
local root = Gui.vbox()

-- ── Header row (count + time) ─────────────────────────────────────────────
local lbl_count = Gui.label("Gemstones Generated: 0")
local lbl_time  = Gui.label("")
local lbl_date  = Gui.label("")
local hdr_row   = Gui.hbox()
hdr_row:add(lbl_count)
hdr_row:add(Gui.separator())
hdr_row:add(lbl_time)
hdr_row:add(lbl_date)
root:add(hdr_row)
root:add(Gui.separator())

-- ── Result display ────────────────────────────────────────────────────────
local lbl_result = Gui.label("— Press Generate Gemstone —")
root:add(lbl_result)
root:add(Gui.separator())

-- ── Filter dropdowns ──────────────────────────────────────────────────────
-- First property: ANY + all commons
local first_opts = { "ANY" }
for _, v in ipairs(COMMON) do first_opts[#first_opts + 1] = v end

-- Second property: ANY + commons section + rares section
local second_opts = { "ANY", "----------COMMONS----------" }
for _, v in ipairs(COMMON) do second_opts[#second_opts + 1] = v end
second_opts[#second_opts + 1] = "----------RARES------------"
for _, v in ipairs(RARE)   do second_opts[#second_opts + 1] = v end

-- Third property: ANY + legendaries
local third_opts = { "ANY" }
for _, v in ipairs(LEGENDARY) do third_opts[#third_opts + 1] = v end

local combo1 = Gui.editable_combo({ text = "ANY", hint = "First property…",  options = first_opts  })
local combo2 = Gui.editable_combo({ text = "ANY", hint = "Second property…", options = second_opts })
local combo3 = Gui.editable_combo({ text = "ANY", hint = "Third property…",  options = third_opts  })

local chk_lock1 = Gui.checkbox("LOCKED", false)
local chk_lock2 = Gui.checkbox("LOCKED", false)
local chk_lock3 = Gui.checkbox("LOCKED", false)

local filter_row = Gui.hbox()

local function filter_col(label_text, combo, lock_chk)
    local col = Gui.vbox()
    col:add(Gui.label(label_text))
    col:add(combo)
    col:add(lock_chk)
    return col
end

filter_row:add(filter_col("First Property",              combo1, chk_lock1))
filter_row:add(filter_col("Second Property",             combo2, chk_lock2))
filter_row:add(filter_col("Third Property (Legendary)",  combo3, chk_lock3))
root:add(filter_row)
root:add(Gui.separator())

-- ── Button rows ───────────────────────────────────────────────────────────
local btn_generate  = Gui.button("Generate Gemstone")
local btn_roll_rare = Gui.button("Roll Rare")
local btn_roll_leg  = Gui.button("Roll Legendary")

local btn_stop  = Gui.button("Stop Rolling")
local btn_reset = Gui.button("Reset Rolls")

local btn_reroll_cc   = Gui.button("Reroll Common/Common")
local btn_reroll_rare = Gui.button("Reroll Rare")
local btn_reroll_leg  = Gui.button("Reroll Legendary")

local row1 = Gui.hbox()
row1:add(btn_generate)
row1:add(btn_roll_rare)
row1:add(btn_roll_leg)
root:add(row1)

local row2 = Gui.hbox()
row2:add(btn_stop)
row2:add(btn_reset)
root:add(row2)

local row3 = Gui.hbox()
row3:add(btn_reroll_cc)
row3:add(btn_reroll_rare)
row3:add(btn_reroll_leg)
root:add(row3)

win:set_root(root)

-- ─────────────────────────────────────────────────────────────────────────────
-- Display update
-- ─────────────────────────────────────────────────────────────────────────────

local function rarity_header(r)
    if     r == "Legendary"     then return "*LEGENDARY* GEMSTONE FOUND!"
    elseif r == "Rare"          then return "RARE GEMSTONE FOUND!"
    elseif r == "Common/Common" then return "COMMON\\COMMON GEMSTONE FOUND!"
    else                             return r:upper() .. " GEMSTONE FOUND!"
    end
end

local function update_display(p1, p2, p3, rarity)
    lbl_count:set_text("Gemstones Generated: " .. total)
    lbl_time:set_text(time_string(total))
    lbl_date:set_text("  →  Future date: " .. future_date_str(total))

    local lines = { rarity_header(rarity) }
    if p1 then lines[#lines + 1] = "  [" .. prop_rarity_tag(p1) .. "]  " .. p1 end
    if p2 then lines[#lines + 1] = "  [" .. prop_rarity_tag(p2) .. "]  " .. p2 end
    if p3 then lines[#lines + 1] = "  [" .. prop_rarity_tag(p3) .. "]  " .. p3 end
    lbl_result:set_text(table.concat(lines, "\n"))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Filter matching (mirrors .lic click_the_button logic)
-- ─────────────────────────────────────────────────────────────────────────────

-- Returns true when current filter combos are satisfied for (rarity, p1, p2, p3).
-- Separator/ANY entries count as wildcard (match anything).
local function is_separator(text)
    return text == "ANY" or text == "" or text:find("^%-%-%-%-%-%-") ~= nil
end

local function matches_filter(rarity, p1, p2, p3)
    local f1 = combo1:get_text()
    local f2 = combo2:get_text()
    local f3 = combo3:get_text()

    if not is_separator(f1) and p1 ~= f1 then return false end

    if rarity == "Legendary" then
        -- second slot: commons or rares
        if not is_separator(f2) and p2 ~= f2 then return false end
        if not is_separator(f3) and p3 ~= f3 then return false end
    elseif rarity == "Rare" or rarity == "Common/Common" then
        if not is_separator(f2) and p2 ~= f2 then return false end
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lock application — overrides generated properties with locked filter values
-- ─────────────────────────────────────────────────────────────────────────────

local function apply_locks(p1, p2, p3)
    if chk_lock1:get_checked() then
        local f = combo1:get_text()
        if not is_separator(f) then p1 = f end
    end
    if chk_lock2:get_checked() then
        local f = combo2:get_text()
        if not is_separator(f) then p2 = f end
    end
    if chk_lock3:get_checked() then
        local f = combo3:get_text()
        if not is_separator(f) then p3 = f end
    end
    return p1, p2, p3
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-roll: keep rolling until filter matches or stop requested.
-- Mirrors GLib::Timeout loop in original .lic.
-- pause(0) on each iteration yields the coroutine so Stop Rolling can fire.
-- ─────────────────────────────────────────────────────────────────────────────

-- apply_locks_for_reroll: only applies to the three Reroll buttons (matches .lic behavior).
-- Roll Rare / Roll Legendary / plain Generate do not apply locks.
local function apply_locks_for_reroll(p1, p2, p3)
    return apply_locks(p1, p2, p3)
end

local function auto_roll(target_rarity, force_rarity)
    local is_reroll = force_rarity ~= nil
    stop_rolling = false

    -- Pre-clear combo2 when the current selection is invalid for the target rarity.
    -- Mirrors the .lic click_the_button guard that runs before each roll attempt.
    if target_rarity == "Common/Common" then
        local f1 = combo1:get_text()
        local f2 = combo2:get_text()
        -- Clear second slot if it holds a rare (invalid for CC) or duplicates first slot
        if f2 ~= "ANY" and f2 ~= "" and (rare_set[f2] or f2 == f1) then
            combo2:set_text("ANY")
        end
    elseif target_rarity == "Rare" or target_rarity == "Legendary" then
        -- Clear second slot if it holds a common (Reroll Rare/Legendary expect rare in slot 2)
        local f2 = combo2:get_text()
        if f2 ~= "ANY" and f2 ~= "" and common_set[f2] then
            combo2:set_text("ANY")
        end
    end

    repeat
        local p1, p2, p3, r = do_generate(force_rarity)
        -- Locks only apply for the Reroll buttons, not Roll Rare/Legendary (matches .lic)
        if is_reroll then p1, p2, p3 = apply_locks_for_reroll(p1, p2, p3) end
        update_display(p1, p2, p3, r)
        if r == target_rarity and matches_filter(r, p1, p2, p3) then
            stop_rolling = true
        end
        if not stop_rolling then pause(0) end
    until stop_rolling
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Button callbacks
-- ─────────────────────────────────────────────────────────────────────────────

btn_generate:on_click(function()
    local p1, p2, p3, r = do_generate()
    update_display(p1, p2, p3, r)
end)

btn_roll_rare:on_click(function()
    auto_roll("Rare")
end)

btn_roll_leg:on_click(function()
    auto_roll("Legendary")
end)

btn_stop:on_click(function()
    stop_rolling = true
end)

btn_reset:on_click(function()
    stop_rolling = true
    total = 0
    combo1:set_text("ANY")
    combo2:set_text("ANY")
    combo3:set_text("ANY")
    chk_lock1:set_checked(false)
    chk_lock2:set_checked(false)
    chk_lock3:set_checked(false)
    lbl_count:set_text("Gemstones Generated: 0")
    lbl_time:set_text("")
    lbl_date:set_text("")
    lbl_result:set_text("— Press Generate Gemstone —")
end)

btn_reroll_cc:on_click(function()
    auto_roll("Common/Common", "Common/Common")
end)

btn_reroll_rare:on_click(function()
    auto_roll("Rare", "Rare")
end)

btn_reroll_leg:on_click(function()
    auto_roll("Legendary", "Legendary")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Launch window
-- ─────────────────────────────────────────────────────────────────────────────

win:on_close(function()
    stop_rolling = true
end)
win:show()
Gui.wait(win, "close")
