--- @revenant-script
--- name: blackarts
--- version: 3.12.0
--- author: elanthia-online
--- contributors: Demandred, Lieo, Selandriel, Ondreian, Tysong, Deysh, Luxelle
--- game: gs
--- description: Sorcerer guild alchemy automation — task management, recipe tracking, foraging, hunting, and crafting
--- tags: alchemy,guild,sorcerer,crafting,hunting
---
--- Ported from Lich5 Ruby BlackArts.lic v3.12.x
--- Original authors: elanthia-online, Deysh, Tysong, Gob
---
--- Changelog:
---   v3.12.0 (2026-03-18) — Full Revenant conversion (folder script)
---     - Complete recipe database (all alchemy/potions/trinkets/buy/grind/forage/kill)
---     - Full 5-tab settings GUI (Revenant Gui API)
---     - All 6 illusion types (rose, vortex, maelstrom, void, shadow, demon)
---     - Full hunting module (70+ creature/room mappings)
---     - Complete guild task routing with cauldron workshop recipes
---     - Buy/forage/kill supply acquisition
---     - Multi-guild travel
---     - Consignment selling, banking, mana management
---
--- Usage:
---   ;blackarts              Start automated guild tasking
---   ;blackarts setup        Open settings GUI
---   ;blackarts suggest      Show recipe suggestions
---   ;blackarts check ITEM   Check if you can make an item
---   ;blackarts make ITEM    Make a specific item
---   ;blackarts forage HERB  Forage for a specific herb
---   ;blackarts buy          Buy elusive reagents from reagent shop
---   ;blackarts remove SKILL Trade in current guild task
---   ;blackarts guild        Travel to the alchemy administrator
---   ;blackarts help         Show help
---   ;blackarts finish       Stop after current task (while running)
---
--- @lic-certified: complete 2026-03-18

no_pause_all()

--------------------------------------------------------------------------------
-- Module loading
--------------------------------------------------------------------------------

local settings_mod = require("settings")
local state        = require("state")
local util         = require("util")
local inv          = require("inventory")
local guild        = require("guild")

--------------------------------------------------------------------------------
-- Load settings
--------------------------------------------------------------------------------

local cfg = settings_mod.load()
util.cfg  = cfg   -- inject into util so all modules can access

-- Parse banking amounts from string settings
state.note_withdrawal = settings_mod.parse_silver(cfg.note_withdrawal, 50000)
state.note_refresh    = settings_mod.parse_silver(cfg.note_refresh, 5000)

-- River's Rest travel setting
if cfg.rr_travel then
    state.west_guilds[#state.west_guilds + 1] = 10861
end

-- No-forage rooms from settings (merged with hardcoded list)
if cfg.no_forage_rooms and cfg.no_forage_rooms ~= "" then
    for _, id_str in ipairs(util.split(cfg.no_forage_rooms, ",")) do
        local id = tonumber(id_str)
        if id then
            local already = false
            for _, nf in ipairs(state.no_forage) do
                if nf == id then already = true; break end
            end
            if not already then state.no_forage[#state.no_forage + 1] = id end
        end
    end
end

-- Voln forage exclusion (room behind Voln gate, skip if Voln member)
if Society.member and not Society.member:lower():find("voln") then
    local voln_ids = Map.ids_from_uid(14116015)
    if voln_ids and voln_ids[1] then
        state.no_forage[#state.no_forage + 1] = voln_ids[1]
    end
end

-- Initialise shared regex patterns
state.get_regex = Regex.new(
    "^You (?:shield|discreetly |carefully |deftly |slowly )?(?:remove|draw|grab|reach|slip|tuck|retrieve|already have|unsheathe|detach|swap|sling)" ..
    "|^Get what\\?$" ..
    "|^Why don't you leave some for others" ..
    "|^You need a free hand" ..
    "|^You already have" ..
    "|^You take" ..
    "|Reaching over your shoulder" ..
    "|^As you draw" ..
    "|^Ribbons of.*?light" ..
    "|^An eclipse of spectral moths" ..
    "|^You aren't assigned that task"
)
state.put_regex = Regex.new(
    "^(?:You carefully (?:add|hang|secure))" ..
    "|^(?:You (?:put|(?:discreetly )?tuck|attach|toss|place|.*? place|slip|wipe off the blade|absent-mindedly drop|find an incomplete bundle|untie your drawstring))" ..
    "|^The .+ is already a bundle" ..
    "|^Your bundle would be too large" ..
    "|^The .+ is too large to be bundled" ..
    "|If you wish to continue, throw the item away" ..
    "|you feel pleased with yourself at having cleaned" ..
    "|over your shoulder" ..
    "|two items in that location" ..
    "|^Your .*? won't fit"
)

--------------------------------------------------------------------------------
-- Start town and profile directory setup
--------------------------------------------------------------------------------

local start_town_result = Map.find_nearest_by_tag("town")
if start_town_result then
    state.start_town = start_town_result.id
end
state.visited_towns = {state.start_town}

state.profile_dir = string.format("data/gs/%s/bigshot_profiles", Char.name)

--------------------------------------------------------------------------------
-- Upstream hook: ;blackarts finish → set once_and_done
--------------------------------------------------------------------------------

local HOOK_ID         = "blackarts_finish_hook"
local original_once   = cfg.once_and_done

Hook.add(HOOK_ID, "upstream", function(line)
    if Regex.test(line, "^(?:<c>)?;bla.*finish") then
        cfg.once_and_done = true
        respond("[BlackArts] Will stop after the next task completes.")
        return nil
    end
    return line
end)

before_dying(function()
    Hook.remove(HOOK_ID)
    cfg.once_and_done = original_once
end)

--------------------------------------------------------------------------------
-- Silence output
--------------------------------------------------------------------------------

if cfg.silence then silence_me() end

--------------------------------------------------------------------------------
-- Argument dispatch
--------------------------------------------------------------------------------

local cmd  = (Script.vars[1] or ""):lower()
local args = Script.vars

-- Help
if cmd == "help" then
    respond("")
    respond("=== BlackArts v3.12.0 — Alchemy Guild Automation ===")
    respond("")
    respond("  ;blackarts              Start automated guild tasking")
    respond("  ;blackarts setup        Open settings GUI")
    respond("  ;blackarts suggest      Show recipe suggestions for current tasks")
    respond("  ;blackarts check ITEM   Check ingredients for a recipe")
    respond("  ;blackarts make ITEM    Make a specific item")
    respond("  ;blackarts forage HERB  Forage for a specific herb")
    respond("  ;blackarts buy          Buy elusive reagents from reagent shop")
    respond("  ;blackarts remove SKILL Trade in current guild task")
    respond("  ;blackarts guild        Travel to the alchemy administrator")
    respond("  ;blackarts list         Show current settings")
    respond("  ;blackarts --debug=on   Toggle debug output")
    respond("")
    respond("  While running:")
    respond("    ;blackarts finish     Stop after current task completes")
    respond("")
    return
end

-- Setup GUI
if cmd == "setup" or cmd == "config" then
    require("gui_settings").show(cfg)
    return
end

-- List settings
if cmd == "list" then
    respond("")
    respond("=== BlackArts Settings ===")
    respond("  Skills: " .. table.concat(cfg.skill_types, ", "))
    respond("  Guild Travel: " .. tostring(cfg.guild_travel))
    respond("  Buy Reagents: " .. tostring(cfg.buy_reagents))
    respond("  No Bank: " .. tostring(cfg.no_bank))
    respond("  Silence: " .. tostring(cfg.silence))
    respond("  Debug: " .. tostring(cfg.debug))
    respond("")
    return
end

-- Debug toggle
if cmd == "--debug=on" then
    cfg.debug = true
    settings_mod.save(cfg)
    respond("[BlackArts] Debug mode on.")
    return
elseif cmd == "--debug=off" then
    cfg.debug = false
    settings_mod.save(cfg)
    respond("[BlackArts] Debug mode off.")
    return
end

-- Suggest recipes
if cmd == "suggest" or cmd == "suggestions" then
    local guild_status = guild.gld()
    guild_status = guild.gld_suggestions(guild_status)
    respond("")
    respond("=== BlackArts Recipe Suggestions ===")
    respond("")
    for _, skill_type in ipairs({"alchemy", "potions", "trinkets", "illusions"}) do
        local info = guild_status[skill_type]
        if info then
            local rank = info.rank or 0
            local reps = info.reps or 0
            local task = info.task or "no task"
            respond(string.format("  %s: Rank %d, %d reps remaining", skill_type, rank, reps))
            respond(string.format("  Task: %s", task))
            if info.recipes and #info.recipes > 0 then
                respond(string.format("  Viable recipes (%d):", #info.recipes))
                local shown = 0
                for _, r in ipairs(info.recipes) do
                    if shown < 10 then
                        respond(string.format("    - %s (rank %d–%d)", r.product,
                            r.rank and r.rank[1] or 0, r.rank and r.rank[2] or 0))
                        shown = shown + 1
                    end
                end
                if #info.recipes > 10 then
                    respond(string.format("    ...and %d more", #info.recipes - 10))
                end
            else
                respond("  No viable recipes found.")
            end
            respond("")
        end
    end
    return
end

-- Check ingredients for a recipe
if cmd == "check" or cmd == "prepare" then
    local product = table.concat(args, " ", 2)
    if product == "" then
        respond("Usage: ;blackarts check <recipe name> [x<count>]")
        return
    end
    -- Parse optional count suffix x<n>
    local count_str = product:match("x(%d+)$")
    local reps = count_str and tonumber(count_str) or 1
    product = product:gsub("%s*x%d+$", "")
    inv.init_sacks()
    local ok, tracker = pcall(guild.check_recipe, {name=product, reps=reps})
    if not ok then
        respond("[BlackArts] Error: " .. tostring(tracker))
        return
    end
    respond("")
    respond(string.format("=== Check: %s x%d ===", product, reps))
    if next(tracker.error) then
        respond("  Missing:")
        for k, v in pairs(tracker.error) do
            respond(string.format("    %s x%d", k, v))
        end
    else
        respond("  All ingredients available!")
    end
    if next(tracker.buy) then
        respond("  Need to buy:")
        for room, items in pairs(tracker.buy) do
            for item, n in pairs(items) do
                respond(string.format("    %s x%d from room %s", item, n, room))
            end
        end
    end
    if next(tracker.forage) then
        respond("  Need to forage:")
        for herb, n in pairs(tracker.forage) do
            respond(string.format("    %s x%d", herb, n))
        end
    end
    if next(tracker.kill_for) then
        respond("  Need to kill for:")
        for creature, skins in pairs(tracker.kill_for) do
            for skin, n in pairs(skins) do
                respond(string.format("    %s x%d (from %s)", skin, n, creature))
            end
        end
    end
    respond(string.format("  Estimated cost: %d silvers, time: ~%d seconds",
        tracker.cost, tracker.time))
    respond("")
    return
end

-- Make a specific item
if cmd == "make" then
    local product = table.concat(args, " ", 2)
    if product == "" then
        respond("Usage: ;blackarts make <recipe name> [x<count>]")
        return
    end
    local count_str = product:match("x(%d+)$")
    local reps = count_str and tonumber(count_str) or 1
    product = product:gsub("%s*x%d+$", "")

    inv.init_sacks()
    local tracker = guild.check_recipe({name=product, reps=reps})
    local actions = require("actions")
    actions.get_supplies(tracker.buy, tracker.forage, tracker.kill_for, cfg, require("recipes"))
    guild.get_cauldron()
    actions.go_empty_workshop()
    local tasks = require("tasks")
    local steps = {}
    for _, s in ipairs(tracker.finish_steps) do steps[#steps+1] = s end
    for _ = 1, reps do tasks.do_steps(steps) end
    actions.cleanup(cfg)
    return
end

-- Forage standalone
if cmd == "forage" then
    local forage_arg = table.concat(args, " ", 2)
    if forage_arg == "" then
        respond("Usage: ;blackarts forage <herb name> [x<count>]")
        return
    end
    local count_str = forage_arg:match("x(%d+)$")
    local reps = count_str and tonumber(count_str) or 1
    local herb = forage_arg:gsub("%s*x%d+$", ""):match("^%s*(.-)%s*$")
    inv.init_sacks()
    require("actions").forage({[herb] = reps}, cfg)
    return
end

-- Buy elusive reagents
if cmd == "buy" then
    require("actions").buy_elusive(true)
    return
end

-- Remove/trade in current task
if cmd == "remove" then
    local skill = args[2] and args[2]:lower() or nil
    if not skill then
        respond("Usage: ;blackarts remove <alchemy|potions|trinkets>")
        return
    end
    inv.init_sacks()
    guild.remove_task(skill)
    return
end

-- Travel to guild administrator
if cmd == "guild" then
    util.go2(Char.prof:lower() .. " alchemy administrator")
    return
end

--------------------------------------------------------------------------------
-- Main loop validation
--------------------------------------------------------------------------------

if #cfg.skill_types == 0 then
    respond("[BlackArts] No guild skills selected. Opening setup...")
    require("gui_settings").show(cfg)
    return
end

if Char.level < 15 then
    respond("[BlackArts] You must be at least level 15 to join a guild.")
    return
end

-- Initialise sacks
inv.init_sacks()

if not cfg.no_alchemy then
    if not state.sacks["default"] then
        respond("[BlackArts] Default container not set. Use STOW SET in-game.")
        return
    end
    if not state.sacks["herb"] then
        respond("[BlackArts] Herb container not set. Use STOW SET in-game.")
        return
    end
    if not state.sacks["reagent"] then
        respond("[BlackArts] Reagent container not set. Use STOW SET in-game.")
        return
    end
end

-- Record starting admin location
local admin_result = Map.find_nearest_by_tag(Char.prof:lower() .. " alchemy administrator")
if admin_result then
    state.current_admin = admin_result.id
end

-- Store initial guild ranks
local init_status = guild.gld()
for _, skill in ipairs(cfg.skill_types) do
    if init_status[skill] then
        state.ranks = init_status[skill].rank or 0
        break
    end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

respond("")
respond("[BlackArts] Starting guild automation v3.12.0")
respond(string.format("[BlackArts] Skills: %s", table.concat(cfg.skill_types, ", ")))
if cfg.once_and_done then
    respond("[BlackArts] Once-and-done mode: will exit after one task.")
end
respond("")

-- Navigate to administrator
if state.current_admin then
    util.travel(state.current_admin)
else
    util.go2(Char.prof:lower() .. " alchemy administrator")
end

-- Begin task loop
guild.new_task(nil, cfg)
