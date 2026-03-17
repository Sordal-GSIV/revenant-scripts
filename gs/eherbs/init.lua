--- @revenant-script
--- name: eherbs
--- version: 1.0.0
--- author: Elanthia-Online
--- contributors: Tillmen, Tysong, Doug, Rinualdo, Xanlin, Deysh
--- description: Self-healing with herbs — diagnosis, auto-eat/drink, inventory management
--- game: gs
---
--- Changelog (from Lich5):
---   v2.1.12 (2026-03-14)
---     - fix for drinkable status not resetting in rare situations
---   v2.1.11 (2026-03-13)
---     - highlight herbs needed for current wounds in the list command
---   v2.1.10 (2026-03-10)
---     - case insensitive the container name when finding herb container
---   v2.1.9 (2025-11-26)
---     - improve the various look in container regex matches with existing ID in comparison
---   v2.1.8 (2025-11-03)
---     - fix for buy_herb to rebuy correct amount when not enough money instead of just qty 1
---   v2.1.7 (2025-08-05)
---     - fix for Hinterwilds herbs mapdb location including "the"
---   v2.1.6 (2025-08-05)
---     - add debug messaging to dead character healing
---   v2.1.5 (2025-05-13)
---     - fix for Cysaegir not matching probably for stocking
---   v2.1.4 (2025-04-22)
---     - add additional put regex for survival kit when fully stocked
---   v2.1.3 (2025-03-25)
---     - remove waitcastrt? from wait_rt method
---     - add waitcastrt? to cast_spells method
---     - add Do Not Buy herbs for Solhaven backroom bundles
---     - bugfix in check_herbs_in_container method for nil measures
---     - bugfix in get_current_stock to also count herbs in a survival kit
---     - redetect survival kit if changed stock, distiller or herb_sack
---   v2.1.2 (2025-02-22)
---     - add additional unpoison herbs
---     - add logic to eat/drink poison & disease curing herbs
---     - bugfix for cached pricing of herbalist in distant town
---     - remove deprecated calls to maxhealth & checkhealth
---     - update logic of survival kits to include non-bundled liquid/solid doses
---   v2.1.1 (2025-02-20)
---     - change ;eherbs load to also redetermine survival kit
---   v2.1.0 (2025-01-19)
---     - add --spellcast and --ranged options to healdown
---   v2.0.18 (2025-01-06)
---     - fix for min_stock_doses to persist thru current session running
---   v2.0.17 (2025-01-06)
---     - fix for survival_kit to persist thru current session running
---     - fix for not being able to analyze kit during distill function
---   v2.0.16 (2024-12-06)
---     - add additional debug messaging
---   v2.0.15 (2024-10-10)
---     - skip herbs that can't be bundled when bundling herbs
---   v2.0.14 (2024-09-25)
---     - bugfix for depositing in Pinefar, need to wait for banker
---   v2.0.13 (2024-08-30)
---     - bugfix for excessive ANALYZE for survival kits logic
---     - bugfix for wait_rt method
---   v2.0.12 (2024-08-27)
---     - adjust doses for Ta'Vaalor
---     - update note buying process for in-hand recognition
---     - bugfix in stock_requested_herbs when not using a note
---   v2.0.11 (2024-08-26)
---     - Add missing Ta'Vaalor tinctures
---   v2.0.10 (2024-08-15)
---     - bugfix failed finding blood herbs if use_yaba is on with no yaba found
---   v2.0.9 (2024-07-20)
---     - change note variable to just use the noun instead of full name
---     - use quiet command for _injury 2
---     - consolidate inventory check methods
---     - general code consolidation
---   v2.0.8 (2024-07-12)
---     - pause script ego2 if running
---   v2.0.7 (2024-07-12)
---     - drinkable variable not being set when buying
---   v2.0.6 (2024-07-10)
---     - changed drinkable boolean in favor of checking regex during herb usage or boolean
---   v2.0.5 (2024-01-17)
---     - fix for wrong variable reference
---   v2.0.4 (2024-01-03)
---     - bugfix for Zul Logoth location check
---   v2.0.3 (2024-01-01)
---     - bugfix for use_potions variable
---   v2.0.2 (2023-12-15)
---     - send injury command to refresh XML before attempting to heal self
---   v2.0.1 (2023-11-10)
---     - bugfix to use id instead of name for distiller
---     - added setting output for debugging ;eherbs settings
---   Previous changelogs: https://gswiki.play.net/Lich:Script_Eherbs

local args_lib = require("lib/args")
local settings = require("settings")
local herbs = require("lib/herbs")
local diagnosis = require("diagnosis")
local actions = require("actions")
local shopping = require("shopping")
local bundling = require("bundling")

local state = settings.load()
state.skipped = {}

local input = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd = parsed.args[1]

-- === CLI flag overrides ===
if parsed.skipscars then state.skip_scars = (parsed.skipscars == "on") end
if parsed.yaba then state.use_yaba = (parsed.yaba == "on") end
if parsed.potions then state.use_potions = (parsed.potions == "on") end
if parsed.buy then state.buy_missing = (parsed.buy == "on") end

-- === Command dispatch ===

local function show_help()
    respond("Usage: ;eherbs [command] [options]")
    respond("")
    respond("Commands:")
    respond("  (no args)        Heal self")
    respond("  blood            Heal blood (HP) only")
    respond("  check            Show herb inventory")
    respond("  list [filter]    List known herbs")
    respond("  setup            Open settings GUI")
    respond("  settings         Show current settings")
    respond("  set <k> <v>      Change a setting")
    respond("  fill             Buy one of each missing herb type")
    respond("  stock [filter]   Stock herbs (herbs|potions|combined)")
    respond("  escort           Heal NPC escort")
    respond("  bundle           Consolidate herbs in container")
    respond("  help             Show this help")
    respond("")
    respond("Options:")
    respond("  --skipscars=on/off  --yaba=on/off  --potions=on/off  --buy=on/off")
end

if cmd == "help" then
    show_help()
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "settings" then
    respond("[eherbs] Current settings:")
    for k, v in pairs(state) do
        if k ~= "skipped" then
            respond("  " .. k .. " = " .. tostring(v))
        end
    end
    return

elseif cmd == "set" then
    local key = parsed.args[2]
    local val = parsed.args[3]
    if not key or not val then
        respond("Usage: ;eherbs set <key> <value>")
        return
    end
    if val == "on" or val == "true" then val = true
    elseif val == "off" or val == "false" then val = false
    end
    state[key] = val
    settings.save(state)
    respond("[eherbs] Set " .. key .. " = " .. tostring(val))
    return

elseif cmd == "list" then
    local filter = parsed.args[2]
    -- Build set of wound types the player currently has
    local needed = {}
    local parts = {"head","neck","back","chest","abdomen","left_eye","right_eye",
        "left_arm","right_arm","left_hand","right_hand","left_leg","right_leg",
        "left_foot","right_foot","nsys"}
    for _, part in ipairs(parts) do
        if (Wounds[part] or 0) > 0 or (Scars[part] or 0) > 0 then
            -- Map body part to herb wound type (head wound, neck wound, etc.)
            local wound_type = part:gsub("_", " ") .. " wound"
            needed[wound_type] = true
            local scar_type = part:gsub("_", " ") .. " scar"
            needed[scar_type] = true
        end
    end
    if (Wounds.nsys or 0) > 0 or (Scars.nsys or 0) > 0 then
        needed["nerve wound"] = true
        needed["nerve scar"] = true
    end
    local has_wounds = next(needed) ~= nil
    if has_wounds then
        respond("[eherbs] Highlighted entries indicate herbs needed for current wounds.")
    end
    respond("[eherbs] Known herbs:")
    for _, herb in ipairs(herbs.database) do
        if not filter or herb.type:find(filter, 1, true) or herb.name:find(filter, 1, true) then
            local line = string.format("  %-30s  %-25s  %s",
                herb.name, herb.type, herb.drinkable and "drink" or "eat")
            if has_wounds and needed[herb.type] then
                -- Highlight with info preset (matches Lich5 v2.1.11)
                Messaging.msg("info", line)
            else
                respond(line)
            end
        end
    end
    return

elseif cmd == "check" then
    respond("[eherbs] Herb inventory check not yet implemented (Plan 2)")
    return

elseif cmd == "fill" then
    shopping.fill_missing(state)
    return

elseif cmd == "stock" then
    local filter = parsed.args[2]  -- "herbs", "potions", "combined", or specific type
    shopping.stock(state, filter)
    return

elseif cmd == "escort" then
    local escort_id = parsed.args[2]
    actions.heal_escort(state)
    return

elseif cmd == "bundle" then
    bundling.bundle_all(state.herb_container or "herbsack")
    return

elseif cmd == "blood" then
    state.blood_only = true
end

-- === Healing mode ===

local container = state.herb_container or "herbsack"
respond("[eherbs] Healing with herbs from " .. container)

-- Force wound refresh
fput("_injury 2")
pause(0.5)

-- Show initial wound state
local summary = diagnosis.get_wound_summary()
if #summary > 0 then
    respond("[eherbs] Wounds detected:")
    for _, s in ipairs(summary) do
        local parts = {}
        if s.wound_severity > 0 then parts[#parts + 1] = "wound:" .. s.wound_severity end
        if s.scar_severity > 0 then parts[#parts + 1] = "scar:" .. s.scar_severity end
        respond("  " .. s.area .. ": " .. table.concat(parts, ", "))
    end
else
    respond("[eherbs] No wounds or scars detected")
    return
end

-- Healing loop
local herbs_used = 0
local max_herbs = 50  -- safety limit

while herbs_used < max_herbs do
    local wound_type = nil

    if state.blood_only then
        if Char.percent_health and Char.percent_health < 100 then
            wound_type = "blood"
        end
    else
        wound_type = diagnosis.next_herb_type(state)
    end

    if not wound_type then
        break  -- fully healed
    end

    -- Find herb in container
    local item, herb = actions.find_herb_in_container(wound_type, container, state)
    if not item then
        state.skipped[wound_type] = true
        respond("[eherbs] No " .. wound_type .. " herb found — skipping")
    else
        respond("[eherbs] Using " .. item.name .. " for " .. wound_type)
        actions.use_herb(item, herb, container, state)
        herbs_used = herbs_used + 1
        pause(0.3)
    end
end

-- Summary
respond("[eherbs] Done. Used " .. herbs_used .. " herbs.")
local remaining = diagnosis.get_wound_summary()
if #remaining > 0 then
    respond("[eherbs] Remaining wounds:")
    for _, s in ipairs(remaining) do
        local parts = {}
        if s.wound_severity > 0 then parts[#parts + 1] = "wound:" .. s.wound_severity end
        if s.scar_severity > 0 then parts[#parts + 1] = "scar:" .. s.scar_severity end
        respond("  " .. s.area .. ": " .. table.concat(parts, ", "))
    end
end
