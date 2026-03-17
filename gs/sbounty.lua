--- @revenant-script
--- name: sbounty
--- version: 1.2.0
--- author: spiffyjr
--- maintainer: Elanthia-Online
--- game: gs
--- tags: bounty
--- description: Smart bounty automation — handles cull, dangerous, forage, skin, search, heirloom, escort, bandits
---
--- Original Lich5 authors: spiffyjr, Elanthia-Online
--- Ported to Revenant Lua from sbounty.lic v1.2
---
--- Usage:
---   ;sbounty              — run bounty loop
---   ;sbounty setup        — configure locations and settings (terminal UI)
---   ;sbounty help         — show help
---   ;sbounty forage       — run forage task only
---   ;sbounty bandits      — run bandit task only
---   ;sbounty check        — check if current bounty is doable

local VERSION = "1.2.0"

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local settings = CharSettings.get("sbounty") or {}

-- Defaults
settings.hunter               = settings.hunter or "bigshot"
settings.enable_cull          = (settings.enable_cull == nil) and true or settings.enable_cull
settings.enable_dangerous     = (settings.enable_dangerous == nil) and true or settings.enable_dangerous
settings.enable_forage        = (settings.enable_forage == nil) and true or settings.enable_forage
settings.enable_loot          = (settings.enable_loot == nil) and true or settings.enable_loot
settings.enable_rescue        = (settings.enable_rescue == nil) and true or settings.enable_rescue
settings.enable_search        = (settings.enable_search == nil) and true or settings.enable_search
settings.enable_bandit        = (settings.enable_bandit == nil) and false or settings.enable_bandit
settings.enable_skin          = (settings.enable_skin == nil) and true or settings.enable_skin
settings.enable_expedite      = (settings.enable_expedite == nil) and true or settings.enable_expedite
settings.enable_hunt_complete = (settings.enable_hunt_complete == nil) and true or settings.enable_hunt_complete
settings.enable_turn_in       = (settings.enable_turn_in == nil) and true or settings.enable_turn_in

settings.hunting_scripts      = settings.hunting_scripts or {}
settings.bandit_script        = settings.bandit_script or "sbounty-bandit-example"
settings.pre_search_commands  = settings.pre_search_commands or { "store all" }
settings.post_search_commands = settings.post_search_commands or { "gird" }
settings.pre_forage_commands  = settings.pre_forage_commands or { "store all" }
settings.post_forage_commands = settings.post_forage_commands or { "gird" }
settings.forage_retry_delay   = settings.forage_retry_delay or 300
settings.loot_script          = settings.loot_script or "eloot"
settings.turn_in_percent      = settings.turn_in_percent or 95

settings.should_hunt_mind     = settings.should_hunt_mind or 75
settings.should_hunt_mana     = settings.should_hunt_mana or 0
settings.should_hunt_spirit   = settings.should_hunt_spirit or 7
settings.hunt_pre_commands    = settings.hunt_pre_commands or { "gird" }

settings.should_rest_mind     = settings.should_rest_mind or 100
settings.should_rest_mana     = settings.should_rest_mana or 0
settings.should_rest_encum    = settings.should_rest_encum or 20

settings.rest_room            = settings.rest_room or ""
settings.rest_in_commands     = settings.rest_in_commands or { "go table", "sit" }
settings.rest_out_commands    = settings.rest_out_commands or { "stand", "out" }
settings.rest_pre_commands    = settings.rest_pre_commands or { "store all" }
settings.rest_scripts         = settings.rest_scripts or {}
settings.rest_sleep_interval  = settings.rest_sleep_interval or 30

settings.locations            = settings.locations or {}

local function save_settings()
    CharSettings.set("sbounty", settings)
end

save_settings()

--------------------------------------------------------------------------------
-- Bounty patterns
--------------------------------------------------------------------------------

local bounty_patterns = {
    none            = "^You are not currently assigned a task%.",
    help_bandit     = "It appears they have a bandit problem",
    help_creature   = "It appears they have a creature problem",
    help_resident   = "It appears that a local resident urgently needs our help",
    help_heirloom   = "It appears they need your help in tracking down some kind of lost heirloom",
    help_gemdealer  = "The local gem dealer",
    help_herbalist  = "local herbalist|local healer|local alchemist",
    help_furrier    = "The local furrier",

    task_bandit     = "^You have been tasked to suppress bandit activity",
    task_escort     = "^You have made contact with the child",
    task_dangerous  = "You have been tasked to hunt down and kill a particularly dangerous",
    task_provoked   = "You have been tasked to hunt down.*You have provoked",
    task_dealer     = "^The(?: local)? gem dealer",
    task_forage     = "concoction that requires .+ found .+These samples must be in pristine condition",
    task_cull       = "You have been tasked to.+suppress",
    task_search     = "unfortunate citizen lost after being attacked by.+SEARCH",
    task_heirloom   = "unfortunate citizen lost after being attacked by.+LOOT",
    task_found      = "You have located .+ and should bring it back",
    task_skin       = "^You have been tasked to retrieve",
    task_rescue     = "A local divinist has had visions of the child fleeing from",
    fail_child      = "The child you were tasked to rescue is gone",

    success         = "^You have succeeded in your task and can return",
    success_guard   = "^You succeeded in your task and should report back to",
    success_heirloom = "^You have located .+ and should bring it back",
}

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local in_rest_area = false
local last_forage_attempt = 0
local expedite_left = true
local first_run = true
local can_do_bounty_cache = nil

local function msg(text)
    echo("-- " .. text)
end

local function err(text)
    echo("** " .. text)
end

local function is_bounty(types)
    if type(types) == "string" then types = { types } end
    local task = Bounty and Bounty.task or ""
    for _, t in ipairs(types) do
        local pat = bounty_patterns[t]
        if pat and Regex.test(task, pat) then return true end
    end
    return false
end

local function go2(room)
    if not room or room == "" then return end
    local current = Map.current_room()
    if current and tostring(current) == tostring(room) then return end
    Script.run("go2", tostring(room))
end

local function go2_tag(tag)
    -- Find nearest room with tag relative to rest room
    local rooms = Map.tags(tag) or {}
    if #rooms == 0 then err("No room found with tag: " .. tag); return end

    local current = Map.current_room()
    local best, best_dist = rooms[1], math.huge
    for _, rid in ipairs(rooms) do
        local path = Map.find_path(current, rid)
        if path and #path < best_dist then
            best = rid
            best_dist = #path
        end
    end
    go2(best)
end

local function run_commands(commands)
    if not commands or #commands == 0 then return end
    for _, cmd in ipairs(commands) do
        if cmd:sub(1, 1) == ";" then
            local script_name = cmd:sub(2)
            Script.run(script_name)
        else
            fput(cmd)
        end
    end
end

local function run_scripts(scripts)
    for _, s in ipairs(scripts) do
        local parts = {}
        for word in s:gmatch("%S+") do parts[#parts+1] = word end
        local name = table.remove(parts, 1)
        Script.run(name, table.concat(parts, " "))
    end
end

local function run_loot_script()
    Script.run(settings.loot_script, "")
end

local function change_stance(stance)
    fput("stance " .. stance)
    waitrt()
end

local function should_rest()
    if GameState.health and GameState.max_health and GameState.health < (GameState.max_health * 0.5) then
        return true, "low health"
    end
    local mind_pct = GameState.mind_value or 0
    if mind_pct >= (settings.should_rest_mind or 100) then
        return true, "mind full"
    end
    return false, nil
end

local function should_hunt()
    local mind_pct = GameState.mind_value or 0
    if mind_pct > (settings.should_hunt_mind or 75) then return false end
    return true
end

local function can_turn_in()
    if not is_bounty({"success", "success_guard", "success_heirloom"}) then return false end
    local mind_pct = GameState.mind_value or 0
    if settings.enable_turn_in and mind_pct >= (settings.turn_in_percent or 95) then
        return true
    end
    return true -- always try to turn in when success
end

local function can_do_bounty()
    if can_do_bounty_cache ~= nil then return can_do_bounty_cache end

    if is_bounty({"success", "success_heirloom", "success_guard"}) then
        can_do_bounty_cache = true
    elseif is_bounty({"task_bandit"}) and settings.enable_bandit then
        can_do_bounty_cache = true
    elseif is_bounty({"task_search"}) and settings.enable_search then
        can_do_bounty_cache = true
    elseif is_bounty({"task_heirloom"}) and settings.enable_loot then
        can_do_bounty_cache = true
    elseif is_bounty({"task_forage"}) and settings.enable_forage then
        can_do_bounty_cache = true
    elseif is_bounty({"task_skin"}) and settings.enable_skin then
        can_do_bounty_cache = true
    elseif is_bounty({"task_dangerous", "task_provoked"}) and settings.enable_dangerous then
        can_do_bounty_cache = true
    elseif is_bounty({"task_cull"}) and settings.enable_cull then
        can_do_bounty_cache = true
    elseif is_bounty({"task_escort", "task_rescue"}) and settings.enable_rescue then
        can_do_bounty_cache = true
    else
        can_do_bounty_cache = false
    end

    return can_do_bounty_cache
end

--------------------------------------------------------------------------------
-- Task handlers
--------------------------------------------------------------------------------

local function get_bounty()
    go2_tag("advguild")
    waitrt()

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if npc.name:lower():find("taskmaster") then taskmaster = npc; break end
    end

    if not taskmaster then
        err("Failed to find taskmaster")
        return
    end

    put("ask #" .. taskmaster.id .. " for bounty")
    local result = matchtimeout(5,
        "protective escort", "creature problem", "local gem dealer",
        "local furrier", "lost heirloom", "local healer", "local herbalist",
        "local alchemist", "local resident", "bandit problem",
        "I'm kind of busy", "don't seem to have any",
        "Come back in about"
    )

    if result and result:find("Come back in about") then
        local mins = result:match("about (%d+) minute") or "1"
        msg("Cooldown: " .. mins .. " minutes")
    end

    can_do_bounty_cache = nil
end

local function remove_bounty()
    if is_bounty({"none"}) then return end

    go2_tag("advguild")

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if npc.name:lower():find("taskmaster") then taskmaster = npc; break end
    end

    if not taskmaster then err("Failed to find taskmaster"); return end

    msg("Removing bounty in 5 seconds...")
    pause(5)

    put("ask " .. taskmaster.noun .. " about remove")
    matchtimeout(5, "want to be removed", "have removed you", "Trying to sneak")
    put("ask " .. taskmaster.noun .. " about remove")
    matchtimeout(5, "have removed you")

    can_do_bounty_cache = nil
end

local function turn_in()
    if is_bounty({"success_guard"}) then
        go2_tag("advguard")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name:lower():find("guard") or npc.name:lower():find("sergeant") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    end

    go2_tag("advguild")

    local npcs = GameObj.npcs()
    local taskmaster = nil
    for _, npc in ipairs(npcs) do
        if npc.name:lower():find("taskmaster") then taskmaster = npc; break end
    end

    if taskmaster then
        put("ask " .. taskmaster.noun .. " about bounty")
        local result = matchtimeout(5, "done with that assignment", "bounty points")
        if result and result:find("bounty points") then
            local points, xp, silver = result:match("(%d+) bounty points?, (%d+) experience points, and (%d+) silver")
            if points then
                msg("Finished task (" .. points .. " pts, " .. xp .. " exp, " .. silver .. " silver)")
            end
        end
    end

    run_loot_script()
    can_do_bounty_cache = nil
end

local function talk_to_npc()
    if is_bounty({"help_creature", "help_resident", "help_heirloom", "success_guard"}) then
        go2_tag("advguard")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name:lower():find("guard") or npc.name:lower():find("sergeant") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    elseif is_bounty({"help_bandit"}) and settings.enable_bandit then
        go2_tag("advguard")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name:lower():find("guard") or npc.name:lower():find("sergeant") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    elseif is_bounty({"help_furrier"}) then
        go2_tag("furrier")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if npc.name:lower():find("furrier") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    elseif is_bounty({"help_herbalist"}) then
        go2_tag("herbalist")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if Regex.test(npc.name, "herbalist|healer|alchemist") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    elseif is_bounty({"help_gemdealer"}) then
        go2_tag("gemshop")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if Regex.test(npc.name, "gem dealer|jeweler|clerk") then
                fput("ask " .. npc.noun .. " about bounty")
                break
            end
        end
    end
end

local function task_forage()
    local task = Bounty and Bounty.task or ""
    local herb = task:match("requires (?:a|an|some) (.+) found") or "unknown herb"
    local count = tonumber(task:match("retrieve (%d+)")) or 1

    msg("Foraging for " .. count .. " " .. herb)

    -- Find forage rooms
    herb = herb:gsub("^some ", ""):gsub("^a ", ""):gsub("^an ", "")
    local herb_rooms = Map.tags(herb) or {}
    if #herb_rooms == 0 then
        herb_rooms = Map.tags(herb:gsub("s$", "")) or {}
    end

    if #herb_rooms == 0 then
        msg("No forage rooms found for: " .. herb)
        return
    end

    -- Sort by distance
    local current = Map.current_room()
    local sorted = {}
    for _, rid in ipairs(herb_rooms) do
        local path = Map.find_path(current, rid)
        if path then sorted[#sorted+1] = { id = rid, dist = #path } end
    end
    table.sort(sorted, function(a, b) return a.dist < b.dist end)

    run_commands(settings.pre_forage_commands)

    local foraged = 0
    for _, room_info in ipairs(sorted) do
        if foraged >= count then break end

        go2(room_info.id)

        for attempt = 1, 10 do
            if foraged >= count then break end
            fput("kneel")
            waitrt()
            put("forage " .. herb)
            local result = matchtimeout(10,
                "and manage to find", "find no trace", "not even positive",
                "it could be", "Roundtime", "In order to forage"
            )
            waitrt()

            if result and result:find("manage to find") then
                fput("stow right"); fput("stow left")
                foraged = foraged + 1
                msg(foraged .. " of " .. count .. " " .. herb .. " foraged")
            elseif result and (result:find("find no trace") or result:find("not even positive") or result:find("it could be")) then
                break -- move to next room
            end
        end
        fput("stand")
    end

    run_commands(settings.post_forage_commands)
    fput("stand")

    last_forage_attempt = os.time()

    -- Turn in herbs if we have enough
    if foraged >= count then
        go2_tag("herbalist")
        local npcs = GameObj.npcs()
        for _, npc in ipairs(npcs) do
            if Regex.test(npc.name, "herbalist|healer|alchemist") then
                -- Give herbs from inventory
                fput("give " .. npc.noun)
                break
            end
        end
    end
end

local function task_search()
    msg("Searching for heirloom")
    run_commands(settings.pre_search_commands)

    -- Wander and search in the bounty area
    local visited = {}
    for attempt = 1, 200 do
        if not is_bounty({"task_search"}) then break end

        local npcs = GameObj.npcs()
        local hostile = false
        for _, npc in ipairs(npcs) do
            if npc.status ~= "dead" then hostile = true; break end
        end

        if not hostile then
            fput("kneel")
            waitrt()
            put("search")
            local result = matchtimeout(5, "intently search", "put your head")
            waitrt()
            fput("stand")

            if is_bounty({"task_found"}) then
                run_loot_script()
                break
            end
        end

        -- Wander to adjacent room
        local room = Room.current()
        if room and room.wayto then
            local exits = {}
            for dest, cmd in pairs(room.wayto) do
                if not visited[dest] then exits[#exits+1] = { dest = dest, cmd = cmd } end
            end
            if #exits == 0 then
                for dest, cmd in pairs(room.wayto) do
                    exits[#exits+1] = { dest = dest, cmd = cmd }
                end
            end
            if #exits > 0 then
                local choice = exits[math.random(#exits)]
                visited[choice.dest] = true
                move(choice.cmd)
            else break end
        else break end
    end

    run_commands(settings.post_search_commands)
end

local function rest_goto()
    if in_rest_area then return end
    if settings.rest_room and settings.rest_room ~= "" then
        go2(settings.rest_room)
    end
end

local function rest_enter()
    if in_rest_area then return end
    run_commands(settings.rest_in_commands)
    in_rest_area = true
end

local function rest_exit()
    if not in_rest_area then return end
    run_commands(settings.rest_out_commands)
    in_rest_area = false
end

local function rest_run_scripts()
    rest_exit()
    run_scripts(settings.rest_scripts)
end

--------------------------------------------------------------------------------
-- Setup (terminal-based)
--------------------------------------------------------------------------------

local function show_setup()
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
    if settings.locations then
        for name, loc in pairs(settings.locations) do
            respond("  " .. name .. ": room=" .. (loc.room or "?") .. " targets=" .. table.concat(loc.targets or {}, ","))
        end
    end
    respond("")
    respond("Hunt thresholds: mind<=" .. settings.should_hunt_mind .. " mana>=" .. settings.should_hunt_mana .. " spirit>=" .. settings.should_hunt_spirit)
    respond("Rest thresholds: mind>=" .. settings.should_rest_mind .. " mana<=" .. settings.should_rest_mana)
    respond("===\n")
end

local function show_help()
    respond("\nSBounty v" .. VERSION .. " by spiffyjr")
    respond("Usage: ;sbounty [option]")
    respond("")
    respond("  (no args)   — run bounty loop")
    respond("  setup       — show settings")
    respond("  help        — show this help")
    respond("  forage      — run forage task")
    respond("  bandits     — run bandit task")
    respond("  check       — check if current bounty is doable")
    respond("")
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local input = Script.vars[1] or ""

if input:match("^setup$") then
    show_setup()
    return
elseif input:match("^help$") then
    show_help()
    return
elseif input:match("^forage$") then
    task_forage()
    return
elseif input:match("^check$") then
    echo("Can do bounty: " .. tostring(can_do_bounty()))
    return
end

-- Death monitor
Script.at_exit(function()
    -- cleanup
end)

echo("SBounty v" .. VERSION .. " starting bounty loop")

while true do
    if GameState.dead then break end

    talk_to_npc()

    if can_do_bounty() then
        if is_bounty({"task_search"}) then
            task_search()
        elseif is_bounty({"task_forage"}) and os.time() >= last_forage_attempt + settings.forage_retry_delay then
            task_forage()
        end
    end

    if is_bounty({"success_heirloom"}) then
        -- Turn in heirloom to guard
        turn_in()
    end

    if can_turn_in() then
        turn_in()
    else
        if not can_do_bounty() and not is_bounty({"success", "success_heirloom", "success_guard"}) then
            remove_bounty()
            get_bounty()
        elseif should_hunt() and not should_rest() then
            first_run = false
            rest_exit()
            run_commands(settings.hunt_pre_commands)

            -- Start hunting
            if can_do_bounty() and is_bounty({"task_cull", "task_dangerous", "task_heirloom", "task_rescue", "task_skin"}) then
                msg("Starting bounty hunt")
                -- In Lich5, starts the external hunter script with location data
                -- In Revenant, delegate to bigshot or similar
                if Script.exists(settings.hunter) then
                    Script.run(settings.hunter)
                else
                    msg("Hunter script '" .. settings.hunter .. "' not found. Waiting.")
                end
            else
                msg("No actionable bounty — getting new bounty")
                get_bounty()
            end

            change_stance("defensive")
            run_loot_script()
        else
            -- Rest
            local resting, reason = should_rest()
            rest_goto()
            if resting then
                rest_run_scripts()
                rest_goto()
            end
            rest_enter()

            while true do
                local still_resting, rest_reason = should_rest()
                if can_turn_in() then break end
                if not still_resting and should_hunt() then break end
                if not can_do_bounty() then break end
                msg("Resting" .. (rest_reason and (": " .. rest_reason) or ""))
                pause(settings.rest_sleep_interval)
            end

            rest_exit()
        end
    end

    pause(0.5)
end
