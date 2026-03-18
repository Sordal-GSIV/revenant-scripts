--- @revenant-script
--- name: foreach
--- version: 2.1.0
--- author: Elanthia-Online
--- contributors: LostRanger
--- game: gs
--- description: Iterate commands over container items or targets with flexible filtering
--- tags: utility,inventory
--- @lic-certified: complete 2026-03-18

--------------------------------------------------------------------------------
-- ForEach - Execute commands for matching items in containers
--
-- Usage:
--   ;foreach [OPTIONS] [ATTR=]VALUE in/on/under/behind CONTAINER[,CONTAINER,...][; command; command; ...]
--   ;foreach help               - Full help
--
-- Examples:
--   ;foreach box in inv; move to locker
--   ;foreach gem in cloak; get item; appraise item; put item in container
--   ;foreach gem in backpack,cloak; get item; sell item
--   ;foreach noun=sword in locker; get item; put item in backpack
--   ;foreach gem in backpack; stash item
--   ;foreach gem in backpack; giveitem Player
--
-- ATTRIBUTE: type (default), noun, name, fullname, quick, sellable
-- TARGETS: any container, INV, FASTINV/QINV, WORN, FLOOR, GROUND, ROOM, DESC, LOOT, LOCKER, PREVIOUS/LAST
-- OPTIONS: UNIQUE, FIRST n, AFTER n, SORTED, NOUNSORTED, REVERSED, [UN]MARKED, [UN]REGISTERED
-- PREPOSITIONS: in, on, under, behind
-- COMMANDS: game commands, MOVE, STASH, GIVEITEM, RETURN, UNMARK, TRASH, ECHO, PAUSE, SLEEP, WAIT*
-- PREFIX: ! before a command skips wait-for-response for speed
--------------------------------------------------------------------------------

local VERSION   = "2.1.0"
local HELP_URL  = "https://github.com/dewiniaid/gs4-lich-scripts/blob/master/Foreach.md"

--------------------------------------------------------------------------------
-- Persistent state across runs (module-level)
--------------------------------------------------------------------------------

-- Store previous matcher results for PREVIOUS/LAST target
local _previous_results = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function str_lower(s)
    return s and string.lower(s) or ""
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if string.lower(v) == string.lower(val) then return true end
    end
    return false
end

local function split(str, sep)
    local parts = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(parts, part:match("^%s*(.-)%s*$"))
    end
    return parts
end

local function str_trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function str_starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

--- Check if `input` autocompletes to the command described by `spec`.
--- spec format: "dr|op" means minimum prefix is "dr", full command is "drop".
local function autocompletes_to(input, spec)
    local prefix, rest = spec:match("^(.-)|(.*)")
    if not prefix then return input == spec end
    local full = prefix .. rest
    return #input >= #prefix and str_starts_with(full, string.lower(input))
end

--- Find lootsacks from Vars (lootsack, lootsack1, lootsack2, ...)
local function find_sacks()
    local sacks = {}
    local ix = nil
    while true do
        local var_name = "lootsack" .. (ix or "")
        if ix == nil then ix = 0 end
        ix = ix + 1
        local name = Vars and Vars[var_name]
        if not name or str_trim(name) == "" then
            return sacks
        end
        name = str_trim(name)
        -- Strip leading "my " if present
        local stripped = name:match("^[Mm][Yy]%s+(.+)$")
        if stripped then name = stripped end
        -- Find matching inventory item
        local inv = GameObj.inv() or {}
        local sack = nil
        for _, obj in ipairs(inv) do
            if string.find(str_lower(obj.name or ""), str_lower(name), 1, true) or
               string.find(str_lower(obj.noun or ""), str_lower(name), 1, true) then
                sack = obj
                break
            end
        end
        if sack then
            table.insert(sacks, sack)
        else
            echo("warning: failed to find " .. var_name .. " '" .. name .. "'")
        end
    end
end

--------------------------------------------------------------------------------
-- Item filter builder
--------------------------------------------------------------------------------

local function build_filter(attr, value)
    if not value or value == "" then
        return function() return true end
    end

    attr = str_lower(attr or "type")

    -- Check for regex pattern /pattern/
    local regex_body = string.match(value, "^/(.+)/$")
    if regex_body then
        -- Use Lua pattern matching (case insensitive via lowering)
        local pattern = string.lower(regex_body)
        if attr == "type" or attr == "t" then
            return function(item)
                local t = str_lower(item.type or "")
                return string.find(t, pattern) ~= nil
            end
        elseif attr == "name" or attr == "m" then
            return function(item)
                return string.find(str_lower(item.name or ""), pattern) ~= nil
            end
        elseif attr == "fullname" or attr == "f" or attr == "quick" or attr == "q" then
            return function(item)
                return string.find(str_lower(item.full_name or item.name or ""), pattern) ~= nil
            end
        elseif attr == "noun" or attr == "n" then
            return function(item)
                return string.find(str_lower(item.noun or ""), pattern) ~= nil
            end
        elseif attr == "sellable" or attr == "s" then
            return function(item)
                local s = str_lower(item.sellable or "")
                return string.find(s, pattern) ~= nil
            end
        end
    end

    -- Wildcard/exact matching
    local values = split(value, ",")

    -- Convert wildcards to patterns
    local patterns = {}
    for _, v in ipairs(values) do
        local escaped = string.gsub(str_lower(str_trim(v)), "([%(%)%.%%%+%-%[%]%^%$%?])", "%%%1")
        escaped = string.gsub(escaped, "%*", ".*")
        table.insert(patterns, escaped)
    end

    local function matches_any(str)
        str = str_lower(str or "")
        for _, pat in ipairs(patterns) do
            if attr == "quick" or attr == "q" then
                if string.find(str, pat) then return true end
            else
                if string.match(str, "^" .. pat .. "$") then return true end
            end
        end
        return false
    end

    if attr == "type" or attr == "t" then
        -- Handle none/unknown type
        if string.match(str_lower(value), "^none$") or string.match(str_lower(value), "^unknown$") then
            return function(item)
                return (item.type or "") == ""
            end
        end
        return function(item)
            local types = split(item.type or "", ",")
            for _, t in ipairs(types) do
                if matches_any(t) then return true end
            end
            return false
        end
    elseif attr == "sellable" or attr == "s" then
        if string.match(str_lower(value), "^none$") or string.match(str_lower(value), "^unknown$") then
            return function(item)
                return (item.sellable or "") == ""
            end
        end
        return function(item)
            local types = split(item.sellable or "", ",")
            for _, t in ipairs(types) do
                if matches_any(t) then return true end
            end
            return false
        end
    elseif attr == "name" or attr == "m" then
        return function(item) return matches_any(item.name) end
    elseif attr == "fullname" or attr == "f" or attr == "quick" or attr == "q" then
        return function(item) return matches_any(item.full_name or item.name) end
    elseif attr == "noun" or attr == "n" then
        return function(item) return matches_any(item.noun) end
    end

    return function() return true end
end

--------------------------------------------------------------------------------
-- Item collection from various sources
--------------------------------------------------------------------------------

local function collect_from_container(container_name, preposition)
    local items = {}
    preposition = preposition or "in"

    -- Try to find container in inventory
    local inv = GameObj.inv() or {}
    local container = nil

    for _, obj in ipairs(inv) do
        if string.find(str_lower(obj.name or ""), str_lower(container_name), 1, true) or
           string.find(str_lower(obj.noun or ""), str_lower(container_name), 1, true) then
            container = obj
            break
        end
    end

    -- Also check loot/room for containers on tables, etc.
    if not container then
        local loot = GameObj.loot() or {}
        for _, obj in ipairs(loot) do
            if string.find(str_lower(obj.name or ""), str_lower(container_name), 1, true) or
               string.find(str_lower(obj.noun or ""), str_lower(container_name), 1, true) then
                container = obj
                break
            end
        end
    end
    if not container then
        local room_desc = GameObj.room_desc() or {}
        for _, obj in ipairs(room_desc) do
            if string.find(str_lower(obj.name or ""), str_lower(container_name), 1, true) or
               string.find(str_lower(obj.noun or ""), str_lower(container_name), 1, true) then
                container = obj
                break
            end
        end
    end

    if container and container.contents then
        for _, item in ipairs(container.contents) do
            table.insert(items, { item = item, container = container, container_key = container.id })
        end
    elseif container then
        -- Container found but no contents loaded; try looking
        fput("look " .. preposition .. " #" .. container.id)
        pause(0.5)
        if container.contents then
            for _, item in ipairs(container.contents) do
                table.insert(items, { item = item, container = container, container_key = container.id })
            end
        end
    else
        echo("Container '" .. container_name .. "' was not found.")
    end

    return items
end

local function collect_from_inventory()
    local items = {}
    local inv = GameObj.inv() or {}
    for _, obj in ipairs(inv) do
        if obj.contents then
            for _, item in ipairs(obj.contents) do
                table.insert(items, { item = item, container = obj, container_key = obj.id })
            end
        end
    end
    return items
end

local function collect_from_worn()
    local items = {}
    local inv = GameObj.inv() or {}
    for _, item in ipairs(inv) do
        table.insert(items, { item = item, container = nil, container_key = "_worn" })
    end
    return items
end

local function collect_from_ground()
    local items = {}
    local loot = GameObj.loot() or {}
    for _, item in ipairs(loot) do
        table.insert(items, { item = item, container = nil, container_key = "_ground" })
    end
    return items
end

local function collect_from_desc()
    local items = {}
    local room_desc = GameObj.room_desc() or {}
    for _, item in ipairs(room_desc) do
        table.insert(items, { item = item, container = nil, container_key = "_desc" })
    end
    return items
end

local function collect_from_room()
    local items = {}
    for _, e in ipairs(collect_from_ground()) do table.insert(items, e) end
    for _, e in ipairs(collect_from_desc()) do table.insert(items, e) end
    return items
end

local function collect_from_loot(preposition)
    local items = {}
    preposition = preposition or "in"
    local loot = GameObj.loot() or {}
    for _, obj in ipairs(loot) do
        if obj.contents then
            for _, item in ipairs(obj.contents) do
                table.insert(items, { item = item, container = obj, container_key = obj.id })
            end
        end
    end
    return items
end

local function collect_from_locker()
    local items = {}
    -- Open locker first
    put("open locker")
    local line = waitforre("Your locker is currently holding|already open|What were you referring to")
    local opened = false
    if string.find(line or "", "currently holding") then
        opened = true
        before_dying(function()
            waitrt()
            put("close locker")
        end)
    end

    -- Scan locker containers (premium locker)
    local loot = GameObj.loot() or {}
    local premium_containers = {
        ["armor stand"] = "on",
        ["weapon rack"] = "on",
        ["magical item bin"] = "in",
        ["clothing wardrobe"] = "in",
        ["deep chest"] = "in",
    }

    local found_premium = 0
    for _, obj in ipairs(loot) do
        local prep = premium_containers[str_lower(obj.full_name or "")]
        if prep then
            found_premium = found_premium + 1
            fput("look " .. prep .. " #" .. obj.id)
            pause(0.3)
            if obj.contents then
                for _, item in ipairs(obj.contents) do
                    table.insert(items, { item = item, container = obj, container_key = obj.id })
                end
            end
        end
    end

    -- Non-premium: scan items directly in room
    if found_premium == 0 then
        for _, obj in ipairs(loot) do
            if obj.contents then
                for _, item in ipairs(obj.contents) do
                    table.insert(items, { item = item, container = obj, container_key = obj.id })
                end
            end
        end
    end

    return items
end

local function collect_from_previous()
    if not _previous_results or #_previous_results == 0 then
        echo("No previous run data is available.")
        return {}
    end
    -- Return a copy
    local items = {}
    for _, entry in ipairs(_previous_results) do
        table.insert(items, {
            item = entry.item,
            container = entry.container,
            container_key = entry.container_key,
        })
    end
    return items
end

--------------------------------------------------------------------------------
-- Command execution
--------------------------------------------------------------------------------

--- Replace placeholders in a command string.
--- Uses word-boundary-aware replacement (NOT Lua balanced match %b).
--- Placeholders: ITEM/item, NAME/name, NOUN/noun, CONTAINER/container
---
--- The Ruby original uses \b (word boundary) regex. In Lua we use the %f[]
--- frontier pattern to simulate word boundaries, matching whole words only.
--- This prevents "name" from matching inside "container".
local function replace_placeholders(cmd, item, container)
    local ref = "#" .. item.id
    local container_ref = container and ("#" .. container.id) or ""

    -- Helper: replace whole-word occurrences of `word` with `repl` (case-sensitive)
    -- Uses %f[%a] (transition to alpha) and %f[%A] (transition to non-alpha) as boundaries
    local function replace_word(s, word, repl)
        return string.gsub(s, "%f[%a]" .. word .. "%f[%A]", repl)
    end

    -- Replace longer tokens first to avoid partial matches
    cmd = replace_word(cmd, "CONTAINER", container_ref)
    cmd = replace_word(cmd, "container", container_ref)
    cmd = replace_word(cmd, "ITEM", ref)
    cmd = replace_word(cmd, "item", ref)
    cmd = replace_word(cmd, "NAME", item.name or "")
    cmd = replace_word(cmd, "name", item.name or "")
    cmd = replace_word(cmd, "NOUN", item.noun or "")
    cmd = replace_word(cmd, "noun", item.noun or "")

    return cmd
end

local function execute_command(cmd, item, container, container_key, opts)
    local immediate = false

    -- Check for ! prefix (immediate mode, skip wait-for-response)
    if cmd:sub(1, 1) == "!" then
        immediate = true
        cmd = cmd:sub(2)
    end

    -- Replace placeholders
    cmd = replace_placeholders(cmd, item, container)

    -- Convenience commands
    local lower_cmd = str_lower(cmd)

    if string.find(lower_cmd, "^waitcastrt%?$") then
        if checkcastrt() > 0 then waitcastrt() end
    elseif string.find(lower_cmd, "^waitcastrt") then
        waitcastrt()
    elseif string.find(lower_cmd, "^waitrt%?$") then
        if checkrt() > 0 then waitrt() end
    elseif string.find(lower_cmd, "^waitrt") then
        waitrt()
    elseif string.find(lower_cmd, "^waitre ") then
        local pattern = string.match(cmd, "^[Ww][Aa][Ii][Tt][Rr][Ee]%s+(.+)$")
        if pattern then
            local inner = string.match(pattern, "^/(.+)/$")
            if inner then pattern = inner end
            local re = Regex.new(pattern)
            while true do
                local line = get()
                if line and re:test(line) then break end
            end
        end
    elseif string.find(lower_cmd, "^pause$") then
        echo("Paused. Unpause to continue.")
        pause(999999)
    elseif string.find(lower_cmd, "^sleep ") then
        local secs = tonumber(string.match(cmd, "sleep (%d+%.?%d*)"))
        if secs then pause(secs) end
    elseif string.find(lower_cmd, "^echo ") then
        local msg = string.match(cmd, "^echo (.+)$")
        if msg then echo(msg) end
    elseif string.find(lower_cmd, "^waitfor ") then
        local phrase = string.match(cmd, "^waitfor (.+)$")
        if phrase then waitfor(phrase) end
    elseif string.find(lower_cmd, "^waitmana ") or string.find(lower_cmd, "^waitmp ") then
        local n = tonumber(string.match(cmd, "%d+"))
        if n then
            echo("Waiting for " .. n .. " mana")
            wait_until(function() return GameState.mana >= n end)
        end
    elseif string.find(lower_cmd, "^waithealth ") or string.find(lower_cmd, "^waithp ") then
        local n = tonumber(string.match(cmd, "%d+"))
        if n then
            wait_until(function() return GameState.health >= n end)
        end
    elseif string.find(lower_cmd, "^waitspirit ") or string.find(lower_cmd, "^waitsp ") then
        local n = tonumber(string.match(cmd, "%d+"))
        if n then
            wait_until(function() return GameState.spirit >= n end)
        end
    elseif string.find(lower_cmd, "^waitstamina ") or string.find(lower_cmd, "^waitst ") then
        local n = tonumber(string.match(cmd, "%d+"))
        if n then
            wait_until(function() return GameState.stamina >= n end)
        end
    elseif string.find(lower_cmd, "^_remget ") then
        -- Internal: get item from container, or remove if worn
        local what = string.match(cmd, "^_remget (.+)$")
        if what then
            if container_key == "_worn" then
                fput("remove " .. what)
            else
                fput("get " .. what)
            end
        end
    elseif string.find(lower_cmd, "^_drag ") then
        -- Internal: drag item to destination
        local what, where = string.match(cmd, "^_drag (.+) (.+)$")
        if what and where then
            if immediate then
                put("get " .. what)
                put("drop " .. what)
            else
                fput("get " .. what)
                fput("drop " .. what)
            end
        end
    elseif string.find(lower_cmd, "^return") then
        -- Return item to original container/worn position
        local ref = "#" .. item.id
        if container_key == "_worn" then
            fput("wear " .. ref)
        elseif container_key == "_ground" or container_key == "_desc" then
            fput("place " .. ref)
        elseif container then
            fput("put " .. ref .. " in #" .. container.id)
        else
            echo("Cannot return item - no container info available")
        end
    elseif string.find(lower_cmd, "^giveitem") then
        -- Give item to player and wait for acceptance
        local who = string.match(cmd, "^giveitem%s+[Tt]?[Oo]?%s*(.+)$")
        if not who then
            who = string.match(cmd, "^giveitem%s+(.+)$")
        end
        if not who or who == "" then
            echo("GIVEITEM requires a target character.")
            return
        end
        who = str_trim(who)
        -- Capitalize first letter
        who = who:sub(1, 1):upper() .. who:sub(2):lower()

        -- Autocomplete player name from PCs in room
        local pcs = GameObj.pcs() or {}
        local exact = nil
        local matches = {}
        for _, pc in ipairs(pcs) do
            if pc.noun == who then
                exact = pc
                break
            end
            if str_starts_with(pc.noun, who) then
                table.insert(matches, pc)
            end
        end
        if exact then
            who = exact.noun
        elseif #matches == 1 then
            who = matches[1].noun
        elseif #matches > 1 then
            local names = {}
            for _, m in ipairs(matches) do table.insert(names, m.noun) end
            echo("GIVEITEM: Multiple PCs found matching '" .. who .. "': " .. table.concat(names, ", "))
            return
        elseif #matches == 0 and #pcs > 0 then
            echo("GIVEITEM: No PCs found matching '" .. who .. "'.")
            return
        end

        local ref = "#" .. item.id
        if immediate then
            put("give " .. ref .. " to " .. who)
        else
            fput("give " .. ref .. " to " .. who)
        end
        -- Wait for acceptance
        waitforre(who .. ".*has accepted your offer")
    elseif string.find(lower_cmd, "^stash") then
        -- Cycle through lootsacks trying each until one accepts the item
        local what = string.match(cmd, "^stash%s+(.+)$") or ("#" .. item.id)
        local lootsacks = opts._lootsacks
        if not lootsacks or #lootsacks == 0 then
            echo("No lootsacks configured. Set with ;vars set lootsack=container")
            return
        end

        local success = false
        for attempt = 1, #lootsacks do
            local sack = lootsacks[1]
            -- Verify sack still exists in inventory
            local inv = GameObj.inv() or {}
            local found = false
            for _, obj in ipairs(inv) do
                if obj.id == sack.id then found = true; break end
            end
            if found then
                if immediate then
                    put("put " .. what .. " in #" .. sack.id)
                else
                    fput("put " .. what .. " in #" .. sack.id)
                end
                -- Check result
                local result = waitforre("won't fit|You put|You place|You tuck|You pop|You absent")
                if result and not string.find(result, "won't fit") then
                    success = true
                    break
                end
            end
            -- Rotate sacks: move first to end
            local first = table.remove(lootsacks, 1)
            table.insert(lootsacks, first)
        end

        if not success then
            echo("All lootsacks are full, pausing script.")
            pause(999999)
        end
    elseif string.find(lower_cmd, "^move ") or string.find(lower_cmd, "^fastmove ") or string.find(lower_cmd, "^mv ") then
        -- MOVE [item] TO container
        local fast = string.find(lower_cmd, "^fast") ~= nil
        local what, where = string.match(cmd, "[MmFf]%w+%s+(.-)%s+[Tt]o%s+(.+)")
        if not what or what == "" then
            what = "#" .. item.id
            where = string.match(cmd, "%w+%s+[Tt]o%s+(.+)")
        end
        if where then
            local lower_where = str_lower(where)
            if lower_where == "ground" or lower_where == "floor" then
                if immediate or fast then
                    put("get " .. what)
                    put("drop " .. what)
                else
                    fput("get " .. what)
                    fput("drop " .. what)
                end
            else
                -- Open locker if moving to locker
                if lower_where == "locker" then
                    put("open locker")
                    waitforre("Your locker is currently holding|already open|What were you referring to")
                end
                if immediate or fast then
                    put("get " .. what)
                    put("put " .. what .. " in " .. where)
                else
                    fput("get " .. what)
                    fput("put " .. what .. " in " .. where)
                end
            end
        end
    elseif string.find(lower_cmd, "^unmark ") then
        local what = string.match(cmd, "unmark (.+)")
        fput("mark " .. what .. " remove")
    elseif string.find(lower_cmd, "^trash ") then
        local what = string.match(cmd, "trash (.+)") or ("#" .. item.id)
        fput("get " .. what)
        fput("trash " .. what)
    elseif string.find(lower_cmd, "^locker$") then
        -- Shortcut: "locker" alone means "move to locker"
        local ref = "#" .. item.id
        fput("get " .. ref)
        fput("put " .. ref .. " in locker")
    else
        -- Generic command
        if immediate then
            put(cmd)
        else
            fput(cmd)
        end
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help(full)
    respond("")
    respond("ForEach v" .. VERSION .. " - Execute commands for matching items")
    respond("")
    respond("Usage:")
    respond("  ;foreach [OPTIONS] [ATTR=]VALUE in/on/under/behind <TARGETS>[; command; command; ...]")
    respond("")
    if full then
        respond("ATTRIBUTE: type (default), noun, name, fullname, quick, sellable")
        respond("  Shorthand: t, n, m, f, q, s")
        respond("  'quick' is equivalent to 'fullname' with automatic wildcards.")
        respond("")
        respond("VALUE: what the attribute must match. Wildcards (*) supported. Multiple values separated by commas.")
        respond("PATTERN: /regex/ for regex matching (always case-insensitive)")
        respond("")
        respond("TARGETS: comma-separated list of containers or:")
        respond("  INV/INVENTORY      - All containers in inventory")
        respond("  FASTINV/QINV       - Like INV but uses cached data (same in Revenant)")
        respond("  WORN               - Worn items")
        respond("  FLOOR/GROUND       - Loot items on the room floor")
        respond("  ROOM               - All items in the room (floor + desc objects)")
        respond("  DESC               - Room description objects only")
        respond("  LOOT               - Contents of containers on the floor")
        respond("  LOCKER             - Contents of your locker (auto-opens/closes)")
        respond("  PREVIOUS/LAST      - Items from the previous run of foreach")
        respond("")
        respond("PREPOSITIONS: in, on, under, behind")
        respond("")
        respond("COMMANDS: any game command, or convenience shortcuts:")
        respond("  MOVE [item] TO <where>   - Get and put (also FASTMOVE for speed)")
        respond("  STASH [item]             - Put in lootsack(s), cycling if full")
        respond("  GIVEITEM <player>        - Give item and wait for acceptance")
        respond("  RETURN [item]            - Return item to original container/worn position")
        respond("  ECHO <message>           - Echo text")
        respond("  UNMARK [item]            - Unmark an item")
        respond("  TRASH [item]             - Trash an item")
        respond("  LOCKER                   - Shortcut for MOVE TO LOCKER")
        respond("  PAUSE                    - Pause script")
        respond("  SLEEP <seconds>          - Wait N seconds")
        respond("  WAITRT / WAITRT?         - Wait for roundtime (? only waits if in RT)")
        respond("  WAITCASTRT / WAITCASTRT? - Wait for cast roundtime")
        respond("  WAITFOR <phrase>         - Wait for game text")
        respond("  WAITRE <pattern>         - Wait for regex match in game output")
        respond("  WAITMANA/WAITMP <n>      - Wait for mana")
        respond("  WAITHEALTH/WAITHP <n>    - Wait for health")
        respond("  WAITSPIRIT/WAITSP <n>    - Wait for spirit")
        respond("  WAITSTAMINA/WAITST <n>   - Wait for stamina")
        respond("")
        respond("COMMAND PREFIX:")
        respond("  !command                 - Skip wait-for-response (faster, riskier)")
        respond("")
        respond("COMMAND AUTO-COMPLETION:")
        respond("  dr->drop, sel->sell, ap->appraise, reg->register, mk->mark, umk->unmark")
        respond("  ge->get, tak->take, r->read, l->look, ana->analyze, ins->inspect, loc->locker")
        respond("")
        respond("IMPLICIT GET/RETURN:")
        respond("  If first command is sell/drop/appraise/etc, 'get item' is auto-added.")
        respond("  If only command is appraise/register/mark/unmark, 'return' is auto-added.")
        respond("")
        respond("OPTIONS:")
        respond("  UNIQUE        - Only first of each name")
        respond("  FIRST n       - Only first n matches")
        respond("  AFTER n       - Skip first n matches (also SKIP n)")
        respond("  SORTED        - Sort alphabetically by full name")
        respond("  NOUNSORTED    - Sort by noun, then by full name")
        respond("  REVERSED      - Reverse iteration order")
        respond("  MARKED        - Only marked items")
        respond("  UNMARKED      - Only unmarked items")
        respond("  REGISTERED    - Only registered items")
        respond("  UNREGISTERED  - Only unregistered items")
        respond("")
        respond("SAFETY:")
        respond("  'ALL in inv' with commands requires explicit 'ALL' keyword to proceed.")
        respond("")
    else
        respond("Use ;foreach help for full documentation.")
    end
    respond("Documentation: " .. HELP_URL)
    respond("")
end

--------------------------------------------------------------------------------
-- Parse arguments
--------------------------------------------------------------------------------

local function parse_args(input)
    if not input or input == "" then return nil end

    -- Support multiple command separators: ; / |
    -- Detect which separator is used
    local filter_part, separator, commands_str
    -- Try semicolons first, then / then |
    for _, sep in ipairs({";", "/", "|"}) do
        local fp, cs = string.match(input, "^(.-)%s*%" .. sep .. "%s*(.*)$")
        if fp then
            -- Verify the filter part contains "in/on/under/behind" to avoid false splits
            if string.match(fp, "%s+[Ii][Nn]%s+") or
               string.match(fp, "%s+[Oo][Nn]%s+") or
               string.match(fp, "%s+[Uu][Nn][Dd][Ee][Rr]%s+") or
               string.match(fp, "%s+[Bb][Ee][Hh][Ii][Nn][Dd]%s+") or
               string.match(fp, "^[Ii][Nn]%s+") or
               string.match(fp, "^[Oo][Nn]%s+") then
                filter_part = fp
                separator = sep
                commands_str = cs
                break
            end
        end
    end
    if not filter_part then
        -- No separator found or no valid split; try whole input as filter
        filter_part = input
        separator = ";"
        commands_str = nil
    end

    -- Parse commands
    local commands = nil
    if commands_str and commands_str ~= "" then
        commands = split(commands_str, separator)
    end

    -- Parse options
    local opts = {
        unique     = false,
        first      = nil,
        after      = nil,
        sorted     = false,   -- false, true (name), or "noun"
        reversed   = false,
        marked     = nil,     -- nil=any, true=only marked, false=only unmarked
        registered = nil,     -- nil=any, true=only registered, false=only unregistered
    }

    -- Extract options from filter (case-insensitive via character classes or lower())
    while true do
        local match = string.match(filter_part, "^%s*[Uu][Nn][Ii][Qq][Uu][Ee]%s+(.+)$")
        if match then opts.unique = true; filter_part = match; goto continue end

        match = string.match(filter_part, "^%s*[Rr][Ee][Vv][Ee][Rr][Ss][Ee][Dd]?%s+(.+)$")
        if match then opts.reversed = true; filter_part = match; goto continue end

        -- NOUNSORTED / NSORTED — sort by noun then name
        match = string.match(filter_part, "^%s*[Nn][Oo][Uu][Nn][Ss][Oo][Rr][Tt][Ee][Dd]?%s+(.+)$")
        if match then opts.sorted = "noun"; filter_part = match; goto continue end
        match = string.match(filter_part, "^%s*[Nn][Ss][Oo][Rr][Tt][Ee][Dd]?%s+(.+)$")
        if match then opts.sorted = "noun"; filter_part = match; goto continue end

        -- SORTED — sort by full name
        match = string.match(filter_part, "^%s*[Ss][Oo][Rr][Tt][Ee][Dd]?%s+(.+)$")
        if match then opts.sorted = true; filter_part = match; goto continue end

        -- MARKED / UNMARKED
        match = string.match(filter_part, "^%s*[Uu][Nn][Mm][Aa][Rr][Kk][Ee][Dd]?%s+(.+)$")
        if match then opts.marked = false; filter_part = match; goto continue end
        match = string.match(filter_part, "^%s*[Mm][Aa][Rr][Kk][Ee][Dd]?%s+(.+)$")
        if match then opts.marked = true; filter_part = match; goto continue end

        -- REGISTERED / UNREGISTERED
        match = string.match(filter_part, "^%s*[Uu][Nn][Rr][Ee][Gg][Ii][Ss][Tt][Ee][Rr][Ee][Dd]?%s+(.+)$")
        if match then opts.registered = false; filter_part = match; goto continue end
        match = string.match(filter_part, "^%s*[Rr][Ee][Gg][Ii][Ss][Tt][Ee][Rr][Ee][Dd]?%s+(.+)$")
        if match then opts.registered = true; filter_part = match; goto continue end

        local n, rest = string.match(filter_part, "^%s*[Ff][Ii][Rr][Ss][Tt]%s+(%d+)%s+(.+)$")
        if n then opts.first = tonumber(n); filter_part = rest; goto continue end

        n, rest = string.match(filter_part, "^%s*[Aa][Ff][Tt][Ee][Rr]%s+(%d+)%s+(.+)$")
        if not n then n, rest = string.match(filter_part, "^%s*[Ss][Kk][Ii][Pp]%s+(%d+)%s+(.+)$") end
        if n then opts.after = tonumber(n); filter_part = rest; goto continue end

        n, rest = string.match(filter_part, "^%s*(%d+)%s+(.+)$")
        if n and not opts.first then opts.first = tonumber(n); filter_part = rest; goto continue end

        break
        ::continue::
    end

    -- Parse attribute=value and preposition and target
    -- Support: in, on, under, behind
    local attr, value, preposition, target

    -- Helper: try to split filter_part around a preposition word
    -- Returns: before, preposition, after  or nil if no preposition found
    local function find_preposition_split(s)
        -- Try each preposition, matching as a whole word boundary
        for _, prep in ipairs({"behind", "under", "on", "in"}) do
            -- Match: stuff <space> prep <space> stuff
            -- Use case-insensitive manual check
            local lower_s = str_lower(s)
            local pat = "%s+" .. prep .. "%s+"
            local start, finish = string.find(lower_s, pat)
            if start then
                local before = str_trim(s:sub(1, start - 1))
                local after = str_trim(s:sub(finish + 1))
                if after ~= "" then
                    return before, prep, after
                end
            end
            -- Also match at the start: "in stuff"
            pat = "^%s*" .. prep .. "%s+"
            start, finish = string.find(lower_s, pat)
            if start then
                local after = str_trim(s:sub(finish + 1))
                if after ~= "" then
                    return "", prep, after
                end
            end
        end
        return nil
    end

    local before_prep, found_prep, after_prep = find_preposition_split(filter_part)

    if before_prep then
        preposition = found_prep
        target = after_prep

        if before_prep ~= "" then
            -- Check if before_prep has attr=value format
            local a, v = string.match(before_prep, "^(%w+)=(.+)$")
            if a then
                attr = a
                value = v
            else
                attr = "type"
                value = before_prep
            end
        else
            attr = nil
            value = nil
        end
    end

    if not target then return nil end

    -- Check for ALL keyword (safety for inv commands)
    local explicit_all = false
    if attr == "type" and value and string.match(str_lower(value), "^all$") then
        explicit_all = true
        attr = nil
        value = nil
    end

    preposition = str_lower(preposition or "in")

    return {
        attr         = attr,
        value        = value,
        target       = str_trim(target),
        preposition  = preposition,
        commands     = commands,
        opts         = opts,
        explicit_all = explicit_all,
    }
end

--------------------------------------------------------------------------------
-- Command auto-completion and implicit GET/RETURN processing
--------------------------------------------------------------------------------

local AUTOCOMPLETE_VERBS = {
    "dr|op", "plac|e", "sel|l", "ap|praise", "reg|ister",
    "ge|t", "tak|e", "r|ead", "l|ook", "ana|lyze", "ins|pect",
    "loc|ker", "ma|rk", "unma|rk",
}

-- Additional shorthand aliases that aren't prefix-based
local COMMAND_ALIASES = {
    mk  = "mark",
    umk = "unmark",
}

local function process_commands(commands, has_filter_value, explicit_all, target_str)
    if not commands or #commands == 0 then return nil end

    -- Check for stash command to pre-load lootsacks
    local lootsacks = nil

    local new_commands = {}
    local count = #commands

    for ix, command in ipairs(commands) do
        -- Preserve ! prefix
        local prefix = ""
        if command:sub(1, 1) == "!" then
            prefix = "!"
            command = command:sub(2)
        end

        if command == "" then
            count = count - 1
            goto next_cmd
        end

        -- Auto-complete first word of command
        local first_word, rest = string.match(command, "^(%w+)(.*)$")
        if first_word then
            local fw_lower = string.lower(first_word)
            -- Check shorthand aliases first (mk->mark, umk->unmark)
            if COMMAND_ALIASES[fw_lower] then
                command = COMMAND_ALIASES[fw_lower] .. rest
                first_word = COMMAND_ALIASES[fw_lower]
            else
                for _, verb_spec in ipairs(AUTOCOMPLETE_VERBS) do
                    if autocompletes_to(fw_lower, verb_spec) then
                        command = verb_spec:gsub("|", "") .. rest
                        first_word = verb_spec:gsub("|", "")
                        break
                    end
                end
            end
        end

        local fw_lower = first_word and string.lower(first_word) or ""

        -- Handle "giveitem" specially (validation done at execution time now)
        -- Handle "locker" shortcut
        if fw_lower == "locker" and (not rest or str_trim(rest) == "") then
            command = "move to locker"
        end

        -- Add implicit ITEM if command has no modifiers
        local implicit_cmds = {
            "drop", "place", "sell", "appraise", "stash", "register",
            "mark", "unmark", "get", "take", "read", "look", "analyze",
            "inspect", "trash",
        }
        for _, ic in ipairs(implicit_cmds) do
            if string.match(command, "^" .. ic .. "$") then
                command = ic .. " item"
                break
            end
        end

        -- Check for stash command
        if string.find(str_lower(command), "^stash%s+") and not lootsacks then
            lootsacks = find_sacks()
            if #lootsacks == 0 then
                echo("Failed to find any lootsacks, STASH will not work.")
                echo("Configure with ;vars set lootsack=container, ;vars set lootsack2=container, etc.")
                return nil
            end
        end

        -- First command: implicit GET/RETURN logic
        if ix == 1 then
            -- Commands that need implicit get before them
            if string.match(str_lower(command), "^drop%s+item$") then
                -- Drop: use drag
                table.insert(new_commands, prefix .. "_drag item drop")
                goto next_cmd
            elseif string.match(str_lower(command), "^giveitem") or
                   string.match(str_lower(command), "^place%s+item$") or
                   string.match(str_lower(command), "^sell%s+item$") or
                   string.match(str_lower(command), "^trash%s+item$") then
                -- These need get first
                local implicit_return = false
                table.insert(new_commands, prefix .. "_remget item")
                table.insert(new_commands, prefix .. command)
                goto next_cmd
            elseif string.match(str_lower(command), "^appraise%s+item$") or
                   string.match(str_lower(command), "^register%s+item$") or
                   string.match(str_lower(command), "^mark%s+item$") or
                   string.match(str_lower(command), "^unmark%s+item$") then
                -- These need get first AND return after if only command
                table.insert(new_commands, prefix .. "_remget item")
                table.insert(new_commands, prefix .. command)
                if count == 1 then
                    table.insert(new_commands, prefix .. "return")
                end
                goto next_cmd
            end
        end

        table.insert(new_commands, prefix .. command)
        ::next_cmd::
    end

    return new_commands, lootsacks
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local input = Script.vars[0]

if not input or input == "" then
    show_help(false)
    return
end

if str_lower(str_trim(input)) == "help" then
    show_help(true)
    return
end

local parsed = parse_args(input)
if not parsed then
    show_help(false)
    return
end

-- Process commands (auto-completion, implicit get/return)
local lootsacks = nil
if parsed.commands then
    local processed, sacks = process_commands(
        parsed.commands, parsed.value ~= nil, parsed.explicit_all, parsed.target
    )
    parsed.commands = processed
    lootsacks = sacks
end

-- Collect items from target(s) - support comma-separated targets
local all_items = {}
local targets = split(parsed.target, ",")

for _, raw_target in ipairs(targets) do
    raw_target = str_trim(raw_target)
    if raw_target == "" then goto next_target end

    -- Strip trailing ? for optional containers
    local allow_errors = false
    if raw_target:sub(-1) == "?" then
        allow_errors = true
        raw_target = raw_target:sub(1, -2)
    end

    local target = str_lower(raw_target)

    -- Safety check for ALL in inv
    if (target == "inv" or target == "inventory") and parsed.commands and not parsed.value then
        if parsed.explicit_all then
            echo("WARNING: THIS COMMAND WILL ACT ON EVERY ITEM IN YOUR ENTIRE INVENTORY!")
            echo(";kill foreach to abort!")
            pause(1)
        else
            echo("WARNING: This would act on every item in your inventory!")
            echo("If you REALLY want to do this, use ';foreach ALL in " .. raw_target .. ";...'")
            return
        end
    end

    local items = {}
    if target == "inv" or target == "inventory" or target == "fastinv" or target == "qinv"
       or target == "fastinventory" or target == "qinventory" then
        items = collect_from_inventory()
    elseif target == "worn" then
        items = collect_from_worn()
    elseif target == "floor" or target == "ground" then
        items = collect_from_ground()
    elseif target == "room" then
        items = collect_from_room()
    elseif target == "desc" then
        items = collect_from_desc()
    elseif target == "loot" then
        items = collect_from_loot(parsed.preposition)
    elseif target == "locker" then
        items = collect_from_locker()
    elseif target == "previous" or target == "prev" or target == "last" then
        items = collect_from_previous()
    else
        -- Specific container
        items = collect_from_container(raw_target, parsed.preposition)
    end

    for _, entry in ipairs(items) do
        table.insert(all_items, entry)
    end

    ::next_target::
end

-- Apply filter
local filter_fn = build_filter(parsed.attr, parsed.value)
local filtered = {}
for _, entry in ipairs(all_items) do
    if filter_fn(entry.item) then
        table.insert(filtered, entry)
    end
end

-- Apply marked/registered filters (uses item.status string from game)
if parsed.opts.marked ~= nil or parsed.opts.registered ~= nil then
    local mark_filtered = {}
    for _, entry in ipairs(filtered) do
        local status = str_lower(entry.item.status or "")
        if parsed.opts.marked ~= nil then
            local is_marked = string.find(status, "marked") ~= nil
            if parsed.opts.marked ~= is_marked then goto skip_mark_entry end
        end
        if parsed.opts.registered ~= nil then
            local is_registered = string.find(status, "registered") ~= nil
            if parsed.opts.registered ~= is_registered then goto skip_mark_entry end
        end
        table.insert(mark_filtered, entry)
        ::skip_mark_entry::
    end
    filtered = mark_filtered
end

-- Apply sorting (strip articles a/an/some/the)
local function strip_articles(s)
    return s:gsub("^a%s+", ""):gsub("^an%s+", ""):gsub("^some%s+", ""):gsub("^the%s+", "")
end

if parsed.opts.sorted == "noun" then
    -- Sort by noun first, then by full name (ignoring articles)
    table.sort(filtered, function(a, b)
        local na = str_lower(a.item.noun or "") .. strip_articles(str_lower(a.item.full_name or a.item.name or ""))
        local nb = str_lower(b.item.noun or "") .. strip_articles(str_lower(b.item.full_name or b.item.name or ""))
        return na < nb
    end)
elseif parsed.opts.sorted then
    table.sort(filtered, function(a, b)
        local na = strip_articles(str_lower(a.item.full_name or a.item.name or ""))
        local nb = strip_articles(str_lower(b.item.full_name or b.item.name or ""))
        return na < nb
    end)
end

-- Apply reversed
if parsed.opts.reversed then
    local rev = {}
    for i = #filtered, 1, -1 do
        table.insert(rev, filtered[i])
    end
    filtered = rev
end

-- Apply unique
if parsed.opts.unique then
    local seen = {}
    local unique_items = {}
    for _, entry in ipairs(filtered) do
        local name = entry.item.full_name or entry.item.name or ""
        if not seen[name] then
            seen[name] = true
            table.insert(unique_items, entry)
        end
    end
    filtered = unique_items
end

-- Apply after
if parsed.opts.after then
    local skipped = {}
    for i = parsed.opts.after + 1, #filtered do
        table.insert(skipped, filtered[i])
    end
    filtered = skipped
end

-- Apply first
if parsed.opts.first then
    local limited = {}
    for i = 1, math.min(parsed.opts.first, #filtered) do
        table.insert(limited, filtered[i])
    end
    filtered = limited
end

-- Store results for PREVIOUS/LAST
_previous_results = filtered

-- Report or execute
if #filtered == 0 then
    echo("No matching items found!")
    return
end

if not parsed.commands or #parsed.commands == 0 then
    -- List mode
    respond("")
    respond("Matching items (" .. #filtered .. "):")
    respond("")
    for _, entry in ipairs(filtered) do
        local item = entry.item
        local type_str = item.type and item.type ~= "" and (" (" .. item.type .. ")") or ""
        respond("  #" .. item.id .. " " .. (item.full_name or item.name or item.noun or "?") .. type_str)
    end
    respond("")
    respond("Total items: " .. #filtered)
else
    -- Execute mode
    local total = #filtered
    local exec_opts = {
        _lootsacks = lootsacks,
    }

    for i, entry in ipairs(filtered) do
        if i % 10 == 1 then
            echo("Item " .. i .. " of " .. total .. " (" .. math.floor(100 * (i - 1) / total) .. "% complete)")
        end

        for _, cmd in ipairs(parsed.commands) do
            execute_command(cmd, entry.item, entry.container, entry.container_key, exec_opts)
        end
    end
    echo("Complete. Processed " .. total .. " items.")
end
