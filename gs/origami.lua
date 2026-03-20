--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: origami
--- version: 2.0.0
--- author: unknown
--- game: gs
--- description: Origami looper - fold/unfold paper for training
--- tags: origami, training, artisan
---
--- Original Lich5: origamitest_optimized.lic (origami.lic)
--- Ported to Revenant Lua
---
--- Usage:
---   ;origami [cycles] [design]
---   ;origami [design] [cycles]
---   ;origami                    (run until out of paper)
---   ;origami help

local DEFAULT_DESIGN    = "palace"
local MAX_FOLDS_PER_SHEET = 5
local BASE_WAIT_TIME    = 0.5
local MAX_GET_ATTEMPTS  = 15

local max_cycles = nil
local design     = DEFAULT_DESIGN

for _, token in ipairs(Script.vars) do
    local t = tostring(token)
    if t == "" then
        -- skip empty tokens
    elseif t == "help" or t == "-h" or t == "--help" then
        echo("=== ORIGAMI LOOPER SCRIPT HELP ===")
        echo("")
        echo("USAGE:")
        echo("  ;origami [cycles] [design]")
        echo("  ;origami [design] [cycles]")
        echo("  ;origami                    (run until out of paper)")
        echo("")
        echo("EXAMPLES:")
        echo("  ;origami 20 palace         (20 cycles of palace design)")
        echo("  ;origami crane 50          (50 cycles of crane design)")
        echo("  ;origami palace            (unlimited palace cycles)")
        echo("  ;origami 100               (100 cycles of default palace)")
        echo("")
        echo("FEATURES:")
        echo("  - Automatically gets paper from Vars.lootsack (or knapsack)")
        echo("  - 5 folds per sheet maximum, then tosses and gets new paper")
        echo("  - Returns unused paper to container when finished")
        echo("  - Shows progress with time estimates")
        echo("  - Stops if hands too injured for origami work")
        echo("  - Stops if invalid design name entered")
        echo("")
        echo("COMMON DESIGNS: palace, crane, flower, box, star, swan")
        return
    elseif t:match("^%d+$") then
        max_cycles = tonumber(t)
    else
        design = t:match("^%s*(.-)%s*$")
    end
end

local sack = (Vars.lootsack or ""):match("^%s*(.-)%s*$")
if sack == "" then sack = "knapsack" end

local function log(msg)
    echo("[origami] " .. msg)
end

local function wait_ready()
    pause(BASE_WAIT_TIME)
    waitrt()
    waitcastrt()
end

local function send_cmd(cmd)
    wait_ready()
    fput(cmd)
    if cmd:find("origami fold") then
        pause(2.0)
        waitrt()
    else
        pause(0.3)
        waitrt()
    end
end

local function has_paper()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    return (rh and rh.name and rh.name:lower():find("paper") ~= nil)
        or (lh and lh.name and lh.name:lower():find("paper") ~= nil)
end

local function get_paper()
    if has_paper() then return true end
    log("Getting paper from " .. sack .. "...")
    send_cmd("get paper from my " .. sack)
    pause(0.2)
    return has_paper()
end

local function check_line_for_injury(line)
    if line:lower():find("hands are far too sore for such delicate work")
        or line:lower():find("tips of your fingers are too sore from previous paper cuts") then
        log("HANDS TOO INJURED FOR ORIGAMI WORK!")
        log("Please heal your hands before continuing.")
        log("Script stopping for safety.")
        exit()
    end
    if line:lower():find("mind feels overloaded with creativity") then
        log("CREATIVITY OVERLOADED!")
        log("Your mind is too overwhelmed to remember origami patterns.")
        log("Please rest until a new day before continuing.")
        log("Script stopping - daily limit reached.")
        exit()
    end
end

local function perform_fold(design_name)
    log("Folding " .. design_name .. "...")
    send_cmd("origami fold " .. design_name)
    send_cmd("origami fold " .. design_name)

    -- Drain buffer and check for injury/invalid-design/creativity messages
    for _ = 1, 3 do
        local line = get_noblock()
        if not line then break end
        check_line_for_injury(line)
        if line:lower():find("does not appear to be a valid mnemonic for an origami pattern") then
            log("INVALID ORIGAMI DESIGN: '" .. design_name .. "'")
            log("Please check your design name and try again.")
            log("Script stopping due to invalid design.")
            exit()
        end
    end
end

local function perform_unfold()
    log("Unfolding...")
    send_cmd("origami unfold")
    send_cmd("origami unfold")

    local result = "unknown"
    for _ = 1, MAX_GET_ATTEMPTS do
        pause(0.2)
        local line = get_noblock()
        if not line then break end

        if line:lower():find("you gently unfold the origami") then
            return "success"
        elseif line:lower():find("not an origami creation") then
            if result == "unknown" then result = "flat" end
        elseif line:lower():find("pain of your injuries") or line:lower():find("concentration.*falters") then
            log("Injury distraction - pausing for recovery")
            pause(2.0)
            waitrt()
        else
            check_line_for_injury(line)
        end
    end

    return result
end

local function discard_paper()
    if not has_paper() then return end
    log("Discarding used paper...")
    send_cmd("toss my paper")
    pause(0.2)
    send_cmd("toss my paper")
    pause(0.1)
end

-- -------- Main execution --------

local cycles_label = max_cycles and tostring(max_cycles) or "unlimited"
log("Starting: " .. cycles_label .. " cycles | design: " .. design .. " | container: " .. sack)

if max_cycles then
    local est_secs = max_cycles * 9
    local est_mins = est_secs / 60.0
    if est_mins < 1 then
        log("Estimated time: " .. est_secs .. " seconds")
    elseif est_mins < 60 then
        log("Estimated time: " .. string.format("%.1f", est_mins) .. " minutes")
    else
        log("Estimated time: " .. string.format("%.1f", est_mins / 60.0) .. " hours")
    end
end

local total_completed    = 0
local current_sheet_folds = 0
local start_time         = os.time()

if not get_paper() then
    log("ERROR: No paper available in " .. sack .. ". Exiting.")
    exit()
end

local fatal_err = nil
local ok = pcall(function()
    while true do
        if max_cycles and total_completed >= max_cycles then break end

        perform_fold(design)
        local unfold_result = perform_unfold()

        if unfold_result == "success" then
            current_sheet_folds = current_sheet_folds + 1
            total_completed     = total_completed + 1

            local elapsed = os.time() - start_time
            if max_cycles and total_completed > 0 then
                local avg       = elapsed / total_completed
                local remaining = (max_cycles - total_completed) * avg
                local time_left
                if remaining < 60 then
                    time_left = math.floor(remaining) .. "s"
                elseif remaining < 3600 then
                    time_left = string.format("%.1f", remaining / 60) .. "m"
                else
                    time_left = string.format("%.1f", remaining / 3600) .. "h"
                end
                log("Cycle " .. total_completed .. "/" .. max_cycles ..
                    " (" .. current_sheet_folds .. "/" .. MAX_FOLDS_PER_SHEET ..
                    " on sheet) - ETA: " .. time_left)
            else
                log("Cycle " .. total_completed ..
                    " (" .. current_sheet_folds .. "/" .. MAX_FOLDS_PER_SHEET .. " on current sheet)")
            end

            if current_sheet_folds >= MAX_FOLDS_PER_SHEET then
                discard_paper()
                current_sheet_folds = 0
                if max_cycles and total_completed >= max_cycles then break end
                if not get_paper() then
                    log("No more paper available in " .. sack .. ". Session complete.")
                    break
                end
            end

        elseif unfold_result == "flat" then
            log("Sheet unusable (flat paper). Discarding and getting new sheet.")
            discard_paper()
            current_sheet_folds = 0
            if not get_paper() then
                log("No more paper available in " .. sack .. ". Session complete.")
                break
            end

        else
            log("WARNING: Unclear unfold result. Continuing...")
        end
    end
end)

-- Discard if we finished exactly at sheet limit
if max_cycles and total_completed >= max_cycles and current_sheet_folds == MAX_FOLDS_PER_SHEET then
    discard_paper()
end

-- Return any paper still in hand to sack
if has_paper() then
    log("Returning unused paper to " .. sack)
    pcall(function() send_cmd("put my paper in my " .. sack) end)
end

local elapsed = os.time() - start_time
local time_summary
if elapsed < 60 then
    time_summary = elapsed .. "s"
elseif elapsed < 3600 then
    time_summary = string.format("%.1f", elapsed / 60) .. "m"
else
    time_summary = string.format("%.1f", elapsed / 3600) .. "h"
end

if not ok then
    log("FATAL ERROR: unexpected script failure after " .. time_summary)
else
    log("Session complete! Total cycles: " .. total_completed .. " in " .. time_summary)
end
