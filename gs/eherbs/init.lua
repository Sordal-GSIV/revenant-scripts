--- @revenant-script
--- @lic-audit: validated 2026-03-17
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
---   Previous changelogs: https://gswiki.play.net/Lich:Script_Eherbs

local args_lib = require("lib/args")
local settings = require("settings")
local herbs = require("lib/herbs")
local diagnosis = require("diagnosis")
local actions = require("actions")
local shopping = require("shopping")
local bundling = require("bundling")

-- Install dose tracking monitor hook
actions.install_dose_monitor()

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
if parsed.deposit then state.deposit_coins = (parsed.deposit == "on") end
if parsed.mending then state.use_mending = (parsed.mending == "on") end
if parsed["650"] then state.use_650 = (parsed["650"] == "on") end
if parsed["1035"] then state.use_1035 = (parsed["1035"] == "on") end

-- Parse --spellcast and --ranged flags
state.spellcast_only = false
state.ranged_only = false
if input:find("%-%-spellcast") or input:find("%-spellcast") then
    state.spellcast_only = true
end
if input:find("%-%-ranged") or input:find("%-ranged") then
    state.ranged_only = true
end

-- Parse --no-get flag
state.no_get = false
if input:find("%-%-no%-?get") or input:find("%-no%-?get") then
    state.no_get = true
end

-- Blood toggle from settings
if state.blood_toggle then state.blood_only = true end

-- === Command dispatch ===

local function show_help()
    respond("Usage: ;eherbs [command] [options]")
    respond("")
    respond("Commands:")
    respond("  (no args)        Heal self")
    respond("  blood            Heal blood (HP) only")
    respond("  check [prep] [c] Show herb inventory (prep: in/on/under/behind)")
    respond("  list [filter]    List known herbs")
    respond("  setup            Open settings GUI")
    respond("  settings         Show current settings")
    respond("  set <k> <v>      Change a setting")
    respond("  debug            Toggle debug mode on/off")
    respond("  fill             Buy one of each missing herb type")
    respond("  stock [filter]   Stock herbs (herbs|potions|combined|<specific type>)")
    respond("  escort [id]      Heal NPC escort")
    respond("  bundle           Consolidate herbs in container")
    respond("  load             Reload settings and redetect survival kit")
    respond("  <name>           Heal dead player (name)")
    respond("  <name> full      Heal dead player fully (wounds + scars)")
    respond("  help             Show this help")
    respond("")
    respond("Options:")
    respond("  --skipscars=on/off  --yaba=on/off  --potions=on/off  --buy=on/off")
    respond("  --deposit=on/off    --mending=on/off  --650=on/off  --1035=on/off")
    respond("  --spellcast         Only heal wounds preventing spellcasting")
    respond("  --ranged            Only heal wounds preventing ranged combat")
    respond("  --no-get            Don't pick up edible herbs (bench mode)")
end

if cmd == "help" then
    show_help()
    return

elseif cmd == "debug" then
    state.debug = not state.debug
    settings.save(state)
    respond("[eherbs] Debug mode " .. (state.debug and "ON" or "OFF"))
    return

elseif cmd == "setup" then
    local gui = require("gui_settings")
    gui.open(state)
    return

elseif cmd == "settings" then
    respond("[eherbs] Current settings:")
    local display_keys = {
        "herb_container", "buy_missing", "deposit_coins", "use_mending", "skip_scars",
        "blood_only", "blood_toggle", "use_yaba", "use_potions", "use_650", "use_1035",
        "stock_percent", "use_distiller", "debug", "heal_cutthroat", "use_npchealer",
        "withdraw_amount", "no_get",
    }
    for _, k in ipairs(display_keys) do
        respond("  " .. k .. " = " .. tostring(state[k]))
    end
    return

elseif cmd == "set" then
    local key = parsed.args[2]
    local val = parsed.args[3]
    if not key or not val then
        respond("Usage: ;eherbs set <key> <value>")
        return
    end
    -- Map short names to actual setting keys
    if settings.var_names[key:lower()] then
        key = settings.var_names[key:lower()]
    end
    -- Handle special cases
    if key == "herbsack" then
        -- Set herb container
        local name = val
        -- Join remaining args for multi-word container names
        if parsed.args[4] then
            for i = 4, #parsed.args do
                name = name .. " " .. parsed.args[i]
            end
        end
        state.herb_container = name
        settings.save(state)
        respond("[eherbs] Herb container set to: " .. name)
        return
    elseif key == "stock" then
        local pct = tonumber(val:gsub("%%", ""))
        if pct then
            state.stock_percent = pct
            settings.save(state)
            respond("[eherbs] Stock percent set to: " .. pct .. "%")
        else
            respond("[eherbs] Invalid stock percent: " .. val)
        end
        return
    end
    if val == "on" or val == "true" or val == "yes" then val = true
    elseif val == "off" or val == "false" or val == "no" then val = false
    end
    state[key] = val
    settings.save(state)
    respond("[eherbs] Set " .. key .. " = " .. tostring(val))
    return

elseif cmd == "load" then
    state = settings.load()
    respond("[eherbs] Settings reloaded")
    -- Re-detect survival kit
    local sk = require("survival_kit")
    local container = state.herb_container or "herbsack"
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item.name and item.name:lower():find(container:lower(), 1, true) then
            sk.detect(item.id)
            break
        end
    end
    return

elseif cmd == "list" then
    local filter = parsed.args[2]
    -- Build set of wound types the player currently has
    local needed = {}
    local parts = {"head","neck","back","chest","abdomen","leftEye","rightEye",
        "leftArm","rightArm","leftHand","rightHand","leftLeg","rightLeg",
        "leftFoot","rightFoot","nsys"}
    for _, part in ipairs(parts) do
        if (Wounds[part] or 0) > 0 or (Scars[part] or 0) > 0 then
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
    -- Group by type and deduplicate
    local by_type = {}
    local type_order = {}
    for _, herb in ipairs(herbs.database) do
        if not filter or herb.type:find(filter, 1, true) or herb.name:find(filter, 1, true) then
            if not by_type[herb.type] then
                by_type[herb.type] = {}
                type_order[#type_order + 1] = herb.type
            end
            local already = false
            for _, existing in ipairs(by_type[herb.type]) do
                if existing == herb.name then already = true; break end
            end
            if not already then
                by_type[herb.type][#by_type[herb.type] + 1] = herb.name
            end
        end
    end
    for _, t in ipairs(type_order) do
        local names = table.concat(by_type[t], ", ")
        local line = "  " .. t .. ": " .. names
        if has_wounds and (needed[t] or needed[t:gsub("major ", ""):gsub("minor ", "")]) then
            if Messaging and Messaging.msg then
                Messaging.msg("info", line)
            else
                respond("** " .. line)
            end
        else
            respond(line)
        end
    end
    return

elseif cmd == "check" then
    -- Full table-formatted herb inventory display
    local container = state.herb_container or "herbsack"
    local preposition = "in"

    -- Parse optional preposition and container from args
    local arg2 = parsed.args[2]
    local arg3 = parsed.args[3]
    if arg2 then
        if arg2 == "in" or arg2 == "on" or arg2 == "under" or arg2 == "behind" then
            preposition = arg2
            if arg3 then container = arg3 end
        else
            container = arg2
        end
    end

    respond("[eherbs] Checking herbs " .. preposition .. " " .. container .. "...")

    -- Open and look in container
    actions.open_container(container)
    fput("look " .. preposition .. " my " .. container)

    -- Collect container contents by parsing game output
    local contents = {}
    for i = 1, 40 do
        local line = get()
        if not line then break end
        -- Parse item links
        for item_id, item_noun, item_name in line:gmatch('exist="(%d+)" noun="(%w+)">([^<]+)</a>') do
            for _, herb in ipairs(herbs.database) do
                if item_name:lower():find(herb.short:lower(), 1, true) then
                    contents[#contents + 1] = {
                        id = item_id,
                        noun = item_noun,
                        name = item_name,
                        herb = herb,
                    }
                    break
                end
            end
        end
        if line:find("Roundtime") or line:find("There is nothing") or line == "" then break end
    end

    if #contents == 0 then
        respond("[eherbs] Nothing found " .. preposition .. " " .. container)
        return
    end

    -- Measure any un-tracked herbs
    local tracker = actions.dose_tracker
    for _, item in ipairs(contents) do
        if not tracker[item.id] then
            fput("get #" .. item.id .. " from my " .. container)
            fput("measure #" .. item.id)
            pause(0.5)
            fput("put #" .. item.id .. " in my " .. container)
        end
    end

    -- Build check list grouped by herb type
    local herb_type_order = {
        "poison", "disease", "blood",
        "minor head wound", "major head wound", "minor head scar", "major head scar",
        "minor nerve wound", "major nerve wound", "minor nerve scar", "major nerve scar",
        "minor organ wound", "major organ wound", "minor organ scar", "major organ scar",
        "missing eye",
        "minor limb wound", "major limb wound", "minor limb scar", "major limb scar",
        "severed limb", "lifekeep", "raisedead",
    }

    local check_list = {}
    for _, item in ipairs(contents) do
        local t = item.herb.type
        if not check_list[t] then
            check_list[t] = { name = item.name, count = 0 }
        end
        local doses = tracker[item.id] or 0
        check_list[t].count = check_list[t].count + doses
    end

    -- Format and display table
    local max_type_len = 0
    local max_name_len = 0
    for _, t in ipairs(herb_type_order) do
        if check_list[t] then
            if #t > max_type_len then max_type_len = #t end
            if #check_list[t].name > max_name_len then max_name_len = #check_list[t].name end
        end
    end
    max_type_len = math.max(max_type_len, 4) + 2
    max_name_len = math.max(max_name_len, 4) + 2

    local title = "Herbs found " .. preposition .. " " .. container
    local separator = " +" .. string.rep("-", max_type_len) .. "+" .. string.rep("-", 5) .. "+" .. string.rep("-", max_name_len) .. "+"
    local fmt = " | %-" .. (max_type_len - 2) .. "s | %3s | %-" .. (max_name_len - 2) .. "s |"

    respond("")
    respond(separator)
    respond(string.format(" | %-" .. (max_type_len + max_name_len + 5) .. "s |", title))
    respond(separator)
    respond(string.format(fmt, "Type", " # ", "Herb"))
    respond(separator)

    for _, t in ipairs(herb_type_order) do
        local vals = check_list[t]
        if vals then
            local count_str = vals.count > 0 and tostring(vals.count) or ""
            respond(string.format(fmt, t, count_str, vals.name))
        end
    end

    respond(separator)
    respond("")
    return

elseif cmd == "fill" then
    shopping.fill_missing(state)
    return

elseif cmd == "stock" then
    local filter = parsed.args[2]  -- "herbs", "potions", "combined", or specific type
    -- Check if we have a multi-word filter like "major head wound"
    if filter and parsed.args[3] and not (filter == "herbs" or filter == "potions" or filter == "combined") then
        filter = filter
        for i = 3, #parsed.args do
            filter = filter .. " " .. parsed.args[i]
        end
    end
    shopping.stock(state, filter)
    return

elseif cmd == "escort" then
    actions.heal_escort(state)
    return

elseif cmd == "bundle" then
    bundling.bundle_all(state.herb_container or "herbsack")
    return

elseif cmd == "blood" then
    state.blood_only = true
end

-- === Check for dead player healing ===
if cmd and cmd ~= "blood" then
    local pcs = GameObj.pcs()
    for _, pc in ipairs(pcs) do
        if pc.name:lower():find(cmd:lower(), 1, true) then
            local full_heal = (parsed.args[2] and parsed.args[2]:lower() == "full")
            local container = state.herb_container or "herbsack"
            actions.heal_dead_player(cmd, full_heal, container, state)
            return
        end
    end
end

-- === Healing mode ===

local container = state.herb_container or "herbsack"
respond("[eherbs] Healing with herbs from " .. container)

-- Check cutthroat before healing
if actions.check_cutthroat(state) then
    return
end

-- Pause ego2 if running
local ego2_was_running = false
if running and running("ego2") then
    ego2_was_running = true
    Script.pause("ego2")
end

-- Ensure cleanup on exit
before_dying(function()
    if ego2_was_running and Script.paused and Script.paused("ego2") then
        Script.unpause("ego2")
    end
end)

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
    -- Check blood
    if Char.health and Char.max_health and (Char.health + 7) < Char.max_health then
        respond("[eherbs] Blood loss detected, healing...")
    else
        respond("[eherbs] No wounds or scars detected")
        -- Run distiller if configured
        if state.use_distiller then
            local sk = require("survival_kit")
            if sk.detected and sk.has_distiller then
                sk.distill(container, nil)
            end
        end
        if ego2_was_running then Script.unpause("ego2") end
        return
    end
end

-- Open herb container
actions.open_container(container)

-- Stow hands for healing
local stowed = actions.stow_hands()

-- Healing loop
local herbs_used = 0
local max_herbs = 100  -- safety limit

while herbs_used < max_herbs do
    local wound_type = nil

    if state.blood_only then
        if Char.health and Char.max_health and (Char.health + 7) < Char.max_health then
            wound_type = "blood"
        end
    else
        wound_type = diagnosis.next_herb_type(state)
    end

    if not wound_type then
        break  -- fully healed
    end

    actions.debug(state, "Next herb type: " .. wound_type)

    -- Cast spells before using herbs
    actions.cast_spells(state)

    -- Find herb in container
    local item, herb = actions.find_herb_in_container(wound_type, container, state)
    if not item then
        -- Try buying if buy_missing is enabled
        if state.buy_missing and not state.blood_only and wound_type ~= "poison" and wound_type ~= "disease" then
            actions.debug(state, "Buying missing herb for: " .. wound_type)
            -- Stow current herbs
            local rh = GameObj.right_hand()
            if rh and rh.id then fput("put #" .. rh.id .. " in my " .. container) end

            local silver = shopping.check_silver()
            if silver < 4000 then
                shopping.withdraw(state.withdraw_amount or 8000, state)
            end
            Script.run("go2", "herbalist")
            local purchased = shopping.buy_herb(wound_type, 1, state)
            if purchased then
                -- Use the purchased herb directly
                item = purchased
                herb = herbs.find_by_type(wound_type)
            end
        end

        if not item then
            state.skipped[wound_type] = true
            respond("[eherbs] No " .. wound_type .. " herb found — skipping")
            goto continue_heal
        end
    end

    actions.debug(state, "Using " .. item.name .. " for " .. wound_type)
    respond("[eherbs] Using " .. item.name .. " for " .. wound_type)
    actions.use_herb(item, herb, container, state)
    herbs_used = herbs_used + 1
    pause(0.3)

    ::continue_heal::
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

-- Cleanup
actions.restore_hands(stowed)

-- Deposit if needed
if state.deposit_coins and state.buy_missing then
    shopping.deposit(state)
end

-- Return to start if we moved
-- (start_room tracking would go here if we navigated away)

-- Run distiller if configured
if state.use_distiller then
    local sk = require("survival_kit")
    if sk.detected and sk.has_distiller then
        sk.distill(container, nil)
    end
end

-- Unpause ego2
if ego2_was_running then
    Script.unpause("ego2")
end
