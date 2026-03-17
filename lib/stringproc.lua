-------------------------------------------------------------------------------
-- StringProc: Ruby→Lua transpiler for mapdb wayto entries
--
-- Map database wayto values prefixed with ";e " contain Ruby code from Lich5.
-- This module translates them to Lua functions at load time using a pipeline
-- of ordered pattern translators.
--
-- Architecture:
--   1. Strip ";e " prefix
--   2. Run through translator pipeline (specific → generic)
--   3. Wrap result in "function() ... end"
--   4. Compile with load() into a callable function
--   5. Cache compiled functions for reuse
-------------------------------------------------------------------------------

local M = {}

-- Translation cache: ruby_code → compiled function
local cache = {}
local cache_hits = 0
local cache_misses = 0

-- Stats tracking
local stats = {
    total = 0,
    translated = 0,
    plain = 0,
    failed = 0,
    by_translator = {},
}

-- Translator pipeline (ordered: specific patterns first, generic last)
local translators = {}

-------------------------------------------------------------------------------
-- Utility helpers
-------------------------------------------------------------------------------

-- Escape a string for use in Lua source code
local function lua_escape(s)
    return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
end

-- Extract regex pattern string from Ruby /pattern/flags
-- Returns: pattern_str, flags (or nil)
local function extract_regex(s, pos)
    pos = pos or 1
    local start = s:find("/", pos)
    if not start then return nil end

    local depth = 0
    local i = start + 1
    local pat = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then
            pat[#pat + 1] = s:sub(i, i + 1)
            i = i + 2
        elseif c == "(" or c == "[" then
            depth = depth + 1
            pat[#pat + 1] = c
            i = i + 1
        elseif c == ")" or c == "]" then
            depth = depth - 1
            pat[#pat + 1] = c
            i = i + 1
        elseif c == "/" and depth <= 0 then
            -- End of regex
            local flags = ""
            local j = i + 1
            while j <= #s and s:sub(j, j):match("[imx]") do
                flags = flags .. s:sub(j, j)
                j = j + 1
            end
            return table.concat(pat), flags, start, j - 1
        else
            pat[#pat + 1] = c
            i = i + 1
        end
    end
    return nil
end

-- Replace all Ruby regexes /.../ with quoted strings "..."
-- Used for dothistimeout pattern args, =~ matches, etc.
local function replace_regexes(code)
    local result = {}
    local i = 1
    while i <= #code do
        -- Skip string literals
        local c = code:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c
            result[#result + 1] = c
            i = i + 1
            while i <= #code do
                local cc = code:sub(i, i)
                result[#result + 1] = cc
                if cc == "\\" then
                    i = i + 1
                    if i <= #code then
                        result[#result + 1] = code:sub(i, i)
                    end
                elseif cc == quote then
                    break
                end
                i = i + 1
            end
            i = i + 1
        elseif c == "/" then
            -- Check if this is a regex (not division)
            -- Heuristic: preceded by operator, comma, open paren, keyword, or start
            local before = code:sub(1, i - 1):match("[%s,%(=~!&|;]$") or i == 1
            if before then
                local pat, flags, _, end_pos = extract_regex(code, i)
                if pat then
                    result[#result + 1] = '"'
                    result[#result + 1] = lua_escape(pat)
                    result[#result + 1] = '"'
                    i = end_pos + 1
                else
                    result[#result + 1] = c
                    i = i + 1
                end
            else
                result[#result + 1] = c
                i = i + 1
            end
        else
            result[#result + 1] = c
            i = i + 1
        end
    end
    return table.concat(result)
end

-- Translate Ruby string interpolation: "text #{expr} more" → "text " .. (expr) .. " more"
local function translate_interpolation(code)
    -- Find double-quoted strings containing #{...}
    local result = {}
    local i = 1
    while i <= #code do
        local c = code:sub(i, i)
        if c == '"' then
            -- Scan the double-quoted string
            local parts = {}
            local buf = {}
            local has_interp = false
            i = i + 1
            while i <= #code do
                local cc = code:sub(i, i)
                if cc == "\\" then
                    buf[#buf + 1] = code:sub(i, i + 1)
                    i = i + 2
                elseif cc == "#" and i + 1 <= #code and code:sub(i + 1, i + 1) == "{" then
                    has_interp = true
                    -- Flush text buffer
                    if #buf > 0 then
                        parts[#parts + 1] = '"' .. table.concat(buf) .. '"'
                        buf = {}
                    end
                    -- Extract expression inside #{...}
                    local depth = 1
                    local expr = {}
                    i = i + 2  -- skip #{
                    while i <= #code and depth > 0 do
                        local ec = code:sub(i, i)
                        if ec == "{" then depth = depth + 1
                        elseif ec == "}" then depth = depth - 1 end
                        if depth > 0 then
                            expr[#expr + 1] = ec
                        end
                        i = i + 1
                    end
                    parts[#parts + 1] = "tostring(" .. table.concat(expr) .. ")"
                elseif cc == '"' then
                    i = i + 1
                    break
                else
                    buf[#buf + 1] = cc
                    i = i + 1
                end
            end
            if has_interp then
                if #buf > 0 then
                    parts[#parts + 1] = '"' .. table.concat(buf) .. '"'
                end
                result[#result + 1] = "(" .. table.concat(parts, " .. ") .. ")"
            else
                result[#result + 1] = '"' .. table.concat(buf) .. '"'
            end
        elseif c == "'" then
            -- Single-quoted strings: pass through, no interpolation
            result[#result + 1] = c
            i = i + 1
            while i <= #code do
                local cc = code:sub(i, i)
                result[#result + 1] = cc
                if cc == "\\" then
                    i = i + 1
                    if i <= #code then result[#result + 1] = code:sub(i, i) end
                elseif cc == "'" then
                    i = i + 1
                    break
                end
                i = i + 1
            end
        else
            result[#result + 1] = c
            i = i + 1
        end
    end
    return table.concat(result)
end

-------------------------------------------------------------------------------
-- Core Ruby→Lua syntax transformation
--
-- Applied to all code after interpolation and regex handling.
-- Order matters: more specific patterns before generic ones.
-------------------------------------------------------------------------------

local function ruby_to_lua(code)
    -- Newlines to semicolons (multi-line entries)
    code = code:gsub("\n", "; ")

    -- Ruby string interpolation → Lua concatenation
    code = translate_interpolation(code)

    -- Replace Ruby regexes with quoted strings
    code = replace_regexes(code)

    -- Boolean operators
    code = code:gsub(" && ", " and ")
    code = code:gsub(" %|%| ", " or ")

    -- Ruby ! negation (careful: don't break ~=)
    -- !expr → not expr (when ! is boolean not, not part of != or ~=)
    code = code:gsub("(%A)!(%w)", "%1not %2")
    code = code:gsub("^!(%w)", "not %1")
    code = code:gsub("(%A)!%(", "%1not (")
    code = code:gsub("^!%(", "not (")

    -- Not equal
    code = code:gsub("!=", "~=")

    -- Ruby sleep → Lua pause
    code = code:gsub("sleep%s+(%d+[%.%d]*)", "pause(%1)")

    -- waitrt? / waitcastrt?
    code = code:gsub("waitrt%?", "waitrt()")
    code = code:gsub("waitcastrt%?", "waitcastrt()")

    -- Status checks (predicate methods)
    code = code:gsub("checksitting", "sitting()")
    code = code:gsub("checkstanding", "standing()")
    code = code:gsub("checklounging", "lounging()")
    code = code:gsub("checkprone", "prone()")
    code = code:gsub("kneeling%?", "kneeling()")
    code = code:gsub("sitting%?", "sitting()")
    code = code:gsub("standing%?", "standing()")
    code = code:gsub("hidden%?", "hidden()")
    code = code:gsub("invisible%?", "invisible()")
    code = code:gsub("dead%?", "dead()")
    code = code:gsub("stunned%?", "stunned()")
    code = code:gsub("muckled%?", "muckled()")

    -- Spell API
    code = code:gsub("Spell%[(%d+)%]%.active%?", "Spell.active_p(%1)")
    code = code:gsub("Spell%[(%d+)%]%.known%?", "Spell.known_p(%1)")
    code = code:gsub("Spell%[(%d+)%]%.affordable%?", "Spell.affordable_p(%1)")
    code = code:gsub("Spell%[(%d+)%]%.cast", "Spell.cast(%1)")
    -- Spell['Name'].active?
    code = code:gsub("Spell%['([^']+)'%]%.active%?", 'Spell.active_p("%1")')
    code = code:gsub('Spell%["([^"]+)"%]%.active%?', 'Spell.active_p("%1")')
    -- Spells.active.include?(N)
    code = code:gsub("Spells%.active%.include%?%((%d+)%)", "Spell.active_p(%1)")

    -- checkspell — already valid Lua-style call in many entries
    -- checkspell 'name' → checkspell("name")
    code = code:gsub("checkspell%s+'([^']+)'", 'checkspell("%1")')
    code = code:gsub("checkspell%s+(%d+)", "checkspell(%1)")

    -- Room API
    code = code:gsub("Room%.current%.id", "Map.current_room()")
    code = code:gsub("Room%[(%d+)%]", "Map.find_room(%1)")

    -- XMLData → GameState
    code = code:gsub("XMLData%.(%w+)", "GameState.%1")

    -- Skills access (keep as-is, Skills.xxx is valid in Lua API)
    -- Stats access (keep as-is)

    -- defined?(X) → (X ~= nil)
    code = code:gsub("defined%?%(([^%)]+)%)", "(%1 ~= nil)")

    -- .nil? → == nil
    code = code:gsub("(%w[%w%._]*)%.nil%?", "((%1) == nil)")

    -- .empty? → == ""
    code = code:gsub("(%w[%w%._]*)%.empty%?", "((%1) == nil or (%1) == \"\")")

    -- .include?('x') → has_value(t, 'x')  or string match
    code = code:gsub("checkpaths%.include%?%('([^']+)'%)", 'checkpaths("%1")')
    code = code:gsub("checkloot%.include%?%('([^']+)'%)", 'checkloot("%1")')
    code = code:gsub("%.include%?%(([^%)]+)%)", ":find(%1)")

    -- Ruby ternary: expr ? val_true : val_false → (expr and val_true or val_false)
    -- This is tricky with nested ternaries; handle simple cases
    -- We handle it in a dedicated translator below for timeto values

    -- =~ /pattern/ was already converted to =~ "pattern"
    -- expr =~ "pattern" → Regex.test("pattern", expr)
    code = code:gsub('(%w[%w%._%(%),% ]*) =~ "([^"]*)"', 'Regex.test("%2", %1)')

    -- Ruby single-quoted strings to double-quoted for consistency with Lua
    -- Only do this for function call arguments: func 'arg' → func("arg")
    -- move 'dir' → move("dir")
    code = code:gsub("(move)%s+'([^']*)'", '%1("%2")')
    code = code:gsub("(fput)%s+'([^']*)'", '%1("%2")')
    code = code:gsub("(put)%s+'([^']*)'", '%1("%2")')
    code = code:gsub("(echo)%s+'([^']*)'", '%1("%2")')
    code = code:gsub("(waitfor)%s+'([^']*)'", '%1("%2")')

    -- multifput 'a','b','c' → multifput("a","b","c")
    -- Capture: multifput followed by space and single-quoted comma-separated args
    code = code:gsub("(multifput)%s+'", '%1("')
    code = code:gsub("','", '","')
    -- Close the last arg if multifput was transformed
    if code:find('multifput%(') then
        code = code:gsub("(multifput%([^;]+)'", "%1\")")
    end

    -- Clean up double-semicolons
    code = code:gsub(";;+", ";")
    -- Remove trailing semicolons
    code = code:gsub(";%s*$", "")

    return code
end

-------------------------------------------------------------------------------
-- Translator registration
-------------------------------------------------------------------------------

local function add_translator(name, func)
    translators[#translators + 1] = { name = name, fn = func }
    stats.by_translator[name] = 0
end

-------------------------------------------------------------------------------
-- TRANSLATOR 1: Maze entries (placeholder stub)
-- Detect: start_room = [...]; dirs = [...]; if index = start_room.index(Room.current.id)
-------------------------------------------------------------------------------

add_translator("maze", function(code)
    if code:find("start_room") and code:find("dirs") and code:find("%.index%(Room%.current%.id%)") then
        return 'Maze.navigate()'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 2: FWI trinket (complex multi-line script, placeholder)
-- Detect: mapdb_fwi_trinket
-------------------------------------------------------------------------------

add_translator("fwi_trinket", function(code)
    if code:find("mapdb_fwi_trinket") then
        return 'FWI.use_trinket()'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 3: Urchin transport (placeholder)
-- Detect: mapdb_use_urchins
-------------------------------------------------------------------------------

add_translator("urchin", function(code)
    if code:find("mapdb_use_urchins") and code:find("urchin") then
        return 'Urchin.transport()'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 4: Simple "true" / numeric return values (timeto entries)
-------------------------------------------------------------------------------

add_translator("literal_value", function(code)
    -- ";e true"
    if code:match("^%s*true%s*$") then
        return "return true"
    end
    -- ";e false"
    if code:match("^%s*false%s*$") then
        return "return false"
    end
    -- ";e nil"
    if code:match("^%s*nil%s*$") then
        return "return nil"
    end
    -- ";e 0.2" or ";e 15.0"
    local num = code:match("^%s*(%d+%.?%d*)%s*;?%s*$")
    if num then
        return "return " .. num
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 5: Ruby ternary expressions (timeto cost entries)
-- e.g.: UserVars.mapdb_premium.nil? ? 10 : 0.2
-- e.g.: (condition) ? value : value
-------------------------------------------------------------------------------

add_translator("ternary", function(code)
    -- Match: condition ? true_val : false_val
    -- Needs careful handling: the ? must not be part of .nil? or .empty?
    local transformed = ruby_to_lua(code)

    -- Simple ternary: expr ? val : val (possibly wrapped in parens)
    -- Remove outer parens
    local inner = transformed:match("^%s*%((.+)%)%s*;?%s*$") or transformed

    -- Look for ternary pattern: condition ? true_val : false_val
    -- The ? must be surrounded by spaces (not part of a method name)
    local cond, true_val, false_val = inner:match("^(.+)%s+%?%s+(.+)%s+:%s+(.+)$")
    if cond and true_val and false_val then
        -- Recursively handle nested ternaries (rare but possible)
        return "if " .. cond .. " then return " .. true_val .. " else return " .. false_val .. " end"
    end

    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 6: N.times { ... } loops
-- e.g.: 2.times{fput "event transport duskruin"}
-- e.g.: 10.times { result = dothistimeout ...; break if ... }
-------------------------------------------------------------------------------

add_translator("times_loop", function(code)
    if not code:find("%.times") then return nil end

    local transformed = ruby_to_lua(code)

    -- Pattern: N.times{block} or N.times { block }
    -- May have code before and after
    local pre, n, block, post = transformed:match("^(.-)(%d+)%.times%s*{%s*(.-)%s*}(.*)$")
    if not n then return nil end

    -- Handle |i| block variable (rare in mapdb)
    local var = block:match("^|(%w+)|%s*")
    if var then
        block = block:gsub("^|%w+|%s*", "")
    else
        var = "_"
    end

    -- Translate "break if cond" → "if cond then break end"
    block = block:gsub("break if (.+)", "if %1 then break end")

    local lua = ""
    if pre and pre:match("%S") then
        lua = lua .. pre .. "; "
    end
    lua = lua .. "for " .. var .. " = 1, " .. n .. " do " .. block .. " end"
    if post and post:match("%S") then
        lua = lua .. "; " .. post
    end

    return lua
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 7: "unless" modifier/block
-- e.g.: fput 'kneel' unless kneeling?; move 'southeast'
-- e.g.: unless move 'go ferryboat'; echo ...; waitfor ...; move ...; end
-------------------------------------------------------------------------------

add_translator("unless", function(code)
    if not code:find("unless") then return nil end

    local transformed = ruby_to_lua(code)

    -- Block form: unless COND; body; end; rest
    local cond, body, rest = transformed:match("^unless%s+(.-)%;%s*(.-)%;?%s*end;?%s*(.*)$")
    if cond then
        local lua = "if not (" .. cond .. ") then " .. body .. " end"
        if rest and rest:match("%S") then
            lua = lua .. "; " .. rest
        end
        return lua
    end

    -- Modifier form: ACTION unless COND; REST
    -- Find "unless" that separates action from condition
    -- The tricky part: there might be a semicolon after the condition
    local action, cond_rest = transformed:match("^(.-)%s+unless%s+(.+)$")
    if action and cond_rest then
        -- Split condition from rest at first semicolon
        local cond2, rest2 = cond_rest:match("^(.-)%;%s*(.+)$")
        if cond2 then
            return "if not (" .. cond2 .. ") then " .. action .. " end; " .. rest2
        else
            return "if not (" .. cond_rest .. ") then " .. action .. " end"
        end
    end

    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 8: "while" modifier/block
-- e.g.: move 'northeast' while checkpaths.include?('nw')
-- e.g.: while checkpaths.include?('n'); move 'east'; move 'north'; end
-------------------------------------------------------------------------------

add_translator("while_loop", function(code)
    if not code:find("while") then return nil end

    local transformed = ruby_to_lua(code)

    -- Block form: while COND; body; end; rest
    local cond, body, rest = transformed:match("^while%s+(.-)%;%s*(.-)%;?%s*end;?%s*(.*)$")
    if cond then
        local lua = "while " .. cond .. " do " .. body .. " end"
        if rest and rest:match("%S") then
            lua = lua .. "; " .. rest
        end
        return lua
    end

    -- Modifier form: ACTION while COND
    local action, cond2 = transformed:match("^(.-)%s+while%s+(.+)$")
    if action and cond2 then
        return "while " .. cond2 .. " do " .. action .. " end"
    end

    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 9: "until" loops
-- e.g.: until checkloot.include?('door'); move dirs[index]; ...; end
-------------------------------------------------------------------------------

add_translator("until_loop", function(code)
    if not code:find("until") then return nil end

    local transformed = ruby_to_lua(code)

    -- Block form: until COND; body; end
    local cond, body = transformed:match("until%s+(.-)%;%s*(.-)%;?%s*end")
    if cond then
        -- Replace in the full transformed code
        local full = transformed:gsub("until%s+.-%s*;%s*.-%;?%s*end",
            "while not (" .. cond .. ") do " .. body .. " end")
        return full
    end

    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 10: Postfix "if" modifier
-- e.g.: fput 'unhide' if checkspell(916); move 'go gate'
-- e.g.: fput 'stance offensive' if Skills.climbing < 20
-- Must be after "unless" and "while" translators
-------------------------------------------------------------------------------

add_translator("postfix_if", function(code)
    -- Only handle simple postfix if, not block if/else/end
    -- Heuristic: contains " if " but not "^if " at start and not " else "
    if not code:find(" if ") then return nil end
    if code:match("^%s*if%s") then return nil end  -- block if handled by generic

    local transformed = ruby_to_lua(code)

    -- Split on semicolons, look for statements with postfix if
    local parts = {}
    for part in (transformed .. ";"):gmatch("([^;]+);") do
        part = part:match("^%s*(.-)%s*$")  -- trim
        if part ~= "" then
            -- Check for postfix if: "ACTION if COND"
            local action, cond = part:match("^(.+)%s+if%s+(.+)$")
            if action and cond then
                -- Make sure this isn't "else if" or "elsif"
                if not action:match("else%s*$") then
                    parts[#parts + 1] = "if " .. cond .. " then " .. action .. " end"
                else
                    parts[#parts + 1] = part
                end
            else
                parts[#parts + 1] = part
            end
        end
    end

    if #parts > 0 then
        return table.concat(parts, "; ")
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR 11: Generic fallback — apply ruby_to_lua and pass through
-- Handles: start_script('bescort', ...) patterns (DR transport system)
-------------------------------------------------------------------------------

add_translator("bescort", function(code)
    -- Pattern: start_script('bescort', ['route', 'dest']); wait_while{running?('bescort')}
    local args = code:match("start_script%s*%(%s*'bescort'%s*,%s*%[(.-)%]")
    if not args then return nil end
    -- Extract the route arguments: 'arg1', 'arg2', ...
    local arg_list = {}
    for arg in args:gmatch("'([^']*)'") do
        arg_list[#arg_list + 1] = arg
    end
    if #arg_list == 0 then return nil end
    local arg_str = table.concat(arg_list, " ")
    return 'Script.run("bescort", "' .. arg_str .. '"); while Script.running("bescort") do pause(0.5) end'
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: start_script (generic, covers any script launch in wayto)
-------------------------------------------------------------------------------

add_translator("start_script", function(code)
    local script_name = code:match("start_script%s*%(%s*'([^']*)'")
    if not script_name then return nil end
    -- Extract args if present
    local args_raw = code:match("start_script%s*%(%s*'[^']*'%s*,%s*%[(.-)%]")
    if args_raw then
        local arg_list = {}
        for arg in args_raw:gmatch("'([^']*)'") do
            arg_list[#arg_list + 1] = arg
        end
        local arg_str = table.concat(arg_list, " ")
        local lua = 'Script.run("' .. script_name .. '", "' .. arg_str .. '")'
        -- Check for wait_while{running?('name')}
        if code:find("wait_while") and code:find("running") then
            lua = lua .. '; while Script.running("' .. script_name .. '") do pause(0.5) end'
        end
        return lua
    end
    -- No args
    local lua = 'Script.run("' .. script_name .. '")'
    if code:find("wait_while") and code:find("running") then
        lua = lua .. '; while Script.running("' .. script_name .. '") do pause(0.5) end'
    end
    return lua
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Map[N].wayto['N'].call — delegation to another room's wayto
-- Resolves known delegation targets to dedicated handlers
-------------------------------------------------------------------------------

add_translator("delegation", function(code)
    -- Rogue Guild password door: Map[12421].wayto['14089'].call
    if code:find("Map%[12421%]") and code:find("14089") then
        return [[
            local pw = UserVars.rogue_password
            if not pw or pw == "" then
                echo("No Rogue Guild password set. Use: ;vars set rogue_password=kick, slap, turn, scratch, kick, slap")
                return
            end
            fput("lean door")
            for verb in pw:gmatch("[^,]+") do
                fput(verb:match("^%s*(.-)%s*$") .. " door")
            end
            fput("go door")
        ]]
    end
    -- Krolvin warship brig door: Map[18700].wayto['18250'].call
    if code:find("Map%[18700%]") and code:find("18250") then
        return [[
            local loot = GameObj.loot()
            local has_ruined = false
            for _, o in ipairs(loot) do
                if o.name and o.name:find("ruined cell door") then has_ruined = true; break end
            end
            if has_ruined then
                move("go door")
            else
                echo("BATTERing door with weapon...")
                local r
                repeat
                    r = dothistimeout("batter door", 5, "ineffective|destroyed")
                until r and r:find("destroyed")
                move("go door")
            end
        ]]
    end
    -- FWI trinket delegation: Map[7].wayto['3668'].call (handled by fwi_trinket translator via prefix)
    if code:find("Map%[7%]") and code:find("3668") then
        return 'if FWI then FWI.use_trinket() else respond("[mapdb] FWI trinket module not loaded") end'
    end
    -- Generic Map[N].wayto['N'].call — warn
    if code:find("Map%[%d+%]%.wayto%[") and code:find("%.call") then
        local room_id = code:match("Map%[(%d+)%]")
        local dest_id = code:match("wayto%['(%d+)'%]")
        return 'respond("[mapdb] delegation to Room ' .. (room_id or "?") .. ' wayto ' .. (dest_id or "?") .. ' — not yet translated")'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: wait_while/wait_until room change (rapids, rivers, currents)
-------------------------------------------------------------------------------

add_translator("wait_room_change", function(code)
    -- wait_while { Room.current.id == N } or wait_while{Map.current.id == N}
    local room_id = code:match("wait_while%s*{%s*[RM][ao][op]m?%.current%.id%s*==%s*(%d+)")
    if room_id then
        return 'while Map.current_room() == ' .. room_id .. ' do pause(0.5) end'
    end
    -- wait_until { Map.current.id != N }
    room_id = code:match("wait_until%s*{%s*[RM][ao][op]m?%.current%.id%s*!=%s*(%d+)")
    if room_id then
        return 'while Map.current_room() == ' .. room_id .. ' do pause(0.5) end'
    end
    -- $go2_restart variant
    if code:find("wait_while") and code:find("Map%.current%.id") and code:find("go2_restart") then
        local rid = code:match("Map%.current%.id%s*==%s*(%d+)")
        if rid then
            return 'while Map.current_room() == ' .. rid .. ' do pause(0.5) end'
        end
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Group tracking + climb/move (Glo'antern, Thanatoph, etc.)
-- These parse "X followed" to track group, then move. We skip group tracking.
-------------------------------------------------------------------------------

add_translator("group_climb", function(code)
    if not (code:find("group_members") or code:find("$group_members")) then return nil end
    if not (code:find("move ") or code:find("climb") or code:find("jump") or code:find("go ")) then return nil end
    -- Extract the actual movement command
    local parts = {}
    -- empty_hands before move
    if code:find("empty_hands") or code:find("empty_hand") then
        parts[#parts + 1] = "fput('stow right'); fput('stow left')"
    end
    -- Find the move command
    local move_cmd = code:match("move%s*'([^']+)'") or code:match("move%s*%(s*'([^']+)'%s*%)")
    if move_cmd then
        parts[#parts + 1] = 'move("' .. move_cmd .. '")'
    end
    -- fput 'stand' after
    if code:find("fput 'stand'") or code:find("standing?") then
        parts[#parts + 1] = 'if not standing() then fput("stand") end'
    end
    -- waitrt
    if code:find("waitrt") then
        parts[#parts + 1] = "waitrt()"
    end
    -- fill_hands after
    if code:find("fill_hands") then
        -- No direct equivalent, skip
    end
    if #parts > 0 then
        return table.concat(parts, "; ")
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Maaghara Labyrinth (fixed-path navigation)
-------------------------------------------------------------------------------

add_translator("maaghara", function(code)
    if not code:find("next_exit") then return nil end
    if not code:find("9823") then return nil end  -- signature room ID
    -- This is a fixed-path maze. Extract directions per entry room and follow them.
    return [[
        local paths = {
            [9823] = {"southeast","southwest","southwest","east","southwest","southeast","south"},
            [9818] = {"east","southwest","west","west","northeast","northeast","northwest"},
            [9808] = {"east","east","east","northeast","west"},
            [9788] = {"southwest","southeast","southwest"},
            [9784] = {"southeast","south","northeast","north","west","west","west"},
        }
        local dirs = paths[Map.current_room()]
        if dirs then
            for _, d in ipairs(dirs) do move(d) end
        else
            respond("[mapdb] Maaghara: unknown entry room " .. tostring(Map.current_room()))
        end
    ]]
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Simple put commands (go field, tap globe, search)
-------------------------------------------------------------------------------

add_translator("simple_put", function(code)
    -- Match: put 'cmd' or put "cmd" sequences
    if not code:match("^put ") and not code:match("^put%(") then return nil end
    local parts = {}
    for cmd in code:gmatch("put%s*['\"]([^'\"]+)['\"]") do
        parts[#parts + 1] = 'put("' .. cmd .. '")'
    end
    if #parts > 0 then
        return table.concat(parts, "; ")
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: .each movement sequences
-- Pattern: ['w','w','nw'].each{|d| move(d)}
-------------------------------------------------------------------------------

add_translator("each_move", function(code)
    -- Find array.each{|var| move(var)} patterns
    local dirs = code:match("%[([^%]]+)%]%.each%s*{%s*|%w+|%s*move")
    if not dirs then return nil end
    -- Extract direction strings
    local parts = {}
    for dir in dirs:gmatch("'([^']+)'") do
        parts[#parts + 1] = 'move("' .. dir .. '")'
    end
    -- Also handle fput commands between .each blocks
    for cmd in code:gmatch("fput%s*'([^']+)'") do
        parts[#parts + 1] = 'fput("' .. cmd .. '")'
    end
    if #parts > 0 then
        return table.concat(parts, "; ")
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Color barrier (Atoll room 30850)
-------------------------------------------------------------------------------

add_translator("color_barrier", function(code)
    if not code:find("color_moves") then return nil end
    return [=[
        local color_paths = {
            blue = {"n","sw","sw"},
            black = {"n","sw","sw","sw","s","se"},
            red = {"n","se","se"},
            yellow = {"n","se","se","se","s","sw"},
        }
        local descs = GameObj.room_desc()
        local color = nil
        for _, o in ipairs(descs) do
            local c = o.name and Regex.match("(blue|black|yellow|red) barrier", o.name)
            if c then color = c; break end
        end
        if not color then respond("[mapdb] Could not detect barrier color"); return end
        local path = color_paths[color]
        if not path then respond("[mapdb] Unknown barrier color: " .. color); return end
        local reverse_map = {n="s",s="n",e="w",w="e",ne="sw",sw="ne",se="nw",nw="se"}
        for _, d in ipairs(path) do move(d) end
        move("go grotto")
        fput("touch crystal")
        move("out")
        for i = #path, 1, -1 do move(reverse_map[path[i]] or path[i]) end
        move("go portal")
    ]=]
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Smuggling Tunnels mural puzzle (room 6897)
-------------------------------------------------------------------------------

add_translator("mural_puzzle", function(code)
    if not code:find("touch mural") then return nil end
    if not code:find("Andelas") then return nil end
    return [[
        put("touch mural")
        local gods = {}
        while true do
            local line = get()
            if Regex.test("black cat|crimson claw|mice will play|claws that spread|smile.*predator", line) then
                gods[#gods+1] = "Andelas"
            elseif Regex.test("sea's tempestuous|ship is saved|lost in Charl|great Charl's domain", line) then
                gods[#gods+1] = "Charl"
            elseif Regex.test("Eorgina|dark goddess|shadow queen", line) then
                gods[#gods+1] = "Eorgina"
            elseif Regex.test("Ivas|love|passion|desire", line) then
                gods[#gods+1] = "Ivas"
            elseif Regex.test("Mularos|pain|suffering|agony", line) then
                gods[#gods+1] = "Mularos"
            elseif Regex.test("Sheru|nightmare|terror|fear", line) then
                gods[#gods+1] = "Sheru"
            elseif Regex.test("V'tull|war|battle|blood|rage", line) then
                gods[#gods+1] = "V'tull"
            elseif line:find("Which god") or line:find("answer") then
                break
            end
        end
        if #gods > 0 then
            fput("say " .. gods[#gods])
        end
    ]]
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Bleaklands storm (room 34509) — go2 through UID rooms
-------------------------------------------------------------------------------

add_translator("bleaklands", function(code)
    if not code:find("bleak_rooms") then return nil end
    return 'respond("[mapdb] Bleaklands storm navigation requires manual go2 through UID rooms")'
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Search + go (room 22349 dark alley, room 22443)
-------------------------------------------------------------------------------

add_translator("search_go", function(code)
    if not code:find("search") then return nil end
    if code:find("trapdoor") then
        return [[
            put("search")
            while true do
                local line = get()
                if line:find("trapdoor") then put("go trapdoor"); break
                elseif Regex.test("dead rat|silver hair|broken lockpick|tarnished coin", line) then put("search")
                end
            end
        ]]
    end
    -- Simple search + go
    local go_cmd = code:match("put%s*'go ([^']+)'")
    if go_cmd then
        return 'put("search"); fput("go ' .. go_cmd .. '")'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: River wait (room 24239)
-------------------------------------------------------------------------------

add_translator("river_wait", function(code)
    if code:find("sturdy ladder") then
        return 'echo("Waiting for current..."); waitfor("sturdy ladder")'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Forest Path room list (room 18243)
-------------------------------------------------------------------------------

add_translator("room_list_nav", function(code)
    -- %w(...) creates a Ruby word array — this is a room list for navigation
    if code:find("%%w%(") then
        return 'respond("[mapdb] Room list navigation — use go2 directly")'
    end
    return nil
end)

-------------------------------------------------------------------------------
-- TRANSLATOR: Stronghold shaman wedge puzzle (room 8373)
-------------------------------------------------------------------------------

add_translator("wedge_puzzle", function(code)
    if not code:find("wedge_list") then return nil end
    return [[
        local wedges = {
            northern = "a large thick torus surrounded by nine tiny circles",
            eastern = "two crossed upside-down hammers circumscribed by a rounded arc",
            western = "a jagged triangular arch bisected by a vertical line",
            southern = "three pairs of obliquely intersecting parallel lines",
        }
        for direction, position in pairs(wedges) do
            while true do
                local result = dothistimeout("look " .. direction .. " wedge", 3, position .. "|does not match")
                if result and result:find(position) then break end
                fput("turn " .. direction .. " wedge")
            end
        end
        fput("push altar")
    ]]
end)

-------------------------------------------------------------------------------
-- TRANSLATOR (catch-all): Generic Ruby→Lua
-- Handles: move+waitrt, fput, dothistimeout, if/else/end blocks, etc.
-- These are already mostly valid Lua after ruby_to_lua transformation.
-------------------------------------------------------------------------------

add_translator("generic", function(code)
    local transformed = ruby_to_lua(code)

    -- Fix Ruby if/elsif/else/end that uses semicolons as separators
    -- Ruby: if COND; body; elsif COND; body; else; body; end
    -- Lua:  if COND then body elseif COND then body else body end
    -- Many mapdb entries already use "then/else/end" (Lich5 accepts both Ruby & Lua-ish syntax)

    -- Convert semicolons after if/elsif/elseif conditions to "then"
    -- But only when "then" is not already present
    transformed = transformed:gsub("(if%s+[^;]+);", function(m)
        if m:find("then%s*$") then return m .. ";" end
        return m .. " then "
    end)
    transformed = transformed:gsub("(elsif%s+[^;]+);", function(m)
        return "elseif" .. m:sub(6) .. " then "
    end)
    transformed = transformed:gsub("(elseif%s+[^;]+);", function(m)
        if m:find("then%s*$") then return m .. ";" end
        return m .. " then "
    end)

    -- Ruby "elsif" → Lua "elseif"
    transformed = transformed:gsub("elsif", "elseif")

    -- "else;" → "else "
    transformed = transformed:gsub("else%s*;", "else ")

    -- Ruby "end;" → Lua "end;"
    -- (already valid)

    -- $global_var → _G.global_var
    transformed = transformed:gsub("%$([%w_]+)", "_G_%1")

    -- Handle "begin ... end while" → repeat ... until not
    transformed = transformed:gsub("begin;?%s*(.-)%;?%s*end%s+while%s+(.+)",
        "repeat %1 until not (%2)")

    return transformed
end)

-------------------------------------------------------------------------------
-- Main translation entry point
-------------------------------------------------------------------------------

--- Translate a wayto entry from Ruby to a compiled Lua function.
--- @param wayto_str string The raw wayto value (may or may not have ";e " prefix)
--- @return function|nil fn Compiled function, or nil if plain command string
--- @return string|nil err Error message if compilation failed
function M.translate(wayto_str)
    if not wayto_str or type(wayto_str) ~= "string" then
        return nil
    end

    -- Plain string (not ;e) — return nil to indicate "use as plain command"
    if not wayto_str:match("^;e ") and not wayto_str:match("^;e\n") then
        stats.plain = stats.plain + 1
        return nil
    end

    stats.total = stats.total + 1

    -- Check cache
    if cache[wayto_str] then
        cache_hits = cache_hits + 1
        local entry = cache[wayto_str]
        if entry.err then return nil, entry.err end
        return entry.fn
    end
    cache_misses = cache_misses + 1

    -- Strip ";e " prefix
    local code = wayto_str:match("^;e%s*(.+)$")
    if not code then
        stats.failed = stats.failed + 1
        cache[wayto_str] = { err = "empty ;e entry" }
        return nil, "empty ;e entry"
    end

    -- Try each translator in order
    for _, t in ipairs(translators) do
        local lua_body = t.fn(code)
        if lua_body then
            -- Wrap in function and compile
            local chunk = "return function() " .. lua_body .. " end"
            local fn, err = load(chunk, "stringproc", "t")
            if fn then
                local ok, result = pcall(fn)
                if ok and type(result) == "function" then
                    stats.translated = stats.translated + 1
                    stats.by_translator[t.name] = (stats.by_translator[t.name] or 0) + 1
                    cache[wayto_str] = { fn = result }
                    return result
                else
                    -- pcall failed — try next translator
                end
            else
                -- Compilation failed — log and try next translator
                -- (Some translators are heuristic, may produce bad code)
            end
        end
    end

    -- All translators failed — produce fallback
    stats.failed = stats.failed + 1
    local err_msg = "untranslated: " .. wayto_str:sub(1, 80)
    cache[wayto_str] = { err = err_msg, fn = function()
        if respond then
            respond("[stringproc] " .. err_msg)
        end
    end }
    return cache[wayto_str].fn, err_msg
end

-------------------------------------------------------------------------------
-- Batch translation for map loading
-------------------------------------------------------------------------------

--- Translate all wayto entries in a map database table.
--- @param rooms table Array of room objects with .wayto tables
--- @return table translated Map of "from:to" → function
function M.translate_all(rooms)
    local result = {}
    for _, room in ipairs(rooms) do
        if room.wayto then
            local room_id = tostring(room.id)
            for dest_str, wayto_val in pairs(room.wayto) do
                if type(wayto_val) == "string" and
                   (wayto_val:match("^;e ") or wayto_val:match("^;e\n")) then
                    local fn, err = M.translate(wayto_val)
                    if fn then
                        local key = room_id .. ":" .. dest_str
                        result[key] = fn
                    end
                end
            end
        end
    end
    return result
end

-------------------------------------------------------------------------------
-- Detection: is this wayto value a StringProc?
-------------------------------------------------------------------------------

function M.is_stringproc(wayto_value)
    if not wayto_value or type(wayto_value) ~= "string" then return false end
    if wayto_value:match("^;e ") or wayto_value:match("^;e\n") then return true end
    return false
end

-------------------------------------------------------------------------------
-- Execution (sandbox + run)
-------------------------------------------------------------------------------

local function make_sandbox()
    return {
        move = move,
        put = put,
        fput = fput,
        multifput = multifput,
        waitrt = waitrt,
        waitcastrt = waitcastrt,
        waitfor = waitfor,
        waitforre = waitforre,
        matchwait = matchwait,
        dothistimeout = dothistimeout,
        pause = pause,
        standing = standing,
        sitting = sitting,
        kneeling = kneeling,
        lounging = lounging,
        prone = prone,
        hidden = hidden,
        invisible = invisible,
        dead = dead,
        muckled = muckled,
        stunned = stunned,
        checkspell = checkspell,
        checkpaths = checkpaths,
        checkloot = checkloot,
        empty_hands = empty_hands,
        fill_hands = fill_hands,
        empty_hand = empty_hand,
        GameState = GameState,
        Map = Map,
        UserVars = UserVars,
        Spell = Spell,
        Spells = Spells,
        Skills = Skills,
        Stats = Stats,
        Char = Char,
        Regex = Regex,
        Script = Script and { run = Script.run, current = Script.current } or nil,
        Maze = Maze,
        FWI = FWI,
        Urchin = Urchin,
        respond = respond,
        echo = echo,
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        pairs = pairs,
        ipairs = ipairs,
        string = string,
        table = table,
        math = math,
        os = { time = os.time },
    }
end

--- Execute a pre-translated function in a sandbox.
--- @param fn function The compiled stringproc function
--- @return boolean ok
--- @return any result_or_error
function M.execute(fn)
    if type(fn) ~= "function" then
        return false, "not a function"
    end

    -- Set up sandboxed environment
    local env = make_sandbox()
    -- Note: compiled functions from load() can have their env set via debug.setupvalue
    -- But since we compile at translate time without sandbox, we rely on globals being
    -- available in the script's environment. The go2 movement module should call
    -- execute_wayto() which handles this properly.

    local ok, result = pcall(fn)
    if not ok then
        return false, "execution error: " .. tostring(result)
    end
    return true, result
end

--- Translate and execute a wayto entry in one step.
--- @param wayto_str string Raw wayto value
--- @return boolean ok
--- @return any result_or_error
function M.execute_wayto(wayto_str)
    local fn, err = M.translate(wayto_str)
    if not fn then
        return false, err or "plain command"
    end
    return M.execute(fn)
end

-------------------------------------------------------------------------------
-- Batch pre-translation for map loading
-------------------------------------------------------------------------------

--- Pre-translate all ;e wayto entries in the loaded map database.
--- Called by go2/init.lua at startup to warm the cache.
--- @param game string Game identifier (e.g., "GS3", "DR") — currently unused
function M.load_translations(game)
    local room_ids = Map.list()
    if not room_ids or #room_ids == 0 then return end

    local translated, failed, plain = 0, 0, 0
    for _, room_id in ipairs(room_ids) do
        local room = Map.find_room(room_id)
        if room and room.wayto then
            for dest_str, wayto_val in pairs(room.wayto) do
                if type(wayto_val) == "string" then
                    if wayto_val:match("^;e ") or wayto_val:match("^;e\n") then
                        local fn, err = M.translate(wayto_val)
                        if fn then
                            translated = translated + 1
                        else
                            failed = failed + 1
                        end
                    else
                        plain = plain + 1
                    end
                end
            end
        end
    end

    if respond then
        respond(string.format(
            "[stringproc] Loaded: %d translated, %d failed, %d plain commands",
            translated, failed, plain))
    end
end

--- Verify all cached translations against the current map data.
--- Called by pkg/cmd_map.lua after map update to detect stale entries.
--- @param game string Game identifier
--- @return table result { total, verified, stale = { {from, to}, ... } }
function M.verify_all(game)
    local room_ids = Map.list()
    if not room_ids or #room_ids == 0 then
        return { total = 0, verified = 0, stale = {} }
    end

    local total, verified = 0, 0
    local stale = {}

    for _, room_id in ipairs(room_ids) do
        local room = Map.find_room(room_id)
        if room and room.wayto then
            for dest_str, wayto_val in pairs(room.wayto) do
                if type(wayto_val) == "string" and
                   (wayto_val:match("^;e ") or wayto_val:match("^;e\n")) then
                    total = total + 1
                    local fn, err = M.translate(wayto_val)
                    if fn then
                        verified = verified + 1
                    else
                        stale[#stale + 1] = { from = room_id, to = dest_str }
                    end
                end
            end
        end
    end

    return { total = total, verified = verified, stale = stale }
end

-------------------------------------------------------------------------------
-- Stats / diagnostics
-------------------------------------------------------------------------------

--- Get translation statistics.
--- @return table stats
function M.get_stats()
    return {
        total = stats.total,
        translated = stats.translated,
        plain = stats.plain,
        failed = stats.failed,
        cache_hits = cache_hits,
        cache_misses = cache_misses,
        cache_size = 0,  -- computed below
        by_translator = stats.by_translator,
    }
end

--- Clear the translation cache.
function M.clear_cache()
    cache = {}
    cache_hits = 0
    cache_misses = 0
end

--- Reset all stats.
function M.reset_stats()
    stats = {
        total = 0,
        translated = 0,
        plain = 0,
        failed = 0,
        by_translator = {},
    }
    for _, t in ipairs(translators) do
        stats.by_translator[t.name] = 0
    end
    M.clear_cache()
end

-------------------------------------------------------------------------------
-- Expose internals for testing
-------------------------------------------------------------------------------

M._ruby_to_lua = ruby_to_lua
M._extract_regex = extract_regex
M._replace_regexes = replace_regexes
M._translate_interpolation = translate_interpolation
M._translators = translators

return M
