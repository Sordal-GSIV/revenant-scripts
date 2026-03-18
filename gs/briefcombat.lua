--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: briefcombat
--- version: 1.0.3
--- author: Daedeus
--- contributors: Tysong, Ragz, Gemini AI
--- game: gs
--- description: Combat text filtering/abbreviation for cleaner output
--- tags: brief,combat,condensing,squelch
---
--- Changelog (from Lich5):
---   v1.0.3 (2026-02-02): --flares/--no-flares, --numbers/--no-numbers, fix ball spell detection
---   v1.0.2 (2026-01-31): standard mode keeps numbers and body part damage
---   v1.0.1 (2026-01-29): bugfix in instance variable location
---   v1.0.0 (2026-01-25): refactor into module, CharSettings support
---
--- Usage:
---   ;briefcombat              - compress other players' combat messages
---   ;briefcombat -x           - extreme mode (aggressive compression)
---   ;briefcombat all          - also compress your own actions
---   ;briefcombat --no-extreme - disable extreme mode
---   ;briefcombat --no-all     - stop compressing own actions
---   ;briefcombat --numbers    - show damage rolls (default: on)
---   ;briefcombat --no-numbers - hide damage rolls
---   ;briefcombat --flares     - show flare messaging (default: on)
---   ;briefcombat --no-flares  - hide flare messaging
---   ;briefcombat --exclude=<players> - exclude players from compression
---   ;briefcombat --list       - show current settings
---   ;briefcombat --help       - show help

---------------------------------------------------------------------------
-- Settings (persisted in CharSettings)
---------------------------------------------------------------------------
local function load_bool_setting(key, default)
    local raw = CharSettings["briefcombat_" .. key]
    if raw == nil or raw == "" then return default end
    return raw == "true"
end

local function save_bool_setting(key, val)
    CharSettings["briefcombat_" .. key] = tostring(val)
end

local function load_string_setting(key, default)
    local raw = CharSettings["briefcombat_" .. key]
    if raw == nil or raw == "" then return default end
    return raw
end

local function save_string_setting(key, val)
    CharSettings["briefcombat_" .. key] = val or ""
end

---------------------------------------------------------------------------
-- Parse arguments
---------------------------------------------------------------------------
local args = Script.vars
local extreme_mode = nil
local compress_self = nil
local show_numbers = nil
local show_flares = nil
local excluded_players = {}
local debug_mode = false

-- Check for --help/--list first
for i = 1, #args do
    local a = args[i]
    if not a then break end
    local lower = a:lower()
    if lower == "--help" or lower == "-h" then
        respond([[

===========================================================================
                                BRIEFCOMBAT HELP
===========================================================================

Dramatically shortens most combat text.  Standard mode is good for groups
up to about 6. Recommend Extreme mode "-x" for larger groups.

USAGE:
  ;briefcombat [OPTIONS]

OPTIONS:
  all, --all              Compress your own combat actions (default: false)
  --no-all                Don't compress your own actions

  --numbers               Show damage rolls (default: true)
  --no-numbers            Hide damage rolls
  --flares                Show flare messaging (default: true)
  --no-flares             Hide flare messaging

  -x, --extreme           Extreme mode - more aggressive compression (default: false)
  --no-extreme            Disable extreme mode

  --exclude=<players>     Exclude specific players from compression
                          (comma or space separated)
                          Example: --exclude="Player1,Player2"

  -d, --debug             Enable debug output
  --list                  Show current settings
  -h, --help              Show this help message

EXAMPLES:
  ;briefcombat                                  # Basic mode, exclude self
  ;briefcombat all                              # Compress everything including self
  ;briefcombat all -x                           # Aggressive, compress all
  ;briefcombat --exclude="Thomas,George"        # Exclude specific players
  ;briefcombat all -x --debug                   # Full compression with debug
  ;briefcombat --list                           # View current settings

NOTES:
  - Settings are saved in CharSettings and persist between runs
  - Use --list to view your current configuration
  - Debug mode shows detailed regex matching information

===========================================================================
        ]])
        return
    elseif lower == "--list" then
        respond("")
        respond("===========================================================================")
        respond("                         BRIEFCOMBAT CURRENT SETTINGS")
        respond("===========================================================================")
        respond("")
        respond("Extreme Mode:     " .. tostring(load_bool_setting("extreme", false)))
        respond("Compress Self:    " .. tostring(load_bool_setting("compress_self", false)))
        respond("Show Numbers:     " .. tostring(load_bool_setting("show_numbers", true)))
        respond("Show Flares:      " .. tostring(load_bool_setting("show_flares", true)))
        respond("Excluded Players: " .. load_string_setting("excluded", ""))
        respond("")
        respond("===========================================================================")
        return
    end
end

-- Parse remaining args
for i = 1, #args do
    local a = args[i]
    if not a then break end
    local lower = a:lower()

    if lower == "-x" or lower == "--extreme" then
        extreme_mode = true
    elseif lower == "--no-extreme" then
        extreme_mode = false
    elseif lower == "all" or lower == "--all" then
        compress_self = true
    elseif lower == "--no-all" then
        compress_self = false
    elseif lower == "--numbers" then
        show_numbers = true
    elseif lower == "--no-numbers" then
        show_numbers = false
    elseif lower == "--flares" then
        show_flares = true
    elseif lower == "--no-flares" then
        show_flares = false
    elseif lower == "--debug" or lower == "-d" then
        debug_mode = true
    elseif lower:find("^--exclude=") then
        local players_str = a:match("^--exclude=(.+)")
        if players_str then
            players_str = players_str:gsub("[\"']", "")
            for name in players_str:gmatch("[^, ]+") do
                table.insert(excluded_players, name)
            end
        end
    end
end

-- Apply settings (CLI overrides saved)
if extreme_mode ~= nil then
    save_bool_setting("extreme", extreme_mode)
else
    extreme_mode = load_bool_setting("extreme", false)
end

if compress_self ~= nil then
    save_bool_setting("compress_self", compress_self)
else
    compress_self = load_bool_setting("compress_self", false)
end

if show_numbers ~= nil then
    save_bool_setting("show_numbers", show_numbers)
else
    show_numbers = load_bool_setting("show_numbers", true)
end

if show_flares ~= nil then
    save_bool_setting("show_flares", show_flares)
else
    show_flares = load_bool_setting("show_flares", true)
end

if #excluded_players > 0 then
    save_string_setting("excluded", table.concat(excluded_players, ","))
else
    local saved = load_string_setting("excluded", "")
    if saved ~= "" then
        for name in saved:gmatch("[^,]+") do
            table.insert(excluded_players, name)
        end
    end
end

-- Always exclude self unless compress_self
if not compress_self then
    table.insert(excluded_players, "You")
end

-- Deduplicate excluded
local seen = {}
local unique_excluded = {}
for _, p in ipairs(excluded_players) do
    local key = (p:lower() == "self" or p:lower() == "you") and "You" or p
    if not seen[key] then
        seen[key] = true
        table.insert(unique_excluded, key)
    end
end
excluded_players = unique_excluded

-- Startup messages
if extreme_mode then
    echo("Extreme mode! Will more aggressively shorten non-essential text, at the cost of immersion.")
else
    echo("Standard mode! We'll leave combat numbers, gore, and AOE messaging! Run \";briefcombat -x\" for Extreme mode.")
end

if not compress_self then
    echo("Compressing others' combat messaging.  Run \";briefcombat all\" to also compress your own actions.")
else
    echo("Compressing all combat messaging.  Run \";briefcombat --no-all\" to see your own actions.")
end

if #excluded_players > 0 then
    echo("Will exclude actions by " .. table.concat(excluded_players, ", "))
end

if debug_mode then
    echo("DEBUG MODE ENABLED")
end

-- Request MonsterBold
fput("set MonsterBold On")

---------------------------------------------------------------------------
-- Regex patterns: status effects (8 categories)
---------------------------------------------------------------------------
local his_or_her = "(?:<a[^>]+>)?(?:his|her)(?:</a>)?"
local himself_or_herself = "(?:<a[^>]+>)?(?:himself|herself)(?:</a>)?"

local status_effects = {
    { name = "stunned",     re = Regex.new("stunned|strength of holy incantation") },
    { name = "frozen",      re = Regex.new("freezes|encased in a thick block of ice|stops all movement") },
    { name = "knockdown",   re = Regex.new("falls over|(?:dragged|knocked|down|flattening itself) to the (?:\\w+)|collapses on") },
    { name = "sympathized", re = Regex.new("eyes begin to glow (?:purple|dark)") },
    { name = "pinned",      re = Regex.new("pins? (?:.*) to the") },
    { name = "webbed",      re = Regex.new("ensnared in thick strands of webbing") },
    { name = "buffeted",    re = Regex.new("buffeted by") },
    { name = "dead",        re = Regex.new(
        "tries to crawl away on the (?:ground|floor) but" ..
        "|rolls over on the (?:ground|floor) and goes still" ..
        "|body falls to the (?:ground|floor) as it is consumed by ethereal flame" ..
        "|(?:collapses|crashes) to the (?:ground|floor)" ..
        "|grows dim as s?he falls to the (?:ground|floor)" ..
        "|falls to the (?:ground|floor) motionless" ..
        "|lets out a ragged gasp before collapsing"
    ) },
}

---------------------------------------------------------------------------
-- Verb lists (all 4)
---------------------------------------------------------------------------

-- Standard verbs: "[Player] [verb] [target]" (target optional)
local verbs_standard = {
    "gestures? at",                -- generic spell casting
    "gestures?\\.",                -- generic spell casting without target
    "channels? at",
    "waves? (?:your|an?) .+? at", -- wand casting
    "(?:hurl|fire|swing|thrust|throw)s? (?:an?|the|some|your)? .+? at",
    "slashes with an? [\\w \\-\\'\\.]+ at",
    "thrusts?(?: with)? a [\\w \\-\\'\\.]+ at",
    "continues to sing a disruptive song",
    "draws an intricately glowing pattern in the air before",
    "chants a reverent litany",
    "skillfully begins to weave another verse into (?:.*) harmony",
    "voice carries the power of thunder as (?:.*) calls out an angry incantation in an unknown language",
    "(?:.*) directing the sound of (?:.*) voice at",
    "punches?(?: with)? an? [\\w \\-\\'\\.]+ at",
    "(?:make a precise )?attempts? to (?:punch|jab|grapple|kick)",
    "An obscuring brume descends",
    "take aim and fire an? [\\w \\-\\']+",
    "turns and sweeps",
    "lashes out again and again with the force of a reaping whirlwind",
    "charges? forward at",
    "lunges? forward at",
    "takes? a menacing step toward",
    "brings? (?:your|" .. his_or_her .. ") .+? around in a tight arc to batter",
    "takes? quick assessment and raises?",
    "exhales? a virulent green mist toward",
    "snap your arm forward",
    "snaps? (?:your|" .. his_or_her .. ") arm forward, (?:throwing|hurling) (?:your|" .. his_or_her .. ") .+? at",
    "looses? arrow after arrow",
    "sweeps? (?:your|" .. his_or_her .. ") .+? into a whirling display of keen-edged menace",
    "hurls? (?:yourself|" .. himself_or_herself .. ") at",
    "slowly moves? (?:your|" .. his_or_her .. ") hand in a (?:waving|pushing|throwing|slapping|clenching|pounding) motion",
    "weaves? (?:your|" .. his_or_her .. ") .+? in a two-handed under arm spin, swiftly picking up speed until it becomes a blurred cyclone of .+",
    "(?:'s|r) eyes glow with .*? light, and .*? manifests around",
}

-- Verbs where target appears before the verb in the sentence
local verbs_target_first = {
    "calls? down(?: the)? excoriating power",
    "deliver a sound thrashing",
}

-- Ambient damage: verb first then target, no player noun
local verbs_ambient = {
    "Fiery debris explodes from the ground",
    "Craggy debris explodes from the ground",
    "The earth cracks beneath",
    "Icy stalagmites burst from the ground",
    "flies out of the shadows toward",
    "Light and dark pockmarks appear",
    "sickly green miasma around",
    "waves billow outward from",
    "long thorny vine lashes out",
    "charges forward and bites",
    "rushes forward, sinking " .. his_or_her .. " teeth into",
    "raging sandstorm swirls around",
    "burst of flame leaps from",
    "devastating inferno of flaming rocks ignites the entire sky",
    "flaming rocks burst from the sky and smite the area",
    "Ripples of cold white flame flare up around",
    "several faintly glowing snowflakes settle upon",
    "Waves of sacred energy tear through",
    "powerful wave surges into the area, violently slamming directly into",
    "An ominous shadow falls over your surroundings",
}

-- Ambient damage: target first then verb, no player noun
local verbs_ambient_2 = {
    "convulses with a crippling affliction",
    "as virulent green mist passes through",
    "Large hailstones pound relentlessly",
    "spiritual malady wracks",
    "appear to be in a violent mental struggle",
}

---------------------------------------------------------------------------
-- Spell guess patterns: {regex, spell_id, include_line}
-- spell_id can be a number string, "ball", or nil
---------------------------------------------------------------------------
local spell_guess_patterns = {
    { re = Regex.new("radiant burst of light"),                                                          id = "135",  include = true },
    { re = Regex.new("shoot strands of webbing"),                                                        id = "ball", include = false },
    { re = Regex.new("hazy film"),                                                                       id = "119",  include = false },
    { re = Regex.new("appears more confident"),                                                          id = "211",  include = false },
    { re = Regex.new("scintillating, blue-white aura encompasses"),                                      id = "302",  include = false },
    { re = Regex.new("ambient temperature abruptly plummets"),                                           id = "309",  include = false },
    { re = Regex.new("manifests as an ethereal, pure golden censer"),                                    id = "320",  include = false },
    { re = Regex.new("several faintly glowing snowflakes settle"),                                       id = "335",  include = false },
    { re = Regex.new("hand before it takes the shape of an ethereal chain of keys|A cold mist drifts in, blanketing the area|thunderous din echoes all around as the very earth shudders beneath"), id = "335", include = true },
    { re = Regex.new("dark ethereal (?:waves|sphere)"),                                                  id = "410",  include = true },
    { re = Regex.new("(?:waves?|sphere) of .* (?:expands|moves)"),                                       id = "435",  include = true },
    { re = Regex.new("surrounded by a circle of flickering flame"),                                      id = "502",  include = false },
    { re = Regex.new("a bolt of churning air"),                                                          id = "ball", include = false },
    { re = Regex.new("An airy mist rolls into the (?:area|room)"),                                       id = "512",  include = true },
    { re = Regex.new("unleash(?:es)? a compact swirling vortex"),                                        id = "ball", include = false },
    { re = Regex.new("Wisps of black smoke swirl around"),                                               id = "519",  include = true },
    { re = Regex.new("multitude of sharp pieces of debris splinter off from underfoot|The surroundings advance upon"), id = "635", include = true },
    { re = Regex.new("arms snatch viciously|grotesque limbs"),                                           id = "709",  include = true },
    { re = Regex.new("flames of pure essence"),                                                          id = "719",  include = false },
    { re = Regex.new("leaving behind a sucking void"),                                                   id = "720",  include = false },
    { re = Regex.new("gust of wind tugs at your sleeves"),                                               id = "912",  include = false },
    { re = Regex.new("debris explodes from the ground beneath"),                                         id = "917",  include = true },
    { re = Regex.new("force of the sonic vibrations"),                                                   id = "1030", include = false },
    { re = Regex.new("reels under the force of the sonic vibrations"),                                   id = "1030", include = false },
    { re = Regex.new("pulse of pearlescent energy ripples"),                                             id = "1106", include = false },
    { re = Regex.new("A nebulous haze shimmers into view around"),                                       id = "1115", include = true },
    { re = Regex.new("eyes begin to glow (?:purple|dark)"),                                              id = "1120", include = false },
    { re = Regex.new("utters a pious chant (.*) Suddenly a divine force radiates out from"),             id = "1618", include = true },
    { re = Regex.new("(?:hurl|fire|hurtles forth)s? an? [\\w \\-']+ at"),                                id = "ball", include = false },
    { re = Regex.new("an invisible force guides|considerably more powerful|feel the magic surge through you"), id = nil, include = false },
    { re = Regex.new("overwhelmed by some burdening force"),                                             id = "1602", include = false },
    { re = Regex.new("eyes glow with .*? light, and .*? manifests around"),                              id = nil,    include = true },
}

---------------------------------------------------------------------------
-- Compiled combat regexes
---------------------------------------------------------------------------
local pc_or_you_pattern = '<a exist="(-?\\d+)" noun="[^"]+">[^<]+</a>|You'
local target_pattern = '<pushBold/>(.*?)<popBold/>'

-- Build combined verb patterns
local verbs_standard_joined = table.concat(verbs_standard, "|")
local verbs_target_first_joined = table.concat(verbs_target_first, "|")
local verbs_ambient_joined = table.concat(verbs_ambient, "|")
local verbs_ambient_2_joined = table.concat(verbs_ambient_2, "|")

-- Standard: [Player] [verb] [optional target]
local combat_re = Regex.new(
    "(" .. pc_or_you_pattern .. ") (" .. verbs_standard_joined .. ")" ..
    "(?: (?:an? |the |some )?(" .. target_pattern .. "))?"
)

-- Target first: [Player] ... [target] ... [verb]
local combat_target_first_re = Regex.new(
    "(" .. pc_or_you_pattern .. ").*(" .. target_pattern .. ").*(" .. verbs_target_first_joined .. ")"
)

-- Ambient: verb first, then optional target, no player noun
local combat_ambient_re = Regex.new(
    "^.*?(?:" .. verbs_ambient_joined .. ")(?:.*?(" .. target_pattern .. "))?"
)

-- Ambient2: target first, then verb, no player noun
local combat_ambient_2_re = Regex.new(
    "^.*?(" .. target_pattern .. ").*?(?:" .. verbs_ambient_2_joined .. ")"
)

---------------------------------------------------------------------------
-- Filter regexes
---------------------------------------------------------------------------
local filter_self_spells_casttime_re = Regex.new("<castTime value='\\d+'\\/>")
local filter_self_spells_exist_re    = Regex.new("<spell exist='spell'>([\\w ']+)</spell>")
local filter_self_spells_msg_re      = Regex.new("Your spell(?:song)? is ready\\.|You gesture\\.|Cast Roundtime \\d Seconds\\.?")
local filter_self_search_re          = Regex.new("You search the <pushBold/>|<pushBold/>.*<popBold/> (?:had nothing of interest|didn't carry any silver|had nothing else of value)")
local filter_other_search_re         = Regex.new("(<a exist=\"(?:-\\d+)\" noun=\"\\w+\">\\w+</a>) searches (<pushBold/>.*<popBold/>)")
local filter_other_spell_prep_re     = Regex.new("appears to be focusing (?:his|her) thoughts while chanting|traces a simple symbol as (?:he|she) reverently calls")
local filter_sigils_re               = Regex.new("faint blue glow (?:fades|surrounds)|shimmering aura (?:fades|surrounds)")

-- Simple squelch filters: any line matching these will be squelched
local simple_filters = {
    Regex.new("Roundtime:"),
    Regex.new("incandescent veil fades"),
    Regex.new("knobby layer of bark"),
    Regex.new("briefly before decaying into dust\\."),
    Regex.new("In a breathtaking display of ability and combat mastery|spins about looking mighty stirred up|looks determined and focused"),
    Regex.new("removes a single(.*)from"),
    Regex.new("nocks? an?"),
    Regex.new("surge of empowerment"),
}

-- Regex for extracting exist IDs from XML tags
local exist_id_re = Regex.new('<a exist="(\\d+)"')
-- Regex for extracting exist IDs (including negative for PCs) from XML tags
local exist_any_id_re = Regex.new('<a exist="(-?\\d+)"')
-- Regex for ricochet targeting
local ricochet_re = Regex.new('ricochets off.*?<a exist=".*?".*?flashes toward.*?<a exist="(\\d+)"')
-- Regex for damage extraction
local damage_re = Regex.new("(\\d+) (?:points? of )?damage")
-- Regex for body part detection (check_aim)
local body_part_re = Regex.new("head|neck|eye|left hand|right hand|left leg|right leg|finger|solar plexus|elbow|abdomen|chest|skull|heart|back|brain|jugular|stomach|nose|forearm|knee|sliced open")
local body_part_exclude_re = Regex.new("(?:arrow|bolt) sticks|lands solidly in|cutting invisible runes")
-- Regex to strip XML tags for actor comparison
local strip_tags_re = Regex.new("<[^>]+>")
-- Regex for combat roll lines
local combat_roll_re = Regex.new("CS:|AS:|UAF:|d100")
-- Regex for line-noise squelch during compression
local compress_noise_re = Regex.new("Roundtime|Forcing stance down|appears to gain succour|comdemnation lifts|Feeling nervous yet|A hit|Warding failed|breaks into tiny fragments|gain succor|^\\s*You |(?:arrow|bolt) sticks|lands solidly in|fragrant haze")
-- CastTime tag strip
local casttime_strip_re = Regex.new("<castTime value='\\d+'\\/?\\>")
-- Pattern 9811 special
local pattern_9811_re = Regex.new("draws an intricately glowing pattern in the air before")

---------------------------------------------------------------------------
-- Spell name resolution
---------------------------------------------------------------------------
local function spell_name(spell_id)
    if spell_id == "709" then
        return "Grasp of the Grave"
    end
    local s = Spell[tonumber(spell_id)]
    if s and s.name then
        return s.name
    end
    return "spell " .. spell_id
end

---------------------------------------------------------------------------
-- Compression engine state
---------------------------------------------------------------------------
local compressing = false
local compressed_lines = {}
local targets_damage = {}
local targets_status = {}
local targets_last_message = {}
local targets_numbers = {}
local targets_flare = {}
local targets_aim_message = {}
local current_target = nil
local current_actor = nil
local is_self = false
local is_no_target = false
local is_buff = false
local first_line_has_damage = false
local bounty_message = nil
local spell_guess = nil          -- guessed spell ID string or "ball"
local spell_cast_string = nil    -- an extra informative line to include
local better_action_message = nil -- for ball spells, replaces gesture line
local compress_last = nil
local compress_you_last = nil
local shortening_search = false
local pending_smr = {}           -- buffered SMR lines before target identified

---------------------------------------------------------------------------
-- Helper: check if line contains any excluded player
---------------------------------------------------------------------------
local function check_excluded(line)
    for _, player in ipairs(excluded_players) do
        if line:find(player, 1, true) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Helper: check status effects on a line for a given target
---------------------------------------------------------------------------
local function check_status(line, target_id)
    if not target_id then return end
    for _, eff in ipairs(status_effects) do
        if eff.re:test(line) then
            if not targets_status[target_id] then
                targets_status[target_id] = {}
            end
            table.insert(targets_status[target_id], eff.name)
        end
    end
end

---------------------------------------------------------------------------
-- Helper: flush pending SMR lines to current target
---------------------------------------------------------------------------
local function flush_pending_smr()
    if not current_target then return end
    if #pending_smr > 0 then
        if not targets_numbers[current_target] then
            targets_numbers[current_target] = {}
        end
        for _, smr_line in ipairs(pending_smr) do
            table.insert(targets_numbers[current_target], smr_line)
        end
        pending_smr = {}
    end
end

---------------------------------------------------------------------------
-- Helper: check_aim body part detection
---------------------------------------------------------------------------
local function check_aim(line)
    if not body_part_re:test(line) then return end
    if body_part_exclude_re:test(line) then return end

    -- Don't record aim messages from the actor (they'd be in the first line)
    if current_actor then
        local clean_actor = current_actor:gsub("<[^>]+>", "")
        if line:find(current_actor, 1, true) then return end
        if clean_actor ~= "" and line:find(clean_actor, 1, true) then return end
    end

    if current_target then
        if not targets_aim_message[current_target] then
            targets_aim_message[current_target] = {}
        end
        table.insert(targets_aim_message[current_target], line)
    end
end

---------------------------------------------------------------------------
-- Extract target ID from an XML string with <a exist="ID">
---------------------------------------------------------------------------
local function extract_target_id(target_string)
    if not target_string then return nil end
    local m = Regex.match('<a exist="(\\d+)"', target_string)
    if m then return m end
    return nil
end

---------------------------------------------------------------------------
-- begin_compress: start a new compression block
---------------------------------------------------------------------------
local function begin_compress(line, target_string, actor_string)
    local target_id = extract_target_id(target_string)
    is_no_target = (target_id == nil)

    if not compressing then
        compressing = true
        current_actor = actor_string
        spell_guess = nil
        spell_cast_string = nil
        better_action_message = nil
        pending_smr = {}
        targets_damage = {}
        targets_flare = {}
        targets_numbers = {}
        targets_last_message = {}
        targets_aim_message = {}
        targets_status = {}
        compress_you_last = nil
        compress_last = nil
        bounty_message = nil
        is_buff = false
        first_line_has_damage = false

        -- Check for special spell 9811
        if pattern_9811_re:test(line) then
            spell_guess = "9811"
        end

        compressed_lines = {}
        table.insert(compressed_lines, line:gsub("%s+$", ""))
        current_target = nil

        if target_id then
            current_target = target_id
            targets_damage[target_id] = 0
            targets_last_message[target_id] = line

            -- Sometimes the first line contains damage
            local dmg_match = Regex.match("(\\d+) (?:points? of )?damage", line)
            if dmg_match then
                targets_damage[current_target] = (targets_damage[current_target] or 0) + tonumber(dmg_match)
                first_line_has_damage = true
            end
        end
    end
end

---------------------------------------------------------------------------
-- end_compress: finalize and output compressed block
---------------------------------------------------------------------------
local function end_compress(line)
    compressing = false

    flush_pending_smr()

    local num_targets = 0
    for _ in pairs(targets_damage) do num_targets = num_targets + 1 end

    -- Replace vague "gesture" with spell name on first line
    if spell_guess then
        if spell_guess == "ball" then
            if better_action_message then
                compressed_lines[1] = better_action_message
            end
        else
            if is_self then
                local literal = "cast " .. spell_name(spell_guess)
                compressed_lines[1] = compressed_lines[1]:gsub("gesture", literal)
            else
                if spell_guess == "1030" then
                    local literal = "weaves " .. spell_name(spell_guess)
                    compressed_lines[1] = compressed_lines[1]:gsub("skillfully begins to weave another verse", literal)
                elseif spell_guess == "302" or spell_guess == "309" or spell_guess == "320" or spell_guess == "335" then
                    local literal = "chants " .. spell_name(spell_guess) .. "."
                    compressed_lines[1] = compressed_lines[1]:gsub("chants a reverent litany.*", literal)
                else
                    local literal = "casts " .. spell_name(spell_guess)
                    compressed_lines[1] = compressed_lines[1]:gsub("gestures", literal)
                end
            end
        end
    end

    -- Add spell cast string (extra informative line) unless extreme mode
    if spell_cast_string and not extreme_mode then
        table.insert(compressed_lines, spell_cast_string)
    end

    -- Multi-target summary on first line
    if num_targets == 0 then
        if not spell_cast_string then
            if compress_last then
                table.insert(compressed_lines, compress_last)
            end
        elseif compress_you_last then
            table.insert(compressed_lines, compress_you_last)
        end
    elseif is_no_target and num_targets > 1 then
        compressed_lines[1] = compressed_lines[1] .. ", " .. num_targets .. " targets affected."
    elseif num_targets > 1 then
        -- Remove trailing punctuation from first line and add "and N others"
        compressed_lines[1] = compressed_lines[1]:gsub("[%.!]$", "")
        if num_targets == 2 then
            compressed_lines[1] = compressed_lines[1] .. " and 1 other."
        else
            compressed_lines[1] = compressed_lines[1] .. " and " .. (num_targets - 1) .. " others."
        end
    end

    -- Wait for GameObj updates if we interacted with targets
    if num_targets > 0 then
        pause(0.03)
    end

    if extreme_mode then
        if num_targets > 0 then
            local num_stunned = 0
            local num_knockdown = 0
            local num_frozen = 0
            local num_dead = 0
            local num_sympathized = 0
            local num_pinned = 0
            local num_buffeted = 0
            local num_webbed = 0
            local total_damage = 0
            local killed = {} -- track already-counted kills

            for target_id, damage in pairs(targets_damage) do
                local target = GameObj[target_id]
                if target and target.status and target.status:find("dead") then
                    num_dead = num_dead + 1
                    killed[target_id] = true
                end
                total_damage = total_damage + damage

                -- If damage was in the first line, substitute with total
                if first_line_has_damage then
                    compressed_lines[1] = compressed_lines[1]:gsub("%d+", tostring(damage), 1)
                end
            end

            for target_id, status_array in pairs(targets_status) do
                local has_stunned = false
                local has_knockdown = false
                local has_buffeted = false
                local has_frozen = false
                local has_pinned = false
                local has_sympathized = false
                local has_webbed = false
                local has_dead = false

                for _, s in ipairs(status_array) do
                    if s == "stunned" then has_stunned = true end
                    if s == "knockdown" then has_knockdown = true end
                    if s == "buffeted" then has_buffeted = true end
                    if s == "frozen" then has_frozen = true end
                    if s == "pinned" then has_pinned = true end
                    if s == "sympathized" then has_sympathized = true end
                    if s == "webbed" then has_webbed = true end
                    if s == "dead" then has_dead = true end
                end

                if has_stunned then num_stunned = num_stunned + 1 end
                if has_knockdown then
                    num_knockdown = num_knockdown + 1
                elseif has_buffeted then
                    num_buffeted = num_buffeted + 1
                end
                if has_frozen then num_frozen = num_frozen + 1 end
                if has_pinned then num_pinned = num_pinned + 1 end
                if has_sympathized then num_sympathized = num_sympathized + 1 end
                if has_webbed then num_webbed = num_webbed + 1 end
                if has_dead and not killed[target_id] then num_dead = num_dead + 1 end
            end

            local sum = num_dead + num_stunned + num_knockdown + num_sympathized +
                        num_frozen + num_pinned + num_buffeted + num_webbed + total_damage
            if sum == 0 then
                if not spell_cast_string and compress_last then
                    table.insert(compressed_lines, compress_last)
                end
            else
                local parts = {}
                if num_dead > 0 then table.insert(parts, num_dead .. " targets <pushBold/>KILLED<popBold/>") end
                if num_knockdown > 0 then table.insert(parts, num_knockdown .. " targets knocked down") end
                if num_stunned > 0 then table.insert(parts, num_stunned .. " targets stunned") end
                if num_frozen > 0 then table.insert(parts, num_frozen .. " targets frozen") end
                if num_sympathized > 0 then table.insert(parts, num_sympathized .. " targets sympathized") end
                if num_pinned > 0 then table.insert(parts, num_pinned .. " targets pinned") end
                if num_buffeted > 0 then table.insert(parts, num_buffeted .. " targets buffeted") end
                if num_webbed > 0 then table.insert(parts, num_webbed .. " targets webbed") end
                if total_damage > 0 and not first_line_has_damage then
                    table.insert(parts, total_damage .. " damage dealt")
                end
                if #parts > 0 then
                    table.insert(compressed_lines, "  ... " .. table.concat(parts, ", ") .. "!")
                end
            end
        end
    else
        -- Standard mode: per-target details
        if num_targets > 0 then
            for target_id, damage in pairs(targets_damage) do
                -- Show combat rolls
                if show_numbers and targets_numbers[target_id] then
                    for _, roll in ipairs(targets_numbers[target_id]) do
                        table.insert(compressed_lines, roll)
                    end
                end

                -- Show flares
                if show_flares and targets_flare[target_id] then
                    for _, flare in ipairs(targets_flare[target_id]) do
                        table.insert(compressed_lines, flare)
                    end
                end

                -- Resolve target GameObj for display name
                local target = GameObj[target_id]
                local name
                if target then
                    local prefix = target.name:match("^[aeiouAEIOU]") and "An" or "A"
                    name = "<pushBold/>" .. prefix .. " <a exist=\"" .. target.id ..
                           "\" noun=\"" .. target.noun .. "\">" .. target.name .. "</a><popBold/>"
                else
                    name = "Target"
                end

                -- Build status string
                local status_arr = targets_status[target_id] or {}
                local status_str = ""

                if target and target.status and target.status:find("dead") then
                    status_str = "<pushBold/>KILLED<popBold/>"
                else
                    -- Check status_arr for "dead"
                    local is_dead = false
                    for _, s in ipairs(status_arr) do
                        if s == "dead" then is_dead = true; break end
                    end
                    if is_dead then
                        status_str = "<pushBold/>KILLED<popBold/>"
                    elseif #status_arr > 0 then
                        -- Deduplicate and rename knockdown
                        local seen_s = {}
                        local unique_s = {}
                        for _, s in ipairs(status_arr) do
                            local display = (s == "knockdown") and "knocked down" or s
                            if not seen_s[display] then
                                seen_s[display] = true
                                table.insert(unique_s, display)
                            end
                        end
                        status_str = table.concat(unique_s, ", ")
                    end
                end

                -- Collect aim messages or last message
                local msgs = {}
                if targets_aim_message[target_id] and #targets_aim_message[target_id] > 0 then
                    -- Deduplicate aim messages
                    local aim_seen = {}
                    for _, m in ipairs(targets_aim_message[target_id]) do
                        if not aim_seen[m] then
                            aim_seen[m] = true
                            table.insert(msgs, m)
                        end
                    end
                elseif targets_last_message[target_id] and targets_last_message[target_id] ~= compressed_lines[1] then
                    table.insert(msgs, targets_last_message[target_id])
                end

                -- Filter out the spell cast string from msgs
                if spell_cast_string then
                    local filtered = {}
                    for _, m in ipairs(msgs) do
                        if m ~= spell_cast_string then
                            table.insert(filtered, m)
                        end
                    end
                    msgs = filtered
                end

                -- Output damage + messages
                if damage > 0 then
                    if #msgs > 0 then
                        local first_msg = msgs[1]:match("^%s*(.-)%s*$") -- strip
                        table.insert(compressed_lines, "  .. " .. damage .. " damage!  " .. first_msg)
                        for j = 2, #msgs do
                            table.insert(compressed_lines, "   " .. msgs[j])
                        end
                    else
                        table.insert(compressed_lines, "  .. " .. damage .. " damage!")
                    end
                else
                    for _, m in ipairs(msgs) do
                        table.insert(compressed_lines, m)
                    end
                end

                -- Status display
                local msgs_have_status = false
                for _, m in ipairs(msgs) do
                    if m:find("knocked") or m:find("webbing") or m:find("buffeted") or
                       m:find("stunned") or m:find("to the ground") or m:find("to the floor") then
                        msgs_have_status = true
                        break
                    end
                end

                if msgs_have_status then
                    -- Only show KILLED if the status line would add info
                    if status_str:find("KILLED") then
                        table.insert(compressed_lines, "  " .. name .. " is " .. status_str .. "!")
                    end
                elseif status_str ~= "" then
                    table.insert(compressed_lines, "  " .. name .. " is " .. status_str .. "!")
                end
            end
        end
    end

    -- Final line (prompt) + bounty + blank
    table.insert(compressed_lines, line)
    if bounty_message then
        table.insert(compressed_lines, bounty_message)
    end
    table.insert(compressed_lines, "")

    return table.concat(compressed_lines, "\n")
end

---------------------------------------------------------------------------
-- compress_line: process a line during active compression
---------------------------------------------------------------------------
local function compress_line(line)
    if line:find("Cast Roundtime") then return end

    compress_last = line
    if line:find("You", 1, true) then compress_you_last = line end

    -- Strip and skip empty
    local stripped = line:gsub("%s+$", "")
    if stripped:match("^%s*$") then return end

    -- Check status on current target
    check_status(line, current_target)

    -- Spell guess: run before target switching (moved to top per Ruby v1.0.3 fix)
    for _, sg in ipairs(spell_guess_patterns) do
        if sg.re:test(line) then
            if sg.id then
                spell_guess = sg.id
            end
            if sg.include and not spell_cast_string then
                spell_cast_string = line
            end
            if sg.id == "ball" then
                better_action_message = line
            end
            break
        end
    end

    -- Bounty messaging
    if line:find("You succeeded in your task", 1, true) or Regex.test("kills? remaining", line) then
        bounty_message = line
        return
    end

    -- Check for damage
    local dmg_match = Regex.match("(\\d+) (?:points? of )?damage", line)
    if dmg_match then
        flush_pending_smr()
        local damage_amount = tonumber(dmg_match)
        if current_target then
            targets_damage[current_target] = (targets_damage[current_target] or 0) + damage_amount
        end
    else
        -- Try to switch target if line contains an exist ID
        local potential_target = Regex.match('<a exist="(\\d+)"', line)

        -- Handle ricochets
        local ricochet_target = Regex.match('ricochets off.*?<a exist=".*?".*?flashes toward.*?<a exist="(\\d+)"', line)
        if ricochet_target then
            potential_target = ricochet_target
        end

        if potential_target then
            -- Check if this ID is an NPC in the room
            local npcs = GameObj.npcs()
            local is_npc = false
            for _, npc in ipairs(npcs) do
                if npc.id == potential_target then
                    is_npc = true
                    break
                end
            end

            if is_npc then
                current_target = potential_target
                if not targets_damage[current_target] then
                    targets_damage[current_target] = 0
                end
                check_status(line, current_target)

                if line:find("**", 1, true) then
                    if not targets_flare[current_target] then
                        targets_flare[current_target] = {}
                    end
                    table.insert(targets_flare[current_target], line)
                else
                    targets_last_message[current_target] = line
                end

                check_aim(line)
                flush_pending_smr()
                return
            end
        end
    end

    -- Fallthrough: check for flares, combat rolls, or generic lines
    if line:find("**", 1, true) then
        flush_pending_smr()
        if current_target then
            if not targets_flare[current_target] then
                targets_flare[current_target] = {}
            end
            table.insert(targets_flare[current_target], line)
        end
    elseif combat_roll_re:test(line) then
        flush_pending_smr()
        -- Buffer SMR lines; they go to pending_smr until flushed to a target
        table.insert(pending_smr, line)
    elseif not compress_noise_re:test(line) then
        if current_target then
            targets_last_message[current_target] = line
        end
    else
        check_status(line, current_target)
    end

    check_aim(line)
end

---------------------------------------------------------------------------
-- Filter functions
---------------------------------------------------------------------------
local function filter_self_spells(line)
    -- Truncate after castTime tag
    local ct = Regex.match("<castTime value='\\d+'\\/>", line)
    if ct then
        local pos = line:find(ct, 1, true)
        if pos then
            return line:sub(1, pos + #ct - 1)
        end
    end

    -- Show spell exist tag
    local spell_exist = Regex.match("<spell exist='spell'>([\\w ']+)</spell>", line)
    if spell_exist then
        return "<spell exist='spell'>" .. spell_exist .. "</spell>"
    end

    -- Squelch "Your spell is ready" etc
    if filter_self_spells_msg_re:test(line) then
        return nil
    end

    return line
end

local function filter_self_search(line)
    if filter_self_search_re:test(line) then
        return nil
    end
    return line
end

local function filter_other_search(line)
    if filter_other_search_re:test(line) then
        shortening_search = true
        if extreme_mode then
            return nil
        end
        return line
    end
    return line
end

---------------------------------------------------------------------------
-- compress_combat: try to match combat start patterns
---------------------------------------------------------------------------
local function compress_combat(line)
    -- Strip castTime tags before matching
    local clean_line = line:gsub("<castTime value='%d+'/?%>", "")

    if debug_mode and (line:lower():find("wave") and line:lower():find("wand")) then
        echo("DEBUG: Wand line detected!")
        echo("  Original: " .. line)
        echo("  Cleaned: " .. clean_line)
    end

    -- Standard combat regex
    -- Capture groups: 1=player, 2=exist_id, 3=verb, 4=full target <pushBold/>...<popBold/>, 5=inner target
    local caps = combat_re:captures(clean_line)
    if caps then
        local player_str = caps[1] or ""
        local target_string = caps[4]  -- nil if no target (optional group)

        is_self = (player_str == "You")

        if debug_mode then
            echo("DEBUG: combat_re matched!")
            echo("  Player: " .. tostring(player_str))
            echo("  Target: " .. tostring(target_string))
        end

        -- Check exclusions
        local excluded = false
        for _, player in ipairs(excluded_players) do
            if player_str:find(player, 1, true) then
                excluded = true
                break
            end
        end

        if not excluded then
            begin_compress(line, target_string, player_str)
            return nil
        end
    end

    -- Target-first combat regex
    -- Capture groups: 1=player, 2=exist_id, 3=full target <pushBold/>...<popBold/>, 4=inner target, 5=verb
    caps = combat_target_first_re:captures(clean_line)
    if caps then
        local player_str = caps[1] or ""
        local target_string = caps[3]  -- group 3 = full <pushBold/>...<popBold/> target
        is_self = (player_str == "You")

        local excluded = false
        for _, player in ipairs(excluded_players) do
            if player_str:find(player, 1, true) then
                excluded = true
                break
            end
        end

        if not excluded then
            begin_compress(line, target_string, player_str)
            return nil
        end
    end

    -- Ambient combat regex
    -- Capture groups: 1=full target <pushBold/>...<popBold/>, 2=inner target
    caps = combat_ambient_re:captures(clean_line)
    if caps then
        local target_string = caps[1]  -- nil if no target (optional group)
        begin_compress(line, target_string, nil)
        return nil
    end

    -- Ambient2 combat regex
    -- Capture groups: 1=full target <pushBold/>...<popBold/>, 2=inner target
    caps = combat_ambient_2_re:captures(clean_line)
    if caps then
        local target_string = caps[1]
        begin_compress(line, target_string, nil)
        return nil
    end

    return line
end

---------------------------------------------------------------------------
-- Main downstream hook
---------------------------------------------------------------------------
local function brief_hook(line)
    if not line then return line end

    -- Search shortening mode: squelch until prompt
    if shortening_search then
        if line:find("<prompt") then
            shortening_search = false
            return nil
        else
            return nil
        end
    end

    -- If currently compressing, handle end or continue
    if compressing then
        if line:find("<prompt") then
            return end_compress(line)
        end
        compress_line(line)
        return nil
    end

    -- Check exclusions before any processing
    if check_excluded(line) then
        if debug_mode then
            echo("DEBUG: Line excluded (contains excluded player)")
        end
        return line
    end

    -- Simple squelch filters
    for _, re in ipairs(simple_filters) do
        if re:test(line) then
            return nil
        end
    end

    -- Try to start combat compression
    if debug_mode then
        echo("DEBUG: Calling compress_combat for: " .. line)
    end
    local result = compress_combat(line)
    if result == nil then
        return nil
    end

    -- Apply self-spell filter (only if self is not excluded, i.e., compress_self is true)
    local you_excluded = false
    for _, p in ipairs(excluded_players) do
        if p == "You" then you_excluded = true; break end
    end
    if not you_excluded then
        local filtered = filter_self_spells(line)
        if filtered == nil then return nil end
        if filtered ~= line then return filtered end
    end

    -- Apply search filters
    local filtered = filter_self_search(line)
    if filtered == nil then return nil end

    filtered = filter_other_search(line)
    if filtered == nil then return nil end

    -- Apply other spell prep filter (squelch in extreme mode)
    if extreme_mode then
        if filter_other_spell_prep_re:test(line) then
            return nil
        end
        if filter_sigils_re:test(line) then
            return nil
        end
    end

    return line
end

---------------------------------------------------------------------------
-- Register hook and run
---------------------------------------------------------------------------
DownstreamHook.add("briefcombat", brief_hook)

before_dying(function()
    DownstreamHook.remove("briefcombat")
end)

-- Keep running
while true do
    pause(1)
end
