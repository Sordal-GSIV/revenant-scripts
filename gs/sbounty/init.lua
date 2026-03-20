--- @revenant-script
--- name: sbounty
--- version: 1.3.0
--- author: spiffyjr
--- maintainer: Elanthia-Online
--- game: gs
--- tags: bounty
--- description: Smart bounty automation — handles cull, dangerous, forage, skin, search, heirloom, escort, bandits
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: spiffyjr, Elanthia-Online
--- Ported to Revenant Lua from sbounty.lic v1.2
---
--- changelog:
---   1.3.0 (2026-03-19) complete conversion from sbounty.lic v1.2 — full feature parity
---         - full GUI setup via Revenant Gui API (tab_bar, checkboxes, inputs)
---         - all task handlers: cull, dangerous, forage, skin, search, heirloom, escort, bandits
---         - hunter script integration with SessionVars bridge
---         - expedite bounty support
---         - hunting/rest scripts management
---         - wound/mana/spirit/encumbrance rest checks
---         - Song of Peace, Sanctuary, Light casting during search/forage
---         - proper location matching with target/skin/boundary support
---         - provoked (ancient/grizzled) target handling
---         - herb room finding with location filtering and distance sorting
---         - heirloom turn-in with lootsack search
---         - Vaalor guards room tag setup
---   1.2.0 (2025-10-21) initial Lua port (partial)
---
--- Usage:
---   ;sbounty              — run bounty loop
---   ;sbounty setup        — configure locations and settings (GUI)
---   ;sbounty help         — show help
---   ;sbounty forage       — run forage task only
---   ;sbounty bandits      — run bandit task only
---   ;sbounty npc          — talk to NPC only
---   ;sbounty check        — check if current bounty is doable
---   ;sbounty load [target] — load hunter with optional target

local VERSION = "1.3.0"

--------------------------------------------------------------------------------
-- Settings (JSON-encoded in CharSettings)
--------------------------------------------------------------------------------

local SETTINGS_KEY = "__sbounty_settings"

local function load_settings()
    local raw = CharSettings[SETTINGS_KEY]
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function save_settings_to_db(s)
    CharSettings[SETTINGS_KEY] = Json.encode(s)
end

local settings = load_settings()

-- Defaults
settings.hunter                = settings.hunter or "bigshot"
settings.enable_cull           = (settings.enable_cull == nil) and true or settings.enable_cull
settings.enable_dangerous      = (settings.enable_dangerous == nil) and true or settings.enable_dangerous
settings.enable_forage         = (settings.enable_forage == nil) and true or settings.enable_forage
settings.enable_loot           = (settings.enable_loot == nil) and true or settings.enable_loot
settings.enable_rescue         = (settings.enable_rescue == nil) and true or settings.enable_rescue
settings.enable_search         = (settings.enable_search == nil) and true or settings.enable_search
settings.enable_bandit         = (settings.enable_bandit == nil) and false or settings.enable_bandit
settings.enable_skin           = (settings.enable_skin == nil) and true or settings.enable_skin
settings.enable_expedite       = (settings.enable_expedite == nil) and true or settings.enable_expedite
settings.enable_bandit_script  = (settings.enable_bandit_script == nil) and false or settings.enable_bandit_script
settings.enable_hunt_complete  = (settings.enable_hunt_complete == nil) and true or settings.enable_hunt_complete
settings.enable_turn_in_bounty = (settings.enable_turn_in_bounty == nil) and true or settings.enable_turn_in_bounty

settings.hunting_scripts       = settings.hunting_scripts or { "spellactive" }
settings.bandit_script         = settings.bandit_script or "sbounty-bandit-example"
settings.pre_search_commands   = settings.pre_search_commands or { "store all" }
settings.post_search_commands  = settings.post_search_commands or { "gird" }
settings.pre_forage_commands   = settings.pre_forage_commands or { "store all" }
settings.post_forage_commands  = settings.post_forage_commands or { "gird" }
settings.forage_retry_delay    = settings.forage_retry_delay or 300
settings.loot_script           = settings.loot_script or "eloot"
settings.turn_in_percent       = settings.turn_in_percent or 95

settings.should_hunt_mind      = settings.should_hunt_mind or 75
settings.should_hunt_mana      = settings.should_hunt_mana or 0
settings.should_hunt_spirit    = settings.should_hunt_spirit or 7
settings.hunt_pre_commands     = settings.hunt_pre_commands or { "gird" }
settings.hunt_commands_a       = settings.hunt_commands_a or {}
settings.hunt_commands_b       = settings.hunt_commands_b or {}
settings.hunt_commands_c       = settings.hunt_commands_c or {}

settings.should_rest_mind      = settings.should_rest_mind or 100
settings.should_rest_mana      = settings.should_rest_mana or 0
settings.should_rest_encum     = settings.should_rest_encum or 20

settings.rest_room             = settings.rest_room or ""
settings.boundaries            = settings.boundaries or ""
settings.rest_in_commands      = settings.rest_in_commands or { "go table", "sit" }
settings.rest_out_commands     = settings.rest_out_commands or { "stand", "out" }
settings.rest_pre_commands     = settings.rest_pre_commands or { "store all" }
settings.rest_scripts          = settings.rest_scripts or { "waggle" }
settings.rest_sleep_interval   = settings.rest_sleep_interval or 30

settings.locations             = settings.locations or {}

local function save_settings()
    save_settings_to_db(settings)
end

save_settings()

-- Add Vaalor guards tag if missing
pcall(function() Map.add_tag(5827, "advguard2") end)

--------------------------------------------------------------------------------
-- Bounty patterns (regex)
--------------------------------------------------------------------------------

local bounty_patterns = {
    none             = "^You are not currently assigned a task\\.",

    -- help
    help_bandit      = "It appears they have a bandit problem",
    help_creature    = "It appears they have a creature problem",
    help_resident    = "It appears that a local resident urgently needs our help",
    help_heirloom    = "It appears they need your help in tracking down some kind of lost heirloom",
    help_gemdealer   = "The local gem dealer",
    help_herbalist   = "local herbalist|local healer|local alchemist",
    help_furrier     = "The local furrier",

    -- in progress
    task_bandit      = "^You have been tasked to suppress bandit activity (?:in|on|near) (?:the )?(.*?)\\s(?:near|between|under|\\.)",
    task_escort      = "^You have made contact with the child",
    task_dangerous   = "You have been tasked to hunt down and kill a particularly dangerous (.*) that has established a territory (?:in|on|near) (?:the )?(.*)(?:\\s(?:near|between|under)|\\.)\\s+You can",
    task_provoked    = "You have been tasked to hunt down and kill a particularly dangerous (.*) that has established a territory (?:in|on|near) (?:the )?(.*)(?:\\s(?:near|between|under)|\\.)\\s+You have provoked",
    task_dealer      = "^The(?: local)? gem dealer",
    task_forage      = "concoction that requires (?:a|an|some) (.*) found (?:in|on|near) (?:the )?(.*?)(?: near| between| under|\\.).*These samples must be in pristine condition\\.\\s+You have been tasked to retrieve (\\d+) (?:more )?samples?\\.",
    task_cull        = "You have been tasked to(?: help \\w*)?(?: (?:retrieve an heirloom|kill a dangerous creature|rescue a missing child) by)? suppress(?:ing)? (.*) activity (?:in|on) (?:the )?(.*)(?:\\s(?:near|between|under)|\\.)",
    task_search      = "unfortunate citizen lost after being attacked by (?:a|an) (.*?) (?:in|on|near) (?:the )?(.*?)\\s?(?:near|between|under|\\.  The).*SEARCH",
    task_heirloom    = "unfortunate citizen lost after being attacked by (?:a|an) (.*?) (?:in|on|near) (?:the )?(.*?)\\s?(?:near|between|under|\\.  The).*LOOT",
    task_found       = "You have located .* and should bring it back",
    task_skin        = "^You have been tasked to retrieve (\\d+|\\w+)s? (.*) of at least .*\\.  You can SKIN them off the corpse of (?:a|an) (.*) or ",
    task_rescue      = "A local divinist has had visions of the child fleeing from (?:a|an) (.*) (?:in|on) (?:the )?(.*) (?:near|between|under)",

    -- fail
    fail_child       = "The child you were tasked to rescue is gone",

    -- success
    success          = "^You have succeeded in your task and can return",
    success_guard    = "^You succeeded in your task and should report back to",
    success_heirloom = "^You have located (?:a|an|the|some) (.*) and should bring it back .*\\.$",
}

--------------------------------------------------------------------------------
-- State variables
--------------------------------------------------------------------------------

local in_rest_area        = false
local rest_reason         = nil
local hunt_reason         = nil
local can_do_bounty_cache = nil
local expedite_left       = true
local last_forage_attempt = 0
local last_forage_delay   = 300
local first_run           = true
local resting             = false
local hunter_name         = nil  -- actual hunter script name (set by bridge)

-- Body parts for wound checking
local BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nsys"
}

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local function msg(text)
    echo("-- " .. text)
end

local function err(text)
    echo("** " .. text)
    error(text)
end

local function is_bounty(types)
    if type(types) == "string" then types = { types } end
    local task = Bounty.task or ""
    if task == "" then
        -- check "none" pattern
        for _, t in ipairs(types) do
            if t == "none" then return true end
        end
        return false
    end
    local patterns = {}
    for _, t in ipairs(types) do
        local pat = bounty_patterns[t]
        if pat then patterns[#patterns + 1] = pat end
    end
    if #patterns == 0 then return false end
    local combined = table.concat(patterns, "|")
    return Regex.test(combined, task)
end

local function get_bounty_captures(pattern_name)
    local task = Bounty.task or ""
    local pat = bounty_patterns[pattern_name]
    if not pat then return nil end
    local re = Regex.new(pat)
    return re:captures(task)
end

local function check_wounded()
    if bleeding() then return true end
    if percenthealth() <= 50 then return true end
    for _, part in ipairs(BODY_PARTS) do
        if (Wounds[part] or 0) > 1 then return true end
    end
    return false
end

local function do_kneel()
    while not kneeling() do
        waitrt()
        put("kneel")
        pause(0.50)
    end
end

local function do_stand()
    while not standing() do
        waitrt()
        put("stand")
        pause(0.50)
    end
end

local function do_change_stance(stance)
    if Spell.active_p(1617) or Spell.active_p(216) or dead() then return end

    local cur = checkstance()
    while cur ~= stance do
        local res = dothistimeout("stance " .. stance, 2,
            "You are now", "Roundtime", "Wait", "wait", "Your rage causes you")
        if not res then break end
        if res:find("Roundtime: (%d+)") or res:find("wait (%d+)") then
            local d = tonumber(res:match("(%d+)")) or 1
            if d > 1 then pause(d - 1) end
        elseif res:find("Your rage causes you") then
            -- Frenzy active
            break
        end
        cur = checkstance()
        if cur == "guarded" and stance == "defensive" then break end
    end
end

local function clean_skin(name)
    return name:lower():gsub("%s+$", ""):gsub("^%s+", "")
        :gsub("s$", "")
        :gsub("teeth", "tooth")
        :gsub("hooves?", "hoof")
end

local function clean_targets(targets)
    if not targets then return {} end
    local result = {}
    for _, t in ipairs(targets) do
        result[#result + 1] = t:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    end
    return result
end

local function empty_hands()
    local saved = {}
    local rh = GameObj.right_hand()
    if rh then saved.right = rh.id; fput("stow right") end
    if GameObj.right_hand() then fput("store right") end
    local lh = GameObj.left_hand()
    if lh then saved.left = lh.id; fput("stow left") end
    if GameObj.left_hand() then fput("store left") end
    return saved
end

local function fill_hands(saved)
    if not saved then return end
    if saved.left then fput("get #" .. saved.left) end
    if saved.right then fput("get #" .. saved.right) end
end

local function find_lootsack()
    local sack_name = UserVars.lootsack
    if not sack_name or sack_name == "" then return nil end
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item.noun:find(sack_name) or item.name:find(sack_name) then
            return item
        end
    end
    return nil
end

local function find_skinsack()
    local sack_name = UserVars.skinsack
    if not sack_name or sack_name == "" then return nil end
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        if item.noun:find(sack_name) or item.name:find(sack_name) then
            return item
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

local function go2(room)
    if not room or room == "" then return end
    local current = Map.current_room()
    if current and tostring(current) == tostring(room) then return end

    -- Exit rest area table if needed
    if checkarea() and checkarea():find("Table") then
        if tostring(room) == tostring(settings.rest_room) then return end
        do_stand()
        move("out")
    end

    -- Use go2 script for navigation
    if Script.running("go2") then
        wait_while(function() return Script.running("go2") end)
    end
    Script.run("go2", tostring(room))
    wait_while(function() return Script.running("go2") end)
end

local function go2_nearest_tag(tag)
    if checkarea() and checkarea():find("Table") then
        do_stand()
        fput("out")
    end

    -- Find nearest room with tag from rest room context
    local tag_rooms = Map.tags(tag) or {}
    if #tag_rooms == 0 then
        err("failed to find room by tag: " .. tag)
        return
    end

    local rest_id = tonumber(settings.rest_room)
    if rest_id and rest_id > 0 then
        local nearest = Map.find_nearest_room(rest_id, tag_rooms)
        if nearest then
            -- Navigate via nearest room found relative to rest
            -- But we still nav from current position
            go2(nearest.id)
            return
        end
    end

    -- Fallback: find nearest from current room
    local result = Map.find_nearest_by_tag(tag)
    if result then
        go2(result.id)
    else
        err("failed to find nearest room by tag: " .. tag)
    end
end

local function go2_nearest(room_list)
    local rest_id = tonumber(settings.rest_room)
    local from = rest_id and rest_id > 0 and rest_id or Map.current_room()
    if not from then err("failed to find current room"); return end

    local nearest = Map.find_nearest_room(from, room_list)
    if not nearest then
        err("failed to find nearest room")
        return
    end
    go2(nearest.id)
end

--------------------------------------------------------------------------------
-- Wander (with boundary support)
--------------------------------------------------------------------------------

local sbounty_wander_rooms = {}

local function wander(boundaries)
    local bound_set = {}
    if type(boundaries) == "table" then
        for _, b in ipairs(boundaries) do bound_set[tostring(b)] = true end
    elseif type(boundaries) == "string" and boundaries ~= "" then
        for b in boundaries:gmatch("[^,]+") do
            bound_set[b:gsub("^%s+", ""):gsub("%s+$", "")] = true
        end
    end

    local room = Room.current()
    if not room or not room.wayto then return false end

    local next_room_options = {}
    for dest, cmd in pairs(room.wayto) do
        if not bound_set[tostring(dest)] then
            next_room_options[#next_room_options + 1] = { dest = dest, cmd = cmd }
        end
    end

    -- Prefer unvisited rooms
    local unvisited = {}
    for _, opt in ipairs(next_room_options) do
        local found = false
        for _, wr in ipairs(sbounty_wander_rooms) do
            if tostring(wr) == tostring(opt.dest) then found = true; break end
        end
        if not found then unvisited[#unvisited + 1] = opt end
    end

    local choices = #unvisited > 0 and unvisited or next_room_options
    if #choices == 0 then return false end

    local choice = choices[math.random(#choices)]

    -- Track visited rooms
    for i, wr in ipairs(sbounty_wander_rooms) do
        if tostring(wr) == tostring(choice.dest) then
            table.remove(sbounty_wander_rooms, i)
            break
        end
    end
    sbounty_wander_rooms[#sbounty_wander_rooms + 1] = choice.dest

    if type(choice.cmd) == "string" then
        move(choice.cmd)
    elseif type(choice.cmd) == "function" then
        pcall(choice.cmd)
    end
    return true
end

--------------------------------------------------------------------------------
-- Command runners
--------------------------------------------------------------------------------

local function run_commands(commands)
    if not commands or #commands == 0 then return end
    for _, command in ipairs(commands) do
        if command:sub(1, 1) == ";" then
            local script_name = command:sub(2)
            Script.run(script_name)
            wait_while(function() return Script.running(script_name) end)
        else
            fput(command)
        end
    end
end

local function run_scripts(scripts)
    if not scripts then return end
    for _, s in ipairs(scripts) do
        local parts = {}
        for word in s:gmatch("%S+") do parts[#parts + 1] = word end
        local name = table.remove(parts, 1)
        if name then
            Script.run(name, table.concat(parts, " "))
            wait_while(function() return Script.running(name) end)
        end
    end
end

local function run_loot_script()
    local ls = settings.loot_script
    if Script.running(ls) then
        wait_while(function() return Script.running(ls) end)
    end
    Script.run(ls)
    wait_while(function() return Script.running(ls) end)
end

--------------------------------------------------------------------------------
-- Hunting scripts management
--------------------------------------------------------------------------------

local function start_hunting_scripts()
    for _, script_name in ipairs(settings.hunting_scripts or {}) do
        if not Script.running(script_name) then
            Script.run(script_name)
        end
    end
end

local function kill_hunting_scripts()
    for _, script_name in ipairs(settings.hunting_scripts or {}) do
        if Script.running(script_name) then
            pcall(Script.kill, script_name)
        end
    end
end

local function hunt_prepare()
    run_commands(settings.hunt_pre_commands)
end

--------------------------------------------------------------------------------
-- Rest functions
--------------------------------------------------------------------------------

local function rest_goto()
    if in_rest_area then return end
    if settings.rest_room and settings.rest_room ~= "" then
        go2(settings.rest_room)
    end
end

local function rest_exit()
    if not in_rest_area then return end
    -- Run out-commands only when NOT at rest room and no direct path back
    -- (i.e. we're inside a sub-room like an inn table)
    local current = Map.current_room()
    local rest_id = tonumber(settings.rest_room)
    if current and rest_id and current ~= rest_id then
        local path = Room.path_to(rest_id)
        if not path then
            run_commands(settings.rest_out_commands)
        end
    end
    in_rest_area = false
end

local function rest_enter()
    if in_rest_area then return end
    -- Run in-commands only when NOT at rest room and no direct path to rest
    -- (i.e. we need to enter a sub-room like an inn table)
    local current = Map.current_room()
    local rest_id = tonumber(settings.rest_room)
    if current and rest_id and current ~= rest_id then
        local path = Room.path_to(rest_id)
        if not path then
            run_commands(settings.rest_in_commands)
        end
    else
        run_commands(settings.rest_in_commands)
    end
    in_rest_area = true
end

local function rest_run_scripts()
    rest_exit()
    run_scripts(settings.rest_scripts)
end

--------------------------------------------------------------------------------
-- Location matching
--------------------------------------------------------------------------------

local function get_bounty_location(location_override, target_override)
    local bounty = Bounty.task or ""
    local locations = {}
    for k, v in pairs(settings.locations) do locations[k] = v end

    local target = target_override
    local location = location_override

    if location == nil then
        -- Remove search-only locations for hunting bounties
        if is_bounty({ "task_skin", "task_heirloom", "task_dangerous", "task_cull", "task_rescue" }) then
            for name, data in pairs(locations) do
                if data.enable_search_only then locations[name] = nil end
            end
        end

        -- Try skin matching first
        local skin_caps = get_bounty_captures("task_skin")
        if skin_caps then
            target = (skin_caps[3] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local skin = clean_skin(skin_caps[2] or "")

            for loc_name, data in pairs(locations) do
                local cleaned = clean_targets(data.targets)
                local target_found = false
                for _, t in ipairs(cleaned) do
                    if Regex.test(t, target) then target_found = true; break end
                end
                if target_found and data.skins then
                    for _, s in ipairs(data.skins) do
                        if Regex.test(s:lower():gsub("^%s+", ""):gsub("%s+$", ""), skin) then
                            location = { loc_name, data }
                            break
                        end
                    end
                end
                if location then break end
            end
        else
            -- Generic pattern matching for other bounties
            for _, pat_name in ipairs({
                "task_dangerous", "task_provoked", "task_cull",
                "task_search", "task_heirloom", "task_rescue"
            }) do
                local caps = get_bounty_captures(pat_name)
                if caps then
                    target = (caps[1] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
                    local loc_text = (caps[2] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

                    for loc_name, data in pairs(locations) do
                        local cleaned = clean_targets(data.targets)
                        local loc_match = data.location and Regex.test(data.location:lower():gsub("^%s+", ""):gsub("%s+$", ""), loc_text)
                        if loc_match then
                            for _, t in ipairs(cleaned) do
                                if Regex.test(t, target) then
                                    location = { loc_name, data }
                                    break
                                end
                            end
                        end
                        if location then break end
                    end
                    if location then break end
                end
            end
        end
    end

    if not location then
        msg("could not find bounty location")
        return nil
    end

    local name = location[1]
    local data = {}
    for k, v in pairs(location[2]) do data[k] = v end

    -- Handle provoked targets (ancient/grizzled variants)
    if target and data.targets then
        local targets = {}
        for _, t in ipairs(data.targets) do targets[#targets + 1] = t end
        local cleaned = clean_targets(data.targets)

        if is_bounty({ "task_provoked" }) then
            local target_key = nil
            for i, t in ipairs(cleaned) do
                if t:find("ancient") or t:find("grizzled") then
                    if Regex.test(t, "ancient " .. target) or Regex.test(t, "grizzled " .. target) then
                        target_key = i
                        break
                    end
                end
            end
            if not target_key then
                for i, t in ipairs(cleaned) do
                    if Regex.test(t, target) then
                        target_key = i
                        break
                    end
                end
            end
            if target_key then
                local orig = targets[target_key]
                if not orig:find("ancient") and not orig:find("grizzled") then
                    targets[target_key] = "(?:ancient|grizzled).*" .. cleaned[target_key]
                end
            end
        end

        if data.enable_bounty_only and target then
            -- Only attack bounty creature
            local found_target = nil
            for i, t in ipairs(cleaned) do
                if Regex.test(t, target) then
                    found_target = targets[i]
                    break
                end
            end
            if found_target then
                targets = { found_target }
            end
        end

        data.targets = targets
    end

    return { name, data }
end

local function get_herb_rooms(location, herb)
    local target_list = {}
    local names = { herb }

    -- Handle ayana variants
    if herb == "ayana leaf" then
        names = { herb, "ayana leaf", "ayana lichen", "ayana weed", "ayana berry", "ayana root" }
    elseif herb == "ayana'al leaf" then
        names = { herb, "ayana'al leaf", "ayana'al lichen", "ayana'al weed", "ayana'al berry", "ayana'al root" }
    end

    -- Find rooms with matching tags
    for _, name in ipairs(names) do
        local rooms = Map.tags(name) or {}
        for _, rid in ipairs(rooms) do
            local found = false
            for _, existing in ipairs(target_list) do
                if existing == rid then found = true; break end
            end
            if not found then target_list[#target_list + 1] = rid end
        end
    end

    -- Filter by location
    if location and location ~= "" then
        local filtered = {}
        for _, room_id in ipairs(target_list) do
            local room_data = Map.find_room(room_id)
            if room_data then
                local room_loc = room_data.location
                local room_title = room_data.title or ""
                if room_loc and Regex.test(location, room_loc) then
                    filtered[#filtered + 1] = room_id
                elseif not room_loc and Regex.test(location, room_title) then
                    filtered[#filtered + 1] = room_id
                end
            end
        end
        target_list = filtered
    end

    -- If nothing found, try similar tags
    if #target_list == 0 then
        local all_tags = Map.all_tags() or {}
        local similar = {}
        for _, tag in ipairs(all_tags) do
            if Regex.test(herb, tag) then similar[#similar + 1] = tag end
        end
        if #similar > 0 then
            for _, tag in ipairs(similar) do
                local rooms = Map.tags(tag) or {}
                for _, rid in ipairs(rooms) do
                    target_list[#target_list + 1] = rid
                end
            end
            -- Re-filter by location
            if location and location ~= "" then
                local filtered = {}
                for _, room_id in ipairs(target_list) do
                    local room_data = Map.find_room(room_id)
                    if room_data then
                        local room_loc = room_data.location
                        if room_loc and Regex.test(location, room_loc) then
                            filtered[#filtered + 1] = room_id
                        end
                    end
                end
                target_list = filtered
            end
        end
    end

    -- Filter by distance from rest room (max 600 steps)
    local rest_id = tonumber(settings.rest_room)
    if rest_id and rest_id > 0 then
        local reachable = {}
        for _, room_id in ipairs(target_list) do
            local cost = Map.path_cost(rest_id, room_id)
            if cost and cost <= 600 then
                reachable[#reachable + 1] = { id = room_id, dist = cost }
            end
        end
        -- Sort by distance
        table.sort(reachable, function(a, b) return a.dist < b.dist end)
        target_list = {}
        for _, r in ipairs(reachable) do target_list[#target_list + 1] = r.id end
    end

    return target_list
end

local function get_random_location()
    local keys = {}
    for name, data in pairs(settings.locations) do
        if data.enable_hunting_rotation then
            keys[#keys + 1] = name
        end
    end
    if #keys == 0 then
        err("failed to find a hunting area")
        return nil
    end
    local name = keys[math.random(#keys)]
    return { name, settings.locations[name] }
end

local function has_skins()
    local caps = get_bounty_captures("task_skin")
    if not caps then return false end

    local count = tonumber(caps[1]) or 0
    local skin = (caps[2] or ""):lower()

    local skinsack = find_skinsack()
    if not skinsack or not skinsack.contents then return false end

    local skin_clean = clean_skin(skin)
    local found = 0
    for _, item in ipairs(skinsack.contents) do
        if Regex.test(skin_clean, item.name:lower()) then
            found = found + 1
        end
    end

    return found >= (count + 3)
end

--------------------------------------------------------------------------------
-- Decision functions
--------------------------------------------------------------------------------

local function can_turn_in()
    if not is_bounty({ "success", "success_guard", "success_heirloom" }) then return false end

    if settings.turn_in_percent == nil then return true end
    if settings.enable_turn_in_bounty and not Spell.active_p(9998) then return true end -- Next Bounty spell
    if percentmind() >= (tonumber(settings.turn_in_percent) or 95) and checkmind() ~= "saturated" then
        return true
    end
    return false
end

local function can_do_bounty()
    if can_do_bounty_cache ~= nil then return can_do_bounty_cache end

    if is_bounty({ "success", "success_heirloom", "success_guard" }) then
        can_do_bounty_cache = true
    elseif is_bounty({ "task_bandit" }) and settings.enable_bandit
        and not Regex.test("Locksmehr Trail", Bounty.task or "") then
        can_do_bounty_cache = true
    elseif (is_bounty({ "task_search" }) and settings.enable_search and get_bounty_location() ~= nil)
        or (is_bounty({ "task_heirloom" }) and settings.enable_loot and get_bounty_location() ~= nil) then
        can_do_bounty_cache = true
    elseif is_bounty({ "task_forage" }) and settings.enable_forage then
        local caps = get_bounty_captures("task_forage")
        if caps then
            local herb = caps[1] or ""
            local loc = caps[2] or ""
            local rooms = get_herb_rooms(loc, herb)
            if #rooms > 0 and not Regex.test("green fleshbulb", Bounty.task or "") then
                can_do_bounty_cache = true
            end
        end
        if can_do_bounty_cache == nil then can_do_bounty_cache = false end
    elseif is_bounty({ "task_skin" }) and settings.enable_skin and get_bounty_location() ~= nil then
        can_do_bounty_cache = true
    elseif is_bounty({ "task_provoked", "task_dangerous" }) and settings.enable_dangerous and get_bounty_location() ~= nil then
        can_do_bounty_cache = true
    elseif is_bounty({ "task_cull" }) and settings.enable_cull and get_bounty_location() ~= nil then
        can_do_bounty_cache = true
    elseif (is_bounty({ "task_escort" }) and settings.enable_rescue)
        or (is_bounty({ "task_rescue" }) and settings.enable_rescue and get_bounty_location() ~= nil) then
        can_do_bounty_cache = true
    else
        can_do_bounty_cache = false
    end

    -- Expose to hunter scripts via SessionVars
    SessionVars.sbounty_can_do_bounty = can_do_bounty_cache

    return can_do_bounty_cache
end

local function should_hunt()
    if is_bounty({ "success", "success_heirloom", "success_guard" }) and not can_turn_in() then
        return true
    end
    if can_do_bounty() and not checkfried() and not checksaturated() and first_run then
        return true
    end
    if (not can_do_bounty() or is_bounty({ "success", "success_heirloom", "success_guard" }) or not settings.enable_hunt_complete)
        and percentmind() > (tonumber(settings.should_hunt_mind) or 75) then
        hunt_reason = "mind not clear enough"
        return false
    end
    if not checkmana(tonumber(settings.should_hunt_mana) or 0) then
        hunt_reason = "out of mana"
        return false
    end
    if not checkspirit(tonumber(settings.should_hunt_spirit) or 7) then
        hunt_reason = "low spirit"
        return false
    end
    return true
end

local function should_rest()
    if check_wounded() then
        rest_reason = "wounded"
        return true
    end
    -- Check inter-script rest signal (hunter can set SessionVars.sbounty_rest = true)
    if SessionVars.sbounty_rest then
        rest_reason = SessionVars.sbounty_rest_reason or "sbounty_rest was set"
        if SessionVars.sbounty_rest_until then
            if os.time() > SessionVars.sbounty_rest_until then
                SessionVars.sbounty_rest = nil
                SessionVars.sbounty_rest_reason = nil
                SessionVars.sbounty_rest_until = nil
            end
        else
            SessionVars.sbounty_rest = nil
            SessionVars.sbounty_rest_reason = nil
        end
        return true
    end
    if not checkmana(tonumber(settings.should_rest_mana) or 0) then
        rest_reason = "out of mana"
        return true
    end
    if checkencumbrance(tonumber(settings.should_rest_encum) or 20) then
        rest_reason = "encumbered"
        return true
    end
    if is_bounty({ "task_provoked" }) then
        return false
    end
    if is_bounty({ "task_forage" }) and can_do_bounty()
        and os.time() < last_forage_attempt + last_forage_delay
        and percentmind() >= (tonumber(settings.should_rest_mind) or 100) then
        rest_reason = "mind is full (waiting on foraging cooldown)"
        return true
    end
    if ((not can_turn_in() and is_bounty({ "success", "success_guard", "success_heirloom" }))
        or not can_do_bounty() or not settings.enable_hunt_complete)
        and percentmind() >= (tonumber(settings.should_rest_mind) or 100) then
        rest_reason = "mind is full"
        return true
    end
    rest_reason = nil
    return false
end

--------------------------------------------------------------------------------
-- NPC interaction
--------------------------------------------------------------------------------

local function get_guard_npc()
    local current = Map.current_room()
    if current == 10915 then return "purser" end

    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        if Regex.test("guard|sergeant|guardsman|purser|Belle", npc.name) then
            return npc
        end
    end
    return nil
end

local function find_guard()
    go2_nearest_tag("advguard")
    local npc = get_guard_npc()

    if not npc then
        go2_nearest_tag("advguard2")
        npc = get_guard_npc()
    end

    if not npc then
        err("failed to locate guard")
    end

    return npc
end

local function ask_npc(npc, topic, timeout)
    timeout = timeout or 5
    if type(npc) == "string" then
        return dothistimeout("ask " .. npc .. " about " .. topic, timeout,
            "Yes, I do have", "Yes, we do have", "Ah, so you have",
            "want to be removed", "have removed you", "done with that",
            "bounty points", "creature problem", "local gem dealer",
            "local furrier", "lost heirloom", "local healer", "local herbalist",
            "local alchemist", "local resident", "bandit problem",
            "I'm kind of busy", "don't seem to have any", "Come back in about",
            "I'll expedite", "You don't seem", "I still need",
            "interested in purchasing", "recently received an order",
            "Trying to sneak")
    else
        return dothistimeout("ask #" .. npc.id .. " about " .. topic, timeout,
            "Yes, I do have", "Yes, we do have", "Ah, so you have",
            "want to be removed", "have removed you", "done with that",
            "bounty points", "creature problem", "local gem dealer",
            "local furrier", "lost heirloom", "local healer", "local herbalist",
            "local alchemist", "local resident", "bandit problem",
            "I'm kind of busy", "don't seem to have any", "Come back in about",
            "I'll expedite", "You don't seem", "I still need",
            "interested in purchasing", "recently received an order",
            "Trying to sneak")
    end
end

local function talk_to_guard()
    local npc = find_guard()
    if not npc then return end

    local res = dothistimeout(
        type(npc) == "string" and ("ask " .. npc .. " about bounty") or ("ask " .. npc.noun .. " about bounty"),
        5, "Yes, we do have a task for you", "Ah, so you have returned")
    if not res then
        msg("unknown response from guard")
    end
end

local function talk_to_herbalist()
    go2_nearest({ 3824, 1851, 10396, 640, 5722, 2406, 11002, 9505 })

    local npc
    local current = Map.current_room()
    if current == 10396 then
        npc = "maraene"
    else
        local npcs = GameObj.npcs()
        for _, n in ipairs(npcs) do
            if Regex.test("brother Barnstel|scarred Agarnil kris|healer|herbalist|merchant Kelph|famed baker Leaftoe|Akrash|old Mistress Lomara", n.name) then
                npc = n
                break
            end
        end
    end

    if not npc then msg("could not find herbalist NPC"); return end

    if is_bounty({ "help_herbalist" }) then
        local res = dothistimeout(
            type(npc) == "string" and ("ask " .. npc .. " about bounty") or ("ask " .. npc.noun .. " about bounty"),
            5, "Yes, I do have a task for you")
        if res then
            local caps = Regex.new("recently received an order for (\\d+) (.*?)\\."):captures(res)
            if caps then
                msg("received bounty from herbalist [" .. caps[1] .. " " .. caps[2] .. "]")
            end
        end
    elseif is_bounty({ "task_forage" }) then
        -- Turn in herbs
        local forage_caps = get_bounty_captures("task_forage")
        if not forage_caps then err("no forage bounty data"); return end

        local herb_name = (forage_caps[1] or ""):gsub("s?$", "")
        local lootsack = find_lootsack()
        if not lootsack then err("no herbs to turn in, why are you here?"); return end

        -- Open lootsack if needed to see contents
        if not lootsack.contents then
            local open_result = dothistimeout("open #" .. lootsack.id, 5, "You open", "That is already open")
            if not open_result or not open_result:find("open") then
                dothistimeout("look in #" .. lootsack.id, 5, "In .* you see")
            end
        end

        local herbs = {}
        if lootsack.contents then
            for _, item in ipairs(lootsack.contents) do
                if Regex.test(herb_name, item.name) then
                    herbs[#herbs + 1] = item
                end
            end
        end

        if #herbs == 0 then err("no herbs to turn in, why are you here?"); return end

        -- Stow right hand if occupied
        local prev_item = nil
        local rh = GameObj.right_hand()
        if rh then
            prev_item = rh
            fput("stow right")
            if GameObj.right_hand() then fput("store right") end
        end

        for _, herb in ipairs(herbs) do
            fput("get #" .. herb.id .. " from #" .. lootsack.id)
            local npc_target = type(npc) == "string" and npc or npc.noun
            local result = dothistimeout("give #" .. herb.id .. " to " .. npc_target, 3,
                "This looks perfect", "That looks like it has been partially used up")
            if not result or not result:find("perfect") then
                fput("drop #" .. herb.id)
            end
        end

        if prev_item then
            fput("get #" .. prev_item.id)
        end
    end
end

local function talk_to_gemdealer()
    go2_nearest_tag("gemshop")

    local npc
    local current = Map.current_room()
    if current == 10327 then
        npc = "areacne"
    else
        local npcs = GameObj.npcs()
        for _, n in ipairs(npcs) do
            if Regex.test("dwarven clerk|gem dealer|jeweler|Zirconia", n.name) then
                npc = n
                break
            end
        end
    end

    if not npc then msg("could not find gem dealer NPC"); return end

    local npc_target = type(npc) == "string" and npc or npc.noun
    local res = dothistimeout("ask " .. npc_target .. " about bounty", 5,
        "Yes, I do have a task for you")
    if res then
        local caps = Regex.new("interested in purchasing an? (.*?)\\. .* go round up (\\d+) of them"):captures(res)
        if caps then
            msg("received bounty from gem dealer [" .. caps[2] .. " " .. caps[1] .. "]")
        end
    end
end

local function talk_to_furrier()
    go2_nearest_tag("furrier")

    local npc
    local current = Map.current_room()
    if current == 10327 then
        npc = "areacne"
    else
        local npcs = GameObj.npcs()
        for _, n in ipairs(npcs) do
            if Regex.test("dwarven clerk|furrier", n.name) then
                npc = n
                break
            end
        end
    end

    if not npc then msg("could not find furrier NPC"); return end

    local npc_target = type(npc) == "string" and npc or npc.noun
    local res = dothistimeout("ask " .. npc_target .. " about bounty", 5,
        "Yes, I do have a task for you")
    if res then
        local caps = Regex.new("recently received an order for (\\d+) (.*?)\\."):captures(res)
        if caps then
            msg("received bounty from furrier [" .. caps[1] .. " " .. caps[2] .. "]")
        end
    end
end

local function talk_to_npc()
    if is_bounty({ "help_creature", "help_resident", "help_heirloom", "success_guard" }) then
        talk_to_guard()
    elseif is_bounty({ "help_bandit" }) and settings.enable_bandit then
        talk_to_guard()
    elseif is_bounty({ "help_furrier" }) then
        talk_to_furrier()
    elseif is_bounty({ "help_herbalist" }) then
        talk_to_herbalist()
    elseif is_bounty({ "help_gemdealer" }) then
        talk_to_gemdealer()
    end
end

--------------------------------------------------------------------------------
-- Bounty management
--------------------------------------------------------------------------------

-- Forward declaration for circular reference (get_bounty calls remove_bounty)
local remove_bounty

local function get_bounty()
    rest_exit()
    go2_nearest_tag("advguild")

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if Regex.test("taskmaster", npc.name) then taskmaster = npc; break end
    end

    if not taskmaster then err("failed to find taskmaster"); return end

    local res = dothistimeout("ask #" .. taskmaster.id .. " for bounty", 2,
        "protective escort", "creature problem", "local gem dealer",
        "local furrier", "lost heirloom", "local healer", "local herbalist",
        "local alchemist", "local resident", "bandit problem",
        "I'm kind of busy", "don't seem to have any", "Come back in about")

    if not res then
        err("invalid response from taskmaster")
    elseif res:find("in about (%d+) minute") or res:find("in about a minute") then
        local mins = tonumber(res:match("in about (%d+) minute")) or 1
        msg("Next Bounty cooldown: " .. mins .. " minutes")
        -- Set Next Bounty spell timer so expedite/remove guards work
        -- Spell 9998 = 'Next Bounty' placeholder
        if Spell[9998] then
            pcall(function()
                Spell[9998].active = true
                Spell[9998].timeleft = mins
            end)
        end
    elseif res:find("don't seem to have") then
        msg("No bounties available")
        if Spell[9998] then
            pcall(function()
                Spell[9998].active = true
                Spell[9998].timeleft = 9999
            end)
        end
    elseif res:find("bandit") then
        -- Original always removes bandit bounties from get_bounty
        -- (can_do_bounty handles them separately when enabled)
        remove_bounty()
    end

    can_do_bounty_cache = nil
end

remove_bounty = function()
    if (not settings.enable_expedite and Spell.active_p(9998)) or is_bounty({ "none" }) then return end

    rest_exit()

    if Script.running("go2") then pcall(Script.kill, "go2") end

    go2_nearest_tag("advguild")

    msg("removing bounty, you have five seconds to kill me")
    pause(5)

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if Regex.test("taskmaster", npc.name) then taskmaster = npc; break end
    end

    if not taskmaster then err("failed to find taskmaster"); return end

    local res = dothistimeout("ask " .. taskmaster.noun .. " about remove", 5,
        "want to be removed", "have removed you", "Trying to sneak")
    if res and res:find("Trying to sneak") then
        fput("ask " .. taskmaster.noun .. " about bounty")
    else
        dothistimeout("ask " .. taskmaster.noun .. " about remove", 5,
            "have removed you")
    end

    can_do_bounty_cache = nil
end

local function expedite_bounty()
    msg("expediting bounty, you have five seconds to kill me")
    pause(5)

    remove_bounty()

    rest_exit()
    go2_nearest_tag("advguild")

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if Regex.test("taskmaster", npc.name) then taskmaster = npc; break end
    end

    if not taskmaster then err("failed to find taskmaster"); return end

    local res = dothistimeout("ask " .. taskmaster.noun .. " about expedite", 5,
        "I'll expedite", "You don't seem to have any expedited",
        "I still need to complete")
    if res and res:find("expedited") then
        expedite_left = false
    end

    can_do_bounty_cache = nil
end

local function success_heirloom()
    msg("turning in heirloom")

    local npc = find_guard()
    if not npc then return end

    local saved = empty_hands()

    local lootsack = find_lootsack()
    if not lootsack then err("failed to find lootsack"); return end

    local close_after = false
    if not lootsack.contents then
        local open_result = dothistimeout("open #" .. lootsack.id, 5, "You open", "That is already open")
        if open_result and open_result:find("You open") then
            close_after = true
        else
            dothistimeout("look in #" .. lootsack.id, 5, "In .* you see")
        end
    end

    -- Find the heirloom
    local heirloom_caps = get_bounty_captures("success_heirloom")
    if not heirloom_caps then err("cannot parse heirloom name"); return end
    local heirloom_name = heirloom_caps[1] or ""

    msg("looking for " .. heirloom_name)

    local found = false
    if lootsack.contents then
        for _, item in ipairs(lootsack.contents) do
            if Regex.test(heirloom_name, item.name) then
                local res = dothistimeout("look #" .. item.id, 2,
                    "Engraved .* initials", "You see nothing unusual",
                    "The ring appears", "It takes you a moment", "It is difficult to see")
                if res and res:find("initials") then
                    fput("get #" .. item.id)
                    local npc_target = type(npc) == "string" and npc or ("#" .. npc.id)
                    fput("give #" .. item.id .. " to " .. npc_target)
                    found = true
                    break
                end
            end
        end
    end

    if close_after then fput("close #" .. lootsack.id) end

    if not found then
        err("failed to find heirloom for guard")
    end

    fill_hands(saved)
end

local function turn_in()
    rest_exit()

    if is_bounty({ "success_guard" }) then
        talk_to_guard()
    elseif is_bounty({ "success_heirloom" }) then
        success_heirloom()
    end

    go2_nearest_tag("advguild")

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if Regex.test("taskmaster", npc.name) then taskmaster = npc; break end
    end

    if taskmaster then
        dothistimeout("ask " .. taskmaster.noun .. " about bounty", 5,
            "done with that assignment")

        -- Read bounty reward lines
        for _ = 1, 10 do
            local line = get_noblock()
            if line and line:find("bounty points") then
                local caps = Regex.new("(\\d+) bounty points?, (\\d+) experience points, and (\\d+) silver"):captures(line)
                if caps then
                    msg("finished task (" .. caps[1] .. " pts, " .. caps[2] .. " exp, " .. caps[3] .. " silver)")
                end
                break
            end
            pause(0.1)
        end
    end

    run_loot_script()
    can_do_bounty_cache = nil
    SessionVars.sbounty_can_do_bounty = nil
end

--------------------------------------------------------------------------------
-- Hunter integration
--------------------------------------------------------------------------------

local function start_hunter(location)
    -- Store hunt data in SessionVars for hunter script to read
    if location then
        SessionVars.sbounty_hunt_location = location[1]
        SessionVars.sbounty_hunt_data = location[2]
    end
    SessionVars.sbounty_settings = settings

    hunter_name = settings.hunter
    Script.run(hunter_name)
end

local function finish_hunt()
    if hunter_name and Script.running(hunter_name) then
        pcall(Script.kill, hunter_name)
        wait_while(function() return Script.running(hunter_name) end)
    end

    if Script.running("go2") then pcall(Script.kill, "go2") end
    do_change_stance("defensive")

    -- Wait for looter
    if Script.running(settings.loot_script) then
        wait_while(function() return Script.running(settings.loot_script) end)
    end

    -- Run loot script if dead NPCs or heirloom
    local npcs = GameObj.npcs()
    local has_dead = false
    for _, npc in ipairs(npcs) do
        if npc.status and npc.status:find("dead") then has_dead = true; break end
    end

    if has_dead or is_bounty({ "success_heirloom" }) then
        run_loot_script()
    end
end

local function reload_hunter()
    -- Reload hunter by restarting with new location data
    if hunter_name and Script.running(hunter_name) then
        local new_location = get_bounty_location()
        if new_location then
            SessionVars.sbounty_hunt_location = new_location[1]
            SessionVars.sbounty_hunt_data = new_location[2]
        end
        -- Send reload signal to hunter
        pcall(send_to_script, hunter_name, "reload")
    end
end

--------------------------------------------------------------------------------
-- Task handlers
--------------------------------------------------------------------------------

local function task_escort(target_tag)
    target_tag = target_tag or "advguard"
    msg("escorting child to " .. target_tag)

    waitrt()
    fput("stance defensive")

    local tag_rooms = Map.tags(target_tag) or {}
    if #tag_rooms == 0 then err("no rooms with tag: " .. target_tag); return end

    local rest_id = tonumber(settings.rest_room) or Map.current_room()
    local nearest = Map.find_nearest_room(rest_id, tag_rooms)
    if not nearest then err("failed to find escort destination"); return end
    local destination = nearest.id

    while Map.current_room() ~= destination and is_bounty({ "task_escort" }) do
        -- Check for child
        local npcs = GameObj.npcs()
        local child_present = false
        for _, npc in ipairs(npcs) do
            if Regex.test("child", npc.name) then child_present = true; break end
        end

        if child_present then
            -- Step toward destination
            local path = Map.find_path(Map.current_room(), destination)
            if path and #path > 0 then
                move(path[1])
            end
        end
        pause(0.25)
    end

    if is_bounty({ "fail_child" }) then
        msg("failed to escort child or child was killed")
    else
        local npc = get_guard_npc()
        if npc then
            -- Wait for child to catch up
            msg("waiting for child to arrive")
            wait_until(function()
                local npcs = GameObj.npcs()
                for _, n in ipairs(npcs) do
                    if Regex.test("child", n.name) then return true end
                end
                return false
            end)

            if type(npc) == "string" then
                fput("ask " .. npc .. " for bounty")
            else
                fput("ask #" .. npc.id .. " for bounty")
            end
        elseif target_tag == "advguard" then
            task_escort("advguard2")
        else
            err("failed to find guard for escort")
        end
    end
end

local function task_search()
    if not is_bounty({ "task_search" }) then
        err("you are not on a search bounty")
        return
    end

    msg("searching for heirloom")

    local loc_result = get_bounty_location()
    if not loc_result then err("could not find search location"); return end
    local _, location = loc_result[1], loc_result[2]

    local song_of_peace = false
    local invalid_rooms = {}
    local last_room = nil

    hunt_prepare()
    rest_exit()

    go2(location.room)

    start_hunting_scripts()

    while is_bounty({ "task_search" }) and not check_wounded() do
        -- Song of Peace (1011)
        if Spell[1011] and Spell[1011].known and Spell[1011]:affordable() and not song_of_peace then
            Spell[1011]:cast()
            song_of_peace = true
        -- Presence (506)
        elseif Spell[506] and Spell[506].known and Spell[506]:affordable() and not Spell[506].active then
            Spell[506]:cast()
        end

        wander(location.boundaries)

        do_stand()
        do_change_stance("defensive")

        local current = Map.current_room()
        local npcs = GameObj.npcs()
        local npcs_present = npcs and #npcs > 0

        -- Check location matches
        local room_data = Map.find_room(current)
        local room_loc = room_data and room_data.location or ""
        local loc_matches = location.location and Regex.test(location.location:lower(), room_loc:lower())

        if not npcs_present and loc_matches
            and not invalid_rooms[current] and current ~= last_room then

            run_commands(settings.pre_search_commands)

            do_kneel()

            local res = dothistimeout("search", 1,
                "You intently search the area", "You put your head to the")
            if res and (res:find("intently search") or res:find("put your head")) then
                last_room = current
            else
                msg("invalid room, skipping in the future")
                invalid_rooms[current] = true
            end

            waitrt()

            run_commands(settings.post_search_commands)

            -- Try offensive stance if safe
            if song_of_peace then
                fput("stance offensive")
                pause(0.10)
            end

            do_stand()
            do_change_stance("defensive")

            if is_bounty({ "task_found" }) then
                run_loot_script()
                break
            end
        end
    end

    waitrt()

    if song_of_peace then
        fput("stop 1011")
    end

    kill_hunting_scripts()
end

local function task_bandit()
    if not is_bounty({ "task_bandit" }) then
        err("you are not on a bandits bounty")
        return
    end

    if settings.enable_bandit_script and not Script.exists(settings.bandit_script) then
        err("bandit script is enabled and could not be found")
        return
    end

    local caps = get_bounty_captures("task_bandit")
    if not caps then err("could not parse bandit bounty"); return end
    local location = (caps[1] or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    -- Find rooms matching the bandit location
    local function get_bandit_rooms()
        local all_rooms = Map.list() or {}
        local matching = {}
        for _, room in ipairs(all_rooms) do
            if room.location and Regex.test(location, room.location:lower()) then
                matching[#matching + 1] = room.id
            end
        end

        -- Filter unreachable and special rooms
        local rest_id = tonumber(settings.rest_room) or Map.current_room()
        local reachable = {}
        for _, room_id in ipairs(matching) do
            if room_id ~= 38 and room_id ~= 39 and room_id ~= 40 then
                local cost = Map.path_cost(rest_id, room_id)
                if cost then
                    reachable[#reachable + 1] = { id = room_id, dist = cost }
                end
            end
        end

        -- Sort by distance and take top 10
        table.sort(reachable, function(a, b) return a.dist < b.dist end)
        local result = {}
        for i = 1, math.min(10, #reachable) do
            result[#result + 1] = reachable[i].id
        end

        -- Re-sort by distance from current room
        local current = Map.current_room()
        local resorted = {}
        for _, room_id in ipairs(result) do
            if room_id ~= current then
                local cost = Map.path_cost(current, room_id)
                resorted[#resorted + 1] = { id = room_id, dist = cost or 9999 }
            end
        end
        table.sort(resorted, function(a, b) return a.dist < b.dist end)

        local final = {}
        for _, r in ipairs(resorted) do final[#final + 1] = r.id end
        return final
    end

    msg("culling bandits")
    start_hunting_scripts()

    while not check_wounded() and is_bounty({ "task_bandit" }) do
        local rooms = get_bandit_rooms()
        for _, room_id in ipairs(rooms) do
            waitrt()
            waitcastrt()

            msg("moving to room " .. room_id)
            do_change_stance("defensive")
            go2(room_id)

            msg("waiting for attack")
            local start = os.time()
            while true do
                if os.time() - start > 2 then break end
                local npcs = GameObj.npcs()
                for _, npc in ipairs(npcs) do
                    if npc.type and npc.type:find("bandit") then
                        goto bandit_found
                    end
                end
                pause(0.25)
            end
            ::bandit_found::

            while not check_wounded() do
                local npcs = GameObj.npcs()
                local alive_bandits = {}
                local dead_bandits = {}
                for _, npc in ipairs(npcs) do
                    if npc.type and npc.type:find("bandit") then
                        if npc.status and npc.status:find("dead") then
                            dead_bandits[#dead_bandits + 1] = npc
                        else
                            alive_bandits[#alive_bandits + 1] = npc
                        end
                    end
                end

                if #alive_bandits == 0 then
                    if #dead_bandits > 0 then run_loot_script() end
                    break
                elseif settings.enable_bandit_script then
                    waitrt()
                    waitcastrt()
                    if #dead_bandits > 0 then
                        run_loot_script()
                    else
                        local ids = {}
                        for _, b in ipairs(alive_bandits) do ids[#ids + 1] = b.id end
                        Script.run(settings.bandit_script, table.concat(ids, " "))
                        wait_while(function() return Script.running(settings.bandit_script) end)
                    end
                else
                    msg("kill them all!")
                    Script.pause(Script.name)
                    wait_until(function() return true end) -- wait for unpause
                end

                pause(0.25)
            end

            if check_wounded() or not is_bounty({ "task_bandit" }) then break end
        end

        pause(0.1)
    end

    kill_hunting_scripts()
end

local function task_forage()
    local caps = get_bounty_captures("task_forage")
    if not caps then err("you are not on a forage bounty"); return end

    local herb = caps[1] or ""
    local location = caps[2] or ""
    local count = tonumber(caps[3]) or 1

    msg("foraging for " .. count .. " " .. herb .. " at " .. location)

    herb = herb:lower()

    local lootsack = find_lootsack()
    if not lootsack then err("could not find lootsack"); return end

    local function get_herb_count()
        if not lootsack.contents then
            -- Try to open/look
            dothistimeout("look in #" .. lootsack.id, 3, "In .* you see")
        end
        if not lootsack.contents then return 0 end
        local herb_pat = herb:gsub("s?$", "")
        local n = 0
        for _, item in ipairs(lootsack.contents) do
            if Regex.test(herb_pat, item.name:lower()) then n = n + 1 end
        end
        return n
    end

    local function refresh_spells()
        local spells_to_check = { 506, 603, 9704 }
        for _, spell_num in ipairs(spells_to_check) do
            local sp = Spell[spell_num]
            if sp and sp.known and not sp.active and sp:affordable() then
                waitrt()
                waitcastrt()
                sp:cast()
                pause(0.50)
            end
        end
    end

    last_forage_attempt = os.time()

    if get_herb_count() < count then
        hunt_prepare()
        rest_exit()

        local rooms = get_herb_rooms(location, herb)
        local bright_rooms = {}
        local cur_room = 1
        local num_tries = 0
        local song_of_peace = false

        start_hunting_scripts()

        while get_herb_count() < count and not check_wounded() and num_tries < 3 do
            local sanct_cast = false
            local light_cast = false

            if cur_room > #rooms then
                cur_room = 1
                num_tries = num_tries + 1
                if num_tries >= 3 then break end
            end

            go2(rooms[cur_room])
            cur_room = cur_room + 1

            while get_herb_count() < count and #rooms > 0 and not check_wounded() do
                -- Break if other PCs present and we're kneeling
                if not kneeling() and #(GameObj.pcs() or {}) > 0 then
                    break
                end

                -- Song of Peace (1011)
                if Spell[1011] and Spell[1011].known and Spell[1011]:affordable() and not song_of_peace then
                    Spell[1011]:cast()
                    song_of_peace = true
                end

                waitrt()
                do_change_stance("defensive")

                refresh_spells()

                -- Check for hostiles
                if not song_of_peace then
                    local npcs = GameObj.npcs()
                    local hostile = false
                    for _, npc in ipairs(npcs) do
                        if npc.type and npc.type:find("aggressive")
                            and (not npc.status or not npc.status:find("dead")) then
                            hostile = true
                            break
                        end
                    end
                    if hostile then break end
                end

                if not kneeling() then
                    run_commands(settings.pre_forage_commands)
                    do_kneel()
                end

                -- Sanctuary (213) if known
                if Spell[213] and Spell[213].known and Spell[213]:affordable() and not sanct_cast then
                    sanct_cast = true
                    fput("incant 213")
                    waitcastrt()
                end

                -- Light (205) if known
                if Spell[205] and Spell[205].known and Spell[205]:affordable()
                    and not bright_rooms[cur_room - 1] and not light_cast then
                    light_cast = true
                    fput("incant 205")
                    bright_rooms[cur_room - 1] = true
                    waitcastrt()
                end

                -- Hide if skilled
                if Skills.stalking_and_hiding >= 50 then
                    while not hidden() do fput("hide") end
                end

                -- Clean herb name for forage command (use plain Lua gsub, no PCRE)
                local forage_herb = herb
                forage_herb = forage_herb:gsub("handful of ", "")
                forage_herb = forage_herb:gsub("bunch of ", "")
                forage_herb = forage_herb:gsub("sprig of ", "")
                forage_herb = forage_herb:gsub("fragrant ", "")
                forage_herb = forage_herb:gsub("fetid ", "")
                forage_herb = forage_herb:gsub("dark pink ", "")
                forage_herb = forage_herb:gsub("mass of ", "")
                forage_herb = forage_herb:gsub("slime%-covered ", "")
                forage_herb = forage_herb:gsub("layer of ", "")

                local res = dothistimeout("forage " .. forage_herb, 1,
                    "find no trace of what", "not even positive",
                    "it could be", "it could even be found",
                    "and manage to find", "Roundtime",
                    "In order to forage", "foraging here recently")

                if res and (res:find("it could be") or res:find("it could even be found")
                    or res:find("not even positive") or res:find("find no trace")) then
                    table.remove(rooms, cur_room - 1)
                    cur_room = cur_room - 1
                    break
                elseif res and res:find("manage to find") then
                    -- Stow herbs into lootsack
                    local lh = GameObj.left_hand()
                    while lh and (Regex.test(herb, lh.name:lower()) or Regex.test(lh.name:lower(), herb)) do
                        fput("put " .. lh.noun .. " in #" .. lootsack.id)
                        lh = GameObj.left_hand()
                    end
                    local rh = GameObj.right_hand()
                    while rh and (Regex.test(herb, rh.name:lower()) or Regex.test(rh.name:lower(), herb)) do
                        fput("put " .. rh.noun .. " in #" .. lootsack.id)
                        rh = GameObj.right_hand()
                    end
                    msg("success, found " .. get_herb_count() .. " of " .. count .. " " .. herb)
                elseif res and res:find("In order to forage") then
                    fput("stow all")
                elseif res and res:find("foraging here recently") then
                    msg("herb can not be found here, skipping room...")
                    table.remove(rooms, cur_room - 1)
                    cur_room = cur_room - 1
                    break
                else
                    msg("failure, found " .. get_herb_count() .. " of " .. count .. " " .. herb)
                end
            end

            -- Cleanup stray herbs in hands (loop in case of stacking)
            local lh = GameObj.left_hand()
            while lh and (Regex.test(herb, lh.name:lower()) or Regex.test(lh.name:lower(), herb)) do
                fput("put " .. lh.noun .. " in #" .. lootsack.id)
                lh = GameObj.left_hand()
            end
            local rh = GameObj.right_hand()
            while rh and (Regex.test(herb, rh.name:lower()) or Regex.test(rh.name:lower(), herb)) do
                fput("put " .. rh.noun .. " in #" .. lootsack.id)
                rh = GameObj.right_hand()
            end

            if not standing() then
                run_commands(settings.post_forage_commands)

                if song_of_peace then
                    fput("stance offensive")
                    pause(0.10)
                end

                do_stand()
                do_change_stance("defensive")
            end
        end

        if song_of_peace then
            fput("stop 1011")
        end

        if get_herb_count() >= count then
            talk_to_herbalist()
            last_forage_attempt = 0
        end

        kill_hunting_scripts()
    else
        -- Already have enough herbs, just turn them in
        talk_to_herbalist()
        last_forage_attempt = 0
    end
end

--------------------------------------------------------------------------------
-- GUI Setup
--------------------------------------------------------------------------------

local function show_setup()
    if not Gui then
        -- Fallback: terminal-based setup display
        respond("\n=== SBounty Settings ===")
        respond("Hunter script:     " .. settings.hunter)
        respond("Loot script:       " .. settings.loot_script)
        respond("Rest room:         " .. (settings.rest_room or ""))
        respond("")
        respond("Bounty types enabled:")
        respond("  Cull:       " .. tostring(settings.enable_cull))
        respond("  Dangerous:  " .. tostring(settings.enable_dangerous))
        respond("  Forage:     " .. tostring(settings.enable_forage))
        respond("  Loot:       " .. tostring(settings.enable_loot))
        respond("  Rescue:     " .. tostring(settings.enable_rescue))
        respond("  Search:     " .. tostring(settings.enable_search))
        respond("  Bandit:     " .. tostring(settings.enable_bandit))
        respond("  Skin:       " .. tostring(settings.enable_skin))
        respond("  Expedite:   " .. tostring(settings.enable_expedite))
        respond("")
        respond("Locations (" .. #(settings.locations or {}) .. "):")
        for name, loc in pairs(settings.locations or {}) do
            respond("  " .. name .. ": room=" .. (loc.room or "?") .. " targets=" .. table.concat(loc.targets or {}, ","))
        end
        respond("")
        respond("Hunt thresholds: mind<=" .. settings.should_hunt_mind .. " mana>=" .. settings.should_hunt_mana .. " spirit>=" .. settings.should_hunt_spirit)
        respond("Rest thresholds: mind>=" .. settings.should_rest_mind .. " mana<=" .. settings.should_rest_mana)
        respond("===\n")
        return
    end

    -- Full GUI setup
    local win = Gui.window("SBounty Setup", { width = 600, height = 500, resizable = true })

    -- Working copy of locations
    local work_locations = {}
    for k, v in pairs(settings.locations) do
        work_locations[k] = {}
        for kk, vv in pairs(v) do work_locations[k][kk] = vv end
    end
    local current_location = nil

    -- Tab bar
    local tabs = Gui.tab_bar({ "Locations / Options", "Resting / Hunting" })

    ---------- Tab 1: Locations / Options ----------
    local tab1 = Gui.vbox()

    -- Locations frame
    local loc_card = Gui.card({ title = "Locations" })
    local loc_vbox = Gui.vbox()

    -- Create location row
    local create_row = Gui.hbox()
    local new_name_label = Gui.label("New name:")
    local new_name_input = Gui.input({ placeholder = "Location name" })
    local create_btn = Gui.button("Create")
    create_row:add(new_name_label)
    create_row:add(new_name_input)
    create_row:add(create_btn)
    loc_vbox:add(create_row)

    -- Select/delete location row
    local select_row = Gui.hbox()
    local loc_label = Gui.label("Locations:")
    local loc_names = {}
    for name in pairs(work_locations) do loc_names[#loc_names + 1] = name end
    table.sort(loc_names)
    local loc_combo = Gui.editable_combo({ options = loc_names, hint = "Select location" })
    local delete_btn = Gui.button("Delete")
    select_row:add(loc_label)
    select_row:add(loc_combo)
    select_row:add(delete_btn)
    loc_vbox:add(select_row)

    loc_vbox:add(Gui.separator())

    -- Location detail fields
    local loc_location_input = Gui.input({ placeholder = "Location pattern", text = "" })
    local loc_room_input = Gui.input({ placeholder = "Room #", text = "" })
    local loc_targets_input = Gui.input({ placeholder = "Targets (comma-sep)", text = "" })
    local loc_skins_input = Gui.input({ placeholder = "Skins (comma-sep)", text = "" })
    local loc_boundaries_input = Gui.input({ placeholder = "Boundaries (comma-sep)", text = "" })
    local loc_hunting_rotation_cb = Gui.checkbox("In hunting rotation", false)
    local loc_bounty_only_cb = Gui.checkbox("Only attack bounty critters", false)
    local loc_search_only_cb = Gui.checkbox("Only search here (no hunting)", false)

    local detail1 = Gui.hbox()
    detail1:add(Gui.label("Location:"))
    detail1:add(loc_location_input)
    detail1:add(Gui.label("Room #:"))
    detail1:add(loc_room_input)
    loc_vbox:add(detail1)

    local detail2 = Gui.hbox()
    detail2:add(Gui.label("Targets:"))
    detail2:add(loc_targets_input)
    detail2:add(Gui.label("Skins:"))
    detail2:add(loc_skins_input)
    loc_vbox:add(detail2)

    local detail3 = Gui.hbox()
    detail3:add(Gui.label("Boundaries:"))
    detail3:add(loc_boundaries_input)
    loc_vbox:add(detail3)

    local detail4 = Gui.hbox()
    detail4:add(loc_hunting_rotation_cb)
    detail4:add(loc_bounty_only_cb)
    detail4:add(loc_search_only_cb)
    loc_vbox:add(detail4)

    loc_card:add(loc_vbox)
    tab1:add(loc_card)

    -- Bounties frame
    local bounty_card = Gui.card({ title = "Bounties" })
    local bounty_vbox = Gui.vbox()

    local cb_cull = Gui.checkbox("Cull critters", settings.enable_cull)
    local cb_dangerous = Gui.checkbox("Dangerous critter", settings.enable_dangerous)
    local cb_rescue = Gui.checkbox("Rescue child", settings.enable_rescue)
    local cb_skin = Gui.checkbox("Skin critters", settings.enable_skin)
    local cb_loot = Gui.checkbox("Loot heirloom", settings.enable_loot)
    local cb_search = Gui.checkbox("Search heirloom", settings.enable_search)
    local cb_forage = Gui.checkbox("Forage herbs", settings.enable_forage)
    local cb_bandit = Gui.checkbox("Bandits", settings.enable_bandit)
    local cb_bandit_script = Gui.checkbox("Use bandit script", settings.enable_bandit_script)
    local cb_expedite = Gui.checkbox("Expedite bounties", settings.enable_expedite)
    local cb_hunt_complete = Gui.checkbox("Hunt until complete?", settings.enable_hunt_complete)
    local cb_turn_in = Gui.checkbox("Force turn in if new bounty", settings.enable_turn_in_bounty)

    local b_row1 = Gui.hbox()
    b_row1:add(cb_cull); b_row1:add(cb_dangerous); b_row1:add(cb_rescue); b_row1:add(cb_skin)
    bounty_vbox:add(b_row1)

    local b_row2 = Gui.hbox()
    b_row2:add(cb_loot); b_row2:add(cb_search); b_row2:add(cb_forage); b_row2:add(cb_bandit)
    bounty_vbox:add(b_row2)

    local b_row3 = Gui.hbox()
    b_row3:add(cb_bandit_script); b_row3:add(cb_expedite); b_row3:add(cb_hunt_complete); b_row3:add(cb_turn_in)
    bounty_vbox:add(b_row3)

    local turn_in_pct_input = Gui.input({ text = tostring(settings.turn_in_percent), placeholder = "95" })
    local hunting_scripts_input = Gui.input({ text = table.concat(settings.hunting_scripts or {}, ","), placeholder = "spellactive" })
    local bandit_script_input = Gui.input({ text = settings.bandit_script or "", placeholder = "sbounty-bandit-example" })

    local b_row4 = Gui.hbox()
    b_row4:add(Gui.label("Turn in when mind >="))
    b_row4:add(turn_in_pct_input)
    b_row4:add(Gui.label("Hunting scripts:"))
    b_row4:add(hunting_scripts_input)
    bounty_vbox:add(b_row4)

    local b_row5 = Gui.hbox()
    b_row5:add(Gui.label("Bandit script:"))
    b_row5:add(bandit_script_input)
    bounty_vbox:add(b_row5)

    local pre_search_input = Gui.input({ text = table.concat(settings.pre_search_commands or {}, ",") })
    local post_search_input = Gui.input({ text = table.concat(settings.post_search_commands or {}, ",") })
    local pre_forage_input = Gui.input({ text = table.concat(settings.pre_forage_commands or {}, ",") })
    local post_forage_input = Gui.input({ text = table.concat(settings.post_forage_commands or {}, ",") })
    local forage_delay_input = Gui.input({ text = tostring(settings.forage_retry_delay) })
    local loot_script_input = Gui.input({ text = settings.loot_script or "" })

    local b_row6 = Gui.hbox()
    b_row6:add(Gui.label("Pre-search:"))
    b_row6:add(pre_search_input)
    b_row6:add(Gui.label("Post-search:"))
    b_row6:add(post_search_input)
    bounty_vbox:add(b_row6)

    local b_row7 = Gui.hbox()
    b_row7:add(Gui.label("Pre-forage:"))
    b_row7:add(pre_forage_input)
    b_row7:add(Gui.label("Post-forage:"))
    b_row7:add(post_forage_input)
    bounty_vbox:add(b_row7)

    local b_row8 = Gui.hbox()
    b_row8:add(Gui.label("Forage retry delay:"))
    b_row8:add(forage_delay_input)
    b_row8:add(Gui.label("Loot script:"))
    b_row8:add(loot_script_input)
    bounty_vbox:add(b_row8)

    bounty_card:add(bounty_vbox)
    tab1:add(bounty_card)

    ---------- Tab 2: Resting / Hunting ----------
    local tab2 = Gui.vbox()

    -- Should Rest frame
    local rest_card = Gui.card({ title = "Should Rest" })
    local rest_vbox = Gui.vbox()

    local rest_mind_input = Gui.input({ text = tostring(settings.should_rest_mind) })
    local rest_mana_input = Gui.input({ text = tostring(settings.should_rest_mana) })
    local rest_encum_input = Gui.input({ text = tostring(settings.should_rest_encum) })

    local r_row1 = Gui.hbox()
    r_row1:add(Gui.label("when mind % >="))
    r_row1:add(rest_mind_input)
    r_row1:add(Gui.label("or mana <="))
    r_row1:add(rest_mana_input)
    rest_vbox:add(r_row1)

    local r_row2 = Gui.hbox()
    r_row2:add(Gui.label("or encumbrance % >="))
    r_row2:add(rest_encum_input)
    rest_vbox:add(r_row2)

    rest_card:add(rest_vbox)
    tab2:add(rest_card)

    -- Resting frame
    local resting_card = Gui.card({ title = "Resting" })
    local resting_vbox = Gui.vbox()

    local rest_room_input = Gui.input({ text = settings.rest_room or "" })
    local rest_pre_input = Gui.input({ text = table.concat(settings.rest_pre_commands or {}, ",") })
    local rest_in_input = Gui.input({ text = table.concat(settings.rest_in_commands or {}, ",") })
    local rest_out_input = Gui.input({ text = table.concat(settings.rest_out_commands or {}, ",") })
    local rest_scripts_input = Gui.input({ text = table.concat(settings.rest_scripts or {}, ",") })

    local re_row1 = Gui.hbox()
    re_row1:add(Gui.label("Room #:"))
    re_row1:add(rest_room_input)
    re_row1:add(Gui.label("Pre-rest commands:"))
    re_row1:add(rest_pre_input)
    resting_vbox:add(re_row1)

    local re_row2 = Gui.hbox()
    re_row2:add(Gui.label("Enter commands:"))
    re_row2:add(rest_in_input)
    re_row2:add(Gui.label("Exit commands:"))
    re_row2:add(rest_out_input)
    resting_vbox:add(re_row2)

    local re_row3 = Gui.hbox()
    re_row3:add(Gui.label("Scripts:"))
    re_row3:add(rest_scripts_input)
    resting_vbox:add(re_row3)

    resting_card:add(resting_vbox)
    tab2:add(resting_card)

    -- Should Hunt frame
    local hunt_card = Gui.card({ title = "Should Hunt" })
    local hunt_vbox = Gui.vbox()

    local hunt_mind_input = Gui.input({ text = tostring(settings.should_hunt_mind) })
    local hunt_mana_input = Gui.input({ text = tostring(settings.should_hunt_mana) })
    local hunt_spirit_input = Gui.input({ text = tostring(settings.should_hunt_spirit) })

    local h_row1 = Gui.hbox()
    h_row1:add(Gui.label("when mind % <="))
    h_row1:add(hunt_mind_input)
    h_row1:add(Gui.label("and mana >="))
    h_row1:add(hunt_mana_input)
    hunt_vbox:add(h_row1)

    local h_row2 = Gui.hbox()
    h_row2:add(Gui.label("and spirit >="))
    h_row2:add(hunt_spirit_input)
    hunt_vbox:add(h_row2)

    hunt_card:add(hunt_vbox)
    tab2:add(hunt_card)

    -- Hunting frame
    local hunting_card = Gui.card({ title = "Hunting" })
    local hunting_vbox = Gui.vbox()

    local hunt_pre_input = Gui.input({ text = table.concat(settings.hunt_pre_commands or {}, ",") })
    local hunt_cmd_a_input = Gui.input({ text = table.concat(settings.hunt_commands_a or {}, ",") })
    local hunt_cmd_b_input = Gui.input({ text = table.concat(settings.hunt_commands_b or {}, ",") })
    local hunt_cmd_c_input = Gui.input({ text = table.concat(settings.hunt_commands_c or {}, ",") })

    local hu_row1 = Gui.hbox()
    hu_row1:add(Gui.label("Pre-hunt commands:"))
    hu_row1:add(hunt_pre_input)
    hu_row1:add(Gui.label("Commands (a):"))
    hu_row1:add(hunt_cmd_a_input)
    hunting_vbox:add(hu_row1)

    local hu_row2 = Gui.hbox()
    hu_row2:add(Gui.label("Commands (b):"))
    hu_row2:add(hunt_cmd_b_input)
    hu_row2:add(Gui.label("Commands (c):"))
    hu_row2:add(hunt_cmd_c_input)
    hunting_vbox:add(hu_row2)

    hunting_card:add(hunting_vbox)
    tab2:add(hunting_card)

    ---------- Tab content assignment ----------
    tabs:set_tab_content(1, Gui.scroll(tab1))
    tabs:set_tab_content(2, Gui.scroll(tab2))

    ---------- Location management callbacks ----------

    local function load_location(name)
        current_location = name
        local data = work_locations[name] or {}
        loc_location_input:set_text(data.location or "")
        loc_room_input:set_text(data.room or "")
        loc_targets_input:set_text(table.concat(data.targets or {}, ","))
        loc_skins_input:set_text(table.concat(data.skins or {}, ","))
        loc_boundaries_input:set_text(type(data.boundaries) == "table" and table.concat(data.boundaries, ",") or (data.boundaries or ""))
        loc_hunting_rotation_cb:set_checked(data.enable_hunting_rotation or false)
        loc_bounty_only_cb:set_checked(data.enable_bounty_only or false)
        loc_search_only_cb:set_checked(data.enable_search_only or false)
    end

    local function save_current_location()
        if not current_location then return end
        local data = work_locations[current_location] or {}
        data.location = loc_location_input:get_text()
        data.room = loc_room_input:get_text()

        local function split_csv(s)
            local result = {}
            for item in s:gmatch("[^,]+") do
                result[#result + 1] = item:gsub("^%s+", ""):gsub("%s+$", "")
            end
            return result
        end

        data.targets = split_csv(loc_targets_input:get_text())
        data.skins = split_csv(loc_skins_input:get_text())
        data.boundaries = split_csv(loc_boundaries_input:get_text())
        data.enable_hunting_rotation = loc_hunting_rotation_cb:get_checked()
        data.enable_bounty_only = loc_bounty_only_cb:get_checked()
        data.enable_search_only = loc_search_only_cb:get_checked()
        work_locations[current_location] = data
    end

    loc_combo:on_change(function()
        save_current_location()
        local name = loc_combo:get_text()
        if work_locations[name] then
            load_location(name)
        end
    end)

    create_btn:on_click(function()
        local name = new_name_input:get_text():gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" or #name < 3 then return end
        if work_locations[name] then return end
        work_locations[name] = {}
        new_name_input:set_text("")
        local names = {}
        for n in pairs(work_locations) do names[#names + 1] = n end
        table.sort(names)
        loc_combo:set_options(names)
    end)

    delete_btn:on_click(function()
        local name = loc_combo:get_text()
        if name and work_locations[name] then
            work_locations[name] = nil
            current_location = nil
            local names = {}
            for n in pairs(work_locations) do names[#names + 1] = n end
            table.sort(names)
            loc_combo:set_options(names)
            loc_combo:set_text("")
            loc_location_input:set_text("")
            loc_room_input:set_text("")
            loc_targets_input:set_text("")
            loc_skins_input:set_text("")
            loc_boundaries_input:set_text("")
            loc_hunting_rotation_cb:set_checked(false)
            loc_bounty_only_cb:set_checked(false)
            loc_search_only_cb:set_checked(false)
        end
    end)

    ---------- Save / Close buttons ----------
    local btn_row = Gui.hbox()
    local save_btn = Gui.button("Save & Close")
    local close_btn = Gui.button("Close")
    btn_row:add(save_btn)
    btn_row:add(close_btn)

    local root = Gui.vbox()
    root:add(tabs)
    root:add(btn_row)

    local function split_csv(s)
        local result = {}
        for item in s:gmatch("[^,]+") do
            result[#result + 1] = item:gsub("^%s+", ""):gsub("%s+$", "")
        end
        return result
    end

    save_btn:on_click(function()
        save_current_location()

        -- Save all settings from GUI
        settings.locations = work_locations

        settings.enable_cull = cb_cull:get_checked()
        settings.enable_dangerous = cb_dangerous:get_checked()
        settings.enable_rescue = cb_rescue:get_checked()
        settings.enable_skin = cb_skin:get_checked()
        settings.enable_loot = cb_loot:get_checked()
        settings.enable_search = cb_search:get_checked()
        settings.enable_forage = cb_forage:get_checked()
        settings.enable_bandit = cb_bandit:get_checked()
        settings.enable_bandit_script = cb_bandit_script:get_checked()
        settings.enable_expedite = cb_expedite:get_checked()
        settings.enable_hunt_complete = cb_hunt_complete:get_checked()
        settings.enable_turn_in_bounty = cb_turn_in:get_checked()

        settings.turn_in_percent = tonumber(turn_in_pct_input:get_text()) or 95
        settings.hunting_scripts = split_csv(hunting_scripts_input:get_text())
        settings.bandit_script = bandit_script_input:get_text()
        settings.pre_search_commands = split_csv(pre_search_input:get_text())
        settings.post_search_commands = split_csv(post_search_input:get_text())
        settings.pre_forage_commands = split_csv(pre_forage_input:get_text())
        settings.post_forage_commands = split_csv(post_forage_input:get_text())
        settings.forage_retry_delay = tonumber(forage_delay_input:get_text()) or 300
        settings.loot_script = loot_script_input:get_text()

        settings.should_rest_mind = tonumber(rest_mind_input:get_text()) or 100
        settings.should_rest_mana = tonumber(rest_mana_input:get_text()) or 0
        settings.should_rest_encum = tonumber(rest_encum_input:get_text()) or 20

        settings.rest_room = rest_room_input:get_text()
        settings.rest_pre_commands = split_csv(rest_pre_input:get_text())
        settings.rest_in_commands = split_csv(rest_in_input:get_text())
        settings.rest_out_commands = split_csv(rest_out_input:get_text())
        settings.rest_scripts = split_csv(rest_scripts_input:get_text())

        settings.should_hunt_mind = tonumber(hunt_mind_input:get_text()) or 75
        settings.should_hunt_mana = tonumber(hunt_mana_input:get_text()) or 0
        settings.should_hunt_spirit = tonumber(hunt_spirit_input:get_text()) or 7

        settings.hunt_pre_commands = split_csv(hunt_pre_input:get_text())
        settings.hunt_commands_a = split_csv(hunt_cmd_a_input:get_text())
        settings.hunt_commands_b = split_csv(hunt_cmd_b_input:get_text())
        settings.hunt_commands_c = split_csv(hunt_cmd_c_input:get_text())

        save_settings()
        win:close()
    end)

    close_btn:on_click(function()
        win:close()
    end)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("SpiffyBounty v" .. VERSION .. " by SpiffyJr (theman@spiffyjr.me)")
    respond("usage: ;sbounty [option]")
    respond("")
    respond("  (no args)       — run bounty loop")
    respond("  setup           — configure settings (GUI)")
    respond("  help            — show this help")
    respond("  forage          — run forage task only")
    respond("  bandits         — run bandit task only")
    respond("  npc             — talk to NPC only")
    respond("  check           — check if current bounty is doable")
    respond("  load [target]   — load hunter with optional target")
    respond("")
end

--------------------------------------------------------------------------------
-- Startup validation
--------------------------------------------------------------------------------

local function validate_startup()
    if not UserVars.lootsack or UserVars.lootsack == "" then
        echo("** lootsack has not been set, set it with ;set change lootsack [container]")
        return false
    end
    if settings.enable_skin and (not UserVars.skinsack or UserVars.skinsack == "") then
        echo("** skinsack has not been set, set it with ;set change skinsack [container]")
        return false
    end

    local lootsack = find_lootsack()
    if not lootsack then
        echo("** failed to find your lootsack, set it with ;set change lootsack [container]")
        return false
    end

    if settings.enable_skin then
        local skinsack = find_skinsack()
        if not skinsack then
            echo("** failed to find your skinsack, set it with ;set change skinsack [container]")
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------

local input = Script.vars[1] or ""

if input:match("^setup$") then
    show_setup()
    return
elseif input:match("^help$") then
    show_help()
    return
elseif input:match("^forage$") then
    if not validate_startup() then return end
    task_forage()
    return
elseif input:match("^bandits?$") then
    if not validate_startup() then return end
    task_bandit()
    return
elseif input:match("^npc$") then
    talk_to_npc()
    return
elseif input:match("^load$") then
    if not validate_startup() then return end
    local target = Script.vars[2]
    local location = nil
    if target then
        local locs = {}
        for k, v in pairs(settings.locations) do locs[k] = v end
        for _, data in pairs(locs) do
            local cleaned = clean_targets(data.targets)
            for _, t in ipairs(cleaned) do
                if Regex.test(t, target) then
                    location = { _, data }
                    break
                end
            end
            if location then break end
        end
    end
    SessionVars.sbounty_settings = settings
    if location or get_bounty_location(location, target) then
        local loc = get_bounty_location(location, target)
        if loc then
            SessionVars.sbounty_hunt_location = loc[1]
            SessionVars.sbounty_hunt_data = loc[2]
        end
    end
    Script.run(settings.hunter)
    wait_while(function() return Script.running(settings.hunter) end)
    return
elseif input:match("^check$") then
    echo("Can do bounty: " .. tostring(can_do_bounty()))
    return
elseif input ~= "" then
    -- Custom hunter name
    settings.hunter = "sbounty-" .. input
end

-- Validate before starting main loop
if not validate_startup() then return end

-- Setup cleanup
before_dying(function()
    if hunter_name and Script.running(hunter_name) then
        pcall(Script.kill, hunter_name)
    end
    kill_hunting_scripts()
end)

-- Load hunter bridge script
hunter_name = settings.hunter

echo("SBounty v" .. VERSION .. " starting bounty loop")

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

while true do
    if dead() then break end

    talk_to_npc()

    if can_do_bounty() and not check_wounded() then
        if is_bounty({ "task_search" }) then
            task_search()
        elseif is_bounty({ "task_forage" }) and os.time() >= last_forage_attempt + last_forage_delay then
            task_forage()
        end
    elseif Spell.active_p(9998) -- Next Bounty active
        and (expedite_left and not is_bounty({ "none" }) and not can_do_bounty() and settings.enable_expedite)
        and not is_bounty({ "success" }) then
        expedite_bounty()
        can_do_bounty_cache = nil
        goto continue
    end

    -- Escort child if present
    if is_bounty({ "task_escort" }) then
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if Regex.test("child", npc.name) then
                task_escort("advguard")
                break
            end
        end
    elseif is_bounty({ "fail_child" }) then
        can_do_bounty_cache = nil
    elseif is_bounty({ "success_heirloom" }) then
        success_heirloom()
    end

    if dead() then break end

    if can_turn_in() then
        turn_in()
        resting = false
    else
        if not can_do_bounty() and not Spell.active_p(9998) and not is_bounty({ "success" }) then
            remove_bounty()
            get_bounty()
        elseif should_hunt() and not should_rest() and not has_skins() then
            resting = false
            local provoked = false
            local success = false
            first_run = false
            local bounty_snapshot = Bounty.task or ""

            rest_exit()
            hunt_prepare()

            -- Start hunting
            if can_do_bounty() then
                if is_bounty({ "task_bandit" }) then
                    task_bandit()
                elseif is_bounty({ "task_cull", "task_dangerous", "task_heirloom", "task_rescue", "task_skin" }) then
                    start_hunter(get_bounty_location())
                else
                    start_hunter(get_random_location())
                end
            else
                start_hunter(get_random_location())
            end

            -- Monitor hunt
            while not should_rest() and hunter_name and Script.running(hunter_name) do
                if is_bounty({ "task_provoked" }) and not provoked then
                    reload_hunter()
                    provoked = true
                elseif is_bounty({ "task_escort" }) then
                    break
                elseif has_skins() then
                    break
                elseif not success and ((Bounty.task or "") ~= bounty_snapshot
                    and (is_bounty({ "success", "success_heirloom" })
                        or (provoked and is_bounty({ "success_guard" })))) then
                    finish_hunt()
                    start_hunter(get_random_location())
                    success = true
                elseif can_turn_in() then
                    break
                elseif not can_do_bounty() and not Spell.active_p(9998) then
                    break
                end

                pause(0.10)
            end

            finish_hunt()
        elseif not can_turn_in() then
            -- Rest
            rest_goto()

            if not resting or check_wounded() then
                rest_run_scripts()
                rest_goto()
            end

            rest_enter()

            while should_rest() or not should_hunt() do
                if can_turn_in() then break end
                if check_wounded() then break end
                if not can_do_bounty() and not Spell.active_p(9998) then break end

                fput("exp")

                local reason = rest_reason or hunt_reason
                if reason then
                    msg("still resting because: " .. reason)
                end

                pause(settings.rest_sleep_interval)
            end

            resting = true
            rest_exit()
        end
    end

    ::continue::
    pause(0.10)
end
