--- @revenant-script
--- name: eforgery
--- version: 1.3.0
--- author: elanthia-online
--- contributors: Moredin, Tillek, Gnomad, Tysong, Dissonance
--- game: gs
--- tags: forging, forge, craft, artisan, perfect
--- description: Forgery crafting automation — handles slab/block forging, hammering, tempering, glyphing
---
--- Original Lich5 authors: elanthia-online (Moredin, Tillek, Gnomad, Tysong, Dissonance)
--- Ported to Revenant Lua from eforgery.lic v1.3.0
---
--- Usage:
---   ;eforgery           — start forging with current settings
---   ;eforgery setup     — configure settings (terminal UI)
---   ;eforgery display   — show current settings
---   ;eforgery ?         — show help

local VERSION = "1.3.0"

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local settings = CharSettings.get("eforgery") or {}

-- Defaults
settings.material     = settings.material or ""       -- metal, wood
settings.glyph        = settings.glyph or ""          -- glyph order number
settings.block_sack   = settings.block_sack or ""     -- container for blocks
settings.slab_sack    = settings.slab_sack or ""      -- container for slabs
settings.keeper_sack  = settings.keeper_sack or ""    -- container for keepers
settings.average_sack = settings.average_sack or ""   -- container for average pieces
settings.scrap_sack   = settings.scrap_sack or ""     -- container for scrap
settings.forging_apron = settings.forging_apron or "forging apron"
settings.rent_room    = settings.rent_room or ""      -- room ID for rental workshop
settings.bank_room    = settings.bank_room or ""
settings.afk_check    = (settings.afk_check == nil) and true or settings.afk_check
settings.debug        = settings.debug or false

local function save_settings()
    CharSettings.set("eforgery", settings)
end

save_settings()

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local reps = 0
local total_keepers = 0
local total_average = 0
local total_scrap = 0
local rank_mode = false  -- true if only doing rank work

--------------------------------------------------------------------------------
-- Messaging
--------------------------------------------------------------------------------

local function info(text)
    respond("[eforgery] " .. text)
end

local function dbg(text)
    if settings.debug then respond("[eforgery:debug] " .. text) end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function waitrt_safe()
    waitrt()
end

local function go2(room)
    if not room or room == "" then return end
    Script.run("go2", tostring(room))
end

local function ensure_apron()
    if settings.forging_apron and settings.forging_apron ~= "" then
        fput("remove my " .. settings.forging_apron)
    end
end

local function wear_apron()
    if settings.forging_apron and settings.forging_apron ~= "" then
        fput("wear my " .. settings.forging_apron)
    end
end

local function get_silver(amount)
    if not settings.bank_room or settings.bank_room == "" then
        info("No bank room configured")
        return false
    end
    go2(settings.bank_room)
    fput("withdraw " .. amount .. " silvers")
    local result = matchtimeout(5, "hands you", "don't seem to have")
    return result and result:find("hands you")
end

--------------------------------------------------------------------------------
-- Forging actions
--------------------------------------------------------------------------------

local function rent()
    if not settings.rent_room or settings.rent_room == "" then
        info("No rental workshop room configured")
        return false
    end
    go2(settings.rent_room)

    -- Pay for workshop time
    local npc = nil
    local npcs = GameObj.npcs()
    for _, n in ipairs(npcs) do
        if Regex.test(n.name, "clerk|merchant|attendant") then npc = n; break end
    end
    if npc then
        fput("ask " .. npc.noun .. " about rent")
        local result = matchtimeout(5, "silvers", "already rented", "don't have enough")
        if result and result:find("don't have enough") then
            get_silver(5000)
            fput("ask " .. npc.noun .. " about rent")
        end
    end
    return true
end

local function hammer_time()
    -- Switch to hammer: get hammer, put tongs away
    waitrt_safe()
    fput("get my hammer")
end

local function oil()
    -- Apply oil to the piece on the anvil
    waitrt_safe()
    fput("get my oil")
    fput("pour my oil on anvil")
    waitrt_safe()
    fput("put my oil in my " .. settings.forging_apron)
end

local function glyph()
    if not settings.glyph or settings.glyph == "" then return end
    info("Applying glyph " .. settings.glyph)

    fput("get my burin")
    waitrt_safe()

    -- The burin is used to scribe the glyph
    put("turn my burin to " .. settings.glyph)
    matchtimeout(5, "You turn", "already")
    waitrt_safe()

    put("scribe my burin on anvil")
    local result = matchtimeout(10, "You carefully", "not been placed", "has not been scribed")
    waitrt_safe()

    fput("put my burin in my " .. settings.forging_apron)
end

local function keeper()
    info("KEEPER piece! (rep " .. reps .. ")")
    total_keepers = total_keepers + 1

    if settings.keeper_sack and settings.keeper_sack ~= "" then
        fput("put left in my " .. settings.keeper_sack)
    else
        fput("stow left")
    end
end

local function average()
    info("Average piece (rep " .. reps .. ")")
    total_average = total_average + 1

    if settings.average_sack and settings.average_sack ~= "" then
        fput("put left in my " .. settings.average_sack)
    else
        fput("stow left")
    end
end

local function trash(item_desc)
    info("Scrapping: " .. (item_desc or "piece"))
    total_scrap = total_scrap + 1

    if settings.scrap_sack and settings.scrap_sack ~= "" then
        fput("put left in my " .. settings.scrap_sack)
    else
        -- Look for a barrel/crate to trash it
        local trash_obj = nil
        for _, obj in ipairs(GameObj.loot() or {}) do
            if Regex.test(obj.noun, "barrel|crate|wastebarrel") then trash_obj = obj; break end
        end
        if trash_obj then
            fput("put left in #" .. trash_obj.id)
        else
            fput("drop left")
        end
    end
end

local function afk_wait()
    if not settings.afk_check then return end
    -- Pause and wait for user attention — replaces Lich5's level prompt wait
    info("AFK check — pausing for 30 seconds. Resume with ;unpause eforgery")
    Script.pause()
end

--------------------------------------------------------------------------------
-- Main forge cycle
--------------------------------------------------------------------------------

local function forge_cycle()
    -- Get material from sack
    local material_sack = settings.block_sack
    if settings.material:lower():find("slab") then
        material_sack = settings.slab_sack
    end

    if not material_sack or material_sack == "" then
        info("No material container configured!")
        return false
    end

    fput("get my " .. settings.material .. " from my " .. material_sack)
    local get_result = matchtimeout(3, "You remove", "Get what", "I could not")
    if not get_result or get_result:find("Get what") or get_result:find("could not") then
        info("No more " .. settings.material .. " in " .. material_sack)
        return false
    end

    -- Go to anvil room if not already there
    fput("go door")
    ensure_apron()

    -- Place on anvil
    fput("put my " .. settings.material .. " on anvil")
    waitrt_safe()

    -- Main forging loop
    local done = false
    while not done do
        hammer_time()

        fput("get tongs")
        put("push my tongs on anvil")
        local line = matchtimeout(15,
            "tempering trough is empty",
            "will be ruined if you try",
            "tongs on the anvil",
            "tongs to the anvil",
            "need to be holding",
            "material you want to work",
            "expired",
            "has not been scribed",
            "hanging crystal and spreads",
            "into the tempering trough",
            "anvil as you shake your head",
            "hammer in your right",
            "this would be a real waste",
            "best work"
        )
        dbg(line or "(no match)")
        waitrt_safe()

        if not line then
            info("No response — retrying")
        elseif line:find("need to be holding") or line:find("material you want to work") then
            info("Error: missing material or tongs")
            return false
        elseif line:find("this would be a real waste") or line:find("will be ruined") or line:find("trough is empty") then
            oil()
        elseif line:find("hammer in your right") then
            hammer_time()
        elseif line:find("tongs to the anvil") or line:find("has not been scribed") then
            done = true
            fput("go door")
            wear_apron()
            glyph()
        elseif line:find("expired") then
            fput("go door")
            fput("out")
            rent()
            fput("go door")
        elseif line:find("best work") then
            reps = reps + 1
            done = true
            wear_apron()
            fput("go door")
            if rank_mode then
                trash(GameObj.left_hand and GameObj.left_hand().name or "piece")
            else
                keeper()
            end
        elseif line:find("into the tempering trough") then
            reps = reps + 1
            done = true
            wear_apron()
            fput("go door")
            if rank_mode then
                trash(GameObj.left_hand and GameObj.left_hand().name or "piece")
            else
                average()
            end
        else
            -- AFK check on certain results
            if line:find("anvil as you shake") or line:find("tongs on the anvil") or line:find("hanging crystal") then
                afk_wait()
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Display settings
--------------------------------------------------------------------------------

local function display_settings()
    respond("\n=== eForgery v" .. VERSION .. " Settings ===")
    respond("Material:       " .. (settings.material ~= "" and settings.material or "(not set)"))
    respond("Glyph:          " .. (settings.glyph ~= "" and settings.glyph or "(not set)"))
    respond("Block sack:     " .. (settings.block_sack ~= "" and settings.block_sack or "(not set)"))
    respond("Slab sack:      " .. (settings.slab_sack ~= "" and settings.slab_sack or "(not set)"))
    respond("Keeper sack:    " .. (settings.keeper_sack ~= "" and settings.keeper_sack or "(not set)"))
    respond("Average sack:   " .. (settings.average_sack ~= "" and settings.average_sack or "(not set)"))
    respond("Scrap sack:     " .. (settings.scrap_sack ~= "" and settings.scrap_sack or "(not set)"))
    respond("Forging apron:  " .. settings.forging_apron)
    respond("Rent room:      " .. (settings.rent_room ~= "" and settings.rent_room or "(not set)"))
    respond("Bank room:      " .. (settings.bank_room ~= "" and settings.bank_room or "(not set)"))
    respond("AFK check:      " .. tostring(settings.afk_check))
    respond("Debug:          " .. tostring(settings.debug))
    respond("===\n")
end

--------------------------------------------------------------------------------
-- Setup (terminal-based key=value)
--------------------------------------------------------------------------------

local function show_setup_help()
    respond("\n=== eForgery Setup ===")
    respond("Use ;eforgery set <key> <value> to configure:")
    respond("")
    respond("  material      — block/slab material name (e.g., 'imflass block')")
    respond("  glyph         — glyph order number")
    respond("  block_sack    — container for blocks")
    respond("  slab_sack     — container for slabs")
    respond("  keeper_sack   — container for keeper pieces")
    respond("  average_sack  — container for average pieces")
    respond("  scrap_sack    — container for scrap (or empty to drop)")
    respond("  apron         — forging apron item name")
    respond("  rent_room     — room ID for rental workshop")
    respond("  bank_room     — room ID for bank")
    respond("  afk           — on/off for AFK checking")
    respond("  debug         — on/off for debug messages")
    respond("")
    respond("Example: ;eforgery set material imflass block")
    respond("Example: ;eforgery set glyph 42")
    respond("===\n")
end

local function handle_set(key, value)
    if key == "material" then settings.material = value
    elseif key == "glyph" then settings.glyph = value
    elseif key == "block_sack" then settings.block_sack = value
    elseif key == "slab_sack" then settings.slab_sack = value
    elseif key == "keeper_sack" then settings.keeper_sack = value
    elseif key == "average_sack" then settings.average_sack = value
    elseif key == "scrap_sack" then settings.scrap_sack = value
    elseif key == "apron" then settings.forging_apron = value
    elseif key == "rent_room" then settings.rent_room = value
    elseif key == "bank_room" then settings.bank_room = value
    elseif key == "afk" then settings.afk_check = (value == "on")
    elseif key == "debug" then settings.debug = (value == "on")
    else
        info("Unknown setting: " .. key)
        return
    end
    save_settings()
    info("Set " .. key .. " = " .. value)
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("\n=== eForgery v" .. VERSION .. " ===")
    respond("Author: elanthia-online (Moredin, Tillek, Gnomad, Tysong, Dissonance)")
    respond("")
    respond("Usage:")
    respond("  ;eforgery              — start forging")
    respond("  ;eforgery rank         — forge for rank only (scraps everything)")
    respond("  ;eforgery display      — show current settings")
    respond("  ;eforgery setup        — show setup instructions")
    respond("  ;eforgery set <k> <v>  — set a config value")
    respond("  ;eforgery ?            — show this help")
    respond("")
    respond("IMPORTANT:")
    respond("  - Oil type is auto-determined")
    respond("  - Leaving Average/Scrap sacks blank causes pieces to be discarded")
    respond("  - Block, Slab, Keeper, and Scrap containers MUST be different")
    respond("  - 'Average' & 'Keeper' containers should be different")
    respond("  - To make HANDLES, set handle order # for glyph, and wood/metal for material")
    respond("  - This script does NOT combine/vise the pieces")
    respond("===\n")
end

--------------------------------------------------------------------------------
-- Upstream hook for set command
--------------------------------------------------------------------------------

local function on_upstream(line)
    local key, value = line:match("^;eforgery%s+set%s+(%S+)%s+(.*)")
    if key then
        handle_set(key, value:match("^%s*(.-)%s*$"))
        return nil
    end
    return line
end

UpstreamHook.add("eforgery", on_upstream)
Script.at_exit(function() UpstreamHook.remove("eforgery") end)

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local input = Script.vars[1] or ""

if input:match("^display$") then
    display_settings()
    return
elseif input:match("^setup$") then
    show_setup_help()
    return
elseif input:match("^%?$") or input:match("^help$") then
    show_help()
    return
elseif input:match("^rank$") then
    rank_mode = true
    info("Rank mode: all pieces will be scrapped")
end

-- Validate settings
if settings.material == "" then
    info("Material not set! Run ;eforgery setup")
    return
end

info("eForgery v" .. VERSION .. " starting" .. (rank_mode and " (RANK MODE)" or ""))

-- Main loop: forge until out of materials
local cycle_count = 0
while true do
    local ok = forge_cycle()
    if not ok then break end
    cycle_count = cycle_count + 1
end

info("Forging complete after " .. cycle_count .. " cycles")
info("Keepers: " .. total_keepers .. "  Average: " .. total_average .. "  Scrap: " .. total_scrap)
