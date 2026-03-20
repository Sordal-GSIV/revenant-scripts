--- @revenant-script
--- name: lockpick-maker
--- version: 2.3.0
--- author: Timbalt
--- contributors: (converted for Revenant)
--- game: gs
--- description: Craft lockpicks at the Rogue Guild toolbench — exceptional quality only. GUI with customization (dye, edging, inset), broken-pick remaking, and per-character container settings.
--- tags: lockpicks, crafting, rogue, guild, customization, gui
--- @lic-certified: complete 2026-03-20

local settings_mod = require("lockpick-maker/settings")
local gui_mod      = require("lockpick-maker/gui")

---------------------------------------------------------------------------
-- Data tables (Rogue Guild toolbench order numbers and bar costs)
---------------------------------------------------------------------------
local PICK_NUMBERS = {
    silver  = 30, gold    = 29, steel   = 28, copper  = 26, brass   = 27,
    ora     = 31, mithril = 32, laje    = 33, alum    = 34, vultite = 35,
    rolaren = 36, veniom  = 37, kelyn   = 38, invar   = 39, golvern = 40,
    vaalin  = 41,
}
local PICK_COSTS = {
    silver  = 2000,  gold    = 1600,  steel   = 400,   copper  = 80,
    brass   = 200,   ora     = 4000,  mithril = 4800,  laje    = 13600,
    alum    = 18400, vultite = 24000, rolaren = 28800, veniom  = 40000,
    kelyn   = 49600, invar   = 60000, golvern = 76000, vaalin  = 100000,
}
local EDGE_COSTS = {
    copper  = 20,   brass   = 100,  bronze  = 250,  iron    = 300,
    steel   = 400,  silver  = 500,  gold    = 1000, mithril = 1400,
    ora     = 1600, alum    = 2000, imflass = 2000, vultite = 3000,
    vaalorn = 5000, mithglin = 5000, invar  = 5000, veniom  = 5000,
    laje    = 5000, rhimar  = 5000,
}
local ALL_MATERIALS = {
    "silver", "gold", "steel", "copper", "brass", "ora", "mithril", "laje",
    "alum", "vultite", "rolaren", "veniom", "kelyn", "invar", "golvern", "vaalin",
}

---------------------------------------------------------------------------
-- Helper: bold-style message to client (mirrors Lich5 message() helper)
---------------------------------------------------------------------------
local function message(text)
    respond("<pushBold/>" .. text .. "<popBold/>")
end

---------------------------------------------------------------------------
-- Phase 1 — Inventory scan
-- Build broken_picks count and inventory_summary for gem/inset items.
---------------------------------------------------------------------------
local function scan_inventory(settings)
    local broken_picks    = {}
    local inventory_summary = {}

    for _, mat in ipairs(ALL_MATERIALS) do broken_picks[mat] = 0 end

    -- Scan broken sack for broken lockpicks
    if settings.broken_sack and settings.broken_sack ~= "" then
        fput("look in " .. settings.broken_sack)
        pause(1)   -- wait for container XML to populate before reading GameObj.inv()
        local inv = GameObj.inv()
        for _, cont in ipairs(inv) do
            if cont.noun and cont.noun:lower():find(settings.broken_sack:lower(), 1, true) then
                local contents = cont.contents or {}
                for _, item in ipairs(contents) do
                    for _, mat in ipairs(ALL_MATERIALS) do
                        if item.name and item.name:lower():find(mat .. " lockpick", 1, true) then
                            broken_picks[mat] = (broken_picks[mat] or 0) + 1
                        end
                    end
                end
                break
            end
        end
    end

    -- Scan inset sack and gem sack to build gem dropdown list
    local sacks_to_scan = {}
    if settings.inset_sack and settings.inset_sack ~= "" then
        sacks_to_scan[#sacks_to_scan + 1] = settings.inset_sack
    end
    if settings.gem_sack and settings.gem_sack ~= "" and settings.gem_sack ~= settings.inset_sack then
        sacks_to_scan[#sacks_to_scan + 1] = settings.gem_sack
    end

    for _, sack_name in ipairs(sacks_to_scan) do
        fput("look in " .. sack_name)
        pause(0.3)
    end
    pause(0.5)

    local inv = GameObj.inv()
    for _, sack_name in ipairs(sacks_to_scan) do
        for _, cont in ipairs(inv) do
            if cont.noun and cont.noun:lower():find(sack_name:lower(), 1, true) then
                local counts = {}
                local contents = cont.contents or {}
                for _, item in ipairs(contents) do
                    if item.name then
                        local n = item.name:lower()
                        counts[n] = (counts[n] or 0) + 1
                    end
                end
                inventory_summary[#inventory_summary + 1] = "~ Contents of " .. cont.noun .. ":"
                for name, count in pairs(counts) do
                    inventory_summary[#inventory_summary + 1] = name .. ": " .. count
                end
                break
            end
        end
    end

    return broken_picks, inventory_summary
end

---------------------------------------------------------------------------
-- Phase 2 — Navigate to toolbench if needed
---------------------------------------------------------------------------
local function ensure_at_toolbench()
    local room = GameState.room_name or ""
    if not room:lower():find("toolbench") then
        Script.run("go2", "rogue guild toolbench")
        waitrt()
    end
end

---------------------------------------------------------------------------
-- Phase 3 — Bank note withdrawal (once per run)
---------------------------------------------------------------------------
local function withdraw_bank_note(settings, state)
    if not settings.enable_withdraw_note then return end
    local amount = settings.bank_note_amount or ""
    if amount == "" or state.bank_note_withdrawn then return end

    Script.run("go2", "bank")
    waitrt()
    fput("deposit all")
    pause(0.5)
    fput("withdraw " .. amount .. " note")
    pause(0.5)
    fput("stow note")
    waitrt()
    state.bank_note_withdrawn = true
    Script.run("go2", "rogue guild toolbench")
    waitrt()
end

---------------------------------------------------------------------------
-- Phase 4 — Apply customization to a freshly-crafted exceptional pick
---------------------------------------------------------------------------
local function apply_customization(settings, inv_summary_text)
    -- Dye
    if settings.customizing_dye and settings.custom_color and settings.custom_color ~= "" then
        Script.run("go2", "bank")
        waitrt()
        fput("withdraw 500 silver")
        waitrt()
        Script.run("go2", "rogue guild toolbench")
        waitrt()
        local rh = GameObj.right_hand()
        if not rh or not rh.noun:lower():find("lockpick") then
            fput("swap")
            pause(1)
        end
        fput("lmas cust dye " .. settings.custom_color)
        waitrt()
        pause(1)
        fput("lmas cust dye " .. settings.custom_color)
        waitrt()
        pause(3)
    end

    -- Edging
    if settings.customizing_edge and settings.custom_material and settings.custom_material ~= "" then
        local edge_mat  = settings.custom_material:lower():match("^%s*(.-)%s*$")
        local edge_cost = EDGE_COSTS[edge_mat] or 0
        if edge_cost > 0 then
            message("Withdrawing " .. edge_cost .. " silver for " .. settings.custom_material .. " edging.")
            Script.run("go2", "bank")
            waitrt()
            fput("withdraw " .. edge_cost .. " silver")
            waitrt()
            Script.run("go2", "rogue guild toolbench")
            waitrt()
            local rh = GameObj.right_hand()
            if not rh or not rh.noun:lower():find("lockpick") then
                fput("swap")
                pause(1)
            end
        end
        fput("lmas cust edge " .. settings.custom_material)
        waitrt()
        pause(1)
        fput("lmas cust edge " .. settings.custom_material)
        waitrt()
        pause(3)
    end

    -- Inset gem
    if settings.customizing_inset and settings.custom_gem and settings.custom_gem ~= "" then
        local gem_name = settings.custom_gem:lower():match("^%s*(.-)%s*$")
        -- Find the gem by name in inset_sack or gem_sack
        local gem_obj = nil
        local sacks = { settings.inset_sack, settings.gem_sack }
        local inv = GameObj.inv()
        for _, sack_name in ipairs(sacks) do
            if sack_name and sack_name ~= "" then
                for _, cont in ipairs(inv) do
                    if cont.noun and cont.noun:lower():find(sack_name:lower(), 1, true) then
                        local contents = cont.contents or {}
                        for _, item in ipairs(contents) do
                            if item.name and item.name:lower():find(gem_name, 1, true) then
                                gem_obj = item
                                break
                            end
                        end
                        break
                    end
                end
                if gem_obj then break end
            end
        end

        local rh = GameObj.right_hand()
        if not rh or not rh.noun:lower():find("lockpick") then
            fput("swap")
            pause(0.5)
        end
        waitrt()
        if gem_obj then
            fput("get #" .. gem_obj.id)
            pause(1)
            fput("lmas cust inset #" .. gem_obj.id)
            waitrt()
            pause(1)
            fput("lmas cust inset #" .. gem_obj.id)
            waitrt()
        else
            -- Fallback: use gem name (no ID — may fail if name is ambiguous)
            fput("get my " .. gem_name)
            pause(1)
            fput("lmas cust inset " .. gem_name)
            waitrt()
            pause(1)
            fput("lmas cust inset " .. gem_name)
            waitrt()
        end
        pause(3)
    end
end

---------------------------------------------------------------------------
-- Phase 5 — Craft one material until exceptional
-- @param material  string   material name
-- @param is_remake bool     true if remaking from broken pick
-- @param settings  table    current settings
-- @param state     table    run-wide mutable state (bank_note_withdrawn, etc.)
-- @param stats     table    per-material tracking (attempts, silver_spent, times)
---------------------------------------------------------------------------
local function craft_material(material, is_remake, settings, state, stats)
    local order_num = PICK_NUMBERS[material]
    if not order_num then
        message("Warning: No order number found for " .. material .. " — skipping.")
        return
    end

    local bar_cost   = PICK_COSTS[material] or 0
    stats.attempts   = stats.attempts or 0
    stats.silver     = stats.silver   or 0
    stats.times      = stats.times    or {}

    -- Bank note (once per run, before first material)
    withdraw_bank_note(settings, state)

    while true do
        stats.attempts = stats.attempts + 1
        local attempt_start = os.time()

        local elapsed = os.time() - state.run_start
        message(string.format("Total time so far: %d min %d sec",
            math.floor(elapsed / 60), elapsed % 60))

        -- Order the bar and verify the attendant responds
        local order_result = dothistimeout("order " .. order_num, 15,
            "workshop attendant", "can't do that", "don't have", "already have")
        if not order_result or order_result:find("can't do that") or
           order_result:find("don't have") or order_result:find("already have") then
            message("Failed to order " .. material .. " bar — are you at the Rogue Guild toolbench?")
            return
        end

        -- Pay and stow
        stats.silver = stats.silver + bar_cost
        state.total_silver = (state.total_silver or 0) + bar_cost

        fput("get note")
        pause(1)
        fput("buy")
        pause(1)
        fput("stow right")
        pause(1)

        -- Ensure the material bar is in right hand; swap if holding something else
        local rh = GameObj.right_hand()
        if rh and not rh.name:lower():find(material, 1, true) then
            fput("swap")
            pause(1)
        end

        -- Attempt the craft — wait for outcome; game sends outcome line before Roundtime
        local outcome = dothistimeout("lm create", 60,
            "exceptional",
            "You carefully slice the ruined part",
            "average") or ""

        -- Wait out any active roundtime before acting on the result
        waitrt()

        local attempt_duration = os.time() - attempt_start
        stats.times[#stats.times + 1] = string.format("%d min %d sec",
            math.floor(attempt_duration / 60), attempt_duration % 60)

        message(string.format("Attempt %d — %s lockpick: %s",
            stats.attempts, material,
            outcome:find("exceptional") and "Exceptional" or
            outcome:find("average")     and "Average"     or
            outcome:find("ruined part") and "Bar Ruined"  or
            "Unknown"))
        message(string.format("Time on attempt: %s", stats.times[#stats.times]))
        message(string.format("Silver spent on %s so far: %d", material, stats.silver))

        if outcome:find("average") then
            -- Average quality — stow to average sack and try again
            message("**********************************")
            message("Low quality — making another")
            message("**********************************")
            pause(1)
            fput("put my lockpick in my " .. (settings.average_sack or "backpack"))

        elseif outcome:find("You carefully slice the ruined part") then
            -- Bar ruined — re-order a fresh bar and try again (original Ruby redo restarts
            -- the entire loop body which includes ordering, so this is correct behavior)
            message("**********************************")
            message("Ruined the bar — re-ordering and re-attempting")
            message("**********************************")
            pause(1)

        elseif outcome:find("exceptional") then
            -- Success
            message("*********************************************************")
            message(string.format("Exceptional %s lockpick!", material))
            message(string.format("Craft time: %s", stats.times[#stats.times]))
            message(string.format("Attempts:   %d", stats.attempts))
            message("*********************************************************")
            pause(1)

            apply_customization(settings, nil)

            -- Place finished pick
            if settings.use_keyring then
                waitrt()
                fput("put my lockpick on my keyring")
            else
                waitrt()
                fput("put lockpick in my " .. (settings.exceptional_sack or "backpack"))
            end

            -- Done with this material
            return

        else
            -- Unrecognized result — wait out RT and loop
            waitrt()
            message("Unrecognized result — retrying. Last line: " .. (outcome or "(nil)"))
        end
    end
end

---------------------------------------------------------------------------
-- Phase 6 — Summary report
---------------------------------------------------------------------------
local function print_summary(materials_crafted, per_mat_stats, state)
    message("***************************************")
    message("All Lockpicks Are Exceptional Quality!")
    message("***************************************")
    message("")
    message("***** Lockpick Maker Crafting Summary *****")

    local total_time = os.time() - state.run_start
    message(string.format("** Total Silver Spent: %d", state.total_silver or 0))
    message(string.format("** Total Crafting Time: %d min %d sec",
        math.floor(total_time / 60), total_time % 60))

    message("")
    message("***** Per-Material Breakdown *****")
    for _, mat in ipairs(materials_crafted) do
        local s = per_mat_stats[mat] or {}
        message(string.format("** %s: Attempts=%d  Silver=%d  Times=[%s]",
            mat,
            s.attempts or 0,
            s.silver   or 0,
            table.concat(s.times or {}, ", ")))
    end

    message("Thank you for using Lockpick Maker!")
end

---------------------------------------------------------------------------
-- Main entry point
---------------------------------------------------------------------------
local function main()
    message("Lockpick Maker Script Initializing...")
    pause(0.5)

    -- Load settings
    local settings = settings_mod.load()

    -- Warn if containers are not configured
    local missing = {}
    for _, k in ipairs({ "broken_sack", "average_sack", "exceptional_sack", "gem_sack", "inset_sack" }) do
        if not settings[k] or settings[k] == "" then
            missing[#missing + 1] = k
        end
    end
    if #missing > 0 then
        message("*** Some containers are not configured. Please set them in the GUI Containers tab: "
            .. table.concat(missing, ", "))
    end

    -- Scan inventory for broken picks and gem list
    message("Building inventory summary for GUI...")
    local broken_picks, inventory_summary = scan_inventory(settings)

    -- Print broken pick summary
    local any_broken = false
    for _, mat in ipairs(ALL_MATERIALS) do
        if broken_picks[mat] and broken_picks[mat] > 0 then
            any_broken = true
            message(string.format("%d broken %s lockpick%s found.",
                broken_picks[mat], mat, broken_picks[mat] == 1 and "" or "s"))
        end
    end
    if not any_broken then
        message("No broken lockpicks found in broken sack.")
    end

    -- Show GUI
    local gui_result = gui_mod.show(settings, broken_picks, inventory_summary)

    if not gui_result then
        message("GUI closed unexpectedly.")
        return
    end

    -- Always save settings (the GUI updates settings in place)
    settings_mod.save(gui_result.settings)
    settings = gui_result.settings

    if gui_result.action == "exit" then
        message("Lockpick Maker exiting.")
        return
    end

    -- Build ordered list of materials to craft
    local materials_to_craft = {}
    local is_remake_map = {}

    if gui_result.action == "remake" then
        for _, mat in ipairs(gui_result.selected_remake or {}) do
            materials_to_craft[#materials_to_craft + 1] = mat
            is_remake_map[mat] = true
        end
    elseif gui_result.action == "new" then
        for _, mat in ipairs(gui_result.selected_new or {}) do
            materials_to_craft[#materials_to_craft + 1] = mat
            is_remake_map[mat] = false
        end
    end

    if #materials_to_craft == 0 then
        message("No lockpick materials selected. Exiting.")
        return
    end

    -- Navigate to toolbench
    ensure_at_toolbench()

    if settings.use_keyring then
        pause(1)
        message("*** Keyring Mode Activated — exceptional lockpicks will be placed on your keyring.")
        pause(2)
    end

    -- Run state (shared across material iterations)
    local state = {
        run_start        = os.time(),
        total_silver     = 0,
        bank_note_withdrawn = false,
    }

    -- Per-material statistics
    local per_mat_stats = {}
    for _, mat in ipairs(materials_to_craft) do
        per_mat_stats[mat] = { attempts = 0, silver = 0, times = {} }
    end

    -- Craft each material
    local ok, err = pcall(function()
        for _, mat in ipairs(materials_to_craft) do
            craft_material(mat, is_remake_map[mat], settings, state, per_mat_stats[mat])
        end
    end)

    -- Print summary regardless of crash
    print_summary(materials_to_craft, per_mat_stats, state)

    if not ok then
        message("Script encountered an error: " .. tostring(err))
    end
end

main()
