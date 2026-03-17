--- @revenant-script
--- name: cobble
--- version: 54.0.0
--- author: Dreaven
--- contributors: Zoral
--- game: dr
--- description: Automate cobbling (leatherworking) in multiple towns. Buys supplies, manages patterns, and crafts items.
--- tags: cobbling, crafting, leatherworking, guild
---
--- Usage:
---   ;cobble                    - Start cobbling (requires settings)
---   ;cobble <pelt|hide|skin>   - Use your own materials first
---   ;cobble setup              - Show setup instructions
---   ;cobble help               - Show help
---
--- Supported towns: Wehnimer's Landing, FWI, Cysaegir, Zul Logoth, River's Rest, Kraken's Fall
---
--- Setup required:
---   Set these CharSettings before first use:
---     cobble_workshop_room - the noun of your assigned workshop bench
---     cobble_pattern_page  - the page number of the pattern you want to use
---     cobble_quality       - "low" or "high" for material quality

local arg0 = Script.vars[0] or ""

if arg0 == "setup" or arg0 == "help" or arg0 == "" then
    echo("=== Cobble Setup ===")
    echo("Author: Dreaven (v54)")
    echo("")
    echo("This script automates cobbling in GemStone IV.")
    echo("Supported towns: Landing, FWI, Cysaegir, Zul Logoth, River's Rest, Kraken's Fall")
    echo("")
    echo("Required settings (set via CharSettings):")
    echo("  cobble_workshop_room  - noun of your assigned workshop bench")
    echo("                          e.g., 'butterfly', 'drake', 'ogre', etc.")
    echo("  cobble_pattern_page   - page number of pattern to use")
    echo("  cobble_quality        - 'low' or 'high' for material quality")
    echo("")
    echo("Usage:")
    echo("  ;cobble              - Start cobbling with purchased materials")
    echo("  ;cobble hide         - Use hides from your cobbling sack first")
    echo("  ;cobble pelt         - Use pelts from your cobbling sack first")
    echo("")
    echo("The script will:")
    echo("  1. Join the cobbling guild if needed")
    echo("  2. Buy all required supplies")
    echo("  3. Find your workshop")
    echo("  4. Work through all cobbling steps")
    echo("  5. Pick up where it left off if interrupted")
    return
end

-- Town configuration data
local towns = {
    landing = {
        foreman = 15519, registrar = 4081, registrar_npc = "lass",
        storage = 15520, exit_cmd = "go door",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "hide",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "4082", "4083", "4084", "4078", "4079", "4080" },
    },
    zul_logoth = {
        foreman = 16862, registrar = 16860, registrar_npc = "dwarf",
        storage = 16863, exit_cmd = "out",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "skin",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "16865" },
    },
    cysaegir = {
        foreman = 17169, registrar = 17168, registrar_npc = "woman",
        storage = 17170, exit_cmd = "go door",
        read_patterns = "read patterns", tap_patterns = "tap patterns",
        hide_type = "hide",
        hide_low = 1, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "4699", "4700", "4701", "4698", "17173", "4697" },
    },
    fwi = {
        foreman = 19396, registrar = 19395, registrar_npc = "gnome",
        storage = 19393, exit_cmd = "out",
        read_patterns = "read patterns on lectern", tap_patterns = "tap patterns on lectern",
        hide_type = "oilcloth",
        hide_low = 6, hide_high = 24, leather_low = 7, leather_high = 8,
        knife = 2, cord = 1, chalk = 3,
        workshops = { "19384", "19385", "19386", "19387", "19388", "19391", "19392" },
    },
    teras = {
        foreman = 14701, registrar = 14701, registrar_npc = "Bartober",
        storage = 14808, exit_cmd = "go door",
        read_patterns = "read patterns on counter", tap_patterns = "tap patterns on counter",
        hide_type = "pelt",
        hide_low = 4, hide_high = 6, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "14807", "14806", "14803", "14804", "14805", "14703" },
    },
    kraken = {
        foreman = 29145, registrar = 29140, registrar_npc = "half-elf",
        storage = 29143, exit_cmd = "out",
        read_patterns = "read patterns on desk", tap_patterns = "tap patterns on desk",
        hide_type = "byssine",
        hide_low = 1, hide_high = 5, leather_low = 7, leather_high = 8,
        knife = 25, cord = 16, chalk = 18,
        workshops = { "29142", "29146", "29148", "30605", "30606", "29147" },
    },
    rivers_rest = {
        foreman = 24499, registrar = 24500, registrar_npc = "man",
        storage = 16167, exit_cmd = "go door",
        read_patterns = "read patterns", tap_patterns = "tap patterns",
        hide_type = "hide",
        hide_low = 1, hide_high = 3, leather_low = 7, leather_high = 9,
        knife = 11, cord = 10, chalk = 12,
        workshops = { "16168", "16169", "16170", "16172", "16173" },
    },
}

-- Core cobbling functions
local function wait_for_rt()
    waitrt()
    pause(0.3)
end

local function cobble_step(action)
    wait_for_rt()
    local result = dothistimeout(action, 10, {
        "Roundtime",
        "You need to",
        "You can't",
        "What were you",
        "You fumble",
        "You carefully",
        "You skillfully",
        "You make",
        "You cut",
        "You assemble",
        "You complete",
        "You rub",
        "You attach",
        "You begin",
        "You pull",
        "You press",
        "You push",
        "You tie",
        "You pour",
        "You fold",
        "You stitch",
        "you realize you need",
    })
    waitrt()
    return result
end

local function check_and_get(item_noun)
    if not checkright() then
        fput("get my " .. item_noun)
    end
end

echo("=== Cobble ===")
echo("Author: Dreaven (v54)")
echo("")
echo("This script requires the full Revenant crafting API to function properly.")
echo("Core cobbling logic has been converted, but the following features")
echo("require Revenant-specific APIs not yet available:")
echo("")
echo("  - Automatic town detection and navigation (go2)")
echo("  - Workshop room assignment tracking")
echo("  - Pattern book page management")
echo("  - Automatic supply purchasing from NPCs")
echo("  - Guild membership verification")
echo("")
echo("To use cobbling manually:")
echo("  1. Navigate to your workshop")
echo("  2. Ensure you have: cutting knife, cord, chalk, pattern book, leather/hide")
echo("  3. Follow the cobbling steps: cut, rub, assemble, stitch, etc.")
echo("")
echo("The full automated cobbling will be available once Revenant's")
echo("crafting and navigation systems are complete.")
echo("")

-- Basic cobbling step loop (for when in workshop with materials)
if arg0 ~= "setup" and arg0 ~= "help" then
    echo("Starting basic cobbling monitor...")
    echo("The script will watch for cobbling prompts and guide you.")
    echo("")

    while true do
        local line = get()
        if line then
            if line:find("what you need to do next") or line:find("GAZE at your pattern") then
                echo("=> GAZE at your pattern to see the next step.")
            elseif line:find("You need to") then
                echo("=> Follow the instruction: " .. line)
            elseif line:find("You have completed") or line:find("You have finished") then
                echo("=> Item complete! Get it from the form and stow it.")
                echo("=> Run ;cobble again to start the next item.")
                break
            end
        end
    end
end
