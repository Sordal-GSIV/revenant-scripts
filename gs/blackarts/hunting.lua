--- @module blackarts.hunting
-- Hunting coordination. Ported from BlackArts::Hunting (BlackArts.lic v3.12.x)

local state = require("state")
local util  = require("util")

local M = {}

-- Full creature-to-room-id map. Room IDs are sorted nearest-first at runtime.
-- Multiple room IDs = multiple possible hunting areas.
local HUNTING_LOCATIONS = {
    ["arch wight"]          = {2974, 10729},
    ["arctic titan"]        = {2569},
    ["black bear"]          = {4215, 10659},
    ["black forest viper"]  = {9709},
    ["black leopard"]       = {10171},
    ["bone golem"]          = {7782, 10694},
    ["cave lizard"]         = {9567, 29058},
    ["cave troll"]          = {5129},
    ["centaur"]             = {5323, 5995},
    ["cougar"]              = {5323},
    ["crested basilisk"]    = {5496, 9939},
    ["cyclops"]             = {5368},
    ["dark shambler"]       = {8443, 10729},
    ["dreadnought raptor"]  = {4714},
    ["fenghai"]             = {5251},
    ["fire cat"]            = {6385},
    ["fire rat"]            = {6385},
    ["fire sprite"]         = {2230},
    ["frost giant"]         = {2569},
    ["forest troll"]        = {5213},
    ["ghoul master"]        = {7184, 10729},
    ["giant hawk-owl"]      = {1649},
    ["great boar"]          = {4215, 5148, 6060},
    ["greater faeroth"]     = {4903},
    ["greater ghoul"]       = {5207, 5835},
    ["greater kappa"]       = {7615},
    ["greater moor wight"]  = {10008},
    ["greater spider"]      = {5129},
    ["hill troll"]          = {4251},
    ["hunter troll"]        = {1635},
    ["ice troll"]           = {2569},
    ["kiramon defender"]    = {4969},
    ["kobold"]              = {5055, 10271},
    ["lesser faeroth"]      = {4903},
    ["lesser ghoul"]        = {7173, 5835},
    ["lesser moor wight"]   = {11639, 10008},
    ["lesser mummy"]        = {4144},
    ["lesser vruul"]        = {19261},
    ["mammoth arachnid"]    = {8326},
    ["mastodonic leopard"]  = {4714},
    ["mist wraith"]         = {9344, 5835},
    ["mountain goat"]       = {1617},
    ["mountain lion"]       = {3566},
    ["mountain ogre"]       = {8045},
    ["mountain troll"]      = {6510},
    ["myklian"]             = {7478},
    ["Neartofar orc"]       = {10622},
    ["nightmare steed"]     = {7332},
    ["night mare"]          = {7332},
    ["ogre warrior"]        = {6799, 10660},
    ["phosphorescent worm"] = {9204},
    ["plains lion"]         = {10171},
    ["plains orc warrior"]  = {4990},
    ["plumed cockatrice"]   = {10622},
    ["red bear"]            = {3563},
    ["ridgeback boar"]      = {4612},
    ["roa'ter"]             = {13988},
    ["sea nymph"]           = {487},
    ["scaly burgee"]        = {1633},
    ["shadow mare"]         = {7332},
    ["shadow steed"]        = {7332},
    ["shelfae chieftain"]   = {7659},
    ["skeletal giant"]      = {8450},
    ["skeleton"]            = {7173, 5835},
    ["snowy cockatrice"]    = {3207},
    ["storm giant"]         = {8450},
    ["storm griffin"]       = {3980},
    ["striped warcat"]      = {6385},
    ["tawny brindlecat"]    = {4612},
    ["three-toed tegu"]     = {1633},
    ["tree viper"]          = {1220},
    ["troll chieftain"]     = {11403},
    ["tusked ursian"]       = {4738},
    ["vesperti"]            = {5297},
    ["war troll"]           = {4251},
    ["wraith"]              = {6889},
}

--------------------------------------------------------------------------------
-- Return the nearest accessible hunting room for a creature type
--------------------------------------------------------------------------------

function M.hunting_areas(npc)
    util.msg("debug", "Hunting.hunting_areas: npc = " .. tostring(npc))

    -- Normalise compound creature names
    if npc:find("centaur") then npc = "centaur" end
    if npc:find("tree viper") then npc = "tree viper" end

    local location_list = HUNTING_LOCATIONS[npc]
    if not location_list then
        util.msg("yellow", "The look-up for '" .. tostring(npc) .. "' is not in the hunting list.")
        util.msg("yellow", "Please report this to elanthia-online in the Discord scripting channel.")
        error("creature not in hunting list: " .. tostring(npc))
    end

    -- Filter out rooms that require crossing a boundary
    local filtered = {}
    for _, room_id in ipairs(location_list) do
        local cost = Map.path_cost(Room.id, room_id)
        local crosses_boundary = false
        if cost then
            -- We use Map.path_cost as a proxy for accessibility.
            -- Rooms behind boundaries (mine carts etc.) are very expensive or nil.
            for _, fence in ipairs(state.boundaries) do
                -- A more precise check would inspect the actual path, but Revenant
                -- does not expose the intermediate nodes. We approximate by checking
                -- direct room membership in boundary list as destination.
                if room_id == fence then
                    crosses_boundary = true
                    break
                end
            end
        else
            crosses_boundary = true  -- unreachable
        end
        if not crosses_boundary then
            filtered[#filtered + 1] = room_id
        end
    end

    return filtered[1]  -- nearest accessible room
end

--------------------------------------------------------------------------------
-- Set BigShot bounty_eval for skin/creature collection goal
--------------------------------------------------------------------------------

function M.set_eval()
    local skin        = state.skin or ""
    local skin_number = state.skin_number or 0
    local eval = string.format(
        "local c=0; for _,sack in ipairs(GameObj.inv()) do if sack.contents then" ..
        " for _,i in ipairs(sack.contents) do" ..
        "  if i.name and i.name:find('%s') then c=c+1 end" ..
        " end end end return c >= %d",
        skin, skin_number
    )
    UserVars.op = UserVars.op or {}
    UserVars.op["bounty_eval"] = eval
    util.msg("debug", "Hunting.set_eval: bounty_eval = " .. eval)
    sleep(0.2)
end

--------------------------------------------------------------------------------
-- Run pre-hunt setup commands / scripts
--------------------------------------------------------------------------------

function M.pre_hunt(cfg)
    if not cfg then return end

    -- Prep commands (comma-separated, "script NAME ARGS" or raw game commands)
    if cfg.forage_prep_commands and cfg.forage_prep_commands ~= "" then
        for cmd in (cfg.forage_prep_commands .. ","):gmatch("([^,]+),") do
            cmd = cmd:match("^%s*(.-)%s*$")
            local script_name, script_args = cmd:match("^script%s+(%S+)%s*(.*)")
            if script_name then
                local args = (script_args ~= "") and util.split(script_args, " ") or nil
                Script.run(script_name, args)
            else
                fput(cmd)
                sleep(0.3)
            end
        end
    end

    -- Prep scripts (comma-separated script names with optional args)
    if cfg.forage_prep_scripts and cfg.forage_prep_scripts ~= "" then
        for entry in (cfg.forage_prep_scripts .. ","):gmatch("([^,]+),") do
            local tokens = util.split(entry, " ")
            if #tokens > 1 then
                local args = {}
                for i = 2, #tokens do args[#args+1] = tokens[i] end
                Script.run(tokens[1], args)
            else
                Script.run(tokens[1])
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Post-hunt cleanup — kill prep scripts, run post commands/scripts
--------------------------------------------------------------------------------

function M.post_hunt(cfg)
    if not cfg then return end

    -- Kill prep scripts that are still running
    if cfg.forage_prep_scripts and cfg.forage_prep_scripts ~= "" then
        for entry in (cfg.forage_prep_scripts .. ","):gmatch("([^,]+),") do
            local name = util.split(entry, " ")[1]
            if Script.running(name) then Script.kill(name) end
        end
    end

    -- Post commands
    if cfg.forage_post_commands and cfg.forage_post_commands ~= "" then
        for cmd in (cfg.forage_post_commands .. ","):gmatch("([^,]+),") do
            cmd = cmd:match("^%s*(.-)%s*$")
            local script_name, script_args = cmd:match("^script%s+(%S+)%s*(.*)")
            if script_name then
                local args = (script_args ~= "") and util.split(script_args, " ") or nil
                Script.run(script_name, args)
            else
                fput(cmd)
                sleep(0.3)
            end
        end
    end

    -- Post scripts
    if cfg.forage_post_scripts and cfg.forage_post_scripts ~= "" then
        for entry in (cfg.forage_post_scripts .. ","):gmatch("([^,]+),") do
            local tokens = util.split(entry, " ")
            if #tokens > 1 then
                local args = {}
                for i = 2, #tokens do args[#args+1] = tokens[i] end
                Script.run(tokens[1], args)
            else
                Script.run(tokens[1])
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Go hunting via BigShot bounty mode
--------------------------------------------------------------------------------

function M.go_hunting(cfg)
    local original_targets      = UserVars.op and UserVars.op["targets"]      or ""
    local original_fried        = UserVars.op and UserVars.op["fried"]        or ""
    local original_rest         = UserVars.op and UserVars.op["rest_till_exp"] or ""
    local original_rest_scripts = UserVars.op and UserVars.op["resting_scripts"] or ""

    before_dying(function()
        if Script.running("bigshot") then Script.kill("bigshot") end
        UserVars.op = UserVars.op or {}
        UserVars.op["targets"]          = original_targets
        UserVars.op["bounty_eval"]      = ""
        UserVars.op["fried"]            = original_fried
        UserVars.op["rest_till_exp"]    = original_rest
        UserVars.op["resting_scripts"]  = original_rest_scripts
    end)

    M.set_eval()

    -- Patch resting_scripts to use eloot sell alchemy_mode
    if UserVars.op and UserVars.op["resting_scripts"] then
        local scripts = {}
        for s in (UserVars.op["resting_scripts"] .. ","):gmatch("([^,]+),") do
            s = s:match("^%s*(.-)%s*$")
            if s:find("eloot sell") then
                scripts[#scripts + 1] = "eloot sell alchemy_mode"
            else
                scripts[#scripts + 1] = s
            end
        end
        UserVars.op["resting_scripts"] = table.concat(scripts, ", ")
    end

    UserVars.op = UserVars.op or {}
    UserVars.op["fried"]          = "101"
    UserVars.op["rest_till_exp"]  = "100"

    -- Only hunt the required creature if configured
    if cfg and cfg.only_required_creatures and state.creature then
        UserVars.op["targets"] = state.creature:match("%S+$") or state.creature
    end

    util.mapped_room()

    Script.run("bigshot", {"bounty"})

    -- Final loot pass
    Script.run("eloot")

    -- Restore
    UserVars.op["targets"]          = original_targets
    UserVars.op["bounty_eval"]      = ""
    UserVars.op["fried"]            = original_fried
    UserVars.op["rest_till_exp"]    = original_rest
end

--------------------------------------------------------------------------------
-- Switch BigShot profile to match the required skin
--------------------------------------------------------------------------------

function M.switch_profile(skin, cfg)
    util.msg("debug", "Hunting.switch_profile: skin = " .. tostring(skin))
    skin = skin:gsub("^some ", "")
    local letters = {"a","b","c","d","e","f","g","h","i","j"}

    for _, letter in ipairs(letters) do
        local names_key = "names_" .. letter
        local profile_key = "profile_" .. letter
        local kill_key = "kill_" .. letter
        if cfg[names_key] and cfg[names_key]:lower():find(skin:lower(), 1, true) then
            local profile_file = cfg[profile_key]
            if not profile_file or profile_file == "" then
                util.msg("info", "No BigShot profile file set for profile " .. letter)
                error("missing bigshot profile file")
            end
            -- Load the BigShot YAML profile into UserVars.op
            -- In Revenant, YAML is handled differently; profiles are JSON
            local ok, t = pcall(Json.decode, profile_file)
            if ok and type(t) == "table" then
                UserVars.op = t
            else
                util.msg("info", "Profile " .. letter .. " is not valid JSON; using profile name as-is")
                -- Try to load as a script argument
                UserVars.op = UserVars.op or {}
                UserVars.op["profile"] = profile_file
            end
            state.only_required_creatures = cfg[kill_key] and true or false
            return
        end
    end

    util.msg("info", "No BigShot profile found for '" .. skin .. "' from creature '" ..
             tostring(state.creature) .. "'. Please check the Profiles tab.")
    error("no bigshot profile for skin: " .. skin)
end

return M
