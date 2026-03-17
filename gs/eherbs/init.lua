--- @revenant-script
--- name: eherbs
--- version: 1.0.0
--- author: Sordal
--- description: Self-healing with herbs — diagnosis, auto-eat/drink, inventory management

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
