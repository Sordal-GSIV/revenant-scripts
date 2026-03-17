--- @revenant-script
--- name: foreach
--- version: 1.2.0
--- author: Elanthia-Online
--- contributors: LostRanger
--- game: gs
--- description: Iterate commands over container items or targets with flexible filtering
--- tags: utility,inventory

--------------------------------------------------------------------------------
-- ForEach - Execute commands for matching items in containers
--
-- Usage:
--   ;foreach [OPTIONS] [ATTR=]VALUE in CONTAINER[; command; command; ...]
--   ;foreach help               - Full help
--
-- Examples:
--   ;foreach box in inv; move to locker
--   ;foreach gem in cloak; get item; appraise item; put item in container
--   ;foreach gem in backpack; get item; sell item
--   ;foreach noun=sword in locker; get item; put item in backpack
--
-- ATTRIBUTE: type (default), noun, name, fullname, quick, sellable
-- TARGETS: any container, INV, WORN, FLOOR, GROUND, LOOT, LOCKER
-- OPTIONS: UNIQUE, FIRST n, AFTER n, SORTED, REVERSED
--------------------------------------------------------------------------------

local VERSION   = "1.2.0"
local HELP_URL  = "https://github.com/dewiniaid/gs4-lich-scripts/blob/master/Foreach.md"

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
        return function(item)
            local types = split(item.type or "", ",")
            for _, t in ipairs(types) do
                if matches_any(t) then return true end
            end
            return false
        end
    elseif attr == "sellable" or attr == "s" then
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

local function collect_from_container(container_name)
    local items = {}

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

    if container and container.contents then
        for _, item in ipairs(container.contents) do
            table.insert(items, { item = item, container = container })
        end
    elseif str_lower(container_name) == "locker" then
        -- Open locker first
        put("open locker")
        local line = waitforre("Your locker is currently holding|already open|What were you referring to")
        if string.find(line or "", "currently holding") then
            before_dying(function()
                waitrt()
                put("close locker")
            end)
        end
        local loot = GameObj.loot() or {}
        for _, item in ipairs(loot) do
            if item.contents then
                for _, sub_item in ipairs(item.contents) do
                    table.insert(items, { item = sub_item, container = item })
                end
            end
        end
    end

    return items
end

local function collect_from_inventory()
    local items = {}
    local inv = GameObj.inv() or {}
    for _, obj in ipairs(inv) do
        if obj.contents then
            for _, item in ipairs(obj.contents) do
                table.insert(items, { item = item, container = obj })
            end
        end
    end
    return items
end

local function collect_from_worn()
    local items = {}
    local inv = GameObj.inv() or {}
    for _, item in ipairs(inv) do
        table.insert(items, { item = item, container = nil })
    end
    return items
end

local function collect_from_ground()
    local items = {}
    local loot = GameObj.loot() or {}
    for _, item in ipairs(loot) do
        table.insert(items, { item = item, container = nil })
    end
    local room_desc = GameObj.room_desc() or {}
    for _, item in ipairs(room_desc) do
        table.insert(items, { item = item, container = nil })
    end
    return items
end

local function collect_from_loot()
    local items = {}
    local loot = GameObj.loot() or {}
    for _, obj in ipairs(loot) do
        if obj.contents then
            for _, item in ipairs(obj.contents) do
                table.insert(items, { item = item, container = obj })
            end
        end
    end
    return items
end

--------------------------------------------------------------------------------
-- Command execution
--------------------------------------------------------------------------------

local function execute_command(cmd, item, container)
    -- Replace placeholders
    local ref = "#" .. item.id
    cmd = string.gsub(cmd, "%bITEM", ref)
    cmd = string.gsub(cmd, "%bitem", ref)
    cmd = string.gsub(cmd, "%bNAME", item.name or "")
    cmd = string.gsub(cmd, "%bname", item.name or "")
    cmd = string.gsub(cmd, "%bNOUN", item.noun or "")
    cmd = string.gsub(cmd, "%bnoun", item.noun or "")
    if container then
        cmd = string.gsub(cmd, "%bCONTAINER", "#" .. container.id)
        cmd = string.gsub(cmd, "%bcontainer", "#" .. container.id)
    end

    -- Convenience commands
    local lower_cmd = str_lower(cmd)

    if string.find(lower_cmd, "^waitrt") then
        waitrt()
    elseif string.find(lower_cmd, "^waitcastrt") then
        waitcastrt()
    elseif string.find(lower_cmd, "^pause$") then
        echo("Paused. Unpause to continue.")
        -- Script.pause would go here
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
    elseif string.find(lower_cmd, "^move ") then
        -- MOVE [item] TO container
        local what, where = string.match(cmd, "[Mm]ove%s+(.-)%s+[Tt]o%s+(.+)")
        if not what then
            what = ref
            where = string.match(cmd, "[Mm]ove%s+[Tt]o%s+(.+)")
        end
        if where then
            if str_lower(where) == "ground" or str_lower(where) == "floor" then
                fput("get " .. what)
                fput("drop " .. what)
            else
                fput("get " .. what)
                fput("put " .. what .. " in " .. where)
            end
        end
    elseif string.find(lower_cmd, "^unmark ") then
        local what = string.match(cmd, "unmark (.+)")
        fput("mark " .. what .. " remove")
    elseif string.find(lower_cmd, "^trash ") then
        local what = string.match(cmd, "trash (.+)") or ref
        fput("get " .. what)
        fput("trash " .. what)
    else
        -- Generic command
        fput(cmd)
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
    respond("  ;foreach [OPTIONS] [ATTR=]VALUE in CONTAINER[; command; command; ...]")
    respond("")
    if full then
        respond("ATTRIBUTE: type (default), noun, name, fullname, quick, sellable")
        respond("  Shorthand: t, n, m, f, q, s")
        respond("")
        respond("TARGETS: any container name, or:")
        respond("  INV/INVENTORY  - All containers in inventory")
        respond("  WORN           - Worn items")
        respond("  FLOOR/GROUND   - Items in the room")
        respond("  LOOT           - Contents of items in the room")
        respond("  LOCKER         - Contents of your locker")
        respond("")
        respond("COMMANDS: any game command, or convenience shortcuts:")
        respond("  MOVE [item] TO <where>  - Get and put")
        respond("  ECHO <message>          - Echo text")
        respond("  UNMARK [item]           - Unmark an item")
        respond("  TRASH [item]            - Trash an item")
        respond("  PAUSE                   - Pause script")
        respond("  SLEEP <seconds>         - Wait N seconds")
        respond("  WAITRT / WAITCASTRT     - Wait for roundtime")
        respond("  WAITFOR <phrase>        - Wait for game text")
        respond("  WAITMANA/WAITMP <n>     - Wait for mana")
        respond("  WAITHEALTH/WAITHP <n>   - Wait for health")
        respond("  WAITSPIRIT/WAITSP <n>   - Wait for spirit")
        respond("  WAITSTAMINA/WAITST <n>  - Wait for stamina")
        respond("")
        respond("OPTIONS:")
        respond("  UNIQUE    - Only first of each name")
        respond("  FIRST n   - Only first n matches")
        respond("  AFTER n   - Skip first n matches")
        respond("  SORTED    - Sort alphabetically by name")
        respond("  REVERSED  - Reverse iteration order")
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

    -- Parse out commands (after ; separator)
    local filter_part, commands_str = string.match(input, "^(.-)%s*;%s*(.*)$")
    if not filter_part then
        filter_part = input
        commands_str = nil
    end

    -- Parse commands
    local commands = nil
    if commands_str and commands_str ~= "" then
        commands = split(commands_str, ";")
    end

    -- Parse options
    local opts = {
        unique   = false,
        first    = nil,
        after    = nil,
        sorted   = false,
        reversed = false,
    }

    -- Extract options from filter
    while true do
        local match = string.match(filter_part, "^%s*unique%s+(.+)$")
        if match then opts.unique = true; filter_part = match; goto continue end

        match = string.match(filter_part, "^%s*reversed?%s+(.+)$")
        if match then opts.reversed = true; filter_part = match; goto continue end

        match = string.match(filter_part, "^%s*n?o?u?n?sorted%s+(.+)$")
        if match then opts.sorted = true; filter_part = match; goto continue end

        local n, rest = string.match(filter_part, "^%s*first%s+(%d+)%s+(.+)$")
        if n then opts.first = tonumber(n); filter_part = rest; goto continue end

        n, rest = string.match(filter_part, "^%s*after%s+(%d+)%s+(.+)$")
        if not n then n, rest = string.match(filter_part, "^%s*skip%s+(%d+)%s+(.+)$") end
        if n then opts.after = tonumber(n); filter_part = rest; goto continue end

        n, rest = string.match(filter_part, "^%s*(%d+)%s+(.+)$")
        if n and not opts.first then opts.first = tonumber(n); filter_part = rest; goto continue end

        break
        ::continue::
    end

    -- Parse attribute=value and target
    local attr, value, target

    -- Try: attr=value in target
    attr, value, target = string.match(filter_part, "^%s*(%w+)=(.-)%s+in%s+(.+)%s*$")
    if not attr then
        -- Try: value in target  (default attr is type)
        value, target = string.match(filter_part, "^%s*(.-)%s+in%s+(.+)%s*$")
        if value and value ~= "" then
            attr = "type"
        else
            -- Try: in target  (no filter)
            target = string.match(filter_part, "^%s*in%s+(.+)%s*$")
            attr = nil
            value = nil
        end
    end

    if not target then return nil end

    return {
        attr     = attr,
        value    = value,
        target   = str_trim(target),
        commands = commands,
        opts     = opts,
    }
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

-- Collect items from target
local all_items = {}
local target = str_lower(parsed.target)

if target == "inv" or target == "inventory" then
    all_items = collect_from_inventory()
elseif target == "worn" then
    all_items = collect_from_worn()
elseif target == "floor" or target == "ground" or target == "room" then
    all_items = collect_from_ground()
elseif target == "loot" then
    all_items = collect_from_loot()
else
    -- Specific container
    all_items = collect_from_container(parsed.target)
end

-- Apply filter
local filter_fn = build_filter(parsed.attr, parsed.value)
local filtered = {}
for _, entry in ipairs(all_items) do
    if filter_fn(entry.item) then
        table.insert(filtered, entry)
    end
end

-- Apply sorting
if parsed.opts.sorted then
    table.sort(filtered, function(a, b)
        return str_lower(a.item.full_name or a.item.name or "") < str_lower(b.item.full_name or b.item.name or "")
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
    for i, entry in ipairs(filtered) do
        if i % 10 == 1 then
            echo("Item " .. i .. " of " .. total .. " (" .. math.floor(100 * (i - 1) / total) .. "% complete)")
        end

        for _, cmd in ipairs(parsed.commands) do
            execute_command(cmd, entry.item, entry.container)
        end
    end
    echo("Complete. Processed " .. total .. " items.")
end
