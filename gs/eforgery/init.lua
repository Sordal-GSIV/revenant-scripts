--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: eforgery
--- version: 1.3.0
--- author: elanthia-online
--- contributors: Moredin, Tillek, Gnomad, Tysong, Dissonance
--- game: gs
--- tags: forging, forge, craft, artisan, perfect
--- description: Forgery crafting automation — slab cutting, material forging, tempering, grinding, glyphing, polishing, auto-oil, promissory notes, GUI setup
---
--- Original Lich5 authors: elanthia-online (Moredin, Tillek, Gnomad, Tysong, Dissonance)
--- Ported to Revenant Lua from eforgery.lic v1.3.0
---
--- Changelog (from Lich5):
---   v1.3.0 (2025-12-26)
---     Removed deposit all from withdrawal routine, since it deposits the note we have and resets that
---     Further improved silver handling to avoid unnecessary bank trips
---     Fixed processing of slabs/blocks where they are already the correct size
---     Reworked messaging to use Lich::Messaging instead of puts/respond/echo
---     Significantly expanded in-line documentation
---     Updated afk script guard to pause the script instead of waiting for level prompt
---   v1.2.3 (2025-11-15)
---     bugfix in get note to deposit existing note
---     change to using Script.run instead of start_script/wait_while
---   v1.2.2 (2025-05-23)
---     Remove CharSettings.load - not used
---   v1.2.1 (2025-05-07)
---     Change from CharSettings.save to Settings.save
---   v1.2.0 (2025-03-22)
---     Will uses notes on you instead of running to the bank every action
---     Modified the trashing routine to use the "trash" verb
---     Modified the trash barrel location for Ta'Vaalor to be closer to the forge
---   v1.1.0 (2023-07-11)
---     Remove support for making iron slabs via ;iron script
---   v1.0.5 (2023-06-26)
---     Fix for ClimateWear containers, missing glyph, grind/tongs RT check
---   v1.0.4 (2023-06-03)
---     Fix for vaalor material oil, Rubocop cleanup
---   v1.0.3 (2022-05-03)
---     Bugfix for variables outside of class
---   v1.0.2 (2022-05-02)
---     Bugfix for regex match
---   v1.0.1 (2022-04-29)
---     Fix for commageddon. Combine buy regex, remove location check
---   v1.0.0 (2022-03-29)
---     Rename to eforgery from forgery for ease of distribution
---   Pre-Elanthia Online: Heavily modified from Dalem's dforge script.
---     Gnomad fork Oct 2015 — various bugfixes, rank mode, OHE support, AFK tweaks.
---     Mar 2017: Killed gift/trash options for lumnis change.

---------------------------------------------------------------------------
-- Submodule requires
---------------------------------------------------------------------------
local settings_mod = require("eforgery/settings")
local helpers      = require("eforgery/helpers")
local cutting      = require("eforgery/cutting")
local forge_mod    = require("eforgery/forge")
local gui          = require("eforgery/gui")

---------------------------------------------------------------------------
-- Load settings into runtime state
---------------------------------------------------------------------------
local state = settings_mod.load()

-- Runtime counters (not persisted)
state.keepers        = 0
state.successes      = 0
state.failures       = 0
state.major_failures = 0
state.reps           = 0
state.size           = nil     -- glyph measured block size
state.wastebin       = nil     -- nearest trash receptacle noun
state.note           = nil     -- current promissory note GameObj
state.rank           = false   -- rank mode (trash everything)
state.afk            = false   -- afk checking enabled
state.afk_count      = 2       -- reps between afk checks

---------------------------------------------------------------------------
-- Wire cross-module dependencies
---------------------------------------------------------------------------
helpers.wire({ state = state })
cutting.wire({ helpers = helpers, state = state })
forge_mod.wire({ helpers = helpers, state = state, cutting = cutting })

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
before_dying(function()
    forge_mod.breakdown()
    helpers.remove_squelch()
end)

---------------------------------------------------------------------------
-- First-run notice
---------------------------------------------------------------------------
if state.first_run == nil then
    respond("[eforgery] IMPORTANT (First Run Only):")
    respond("[eforgery] ~Oil type (if needed) will be auto-determined.")
    respond("[eforgery] ~Leaving Average and Scrap settings BLANK will trash those pieces.")
    respond("[eforgery] ~Block, Slab, Keeper, and Scrap containers MUST be different.")
    respond("[eforgery] ~'Average' & 'Keeper' containers should be different.")
    respond("[eforgery] ~To make HANDLES, set handle order # for glyph, and wood/metal for material.")
    respond("[eforgery] ~This script does NOT combine/vise the pieces for you.")
    respond("")
    respond("[eforgery] For help type ;eforgery help")
    respond("")
    respond("[eforgery] Continuing in 10 seconds...")
    state.first_run = false
    settings_mod.save(state)
    pause(10)
end

---------------------------------------------------------------------------
-- Usage / help
---------------------------------------------------------------------------
local function usage()
    respond("")
    respond("eforgery SETUP:")
    respond("  ;eforgery set average <container>   -- container for average pieces (blank = trash)")
    respond("  ;eforgery set oil <container>       -- container for tempering oil")
    respond("  ;eforgery set keepers <container>   -- container for keepers (perfect pieces)")
    respond("  ;eforgery set slabs <container>     -- container for raw slabs")
    respond("  ;eforgery set blocks <container>    -- container for cut slab blocks")
    respond("  ;eforgery set scraps <container>    -- container for scraps (blank = trash)")
    respond("  ;eforgery set glyph <name> <container> <#> <material>")
    respond("  ;eforgery set material <name> <noun> <order #>")
    respond("  ;eforgery set make_hammers <true/false>")
    respond("  ;eforgery set surge <true/false>")
    respond("  ;eforgery set squelch <true/false>")
    respond("  ;eforgery set safe_keepers <true/false>")
    respond("  ;eforgery set note_size <amount>")
    respond("  ;eforgery set debug <true/false>")
    respond("  ;eforgery set <name>               -- clears that setting")
    respond("  ;eforgery display                  -- display current Settings")
    respond("")
    respond("IMPORTANT:")
    respond("  Block, Slab, Scrap, Keeper containers MUST be different.")
    respond("  Leaving the average and scrap settings blank causes them to be trashed.")
    respond("  *To use your own glyphs, do NOT set order # or material.")
    respond("")
    respond("eforgery USAGE:")
    respond("  ;eforgery                  -- begin forging and polishing best pieces")
    respond("  ;eforgery afk [#]          -- forge with AFK checks every # reps (default 2)")
    respond("  ;eforgery rank [afk [#]]   -- forge for rank only (trashes everything)")
    respond("  ;eforgery forge [#]        -- forge [optionally # times]")
    respond("  ;eforgery polish           -- polish rough pieces in keeper container")
    respond("  ;eforgery cut <size> <#>   -- cut # pieces of <size> from one slab")
    respond("  ;eforgery keepers <#>      -- forge until # keepers are made")
    respond("  ;eforgery display          -- show current settings")
    respond("  ;eforgery setup            -- open GUI setup window")
    respond("  ;eforgery set ...          -- set individual settings")
    respond("  ;eforgery help             -- show this help")
    respond("")
end

---------------------------------------------------------------------------
-- Setup routine — initialize forging session
---------------------------------------------------------------------------
local function setup()
    helpers.dbg("setup")

    if state.squelch then
        helpers.dbg("squelch enabled")
        helpers.install_squelch()
        helpers.info("Squelch active")
    end

    helpers.find_wastebin()
    helpers.wear_apron()
    helpers.empty_hands()
    helpers.rent()
end

---------------------------------------------------------------------------
-- Navigate to forge if not already there
---------------------------------------------------------------------------
local function ensure_at_forge()
    waitrt()
    if not checkroom("Forge", "Workshop") then
        Script.run("go2", "forge")
    elseif checkroom("Forge") then
        move("go door")
    end
end

---------------------------------------------------------------------------
-- Show inventory status
---------------------------------------------------------------------------
local function show_inventory()
    if state.average_container then fput("look in my " .. state.average_container) end
    if state.keeper_container then fput("look in my " .. state.keeper_container) end
    fput("inventory")
end

---------------------------------------------------------------------------
-- Parse arguments
---------------------------------------------------------------------------
local args = {}
local raw = Script.vars[0] or ""
for word in raw:gmatch("%S+") do
    table.insert(args, word)
end
local cmd = args[1] and args[1]:lower() or nil

---------------------------------------------------------------------------
-- Command dispatch
---------------------------------------------------------------------------

if cmd == "setup" or cmd == "settings" then
    gui.show(state)
    return

elseif cmd == "display" then
    settings_mod.display(state)
    return

elseif cmd == "set" then
    settings_mod.handle_set(state, args)
    return

elseif cmd == "help" or cmd == "?" then
    usage()
    return

elseif cmd == "polish" then
    ensure_at_forge()
    setup()
    show_inventory()
    helpers.rent()
    forge_mod.polish()

elseif cmd == "cut" then
    local cut_size = tonumber(args[2])
    local cut_count = tonumber(args[3])
    if not cut_size then
        helpers.warn("Usage: ;eforgery cut <size> <count>")
        return
    end
    ensure_at_forge()
    setup()
    fput("inventory")
    cutting.cut(cut_size, cut_count)

elseif cmd == "keepers" then
    local target_keepers = tonumber(args[2])
    if not target_keepers then
        helpers.warn("Usage: ;eforgery keepers <number>")
        return
    end
    if not state.keeper_container then
        helpers.warn("You must first set a keeper container.")
        return
    end
    ensure_at_forge()
    setup()
    cutting.prepare()
    show_inventory()
    while state.keepers < target_keepers do
        forge_mod.forge()
        forge_mod.polish()
    end

elseif cmd == "forge" then
    local forge_count = tonumber(args[2])
    ensure_at_forge()
    setup()
    cutting.prepare()
    show_inventory()
    if forge_count and forge_count > 0 then
        for _ = 1, forge_count do
            forge_mod.forge()
        end
    else
        while true do
            forge_mod.forge()
        end
    end

elseif cmd == "rank" then
    state.rank = true
    if args[2] and args[2]:lower() == "afk" then
        state.afk = true
        state.afk_count = tonumber(args[3]) or 2
    end
    ensure_at_forge()
    setup()
    cutting.prepare()
    show_inventory()
    while true do
        forge_mod.forge()
    end

elseif cmd == "afk" then
    state.afk = true
    state.afk_count = tonumber(args[2]) or 2
    ensure_at_forge()
    setup()
    cutting.prepare()
    show_inventory()
    while true do
        forge_mod.forge()
        forge_mod.polish()
    end

elseif not cmd then
    -- default: forge + polish loop
    ensure_at_forge()
    setup()
    cutting.prepare()
    show_inventory()
    while true do
        forge_mod.forge()
        forge_mod.polish()
    end

else
    usage()
end
