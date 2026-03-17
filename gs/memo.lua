--- @revenant-script
--- name: memo
--- version: 1.0.1
--- author: unknown
--- game: gs
--- tags: notes, memory, storage, utility
--- description: Store, recall, search, and manage short memos
---
--- Original Lich5 authors: unknown
--- Ported to Revenant Lua from memo.lic v1.01
---
--- Usage:
---   ;memo                       - interactive menu
---   ;memo <keyword>             - recall a memory
---   ;memo store <key> <text>    - store a memory
---   ;memo search <word>         - search all entries
---   ;memo help                  - show help

local settings = CharSettings.load("memo_data") or {}

local function save_data()
    CharSettings.save("memo_data", settings)
end

local function store_memory(key, value)
    settings[key] = settings[key] or {}
    -- Avoid duplicates
    for _, v in ipairs(settings[key]) do
        if v == value then
            respond("Already stored for '" .. key .. "'.")
            return
        end
    end
    settings[key][#settings[key] + 1] = value
    save_data()
    respond("Stored memory for '" .. key .. "'.")
end

local function recall_memory(key)
    if settings[key] and #settings[key] > 0 then
        respond("Memory for '" .. key .. "':")
        for i, entry in ipairs(settings[key]) do
            respond(i .. ". " .. entry)
        end
    else
        respond("No memory found for '" .. key .. "'.")
    end
end

local function list_keywords()
    local keywords = {}
    for key, entries in pairs(settings) do
        if type(entries) == "table" and #entries > 0 then
            keywords[#keywords + 1] = key
        end
    end
    if #keywords == 0 then
        respond("No stored memories found.")
    else
        respond("Stored memory keywords: " .. table.concat(keywords, ", "))
    end
end

local function search_entries(word)
    local matches = {}
    for key, entries in pairs(settings) do
        if type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if entry:lower():find(word:lower(), 1, true) then
                    matches[#matches + 1] = "Found in '" .. key .. "': " .. entry
                end
            end
        end
    end
    if #matches == 0 then
        respond("No entries found containing '" .. word .. "'.")
    else
        respond("Search results:")
        for _, m in ipairs(matches) do respond(m) end
    end
end

local function forget_memory(key)
    if not settings[key] or #settings[key] == 0 then
        respond("No memory found for '" .. key .. "'.")
        return
    end
    respond("Memory entries for '" .. key .. "':")
    for i, entry in ipairs(settings[key]) do
        respond(i .. ". " .. entry)
    end
    respond("Please ;send the number to forget:")
    local input = get()
    local num = tonumber(input)
    if num and num >= 1 and num <= #settings[key] then
        local removed = table.remove(settings[key], num)
        save_data()
        respond("Forgot: '" .. removed .. "'")
    else
        respond("Invalid selection.")
    end
end

local args = Script.current.vars

if args[1] and args[1]:lower() == "help" then
    echo("MEMO SCRIPT HELP")
    echo(";memo                  - interactive menu")
    echo(";memo <keyword>        - recall stored memory")
    echo(";memo store <key> <text> - store a memory")
    echo(";memo search <word>    - search all memories")
    return
end

if args[1] and args[1]:lower() == "store" then
    if args[2] and args[3] then
        local value_parts = {}
        for i = 3, #args do value_parts[#value_parts + 1] = args[i] end
        store_memory(args[2]:lower(), table.concat(value_parts, " "))
    else
        respond("Invalid format. Use: ;memo store <keyword> <text>")
    end
    return
end

if args[1] and args[1]:lower() == "search" then
    if args[2] then
        search_entries(args[2])
    else
        respond("Invalid format. Use: ;memo search <word>")
    end
    return
end

if args[1] then
    recall_memory(args[1]:lower())
    return
end

-- Interactive menu
respond("=======================================")
respond("What would you like to do?")
respond("    1. Store a memory - ;send 1 <keyword> <text>")
respond("    2. Recall a memory - ;send 2 <keyword>")
respond("    3. Forget a memory - ;send 3 <keyword>")
respond("    4. List all stored keywords - ;send 4")
respond("    5. Search all entries - ;send 5 <word>")
respond("=======================================")

local line = get()
if line then
    line = line:match("^%s*(.-)%s*$")
    local cmd = line:sub(1, 1)
    local rest = line:sub(3)
    if cmd == "1" then
        local key, value = rest:match("^(%S+)%s+(.+)$")
        if key and value then store_memory(key:lower(), value) end
    elseif cmd == "2" then
        recall_memory(rest:lower())
    elseif cmd == "3" then
        forget_memory(rest:lower())
    elseif cmd == "4" then
        list_keywords()
    elseif cmd == "5" then
        search_entries(rest)
    end
end
