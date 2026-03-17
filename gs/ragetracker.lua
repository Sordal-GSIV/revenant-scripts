--- @revenant-script
--- name: ragetracker
--- version: 1.4.0
--- author: ChatGPT/Claude
--- game: gs
--- description: Track Rage Armor activation bonuses, Storm of Rage tiers, and kill streaks
--- tags: combat, tracking, rage armor, storm of rage
---
--- Usage:
---   ;ragetracker       - Start tracking
---   ;ragetracker reset - Clear saved data

no_kill_all()

local output_mode = CharSettings["rage_output_mode"] or "main"
local buffs = {}
local high_score = CharSettings["rage_high_score"] or 0
local storm_active = false
local storm_tier = 0
local storm_streak = 0
local storm_kills = CharSettings["rage_storm_kills"] or 0
local storm_best = CharSettings["rage_storm_best"] or 0

if script.vars[1] and script.vars[1]:lower() == "reset" then
    CharSettings["rage_high_score"] = 0
    CharSettings["rage_storm_kills"] = 0
    CharSettings["rage_storm_best"] = 0
    echo("Rage tracker data reset.")
    exit()
end

local function save_data()
    CharSettings["rage_high_score"] = high_score
    CharSettings["rage_storm_kills"] = storm_kills
    CharSettings["rage_storm_best"] = storm_best
    CharSettings["rage_output_mode"] = output_mode
end

local function output(msg)
    if output_mode == "off" then return end
    if output_mode == "familiar" then
        respond("--- " .. msg)
    else
        echo(msg)
    end
end

local function update_buffs()
    local now = os.time()
    local new_buffs = {}
    local total = 0
    for _, b in ipairs(buffs) do
        if now < b.end_time then
            table.insert(new_buffs, b)
            total = total + b.bonus
        end
    end
    buffs = new_buffs
    return math.min(total, 50)
end

echo("Rage Tracker started. Output: " .. output_mode:upper())
echo("Commands: *rage main | *rage fam | *rage off | *rage status")

-- Upstream hook for commands
add_hook("upstream", "ragetracker_cmd", function(cmd)
    cmd = cmd:gsub("^<c>", ""):match("^%s*(.-)%s*$")
    if cmd:match("^%*rage") then
        local arg = cmd:match("^%*rage%s+(.+)") or ""
        arg = arg:lower():match("^%s*(.-)%s*$")
        if arg == "" or arg == "status" then
            local total = update_buffs()
            respond("--- Rage Tracker Status ---")
            respond("--- Output: " .. output_mode:upper())
            respond("--- Rage Armor: +" .. total .. " AS (" .. #buffs .. " buffs)")
            respond("--- Biggest Hit: " .. high_score)
            respond("--- Storm: " .. (storm_active and ("Tier " .. storm_tier .. " Streak " .. storm_streak) or "Inactive"))
            respond("--- Best Streak: " .. storm_best .. " | Total Kills: " .. storm_kills)
        elseif arg == "main" or arg == "fam" or arg == "familiar" or arg == "off" then
            output_mode = (arg == "fam") and "familiar" or arg
            save_data()
            respond("--- Rage Tracker output: " .. output_mode:upper())
        end
        return nil -- consume the command
    end
    return cmd
end)

before_dying(function()
    remove_hook("upstream", "ragetracker_cmd")
    save_data()
end)

local line_buffer = {}

while true do
    local line = get()
    table.insert(line_buffer, line)
    if #line_buffer > 5 then table.remove(line_buffer, 1) end

    -- Storm of Rage tracking
    if line:match("burning rage awakens") then
        storm_tier = 1; storm_active = true; storm_streak = storm_streak + 1; storm_kills = storm_kills + 1
    elseif line:match("burning rage mounts") then
        storm_tier = 2; storm_streak = storm_streak + 1; storm_kills = storm_kills + 1
    elseif line:match("burning rage reaches its zenith") then
        storm_tier = 3; storm_streak = storm_streak + 1; storm_kills = storm_kills + 1
    elseif line:match("conflagration of rage continues") then
        storm_streak = storm_streak + 1; storm_kills = storm_kills + 1
    elseif line:match("burning rage abates") then
        storm_active = false; storm_tier = 0
        if storm_streak > storm_best then storm_best = storm_streak end
        output("Storm ended. Streak: " .. storm_streak)
        storm_streak = 0
    end

    -- Rage Armor tracking
    if line:match("rage ignites within you") or line:match("rage within surges") then
        for i = #line_buffer, 1, -1 do
            local dmg = line_buffer[i]:match("(%d+) points? of damage!")
            if dmg then
                dmg = tonumber(dmg)
                table.insert(buffs, {bonus = dmg, end_time = os.time() + 30})
                if dmg > high_score then high_score = dmg end
                local total = update_buffs()
                output("RAGE +" .. dmg .. " (total +" .. total .. " AS)")
                save_data()
                break
            end
        end
    end
    pause(0.1)
end
