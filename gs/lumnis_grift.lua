--- @revenant-script
--- name: lumnis_grift
--- version: 1.0.0
--- author: Anebriated
--- game: gs
--- tags: lumnis, gift, donate, automation
--- description: Check Lumnis donation count, withdraw silver, and donate to reach 4 total
---
--- Original Lich5 authors: Anebriated
--- Ported to Revenant Lua from lumnis_grift.lic v1.0
---
--- Usage: ;lumnis_grift

local DONATION_COST = 250000
local TARGET_DONATIONS = 4

local function get_donation_count()
    fput("lumnis info")
    local timeout = os.time() + 5
    local lines = {}
    while os.time() < timeout do
        local line = get()
        if line then
            lines[#lines + 1] = line
            if line:find("recent donation") or line:find("Temple of Lumnis") then break end
        end
    end
    local full = table.concat(lines, " ")
    local count = full:match("You have made (%d+) recent donation")
    if count then return tonumber(count) end
    if full:find("You have not made any recent donation") then return 0 end
    echo("ERROR: Could not parse donation count from lumnis info.")
    return nil
end

local function go_to_bank()
    if Script.exists("go2") then
        echo("Navigating to bank...")
        Script.run("go2", "bank")
        wait(1)
    else
        echo("WARNING: go2 not available. Please navigate to the bank manually and re-run.")
        return
    end
end

local function withdraw_silver(amount)
    fput("withdraw " .. amount .. " silver")
    local result = waitfor("hands you|do not have that much|insufficient|Unable")
    if result and result:find("hands you") then
        echo("Withdrew " .. amount .. " silver successfully.")
        return true
    else
        echo("ERROR: Could not withdraw " .. amount .. " silver.")
        return false
    end
end

local function do_donations(count)
    for i = 1, count do
        echo("Donating " .. i .. " of " .. count .. "...")
        fput("lumnis donate")
        waitfor("LUMNIS DONATE CONFIRM")
        fput("lumnis donate confirm")
        local confirmed = waitfor("You have now made|do not have enough|cannot donate|Error")
        if confirmed and confirmed:find("You have now made") then
            echo("Donation " .. i .. " successful.")
        else
            echo("ERROR on donation " .. i)
            return false
        end
        wait(0.5)
    end
    return true
end

echo("=== Lumnis Donation Manager ===")

local donation_count = get_donation_count()
if not donation_count then
    echo("Could not determine donation count. Exiting.")
    return
end

echo("Current donations: " .. donation_count .. " / " .. TARGET_DONATIONS)

if donation_count >= TARGET_DONATIONS then
    echo("Already at " .. TARGET_DONATIONS .. " donations. Nothing to do!")
    return
end

local needed = TARGET_DONATIONS - donation_count
local silver_needed = needed * DONATION_COST
echo("Need " .. needed .. " more donation(s). Requires " .. silver_needed .. " silver.")

-- Check current carried silver
local wealth = dothistimeout("wealth quiet", 3, "You have")
local current_silver = 0
if wealth then
    local amt = wealth:match("You have ([%d,]+) silver")
    if amt then current_silver = tonumber(amt:gsub(",", "")) or 0 end
end
echo("Silver on hand: " .. current_silver)

if current_silver < silver_needed then
    local short = silver_needed - current_silver
    echo("Need " .. short .. " more silver from bank. Heading to bank...")
    go_to_bank()
    if not withdraw_silver(short) then return end
else
    echo("Sufficient silver on hand. No bank trip needed.")
end

echo("Beginning donations...")
local success = do_donations(needed)

if success then
    echo("=== Done! Lumnis donations are now at " .. TARGET_DONATIONS .. ". ===")
    if Script.exists("go2") then
        echo("Returning to starting room...")
        Script.run("go2", "goback")
    end
else
    echo("=== Donation process encountered an error. Check output above. ===")
end
