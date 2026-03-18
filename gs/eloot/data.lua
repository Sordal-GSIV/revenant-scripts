--- ELoot runtime data state
-- Ported from eloot.lic ELoot::Data class (lines 226-531)
-- All instance variables become table fields on the returned data object.
--
-- Usage:
--   local Data = require("gs.eloot.data")
--   local d = Data.init(settings)

local M = {}

--- Default crumbly items (weapons/items that crumble on pickup)
local DEFAULT_CRUMBLY = {
    -- Kraken Fall
    "gnarled dark wooden crook",
    "twisted obsidian dagger",
    "immense fel-hafted handaxe",
    "gold-tipped heavy spear",
    "notched bone handaxe",
    "rough pinewood crook",
    "swirling sanguine orb",
    "battered antique faewood crate",
    "copper-traced dark steel hatchet",
    "huge black alloy greatsword",
    "rough leather quiver",

    -- Atoll
    "twisted soot black runestaff",
    "corroded bronze Hammer of Kai",
    "dried seaweed-wrapped longbow",
    "bronze-bound driftwood greatshield",
    "coral-hilted heavy ball and chain",
    "coral-hilted sharply tapered longsword",
}

--- Deposit regex patterns (tested sequentially)
local DEPOSIT_PATTERNS = {
    "You deposit (%d[%d,]*) silvers? into your account",
    "That's a total of (%d[%d,]*) silver",
    "That's (%d[%d,]*) silver",
    "silvers? to your account",
    "You deposit your note worth (%d[%d,]*) into your account",
    "They add up to (%d[%d,]*) silver",
    "You have no coins to deposit",
    "Smiling greedily, Hurshal takes your silvers",
}

--- Withdraw regex patterns
local WITHDRAW_PATTERNS = {
    "I have a bill of (%d[%d,]*) silvers?",
    "that I suggest you pay immediately",
    "Very well, a withdrawal of (%d[%d,]*) silver",
    "teller scribbles the transaction into a book and hands you (%d[%d,]*) silver",
    "teller carefully records the transaction",
    "hands you (%d[%d,]*) silver",
    "The banker nods and says",
}

--- Get regex patterns (item retrieval responses)
local GET_PATTERNS = {
    "^You .*remove",
    "^You .*draw",
    "^You .*equip",
    "^You .*grab",
    "^You .*reach",
    "^You .*slip",
    "^You .*tuck",
    "^You .*retrieve",
    "^You .*already have",
    "^You .*unsheathe",
    "^You .*detach",
    "^You .*swap",
    "^You .*sling",
    "^You .*withdraw",
    "^With subtle movements, you sneak a hand",
    "^Get what%?$",
    "^Why don't you leave some for others%?$",
    "^You need a free hand",
    "^You already have that",
    "Reaching over your shoulder",
    "^As you draw",
    "^Ribbons of.*light",
    "^You are already holding",
}

--- Put regex patterns (item storage responses)
local PUT_PATTERNS = {
    "^You ",
    "Spreading your wings",
    "I could not find what you were referring to",
    "Draping the",
    "Heedful of your surroundings",
    "won't fit",
    "crumbles? and decays? away",
    "crumbles? into a pile of dust",
    "That is not yours",
    "Hey, that belongs to",
    "Get what",
    "Reaching over your shoulder",
    "An ethereal.*light swirls",
    "it reverts to its normal state%.",
}

--- Look regex patterns (container inspection responses)
local LOOK_PATTERNS = {
    '[Pp]eering into the .* noun="toolkit"',
    "[Tt]hat is closed",
    "is shut too tightly to see its contents",
    "[Ii]n the.*you see",
    "[Ii]n the.*:",
    "[Tt]here is nothing",
    "[Yy]ou glance",
    "^Attached to a.*keyring",
    "%[.*%]:",
    'has .- in.*scabbard and .- in.*scabbard%.',
    "^I could not find what you were referring to%.",
    "Hidden within the depths of a cloakwing moth greatcloak",
    "<exposeContainer",
    "<dialogData",
    "<container",
    "stuffed with a variety of shredded up paper and cloth",
    "As much as you'd like to open it, its not closed%.",
    "^Looking at the .*, you notice:",
    "^The .+ has .+ in its left%-hand scabbard and .+ in its right%-hand scabbard%.$",
}

--- Silent open regex patterns (open container responses)
local SILENT_OPEN_PATTERNS = {
    "[Yy]ou throw back",
    "[Yy]ou open",
    "Oh no! It's already",
    "[Yy]ou pick at the knot",
    "already open",
    "is open already",
    "[Yy]ou unfasten",
    "[Yy]ou glance around suspiciously",
    "^What were you referring to%?",
    "^I could not find what you were referring to%.",
    "[Yy]ou pull the long strips of leather",
    "With a flick of your wrist",
    "Sliding the lever on the side",
    "[Yy]ou rub your hand",
    "There doesn't seem to be any way",
    "Roundtime: %d+ [Ss]ec",
    "%.%.%.wait %d+ [Ss]ec",
    "crumbles? and decays? away",
    "crumbles? into a pile of dust",
    "Myriad spectral moths pull a cloakwing",
    "<exposeContainer",
    "<container",
    "[Yy]ou undo each of the",
    "stuffed with a variety of shredded up paper and cloth",
}

--- Close regex patterns
local CLOSE_PATTERNS = {
    "You close .*",
    "That is already closed",
    "It is already closed",
    "What were you referring to",
    "seem to be any way to do that",
    "You tie",
    "You fasten the",
}

--- Urchin message patterns
local URCHIN_MSG_PATTERNS = {
    "You .* ",  -- flag|summon|ask|consult|stride|go|inventory|recollect|offer|strut|sweep|casually|hear|currently
    "An elven page",
    "Unsure exactly",
    "A bloom of wildflowers",
    "A thin layer of hoarfrost",
    "Making a decision",
    "With a cautious glance",
    "As if sensing your",
    "Sudden gusts of wind",
    "Motes of light blink",
    "A single mote of",
    "A dense fog rolls",
    "Shadowy tendrils rise",
}

--- Disk noun patterns
local DISK_NOUNS = {
    "bassinet", "cassone", "chest", "coffer", "coffin", "coffret",
    "disk", "hamper", "saucer", "sphere", "trunk", "tureen",
}

--- Gold ring adjectives for regex matching
local GOLD_RING_ADJECTIVES = {
    "dingy", "plain", "braided", "twisted", "intricate", "large", "thin",
    "wide", "polished", "scratched", "thick", "dull", "faded", "small",
    "flawless", "inlaid", "dirt%-caked", "ornate", "exquisite", "shiny",
    "bright", "narrow",
}

--- Rejected loot names (items never looted)
local REJECT_LOOT_NAMES = {
    -- 335 Deity
    "golden light",
    "jet black scimitar",
    "midnight black flames",
    "reddish haze",
    "sourceless shadow",
    "swirling blue-green pillar of water",

    -- Ranger vines
    "bramble",
    "briar",
    "clutch of twisted branches",
    "creeper",
    "ivy",
    "smilax",
    "swallowwort",
    "tumbleweed",
    "vine",
    "widgeonweed",

    -- Misc
    "child",
    "jagged crater",
    "massive icicle",
    "point of elemental instability",
    "rolton droppings",
    "rotting tree stump",
    "sealed fissure",
    "severed",
    "slender silvery thread",
    "slippery wooden chute",
    "small puddle",
    "vathor club",
}

--- Rejected loot nouns (nouns never looted)
local REJECT_LOOT_NOUNS = {
    "cloud",
    "cyclone",
    "door",
    "gangplank",
    "kitten",
    "maw",
    "mist",
    "muck",
    "puppy",
    "space",
    "staircase",
}

--- All valid loot category names
local ALL_LOOT_CATEGORIES = {
    "alchemy", "armor", "box", "clothing", "collectible", "cursed",
    "food", "gem", "herb", "jewelry", "junk", "lockpick", "lm trap",
    "magic", "reagent", "scroll", "skin", "uncommon", "valuable",
    "wand", "weapon",
}

--- Test if any pattern in a table matches the given text.
-- @param patterns table of Lua pattern strings
-- @param text string to test
-- @return boolean true if any pattern matched
-- @return string|nil the first matching pattern's capture or the matched text
function M.match_any(patterns, text)
    if not text then return false, nil end
    for _, pat in ipairs(patterns) do
        local m1, m2 = string.find(text, pat)
        if m1 then
            -- Try to grab a capture group
            local cap = string.match(text, pat)
            return true, cap
        end
    end
    return false, nil
end

--- Test if a noun matches the disk nouns list
-- @param noun string
-- @return boolean
function M.is_disk_noun(noun)
    if not noun then return false end
    for _, dn in ipairs(DISK_NOUNS) do
        if noun == dn then return true end
    end
    return false
end

--- Test if an item name matches the gold ring pattern
-- @param name string
-- @return boolean
function M.is_gold_ring(name)
    if not name then return false end
    if name == "gold ring" then return true end
    for _, adj in ipairs(GOLD_RING_ADJECTIVES) do
        if string.find(name, "^" .. adj .. " gold ring$") then
            return true
        end
    end
    return false
end

--- Merge and deduplicate a list
-- @param base table
-- @param additions table
-- @return table merged and deduped
local function merge_unique(base, additions)
    local seen = {}
    local result = {}
    for _, v in ipairs(base) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    for _, v in ipairs(additions) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    return result
end

--- Deduplicate a table in-place
-- @param t table
-- @return table the same table, deduped
local function unique(t)
    if not t then return {} end
    local seen = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    return result
end

--- Initialize a new ELoot data state object.
-- @param settings table the user's eloot settings (from CharSettings)
-- @return table the data state object
function M.init(settings)
    local d = {}

    d.settings = settings or {}
    d.start_room = nil
    d.last_called = {}
    d.version = nil  -- set by caller after script version is known
    d.debug_logger = nil
    d.details_check = nil
    d.towns = nil  -- populated by caller from Map.tags("town")

    -- Inventory tracking
    d.sacks_closed = {}
    d.sacks_full = {}
    d.checked_bags = {}
    d.sell_containers = {}
    d.ready_lines = {}
    d.weapon_inv = {}
    d.original_readylist = nil  -- set by caller from ReadyList

    d.coin_hand = nil
    d.coin_container = nil

    d.charm = nil
    d.gauntlet = nil
    d.coin_bag = nil
    d.coin_bag_full = false

    if not d.settings.locksmith_withdraw_amount then
        d.settings.locksmith_withdraw_amount = 8000
    end

    d.gambling_kit = nil
    d.gambling_kit_full = false

    d.disk = nil
    d.disk_full = {}

    d.ready_method = {}

    d.skinners = {}
    d.skinsheath = nil
    d.skin_edged = nil
    d.skin_blunt = nil

    d.blood_band = nil

    d.right_hand = ""
    d.left_hand = ""

    -- Hoarding/bounty
    d.hoard_type = nil
    d.hoard_deposit = nil
    d.items_to_hoard = nil
    d.container_settings = nil
    d.everything_list = nil
    d.everything = nil
    d.only_list = nil
    d.only = nil
    d.inventory = nil
    d.gem_inventory = nil
    d.alchemy_inventory = nil
    d.locker_city = nil
    d.locker = nil
    d.cache = nil
    d.use_hoarding = nil
    d.stash = nil
    d.use_house_locker = nil
    d.che_rooms = {}
    d.che_entry = ""
    d.che_exit = nil

    d.alchemy_mode = false

    d.local_gemshop = nil
    d.local_furrier = nil

    -- Misc
    d.account_type = nil
    d.silver_breakdown = {}  -- default 0 for missing keys handled via setmetatable
    setmetatable(d.silver_breakdown, {
        __index = function() return 0 end,
    })
    d.inv_save = true

    d.gemshop_first = false
    d.log_unlootables = d.settings.log_unlootables
    d.exclude = {}

    -- Build exclude patterns from settings
    if d.settings.loot_exclude then
        for _, r in ipairs(d.settings.loot_exclude) do
            table.insert(d.exclude, r)
        end
    end

    -- Crumbly items: merge defaults with user settings
    if not d.settings.crumbly then
        d.settings.crumbly = {}
    end
    d.settings.crumbly = merge_unique(d.settings.crumbly, DEFAULT_CRUMBLY)

    -- Track full sacks defaults to true
    if d.settings.track_full_sacks == nil then
        d.settings.track_full_sacks = true
    end

    -- Ensure lists exist and are unique
    if not d.settings.unlootable then d.settings.unlootable = {} end
    d.settings.unlootable = unique(d.settings.unlootable)

    if not d.settings.auto_close then d.settings.auto_close = {} end
    d.settings.auto_close = unique(d.settings.auto_close)

    if d.settings.unskinnable then
        d.settings.unskinnable = unique(d.settings.unskinnable)
    end

    -- Sigil determination
    d.sigil_determination_on_fail = nil

    -- Regex pattern tables (used via M.match_any)
    d.deposit_regex = DEPOSIT_PATTERNS
    d.withdraw_regex = WITHDRAW_PATTERNS
    d.get_regex = GET_PATTERNS
    d.put_regex = PUT_PATTERNS
    d.look_regex = LOOK_PATTERNS
    d.silent_open = SILENT_OPEN_PATTERNS
    d.close_regex = CLOSE_PATTERNS
    d.urchin_msg = URCHIN_MSG_PATTERNS
    d.disk_nouns_regex = DISK_NOUNS
    d.regex_gold_rings = GOLD_RING_ADJECTIVES

    -- Reject lists
    d.reject_loot_names = REJECT_LOOT_NAMES
    d.reject_loot_nouns = REJECT_LOOT_NOUNS

    -- All loot categories
    d.all_loot_categories = ALL_LOOT_CATEGORIES

    return d
end

return M
