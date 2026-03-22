--- @revenant-script
--- name: alias
--- version: 1.0.5
--- author: Sordal
--- original-authors: elanthia-online, Tillmen
--- description: Pattern-based command aliases with GUI, per-character and global scopes
--- game: Gemstone
--- tags: core, alias
--- @lic-certified: complete 2026-03-18

local args_lib = require("lib/args")
local cache = require("cache")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function apply_alias(entry, line)
    local repl = entry.replacement
    local t = type(repl)
    -- Case-insensitive matching: compare against lowercased line
    local lower_line = string.lower(line)

    if t == "string" then
        local ok, result = pcall(string.gsub, lower_line, entry.pattern, repl)
        if not ok or result == lower_line then return nil end

        -- Split on \r for multi-command sequences (original alias.lic behavior)
        local parts = {}
        for part in (result .. "\r"):gmatch("([^\r]*)\r") do
            local trimmed = part:match("^%s*(.-)%s*$")
            if #trimmed > 0 then parts[#parts + 1] = trimmed end
        end
        if #parts == 0 then return nil end

        -- Extract extra args after the matched trigger
        local _, match_end = lower_line:find(entry.pattern)
        local extra = nil
        if match_end then
            extra = line:sub(match_end + 1):match("^%s+(.+)$")
        end

        if extra then
            local has_placeholder = false
            for i, part in ipairs(parts) do
                if part:find("\\?", 1, true) then
                    parts[i] = part:gsub("\\%?", extra)
                    has_placeholder = true
                end
            end
            if not has_placeholder then
                -- Append extra to first command only (original behavior)
                parts[1] = parts[1] .. " " .. extra
            end
        else
            -- Strip \? placeholders when no extra args provided
            for i, part in ipairs(parts) do
                parts[i] = part:gsub("\\%?", ""):match("^%s*(.-)%s*$")
            end
        end

        if #parts == 1 then return parts[1] end
        return parts

    elseif t == "table" then
        if not lower_line:match(entry.pattern) then return nil end
        return repl

    elseif t == "function" then
        local captures = { lower_line:match(entry.pattern) }
        if #captures == 0 and not lower_line:match(entry.pattern) then return nil end
        local ok, result = pcall(repl, table.unpack(captures))
        if not ok then
            respond("[alias] function error in '" .. entry.name .. "': " .. tostring(result))
            return nil
        end
        return result
    end
    return nil
end

local function send_commands(cmds)
    -- Use put() (not fput) to match original do_client behavior — no RT wait between cmds
    if type(cmds) == "string" then
        local trimmed = cmds:match("^%s*(.-)%s*$")
        if #trimmed > 0 then put(trimmed) end
    elseif type(cmds) == "table" then
        for _, c in ipairs(cmds) do
            if type(c) == "string" then
                local trimmed = c:match("^%s*(.-)%s*$")
                if #trimmed > 0 then put(trimmed) end
            end
        end
    end
end

-- ── Command mode ─────────────────────────────────────────────────────────────

local input  = Script.vars[0] or ""
local parsed = args_lib.parse(input)
local cmd    = parsed.args[1]

if cmd then
    local is_global = (parsed["global"] == true)
    local scope_lbl = is_global and "global" or "character"

    cache.load_all()

    if cmd == "add" or cmd == "set" then
        local name    = parsed.args[2]
        local pattern = parsed.args[3]
        local repl    = parsed.args[4]
        if not name or not pattern or not repl then
            respond("Usage: ;alias add <name> <pattern> <replacement> [--global]")
            respond("  \\r in replacement = multi-command separator")
            respond("  \\? in replacement = extra args placeholder")
        else
            local list = is_global and cache.get_global() or cache.get_char()
            local found = false
            for i, entry in ipairs(list) do
                if entry.name == name then
                    respond("Alias updated. (old replacement was: " .. tostring(entry.replacement) .. ")")
                    list[i] = { name = name, pattern = pattern, replacement = repl }
                    found = true
                    break
                end
            end
            if not found then
                list[#list + 1] = { name = name, pattern = pattern, replacement = repl }
                respond("Alias '" .. name .. "' saved to " .. scope_lbl .. " list.")
            end
            if is_global then cache.save_global(list) else cache.save_char(list) end
        end

    elseif cmd == "remove" or cmd == "rem" or cmd == "delete" or cmd == "del" then
        local name = parsed.args[2]
        if not name then
            respond("Usage: ;alias remove <name> [--global]")
        else
            local list = is_global and cache.get_global() or cache.get_char()
            local new = {}
            local removed_entry = nil
            for _, entry in ipairs(list) do
                if entry.name ~= name then
                    new[#new + 1] = entry
                else
                    removed_entry = entry
                end
            end
            if removed_entry then
                if is_global then cache.save_global(new) else cache.save_char(new) end
                respond("Alias deleted (" .. name .. " => " .. tostring(removed_entry.replacement) .. ")")
            else
                respond("Alias was not found in " .. scope_lbl .. " list.")
            end
        end

    elseif cmd == "enable" then
        CharSettings["alias_enabled"] = "true"
        respond("Aliases enabled.")

    elseif cmd == "disable" then
        CharSettings["alias_enabled"] = "false"
        respond("Aliases disabled.")

    elseif cmd == "list" then
        local char_list   = cache.get_char()
        local global_list = cache.get_global()
        local enabled     = CharSettings["alias_enabled"] ~= "false"
        local output = "\nAliases: " .. (enabled and "enabled" or "disabled") .. "\n"

        output = output .. "\nGlobal Aliases:\n\n"
        if #global_list == 0 then
            output = output .. "   (none)\n"
        else
            local sorted = {}
            for _, e in ipairs(global_list) do sorted[#sorted + 1] = e end
            table.sort(sorted, function(a, b) return a.name < b.name end)
            for _, e in ipairs(sorted) do
                output = output .. string.format("   %-20s  %s  ->  %s\n",
                    e.name, e.pattern, tostring(e.replacement))
            end
        end

        output = output .. "\n" .. (GameState.name or "Character") .. "'s Aliases:\n\n"
        if #char_list == 0 then
            output = output .. "   (none)\n"
        else
            local sorted = {}
            for _, e in ipairs(char_list) do sorted[#sorted + 1] = e end
            table.sort(sorted, function(a, b) return a.name < b.name end)
            for _, e in ipairs(sorted) do
                output = output .. string.format("   %-20s  %s  ->  %s\n",
                    e.name, e.pattern, tostring(e.replacement))
            end
        end
        respond(output)

    elseif cmd == "setup" then
        cache.load_all()
        local gui = require("gui_settings")
        gui.open(cache)
        return

    elseif cmd == "reload" then
        cache.reload()
        respond("Alias data reloaded.")

    elseif cmd == "stop" then
        UpstreamHook.remove("alias_intercept")
        respond("Alias daemon stopped.")
        return

    elseif cmd == "help" then
        local output = "\n"
        output = output .. "Usage:\n\n"
        output = output .. "     ;alias setup\n"
        output = output .. "          Opens a window to configure aliases.\n\n"
        output = output .. "     ;alias add <name> <pattern> <replacement> [--global]\n"
        output = output .. "          Creates a new alias. When you send a command matching <pattern>,\n"
        output = output .. "          it will be replaced with <replacement>. --global makes it active\n"
        output = output .. "          for all characters. Patterns are Lua patterns (case-insensitive).\n"
        output = output .. "          \\r in replacement = multi-command separator.\n"
        output = output .. "          \\? in replacement = extra args placeholder.\n\n"
        output = output .. "     ;alias remove <name> [--global]\n"
        output = output .. "          Deletes the given alias.\n\n"
        output = output .. "     ;alias list\n"
        output = output .. "          Lists the currently active aliases.\n\n"
        output = output .. "     ;alias enable / disable\n"
        output = output .. "          Toggle alias processing on or off.\n\n"
        output = output .. "     ;alias reload\n"
        output = output .. "          Reload aliases from storage.\n\n"
        output = output .. "     ;alias stop\n"
        output = output .. "          Stop the alias daemon.\n\n"
        output = output .. "Examples:\n\n"
        output = output .. "     ;alias add ls ^ls$ look\n"
        output = output .. "     ;alias add zap ^zap$ ;cast 901 \\? --global\n"
        output = output .. "     ;alias add combo ^combo$ attack troll\\rsmile\n"
        respond(output)

    else
        respond("Unknown command '" .. cmd .. "'. Use ;alias help for usage.")
    end

    return
end

-- ── Bare invocation: show list ───────────────────────────────────────────────
cache.load_all()
do
    local char_list   = cache.get_char()
    local global_list = cache.get_global()
    local enabled     = CharSettings["alias_enabled"] ~= "false"
    respond("Aliases: " .. (enabled and "enabled" or "disabled"))
    respond("Character aliases (" .. #char_list .. "):")
    for _, e in ipairs(char_list) do
        respond(string.format("  %-20s  %s  ->  %s", e.name, e.pattern, tostring(e.replacement)))
    end
    respond("Global aliases (" .. #global_list .. "):")
    for _, e in ipairs(global_list) do
        respond(string.format("  %-20s  %s  ->  %s", e.name, e.pattern, tostring(e.replacement)))
    end
end

-- ── Tier 2: Load personal aliases.lua config ─────────────────────────────────

local tier2_list = {}
local function alias(name, pattern, replacement)
    tier2_list[#tier2_list + 1] = { name = name, pattern = pattern, replacement = replacement }
end

local aliases_src, _ = File.read("aliases.lua")
if aliases_src then
    local fn, err = load(aliases_src, "aliases.lua", "t",
        setmetatable({ alias = alias }, { __index = _G }))
    if fn then
        local ok, load_err = pcall(fn)
        if not ok then respond("aliases.lua load error: " .. tostring(load_err)) end
    else
        respond("aliases.lua syntax error: " .. tostring(err))
    end
end
cache.set_tier2(tier2_list)

-- ── Daemon mode: UpstreamHook ────────────────────────────────────────────────

UpstreamHook.add("alias_intercept", function(data)
    if CharSettings["alias_enabled"] == "false" then return data end

    local line = data:match("^(.-)\r?\n?$") or data
    -- Strip <c> XML prefix
    line = line:gsub("^<c>", "")

    -- Check precedence: char CLI -> global CLI -> tier2
    local lists = {
        cache.get_char(),
        cache.get_global(),
        cache.get_tier2(),
    }

    for _, list in ipairs(lists) do
        for _, entry in ipairs(list) do
            local result = apply_alias(entry, line)
            if result ~= nil then
                send_commands(result)
                return ""
            end
        end
    end

    return data
end)

before_dying(function()
    UpstreamHook.remove("alias_intercept")
end)

respond("alias: daemon running. Use ;alias help for commands.")
while true do pause() end
