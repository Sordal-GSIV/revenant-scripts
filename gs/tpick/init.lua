--- @revenant-script
--- name: tpick
--- version: 27.0.0
--- author: Dreaven
--- contributors: Tgo01
--- game: gs
--- description: Comprehensive lockpicking — traps, picks, pool, calipers, loresing, plinites, bashing, GUI
--- tags: lockpicking, boxes, traps, loot, thief, rogue, pool
--- @lic-certified: complete 2026-03-18

---------------------------------------------------------------------------
-- Submodule requires
---------------------------------------------------------------------------
local data         = require("tpick/data")
local util         = require("tpick/util")
local settings_mod = require("tpick/settings")
local lockpicks    = require("tpick/lockpicks")
local traps        = require("tpick/traps")
local picking      = require("tpick/picking")
local spells_mod   = require("tpick/spells")
local loot         = require("tpick/loot")
local stats_mod    = require("tpick/stats")
local modes        = require("tpick/modes")
local pool         = require("tpick/pool")
local gui_settings = require("tpick/gui_settings")
local gui_info     = require("tpick/gui_info")

---------------------------------------------------------------------------
-- Version constant
---------------------------------------------------------------------------
local TPICK_VERSION = "27.0.0"

---------------------------------------------------------------------------
-- Wire cross-module dependencies
---------------------------------------------------------------------------

-- traps.wire expects individual function references (not modules)
traps.wire({
    open_solo         = modes.open_solo,
    open_others       = modes.open_others,
    measure_lock      = picking.measure_lock,
    wedge_lock        = picking.wedge_lock,
    bash_the_box_open = picking.bash_the_box_open,
    cast_407          = spells_mod.cast_407,
    pop_open_box      = modes.pop_open_box,
    detect_plinite    = modes.detect_plinite,
    tpick_cast_spells = spells_mod.tpick_cast_spells,
    tpick_prep_spell  = spells_mod.tpick_prep_spell,
    tpick_bundle_vials = loot.tpick_bundle_vials,
    stuff_to_do       = modes.stuff_to_do,
    no_vaalin_picks   = lockpicks.no_vaalin_picks,
})

-- picking.wire expects module references
picking.wire({
    util      = util,
    lockpicks = lockpicks,
    traps     = traps,
    spells    = spells_mod,
    modes     = modes,
})

-- spells_mod.wire expects module references
spells_mod.wire({
    util  = util,
    modes = modes,
})

-- loot.wire expects module reference
loot.wire({
    util = util,
})

-- modes.wire expects module references
modes.wire({
    util      = util,
    traps     = traps,
    picking   = picking,
    spells    = spells_mod,
    loot      = loot,
    stats     = stats_mod,
    lockpicks = lockpicks,
})

-- pool.wire expects module references
pool.wire({
    util      = util,
    traps     = traps,
    picking   = picking,
    spells    = spells_mod,
    loot      = loot,
    stats     = stats_mod,
    lockpicks = lockpicks,
    modes     = modes,
})

---------------------------------------------------------------------------
-- Load settings and stats
---------------------------------------------------------------------------
local settings = settings_mod.load()
if not settings then
    settings = settings_mod.load_defaults()
end

local saved_stats = settings_mod.load_stats()
local stats_data  = stats_mod.init()
stats_data = stats_mod.merge_loaded(stats_data, saved_stats,
                                     settings["Track Loot"] or "No")

---------------------------------------------------------------------------
-- Mutable vars table — runtime picking state
---------------------------------------------------------------------------
local vars = {}

---------------------------------------------------------------------------
-- Show help text and exit
---------------------------------------------------------------------------
local function show_help()
    local text = [[
;tpick solo       = Pick all boxes in your open containers.
;tpick other      = Wait for someone to GIVE you a box, pick it and GIVE it back.
;tpick ground     = Pick all boxes on the ground.
;tpick worker     = Pick boxes at a pool. Only works if you're in a pool room.
;tpick pool       = Same as worker.
;tpick setup      = Enter setup menu.
;tpick show       = Show the Information Window with stats and controls.
;tpick drop <tip> = Drop off boxes at a pool with the specified tip.
;tpick pickup     = Pick up finished boxes from a pool.
;tpick return     = Same as pickup.
;tpick buy        = Refill locksmith container with lockpicks.
;tpick repair     = Repair bent lockpicks.
;tpick version    = Show version information.

Options (combine with a mode):
  bash       = Bash open boxes (Warrior only).
  disarm     = Disarm traps only, do not pick locks.
  relock     = Relock boxes after picking.
  loot       = Loot items from the ground.
  pop        = Pop boxes using Piercing Gaze (416).
  plin       = Open plinites instead of regular boxes.
  v          = Always use Vaalin lockpicks.
  c          = Start with Copper lockpicks.
  wedge      = Always use a Wedge.
  exit       = Exit when waiting for boxes.
  percent/%  = Treat tip amount as a percentage.
  <number>   = Tip amount in silvers (or percent with % flag).
]]
    util.tpick_silent(true, text, settings)
end

---------------------------------------------------------------------------
-- Show version and exit
---------------------------------------------------------------------------
local function show_version()
    util.tpick_silent(true, "tpick version " .. TPICK_VERSION, settings)
end

---------------------------------------------------------------------------
-- Parse command-line arguments
-- Ported from tpick.lic lines 6051-6074
---------------------------------------------------------------------------
local function parse_args()
    local script_vars = Script.vars or {}
    local default_commands = {}

    -- Parse Default Mode setting if no command-line args
    if settings["Default Mode"]
       and settings["Default Mode"]:find("%S")
       and (not script_vars[1]) then
        for word in settings["Default Mode"]:gmatch("%S+") do
            default_commands[#default_commands + 1] = word
        end
    end

    -- Helper: check if any script var matches pattern (case-insensitive)
    local function any_var(pat)
        for i = 1, #script_vars do
            if script_vars[i] and script_vars[i]:lower():find(pat) then
                return true
            end
        end
        return false
    end

    -- Helper: check if any script var matches exact lowercase string
    local function any_var_exact(str)
        for i = 1, #script_vars do
            if script_vars[i] and script_vars[i]:lower() == str then
                return true
            end
        end
        return false
    end

    -- Helper: check default commands for exact match
    local function any_default(str)
        for _, cmd in ipairs(default_commands) do
            if cmd:lower() == str then return true end
        end
        return false
    end

    -- Helper: check default commands for pattern match
    local function any_default_pat(pat)
        for _, cmd in ipairs(default_commands) do
            if cmd:lower():find(pat) then return true end
        end
        return false
    end

    -- Early exit commands
    if any_var("setup")   then return "setup" end
    if any_var("help")    then return "help" end
    if any_var("version") then return "version" end

    -- Boolean flags (lines 6053-6074)
    vars["Open Plinites"]     = (any_var("plin")   or any_default("plin"))   or nil
    vars["Bash Open Boxes"]   = (any_var("bash")   or any_default("bash"))   or nil
    vars["Disarm Only"]       = (any_var("disarm") or any_default("disarm")) or nil
    vars["Relock Boxes"]      = (any_var("relock") or any_default("relock")) or nil
    vars["Drop Off Boxes"]    = (any_var("drop")   or any_default("drop"))   or nil
    vars["Pick Up Boxes"]     = (any_var("return") or any_var("pickup")
                                 or any_default("pickup"))                   or nil
    vars["Tip Is A Percent"]  = (any_var("percent") or any_var("%%")
                                 or any_default_pat("%%"))                   or nil
    vars["Start With Copper"] = (any_var_exact("c") or any_default("c"))     or nil
    vars["Always Use Vaalin"] = (any_var_exact("v") or any_default("v"))     or nil
    vars["Always Use Wedge"]  = (any_var("wedge")  or any_default("wedge"))  or nil
    vars["Ground Loot"]       = (any_var("loot")   or any_default("loot"))   or nil
    vars["Pop Boxes"]         = (any_var("pop")    or any_default("pop"))    or nil
    vars["Buy Mode"]          = (any_var("buy")    or any_default("buy"))    or nil
    vars["Repair Mode"]       = (any_var("repair") or any_default("repair")) or nil
    vars["Exit When Waiting"] = any_var("exit")                              or nil

    -- Numeric tip (lines 6065-6066)
    for i = 1, #script_vars do
        local num = script_vars[i] and script_vars[i]:match("^(%d+)$")
        if num then vars["Tip Being Offered"] = tonumber(num) end
    end
    for _, cmd in ipairs(default_commands) do
        local num = cmd:match("^(%d+)$")
        if num then vars["Tip Being Offered"] = tonumber(num) end
    end

    -- Picking mode (order matters — later wins, matching Ruby)
    if any_var("ground") or any_default("ground") then
        vars["Picking Mode"] = "ground"
    end
    if any_var("other") or any_default("other") then
        vars["Picking Mode"] = "other"
    end
    if any_var("worker") or any_var("pool") or any_default("pool") then
        vars["Picking Mode"] = "worker"
    end
    if any_var("solo") or any_default("solo") then
        vars["Picking Mode"] = "solo"
    end

    -- drop/pickup/return set Picking Mode to true (signals "has a mode")
    if any_var("return") or any_var("pickup") or any_var("drop")
       or any_default_pat("return") or any_default_pat("pickup") or any_default_pat("drop") then
        vars["Picking Mode"] = vars["Picking Mode"] or true
    end

    -- Start With Copper overridden by Always Use Vaalin (line 6076)
    if vars["Always Use Vaalin"] and vars["Start With Copper"] then
        vars["Start With Copper"] = nil
    end

    -- Force vaalin if no calipers/loresinging and not starting copper (lines 6077-6078)
    if settings["Use Calipers"] == "No" and settings["Use Loresinging"] == "No"
       and not vars["Start With Copper"] then
        vars["Always Use Vaalin"] = true
    end
    if Stats.prof ~= "Rogue" and Stats.prof ~= "Bard"
       and not vars["Start With Copper"] then
        vars["Always Use Vaalin"] = true
    end

    -- Check if any command-line commands are present
    if vars["Drop Off Boxes"] or vars["Pick Up Boxes"] or vars["Picking Mode"]
       or vars["Buy Mode"] or vars["Repair Mode"] then
        vars["Command Lines Used"] = true
    end

    return nil  -- no early-exit command
end

---------------------------------------------------------------------------
-- Profession checks and skill calculations
-- Ported from tpick.lic lines 1876-1884, 5908-5936
---------------------------------------------------------------------------
local function calculate_skills()
    vars["Dex Bonus"]   = Stats.enhanced_dex[1]
    vars["Pick Skill"]  = Skills.to_bonus(Skills.pickinglocks) + vars["Dex Bonus"]
    vars["Disarm Skill"] = vars["Dex Bonus"] + Skills.to_bonus(Skills.disarmingtraps)

    -- Pick Lore: min(level/2 + pick_bonus/10 + dex + minor_ele/4, pick_bonus)
    local pick_bonus  = Skills.to_bonus(Skills.pickinglocks)
    local disarm_bonus = Skills.to_bonus(Skills.disarmingtraps)
    local level = Stats.level
    local dex   = vars["Dex Bonus"]
    local me_circle = Spells.minorelemental or 0

    vars["Pick Lore"] = math.min(
        math.floor(level / 2) + math.floor(pick_bonus / 10) + dex + math.floor(me_circle / 4),
        pick_bonus
    )

    if Spell[404] and Spell[404].known then
        vars["Disarm Lore"] = math.min(
            math.floor(level / 2) + math.floor(disarm_bonus / 10) + dex + math.floor(me_circle / 4),
            disarm_bonus
        )
    else
        vars["Disarm Lore"] = 0
    end
end

---------------------------------------------------------------------------
-- Profession-specific setup
-- Ported from tpick.lic lines 5908-5936
---------------------------------------------------------------------------
local function setup_profession()
    if Stats.prof == "Rogue" then
        vars["Can Use Calipers"] = true

        -- Trick setting
        if settings["Trick"] == "pick" then
            vars["Do Trick"] = "pick"
        elseif settings["Trick"] ~= "random" then
            vars["Do Trick"] = "lmas ptrick " .. (settings["Trick"] or "pick")
        end

        -- Lock Mastery detection
        if settings["Use Lmaster Focus"] == "Yes" then
            local result = dothistimeout("gld", 3,
                "You have no guild affiliation%.|Click GLD MENU for additional commands%." ..
                "|You have (%d+) ranks in the Lock Mastery skill%." ..
                "|You are a Master of Lock Mastery%.")
            local lm_ranks = 0
            if result then
                if result:find("You have no guild affiliation")
                   or result:find("Click GLD MENU") then
                    lm_ranks = 0
                else
                    local ranks = result:match("You have (%d+) ranks in the Lock Mastery skill")
                    if ranks then
                        lm_ranks = tonumber(ranks)
                    elseif result:find("You are a Master of Lock Mastery") then
                        lm_ranks = 63
                    end
                end
            end
            vars["Pick Lore"]  = (2 * lm_ranks) + math.floor(vars["Dex Bonus"] / 2)
            vars["Disarm Lore"] = (2 * lm_ranks) + math.floor(vars["Dex Bonus"] / 2)
        end
    else
        vars["Can Use Calipers"] = nil
        vars["Do Trick"] = "pick"
    end
end

---------------------------------------------------------------------------
-- Validation checks
-- Ported from tpick.lic lines 6080-6109
---------------------------------------------------------------------------
local function validate_options()
    if Stats.prof ~= "Warrior" and vars["Bash Open Boxes"] then
        util.tpick_silent(true, "Only Warriors can use the 'bash' feature.", settings)
        return false
    end

    if vars["Open Plinites"] then
        if vars["Disarm Only"] then
            util.tpick_silent(true, "Disarm feature cannot be used when opening plinites.", settings)
            return false
        elseif vars["Relock Boxes"] then
            util.tpick_silent(true, "Relock feature cannot be used when opening plinites.", settings)
            return false
        elseif vars["Bash Open Boxes"] then
            util.tpick_silent(true, "Bash feature cannot be used when opening plinites.", settings)
            return false
        elseif vars["Pop Boxes"] then
            util.tpick_silent(true, "Popping feature cannot be used when opening plinites.", settings)
            return false
        end
    end

    if vars["Relock Boxes"] and vars["Bash Open Boxes"] then
        util.tpick_silent(true, "'relock' and 'bash' cannot both be used together.", settings)
        return false
    end

    if vars["Pop Boxes"] and (not Spell[416] or not Spell[416].known) then
        util.tpick_silent(true, "Popping feature requires the knowledge of Piercing Gaze (416).", settings)
        return false
    end

    return true
end

---------------------------------------------------------------------------
-- Mithril/enruned detection hook
-- Ported from tpick.lic lines 1923-1945
---------------------------------------------------------------------------
local function check_mithril_or_enruned()
    local hook_name = Script.name .. "_check_for_mithril_or_enruned"

    local function action(server_string)
        if server_string:find("You glance down to see")
           and (server_string:find("mithril") or server_string:find("enruned")
                or server_string:find("rune%-incised")) then
            vars["Hand Status"] = "mithril or enruned"
            DownstreamHook.remove(hook_name)
            return nil
        elseif server_string:find("You glance down.*left hand") then
            vars["Hand Status"] = "good"
            DownstreamHook.remove(hook_name)
            return nil
        elseif server_string:find("You glance down at your empty hands%.") then
            vars["Hand Status"] = "empty"
            DownstreamHook.remove(hook_name)
            return nil
        else
            return server_string
        end
    end

    DownstreamHook.add(hook_name, action)
    silence_me()
    fput(vars["Check For Command"] or "glance")
    silence_me()
end

-- Store on vars so submodules can call it
vars["check_mithril_or_enruned"] = check_mithril_or_enruned

---------------------------------------------------------------------------
-- before_dying cleanup
-- Ported from tpick.lic lines 1886-1921
---------------------------------------------------------------------------
local function register_cleanup()
    before_dying(function()
        -- Save pool picking time
        if vars["Worker Start Time"] then
            stats_data["Pool Time Spent Picking"] =
                (stats_data["Pool Time Spent Picking"] or 0)
                + (os.time() - vars["Worker Start Time"])
        end

        -- Remove downstream hooks
        DownstreamHook.remove(Script.name .. "_check_locksmiths_container")
        DownstreamHook.remove(Script.name .. "_check_for_mithril_or_enruned")

        -- Close containers if configured (skip for buy/repair/setup)
        local script_vars = Script.vars or {}
        local skip_close = false
        for i = 1, #script_vars do
            if script_vars[i] and script_vars[i]:lower():find("^buy$")
               or (script_vars[i] and script_vars[i]:lower():find("^repair$"))
               or (script_vars[i] and script_vars[i]:lower():find("^setup$")) then
                skip_close = true
                break
            end
        end

        if not skip_close then
            local containers_to_close = {}
            local seen = {}
            local close_map = {
                { name = settings["Lockpick Container"],      close = settings["Lockpick Close"] },
                { name = settings["Broken Lockpick Container"], close = settings["Broken Close"] },
                { name = settings["Wedge Container"],         close = settings["Wedge Close"] },
                { name = settings["Calipers Container"],      close = settings["Calipers Close"] },
                { name = settings["Scale Weapon Container"],  close = settings["Weapon Close"] },
            }
            for _, entry in ipairs(close_map) do
                local name = entry.name
                if name and name:find("%S") and entry.close == "Yes" and not seen[name] then
                    seen[name] = true
                    containers_to_close[#containers_to_close + 1] = name
                end
            end

            if #containers_to_close > 0 then
                if checkrt and checkrt() > 0 then
                    util.tpick_silent(nil,
                        "I will close your containers as soon as you're out of RT then I will exit.",
                        settings)
                    wait_until(function() return checkrt() == 0 end)
                end
                for _, cname in ipairs(containers_to_close) do
                    local inv = GameObj.inv()
                    for _, item in ipairs(inv or {}) do
                        if item.name == cname then
                            fput("close #" .. item.id)
                            break
                        end
                    end
                end
            end

            -- Re-equip armor if removed
            if vars["Armor Removed"] and vars["Armor To Remove"] then
                if checkrt and checkrt() > 0 then
                    util.tpick_silent(nil,
                        "I will equip your armor as soon as you're out of RT then I will exit.",
                        settings)
                    wait_until(function() return checkrt() == 0 end)
                end
                util.tpick_put_stuff_away(vars, settings)
                fput("get " .. vars["Armor To Remove"])
                wait_until(function() return checkright() end)
                fput("wear " .. vars["Armor To Remove"])
            end
        end

        -- Save stats
        settings_mod.save_stats(stats_data)

        -- Show error/crash messages
        if vars["Error Message"] then
            respond("\n########################################\n"
                .. vars["Error Message"]
                .. "\n########################################\n")
        end
        if vars["Crash Report"] then
            respond("\n########################################\n"
                .. vars["Crash Report"]
                .. "\n########################################\n")
        end
    end)
end

---------------------------------------------------------------------------
-- Helper: check if "show" was passed on command line
---------------------------------------------------------------------------
local function any_show_arg()
    local script_vars = Script.vars or {}
    for i = 1, #script_vars do
        if script_vars[i] and script_vars[i]:lower() == "show" then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- start_up_procedure — The main startup orchestrator.
-- Ported from tpick.lic lines 5642-5805
---------------------------------------------------------------------------
local function start_up_procedure()
    -- Check containers (unless drop-off/pickup mode)
    if not vars["Drop Off Boxes"] and not vars["Pick Up Boxes"] then
        if (not vars["Pop Boxes"])
           or (vars["Pop Boxes"] and settings["Pick Enruned"] == "Yes") then
            if not vars["Checked For Containers"] then
                loot.check_for_containers(vars, settings)
            end
        end
        lockpicks.no_vaalin_picks(vars, settings, nil)
    end
    vars["Checked For Containers"] = true

    -- Get pool info for pool modes
    if vars["Picking Mode"] == "worker" or vars["Drop Off Boxes"] or vars["Pick Up Boxes"] then
        pool.get_pool_info(vars)
    end

    -- Gnomish Bracers
    if settings["Gnomish Bracer"] and settings["Gnomish Bracer"]:find("%S") then
        vars["Gnomish Bracers"] = settings["Gnomish Bracer"]
    end

    -- Open containers if configured (lines 5970-5984)
    local containers_to_open = {}
    local seen = {}
    local open_map = {
        { name = settings["Lockpick Container"],       open = settings["Lockpick Open"] },
        { name = settings["Broken Lockpick Container"], open = settings["Broken Open"] },
        { name = settings["Wedge Container"],          open = settings["Wedge Open"] },
        { name = settings["Calipers Container"],       open = settings["Calipers Open"] },
        { name = settings["Scale Weapon Container"],   open = settings["Weapon Open"] },
    }
    for _, entry in ipairs(open_map) do
        local name = entry.name
        if name and name:find("%S") and entry.open == "Yes" and not seen[name] then
            seen[name] = true
            containers_to_open[#containers_to_open + 1] = name
        end
    end
    if #containers_to_open > 0 then
        local inv = GameObj.inv()
        for _, cname in ipairs(containers_to_open) do
            for _, item in ipairs(inv or {}) do
                if item.name == cname then
                    fput("open #" .. item.id)
                    break
                end
            end
        end
    end

    -- Parse Rest When Fried commands (lines 5986-5992)
    if settings["Rest When Fried"] and settings["Rest When Fried"]:find("%S") then
        local parts = {}
        for part in settings["Rest When Fried"]:gmatch("[^:]+") do
            parts[#parts + 1] = part:match("^%s*(.-)%s*$")  -- trim
        end
        vars["Pool Fried Commands"] = parts
    end

    -- Parse Other Containers (line 5995)
    if settings["Other Containers"] then
        local others = {}
        for part in settings["Other Containers"]:gmatch("[^,]+") do
            others[#others + 1] = part:match("^%s*(.-)%s*$")
        end
        vars["Other Containers"] = others
    end

    -- Stow hands (lines 5997-5998)
    if checkright() then fput("stow right") end
    if checkleft()  then fput("stow left") end
    util.tpick_put_stuff_away(vars, settings)

    -- Arcane Symbols warning (line 6002)
    if Skills.arcanesymbols and Skills.arcanesymbols < 20 then
        util.tpick_silent(true,
            "WARNING: You need 20 ranks of Arcane Symbols in order to disarm scarabs "
            .. "with one try. As of now the script doesn't check for your skill or failure "
            .. "messages when disarming scarabs. It is highly recommended you get 20 ranks "
            .. "of Arcane Symbols.", settings)
    end

    -- Max Lock Attempt (lines 6005-6010)
    vars["Max Lock Attempt"] = settings["Max Lock"] or 0
    if settings["Max Lock"] and tonumber(settings["Max Lock"]) and tonumber(settings["Max Lock"]) < 0 then
        vars["Max Lock Compared To Skill"] = true
    else
        vars["Max Lock Compared To Skill"] = nil
    end

    -- 403 spell settings (lines 6012-6016)
    if (Spell[403] and Spell[403].known) or Stats.prof == "Rogue" then
        local s403 = settings["403"] or ""
        local num = s403:match("(%d+)")
        if num then vars["Use 403 For Lock Difficulty"] = tonumber(num) end
        if s403:lower():find("yes") then vars["Use 403"] = true end
        if s403:lower():find("cancel") then vars["Cancel 403"] = "cancel" end
    end

    -- 404 spell settings (lines 6018-6022)
    if (Spell[404] and Spell[404].known) or Stats.prof == "Rogue" then
        local s404 = settings["404"] or ""
        local num = s404:match("(%d+)")
        if num then vars["404 For Trap-Difficulty"] = tonumber(num) end
        if s404:lower():find("yes") then vars["Use 404"] = true end
        if s404:lower():find("cancel") then vars["Cancel 404"] = "cancel" end
    end

    -- Additional spell flags (lines 6024-6029)
    if settings["Presence (402)"]       == "Yes" then vars["Use 402"]  = true end
    if settings["Celerity (506)"]       == "Yes" then vars["Use 506"]  = true end
    if settings["Rapid Fire (515)"]     == "Yes" then vars["Use 515"]  = true end
    if settings["Song of Tonis (1035)"] == "Yes" then vars["Use 1035"] = true end
    if settings["Self Control (613)"]   == "Yes" then vars["Use 613"]  = true end
    if settings["Song of Luck (1006)"]  == "Yes" then vars["Use 1006"] = true end

    -- Minimum tip (line 6031)
    vars["Current Minimum Tip"] = settings["Minimum Tip Start"]

    -- Log max level if not default (line 6033)
    if settings["Max Level"] and settings["Max Level"] ~= 200 then
        util.tpick_silent(true, "Max level wanted: " .. tostring(settings["Max Level"]), settings)
    end

    -- Picks For Critter Level (lines 6035-6049)
    if settings["Picks On Level"] and settings["Picks On Level"]:find("%S")
       and not vars["Always Use Vaalin"] then
        local picks_for_level = {}
        for part in settings["Picks On Level"]:gmatch("[^,]+") do
            picks_for_level[#picks_for_level + 1] = part:match("^%s*(.-)%s*$")
        end
        vars["Picks For Critter Level"] = picks_for_level

        -- Build info string
        local info = "Your picks to use based on critter level settings: "
        local prev_level = 0
        for _, entry in ipairs(picks_for_level) do
            local parts = {}
            for w in entry:gmatch("%S+") do parts[#parts + 1] = w end
            local lvl = parts[1] or "?"
            local pick = parts[2] or "?"
            if prev_level == 0 then
                info = info .. "Levels 0-" .. lvl .. ": " .. pick .. ". "
            else
                info = info .. "Levels " .. (prev_level + 1) .. "-" .. lvl .. ": " .. pick .. ". "
            end
            prev_level = tonumber(lvl) or prev_level
        end
        info = info .. "All higher levels: Vaalin"
        vars["Picks Information"] = info
    end

    -- Cast Light (205) if configured (line 6111)
    if settings["Light (205)"] == "Yes" and Spell[205] then
        Spell[205].cast()
    end

    -- Show Window / silence (lines 6113-6115)
    if settings["Show Window"] ~= "No" or any_show_arg() then
        vars["Window Active"] = true
    end
    if settings["Don't Show Commands"] == "Yes" then
        silence_me()
    end

    -- Solhaven pool warning (line 6117)
    util.tpick_silent(true,
        "There might be an issue with ;tpick working properly when picking at the "
        .. "Locksmith's pool in Solhaven.\nIf ;tpick isn't working correctly here "
        .. "try doing this:\nset Description OFF\nThen move to another room and back "
        .. "to the Locksmith's pool room and try running ;tpick again.", settings)

    ----------- Dispatch to the correct mode (lines 5642-5805) -----------

    if vars["Buy Mode"] then
        loot.fill_up_locksmith_container(vars, settings)
    elseif vars["Repair Mode"] then
        lockpicks.repair_lockpicks_start(vars, settings)
    elseif vars["Drop Off Boxes"] then
        pool.drop_off_boxes(vars, settings)
    elseif vars["Pick Up Boxes"] then
        pool.pick_up_boxes(vars, settings, stats_data)
    elseif vars["Picking Mode"] == "ground" or vars["Bash Open Boxes"] then
        if vars["Open Plinites"] then
            util.tpick_silent(true, "Ground feature cannot be used when opening plinites.", settings)
            return
        end
        if settings["Calibrate On Startup"] == "Yes"
           and not vars["Always Use Vaalin"]
           and not vars["Pop Boxes"]
           and vars["Can Use Calipers"]
           and not vars["Start With Copper"] then
            picking.calibrate_calipers(vars, settings)
        end
        modes.start_ground(vars, settings, stats_data)
    elseif vars["Picking Mode"] == "other" then
        if vars["Open Plinites"] then
            util.tpick_silent(true, "Other feature cannot be used when opening plinites.", settings)
            return
        end
        if vars["Disarm Only"] and not vars["Bash Open Boxes"] then
            util.tpick_silent(true, "Disarm only feature only works for ground picking.", settings)
            return
        end
        util.tpick_say("Ready", settings)
        modes.start_others(vars, settings)
    elseif vars["Picking Mode"] == "worker" then
        if vars["Open Plinites"] then
            util.tpick_silent(true, "Worker feature cannot be used when opening plinites.", settings)
            return
        end
        if vars["Disarm Only"] and not vars["Bash Open Boxes"] then
            util.tpick_silent(true, "Disarm only feature only works for ground picking.", settings)
            return
        end
        if settings["Calibrate On Startup"] == "Yes"
           and not vars["Always Use Vaalin"]
           and not vars["Pop Boxes"]
           and vars["Can Use Calipers"]
           and not vars["Start With Copper"] then
            picking.calibrate_calipers(vars, settings)
        end
        if vars["Picks For Critter Level"] then
            util.tpick_silent(true, vars["Picks Information"], settings)
        end
        vars["Worker Start Time"] = os.time()
        pool.start_worker(vars, settings, stats_data)
    elseif vars["Picking Mode"] == "solo" then
        if vars["Disarm Only"] and not vars["Bash Open Boxes"] then
            util.tpick_silent(true, "Disarm only feature only works for ground picking.", settings)
            return
        end
        modes.check_for_boxes(vars, settings)
        if vars["Pop Boxes"] then
            modes.pop_start(vars, settings)
        elseif vars["Open Plinites"] then
            modes.start_plinites(vars, settings)
        else
            if settings["Calibrate On Startup"] == "Yes"
               and not vars["Always Use Vaalin"]
               and not vars["Pop Boxes"]
               and vars["Can Use Calipers"]
               and not vars["Start With Copper"] then
                picking.calibrate_calipers(vars, settings)
            end
            modes.start_solo(vars, settings, stats_data)
        end
    end
end

---------------------------------------------------------------------------
-- Reset all command vars for looping window mode (line 6156-6159)
---------------------------------------------------------------------------
local ALL_COMMAND_OPTIONS = {
    "Open Plinites", "Bash Open Boxes", "Disarm Only", "Relock Boxes",
    "Drop Off Boxes", "Pick Up Boxes", "Tip Is A Percent",
    "Start With Copper", "Always Use Vaalin", "Always Use Wedge",
    "Ground Loot", "Pop Boxes", "Tip Being Offered", "Picking Mode",
    "Command Lines Used", "Buy Mode", "Repair Mode",
}

local function reset_command_vars()
    for _, key in ipairs(ALL_COMMAND_OPTIONS) do
        vars[key] = nil
    end
end

---------------------------------------------------------------------------
-- Apply commands from the GUI information window (lines 6131-6153)
---------------------------------------------------------------------------
local function apply_gui_commands(commands)
    vars["Always Use Vaalin"] = nil

    for _, cmd in ipairs(commands) do
        if cmd == "Pool Picking"            then vars["Picking Mode"] = "worker" end
        if cmd:find("Ground")               then vars["Picking Mode"] = "ground" end
        if cmd == "Solo Picking"            then vars["Picking Mode"] = "solo" end
        if cmd == "Other Picking"           then vars["Picking Mode"] = "other" end
        if cmd:find("Loot")                 then vars["Ground Loot"] = true end
        if cmd == "Plinites"                then vars["Open Plinites"] = true end
        if cmd:find("Bash")                 then vars["Bash Open Boxes"] = true end
        if cmd:find("Disarm")               then vars["Disarm Only"] = true end
        if cmd == "Relock Boxes"            then vars["Relock Boxes"] = true end
        if cmd == "Drop Off Boxes"          then vars["Drop Off Boxes"] = true end
        if cmd == "Percent"                 then vars["Tip Is A Percent"] = true end
        if cmd == "Pick Up Boxes"           then vars["Pick Up Boxes"] = true end
        if cmd == "Start With Copper"       then vars["Start With Copper"] = true end
        if cmd == "Always Use Vaalin"       then vars["Always Use Vaalin"] = true end
        if cmd == "Always Use Wedge"        then vars["Always Use Wedge"] = true end
        if cmd == "Pop Boxes"               then vars["Pop Boxes"] = true end
        if cmd == "Refill Locksmith's Container" then vars["Buy Mode"] = true end
        if cmd == "Repair Lockpicks"        then vars["Repair Mode"] = true end

        local num = cmd:match("(%d+)")
        if num then vars["Tip Being Offered"] = tonumber(num) end
    end

    -- Re-apply vaalin defaults
    if settings["Use Calipers"] == "No" and settings["Use Loresinging"] == "No"
       and not vars["Start With Copper"] then
        vars["Always Use Vaalin"] = true
    end
    if Stats.prof ~= "Rogue" and Stats.prof ~= "Bard"
       and not vars["Start With Copper"] then
        vars["Always Use Vaalin"] = true
    end
end

---------------------------------------------------------------------------
-- main_program — Top-level control flow.
-- Ported from tpick.lic lines 5908-6167
---------------------------------------------------------------------------
local function main_program()
    -- Profession-specific setup
    setup_profession()

    -- Profession reset check (lines 527-567)
    local reset_prof
    settings, reset_prof = settings_mod.check_profession_reset(settings)
    if reset_prof then
        if reset_prof == "Spells" then
            util.tpick_silent(true,
                "It looks like you unlearned some spells. Some or all of your spell settings "
                .. "have been set to their default settings. You will need to restart the script. "
                .. "You shouldn't see this error message again unless you unlearn spells again.",
                settings)
        else
            util.tpick_silent(true,
                "It looks like you changed your profession from " .. reset_prof .. " to "
                .. Stats.prof .. ". All of your " .. reset_prof .. " only settings have been "
                .. "set to their default settings. You will need to restart the script. "
                .. "You shouldn't see this error message again unless you change your profession again.",
                settings)
        end
        return
    end

    -- Show settings GUI if setup requested (lines 5954-5961)
    local early_cmd = parse_args()
    if early_cmd == "setup" then
        gui_settings.show(settings, function(new_settings)
            settings = new_settings
            settings_mod.save(settings)
        end)
        return
    elseif early_cmd == "help" then
        show_help()
        return
    elseif early_cmd == "version" then
        show_version()
        return
    end

    -- Calculate skills after args parsed (needs vars populated)
    calculate_skills()

    -- Validate incompatible options
    if not validate_options() then return end

    -- Register cleanup hook
    register_cleanup()

    -- Show information window (line 5963-5966)
    gui_info.show(vars, settings, stats_data)

    -- Dispatch based on command-line usage vs window mode (lines 6119-6166)
    if vars["Command Lines Used"]
       and (not vars["Window Active"] or settings["One & Done"] == "Yes") then
        start_up_procedure()
    elseif vars["Window Active"] then
        while true do
            if vars["Command Lines Used"] then
                start_up_procedure()
            else
                util.tpick_silent(true,
                    "Waiting for commands. Select the picking mode and any option you "
                    .. "want then click the 'Start' button in the Information Window "
                    .. "to pick some boxes.", settings)
                -- Wait for Start button click from GUI
                wait_until(function() return gui_info.is_running() end)
                local commands = gui_info.get_tpick_commands()
                apply_gui_commands(commands)
                start_up_procedure()
            end

            -- Reset for next loop iteration (lines 6156-6159)
            reset_command_vars()
            gui_info.set_running(false)
        end
    elseif Script.vars and Script.vars[1] then
        -- Has script args but no recognized mode — run startup anyway
        start_up_procedure()
    else
        -- No mode specified — show help
        local text = "You must specify which mode you want when starting this script.\n"
            .. ";tpick solo = Pick all boxes in your open containers.\n"
            .. ";tpick other = Wait for someone to GIVE you a box, you will then pick "
            .. "the box and GIVE it back to the person.\n"
            .. ";tpick ground = Pick all boxes on the ground.\n"
            .. ";tpick worker = Pick boxes at a pool. Only works if you're in a pool room "
            .. "when starting script.\n"
            .. ";tpick setup = Enter setup menu.\n"
            .. ";tpick show - Shows the Information Window which has more features and stats."
        util.tpick_silent(true, text, settings)
    end
end

---------------------------------------------------------------------------
-- Entry point with crash reporting
-- Ported from tpick.lic lines 6169-6179
---------------------------------------------------------------------------
local ok, err = pcall(main_program)
if not ok then
    local report = "The script has crashed. Please provide the following information "
        .. "to Dreaven or Discord for assistance.\n"
        .. "Tpick Version: " .. TPICK_VERSION .. "\n"
        .. "Revenant\n"
        .. "Error: " .. tostring(err) .. "\n"
    vars["Crash Report"] = report
    -- Crash report will be displayed by before_dying handler
end
