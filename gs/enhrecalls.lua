--- @revenant-script
--- name: enhrecalls
--- version: 2.0.0
--- author: unknown (original .lic)
--- game: gs
--- description: Watch bard recalls, build JSON enhancive item data, write on demand
--- tags: bard, enhancives, recalls, loresong
--- changelog:
---   2.0.0 - Complete port: slot inference, permanence, dedup fingerprinting, JSON output, save/stop signals
---   1.0.0 - Initial stub
---
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;enhrecalls                  watch mode (default) — listens for bard recall output
---   ;enhrecalls save             signal running watcher to write JSON now
---   ;enhrecalls stop             signal running watcher to write JSON and exit
---   ;enhrecalls out=PATH         custom output filename (sandboxed to scripts dir)
---   ;enhrecalls cmd=watch out=enhancives.json
---
---   Default output: enhancives_from_recalls.json

-- ===== helpers =====

local function echo_i(msg)
    echo("[enhrecalls] " .. msg)
end

local function now_iso()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Normalize a string for slot matching: lowercase, collapse non-alnum runs to space, strip.
local function norm_word(s)
    s = s:lower():gsub("[^a-z0-9]+", " ")
    return s:match("^%s*(.-)%s*$")
end

-- ===== arg parsing =====
-- Accepts: bare token (→ cmd), key=value pairs (quoted or unquoted)
local function parse_kv(args_str)
    local h = {}
    if not args_str or args_str == "" then return h end
    -- tokenize respecting quoted strings
    local pattern = '"([^"]*)"' .. "|'([^']*)'" .. "|(%S+)"
    for a, b, c in args_str:gmatch(pattern) do
        local token = a or b or c
        if token then
            local k, v = token:match("^(%w+)=(.+)$")
            if k then
                h[k] = v
            elseif not h.cmd then
                h.cmd = token
            end
        end
    end
    return h
end

local function safe_path(p)
    if not p or p == "" then return "enhancives_from_recalls.json" end
    -- strip surrounding quotes
    return p:match("^['\"](.+)['\"]$") or p
end

local function sig_path(base, kind)
    return base .. "." .. kind .. ".signal"
end

-- ===== compiled regexes (case-insensitive) =====

local RE_START       = Regex.new("(?i)^As you recall")
local RE_END         = Regex.new("(?i)It has a (?:permanent(?:ly)?|temporar(?:y|ily)) unlocked loresong")
local RE_PERM_CRUMBLE = Regex.new("(?i)will\\s+(?:crumbl\\w*|disintegrat\\w*)\\s+.*last\\s+enhancive\\s+charge")
local RE_PERM_PERSIST = Regex.new("(?i)will\\s+persist\\s+.*last\\s+enhancive\\s+charge")
local RE_PROVIDES    = Regex.new("(?i)It provides (?:a )?(?:boost|bonus) of\\s+([+-]?\\d+)\\s+to\\s+(.*?)[\\.(]")
local RE_PROVIDES_TEST = Regex.new("(?i)It provides (?:a )?(?:boost|bonus) of")
local RE_ENHANCIVE   = Regex.new("(?i)It is an enhancive item:")
local RE_NOUSE       = Regex.new("(?i)This enhancement may not be used")
local RE_LORESONG    = Regex.new("(?i)unlocked loresong")
local RE_NAME        = Regex.new("(?i)from the (.*?) in your (?:left |right )?hand")

-- ===== slot inference tables =====
-- Ported directly from the .lic source — phrase-first, SLOT_ORDER precedence.

local SLOT_ORDER = {
    "Weapon", "Shield",
    "Ears", "Ear", "Finger",
    "Hair", "Head",
    "Neck", "Wrist", "Hands",
    "Feet", "Ankle", "Pants",
    "Leggings", "Legs", "Arm",
    "Belt", "Waist", "Armor",
    "Undershirt", "Shoulder", "Back", "Cloak",
    "Socks", "Pin",
}

-- pipe-separated noun lists per slot
local SLOT_PACKED = {
    Head       = "aemikvai|atika|atiki|bandana|barrette|bascinet|basinet|basrenne|bonnet|bow|burgonet|cabasset|cap|capotain|carcanet|caul|chaperon|chaplet|circlet|coif|cowl|crespine|crown|diadem|earmuffs|elothrai|face-veil|fascinator|ferrigem|ferroniere|geldaralad|goggles|greathelm|hairbands|haircombs|hairjewels|hairpins|hairsticks|hat|headband|headdress|headpiece|headscarf|headwrap|helm|hennin|hood|kerchief|mantilla|mask|plume|shawl|snood|tiara|tricorn|tricorne|veil|warhelm|wimple",
    Ear        = "earbob|earcuff|earring|ear-stud|ear stud|earrings|hoops",
    Ears       = "earrings|hoops",
    Neck       = "amulet|beads|bowtie|brooch|choker|collar|cord|lavaliere|locket|medallion|neckchain|necklace|pendant|periapt|talisman|thong|torc|gorget|aventail",
    Back       = "bag|duffel bag|backpack|backsack|back sheath|back-basket|carryall|haversack|harness|knapsack|pack|rucksack",
    Shoulder   = "bag|baldric|bandolier|basket|carryall|case|handbag|harness|kit|pack|purse|quiver|reticule|sack|satchel|scabbard|sheath|shoulderbag|sling|tote",
    Cloak      = "beluque|burnoose|caban|cape|capelet|cassock|chasuble|cloak|coat|coatee|dolman|duster|frock|gaberdine|greatcloak|half-cape|jacket|kimono|leine|longcoat|longcloak|manteau|mantle|overcoat|parka|paletot|pelisse|pelisson|raincoat|robe|robes|shawl|shroud|shrug|stole|surcoat|surcote|toqua|vestment|wrap",
    Front      = "bandolier",
    Undershirt = "arming doublet|blouse|chemise|gambeson|gipon|kirtle|pourpoint|sark|shift|shirt|tunic|underdress|undergown|undershirt|undertunic|underrobe",
    Arm        = "armband|arm greaves|arm guards|armlet|vambrace",
    Wrist      = "bangle|bangles|bracelet|bracer|bracers|cuff|guards|manacle|vambrace|wristband|wrist-band|wristchain|wristcuff|wristlet|wrist pouch",
    Hands      = "gauntlet|gauntlets|gloves|handwraps|hand-harness|handflower",
    Finger     = "band|finger-armor|pinky ring|ring|rings|talon|thumb ring",
    Waist      = "belt|chain|chatelaine|cincher|cincture|corsage|corset|girdle|hip-scarf|sash|scarf|waistchain|waist-cincher",
    Belt       = "bag|buckle|case|clutch|gem bag|gem pouch|gem satchel|handbag|hip-kit|hip-satchel|kit|poke|pouch|purse|reliquary|reticule|sack|satchel|scabbard|sheath|tote|tube",
    Leggings   = "leggings",
    Pants      = "breeches|breeks|hosen|kilt|pants|petticoat|petticoats|skirt|tights|trews|trousers|underskirts|wrap-skirt",
    Legs       = "greaves|leg greaves|leg-greaves|leg guards|leg-guards|leg wraps|shin guards|tassets|thigh band|thigh-band|thigh quiver|thigh-quiver",
    Ankle      = "anklet|cuff|ankle-cuff|sheath|ankle-sheath",
    Socks      = "socks|stockings",
    Feet       = "ankle-boots|boots|brouges|buskins|chopines|clogs|flats|footflower|footwraps|half-boots|knee-boots|poulaines|sabatons|sandals|shoes|slippers|snowshoes|thigh-boots|yatane",
    Hair       = "barrette|hairbands|haircombs|hairjewels|hairpins|hairsticks",
    Pin        = "pin|brooch|badge|clasp|stickpin",
    Shield     = "shield|aegis|buckler|targe|pavis|pavise|kite-shield|tower-shield|scutum",
}

local WEAPON_NOUNS =
    "spear|sword|dagger|axe|handaxe|longsword|broadsword|short sword|scimitar|falchion|rapier|estoc|kukri|" ..
    "mace|morning star|war hammer|maul|flail|whip|bullwhip|cat o nine tails|" ..
    "poleaxe|pole axe|halberd|glaive|guisarme|naginata|ranseur|partisan|spetum|awl-pike|" ..
    "lance|pike|trident|harpoon|" ..
    "bow|longbow|short bow|composite bow|crossbow|hand crossbow|arbalest|" ..
    "staff|runestaff|quarterstaff|warstaff|" ..
    "chakram|bola|bolas|throwing axe|throwing disc|dart"

local ARMOR_NOUNS =
    "leather|leathers|leather armor|leather breastplate|cuirbouilli|cuirbouilli leather|studded leather|brigandine|brigandine armor|" ..
    "lamellar armor|scale|scalemail|coat-of-plates|jack-of-plates|" ..
    "chain|chainmail|ringmail|mail|haubergeon|jazerant|hauberk|augmented chain|" ..
    "plate|plate armor|breastplate|metal breastplate|platemail|half plate|full plate|field plate|plate-and-mail|plate and mail"

-- Build single-word and phrase lookup tables
local SLOT_SINGLES = {}  -- slot → {normed_word → true}
local SLOT_PHRASES = {}  -- slot → [normed_phrase, ...]

local function add_nouns_to_slot(slot, packed)
    if not SLOT_SINGLES[slot] then SLOT_SINGLES[slot] = {} end
    if not SLOT_PHRASES[slot] then SLOT_PHRASES[slot] = {} end
    for noun in packed:gmatch("[^|]+") do
        noun = noun:match("^%s*(.-)%s*$")
        if noun ~= "" then
            local normed = norm_word(noun)
            if normed:find(" ", 1, true) then
                table.insert(SLOT_PHRASES[slot], normed)
            else
                SLOT_SINGLES[slot][normed] = true
                if not normed:match("s$") then
                    SLOT_SINGLES[slot][normed .. "s"] = true
                end
            end
        end
    end
end

for slot, packed in pairs(SLOT_PACKED) do
    add_nouns_to_slot(slot, packed)
end
add_nouns_to_slot("Weapon", WEAPON_NOUNS)
add_nouns_to_slot("Armor",  ARMOR_NOUNS)

--- Infer the wearable slot from an item name using phrase-first precedence.
local function infer_location(name)
    local hay    = " " .. norm_word(name) .. " "
    local tokens = {}
    for t in hay:gmatch("%S+") do
        table.insert(tokens, t)
    end

    for _, slot in ipairs(SLOT_ORDER) do
        -- phrase match first (multi-word nouns)
        for _, phrase in ipairs(SLOT_PHRASES[slot] or {}) do
            if hay:find(" " .. phrase .. " ", 1, true) then
                return slot
            end
        end
        -- single-word token match
        local singles = SLOT_SINGLES[slot] or {}
        for _, t in ipairs(tokens) do
            if singles[t] then
                return slot
            end
        end
    end
    return "Misc"
end

-- ===== chunk parsing =====

local function extract_name(chunk)
    local caps = RE_NAME:captures(chunk)
    if caps and caps[1] then
        return caps[1]:match("^%s*(.-)%s*$")
    end
    return "Unknown item"
end

local function permanence_from(chunk)
    if RE_PERM_CRUMBLE:test(chunk) then return "Crumbly"   end
    if RE_PERM_PERSIST:test(chunk) then return "Permanent" end
    return "Unknown"
end

--- Collect informational "It ..." lines, excluding mechanical ones.
local function collect_notes(chunk)
    local seen  = {}
    local notes = {}
    for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$")
        if  line ~= ""
        and not line:match("^[Aa]s you recall")
        and not RE_ENHANCIVE:test(line)
        and not RE_PROVIDES_TEST:test(line)
        and not RE_NOUSE:test(line)
        and not RE_LORESONG:test(line)
        and line:match("^It")
        and not seen[line]
        then
            seen[line] = true
            table.insert(notes, line)
        end
    end
    return table.concat(notes, " ")
end

--- Parse all "provides X bonus of N to target" lines in a chunk.
local function parse_targets(chunk)
    local targets     = {}
    local bonus_types = { "Bonus", "Ranks", "Base", "Recovery" }
    local special     = { ["Max Mana"]=true, ["Max Stamina"]=true,
                          ["Stamina Recovery"]=true, ["Mana Recovery"]=true,
                          ["Health Recovery"]=true }

    for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$")
        local caps = RE_PROVIDES:captures(line)
        if caps and caps[1] then
            local amt  = caps[1]
            local rest = caps[2]:match("^%s*(.-)%s*$")
            local bonus_type, target = nil, rest

            -- check for trailing type qualifier
            for _, bt in ipairs(bonus_types) do
                local suf = " " .. bt
                if #rest >= #suf and rest:sub(-#suf) == suf then
                    bonus_type = bt
                    target     = rest:sub(1, #rest - #suf)
                    break
                end
            end

            -- fallback: known special names or generic Bonus
            if not bonus_type then
                if special[rest] then
                    bonus_type = "Recovery"
                    target     = rest
                else
                    bonus_type = "Bonus"
                end
            end

            table.insert(targets, {
                target = target,
                type   = bonus_type,
                amount = tonumber(amt),
            })
        end
    end
    return targets
end

--- Build a deduplication fingerprint for an item.
local function make_fingerprint(item)
    local tlist = {}
    for _, t in ipairs(item.targets) do
        table.insert(tlist, t.target .. "|" .. t.type .. "|" .. tostring(t.amount))
    end
    table.sort(tlist)
    return item.name:lower():match("^%s*(.-)%s*$")
        .. "|" .. item.location
        .. "|" .. item.permanence
        .. "|" .. table.concat(tlist, ",")
end

-- ===== runtime state =====

local items   = {}
local seen_fp = {}
local next_id = 1

local function add_chunk(chunk)
    local name    = extract_name(chunk)
    local targets = parse_targets(chunk)
    if #targets == 0 then return end

    local item = {
        id         = next_id,
        name       = name,
        location   = infer_location(name),
        permanence = permanence_from(chunk),
        notes      = collect_notes(chunk),
        targets    = targets,
        dateAdded  = now_iso(),
    }
    local fp = make_fingerprint(item)
    if seen_fp[fp] then return end
    seen_fp[fp] = true
    table.insert(items, item)
    next_id = next_id + 1
    local suffix = #targets == 1 and " enhancive)" or " enhancives)"
    echo_i("Captured: " .. name .. " (" .. #targets .. suffix)
end

local function write_items(out_path)
    local data    = Json.encode({ items = items })
    local ok, err = File.write(out_path, data)
    if ok then
        echo_i("Wrote " .. #items .. " item(s) to " .. out_path)
    else
        echo_i("ERROR writing " .. out_path .. ": " .. tostring(err))
    end
end

-- ===== main: command routing =====

local raw_args  = Script.vars[0] or ""
local args      = parse_kv(raw_args)
local cmd       = (args.cmd or "watch"):lower()
local out_path  = safe_path(args.out)
local save_sig  = sig_path(out_path, "save")
local stop_sig  = sig_path(out_path, "stop")

-- Signal modes: write a sentinel file and exit; the watching instance picks it up.
if cmd == "save" or cmd == "stop" then
    local ok, err = File.write(sig_path(out_path, cmd), now_iso())
    if ok then
        echo_i("Signal " .. cmd:upper() .. " → " .. out_path)
    else
        echo_i("Could not write signal: " .. tostring(err))
    end
    return
end

-- Watcher mode
echo_i("Watching recalls... output: " .. out_path)

before_dying(function()
    write_items(out_path)
end)

local parsing     = false
local chunk_lines = {}

local ok, err = pcall(function()
    while true do
        local line = get()
        if not line then break end
        line = line:match("^(.-)%s*$") or ""

        -- chunk start
        if not parsing and RE_START:test(line) then
            parsing     = true
            chunk_lines = { line }

        -- chunk body
        elseif parsing then
            table.insert(chunk_lines, line)
            if RE_END:test(line) then
                parsing     = false
                add_chunk(table.concat(chunk_lines, "\n"))
                chunk_lines = {}
            end
        end

        -- handle inter-process signals (checked on every game line)
        if File.exists(save_sig) then
            write_items(out_path)
            File.remove(save_sig)
        end
        if File.exists(stop_sig) then
            write_items(out_path)
            File.remove(stop_sig)
            break
        end
    end
end)

if not ok then
    echo_i("Error: " .. tostring(err))
end
