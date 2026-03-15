--- @revenant-script
--- name: alias
--- version: 1.0.0
--- author: Sordal
--- description: Pattern-based command aliases with GUI, per-character and global scopes

local args_lib = require("lib/args")
local cache = require("cache")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function apply_alias(entry, line)
    local repl = entry.replacement
    local t = type(repl)

    if t == "string" then
        local ok, result = pcall(line.gsub, line, entry.pattern, repl)
        if not ok or result == line then return nil end

        -- \? arg interpolation: extract extra args after the trigger match
        local _, match_end = line:find(entry.pattern)
        if match_end then
            local extra = line:sub(match_end + 1):match("^%s+(.+)$")
            if extra then
                if result:find("\\?", 1, true) then
                    result = result:gsub("\\%?", extra)
                elseif not result:find(";") then
                    result = result .. " " .. extra
                end
            end
        end

        return result

    elseif t == "table" then
        if not line:match(entry.pattern) then return nil end
        return repl

    elseif t == "function" then
        local captures = { line:match(entry.pattern) }
        if #captures == 0 and not line:match(entry.pattern) then return nil end
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
    if type(cmds) == "string" then
        for part in cmds:gmatch("[^;]+") do
            local trimmed = part:match("^%s*(.-)%s*$")
            if #trimmed > 0 then
                fput(trimmed)
            end
        end
    elseif type(cmds) == "table" then
        for _, c in ipairs(cmds) do
            if type(c) == "string" then fput(c) end
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

    if cmd == "add" then
        local name    = parsed.args[2]
        local pattern = parsed.args[3]
        local repl    = parsed.args[4]
        if not name or not pattern or not repl then
            respond("Usage: ;alias add <name> <pattern> <replacement> [--global]")
        else
            local list = is_global and cache.get_global() or cache.get_char()
            local found = false
            for i, entry in ipairs(list) do
                if entry.name == name then
                    list[i] = { name = name, pattern = pattern, replacement = repl }
                    found = true
                    break
                end
            end
            if not found then
                list[#list + 1] = { name = name, pattern = pattern, replacement = repl }
            end
            if is_global then cache.save_global(list) else cache.save_char(list) end
            respond("Alias '" .. name .. "' saved to " .. scope_lbl .. " list.")
        end

    elseif cmd == "remove" then
        local name = parsed.args[2]
        if not name then
            respond("Usage: ;alias remove <name> [--global]")
        else
            local list = is_global and cache.get_global() or cache.get_char()
            local new = {}
            for _, entry in ipairs(list) do
                if entry.name ~= name then new[#new + 1] = entry end
            end
            if #new < #list then
                if is_global then cache.save_global(new) else cache.save_char(new) end
                respond("Alias '" .. name .. "' removed from " .. scope_lbl .. " list.")
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
        respond("Aliases: " .. (enabled and "enabled" or "disabled"))
        respond("Character aliases (" .. #char_list .. "):")
        for _, e in ipairs(char_list) do
            respond(string.format("  %-20s  %s  ->  %s", e.name, e.pattern, tostring(e.replacement)))
        end
        respond("Global aliases (" .. #global_list .. "):")
        for _, e in ipairs(global_list) do
            respond(string.format("  %-20s  %s  ->  %s", e.name, e.pattern, tostring(e.replacement)))
        end

    elseif cmd == "setup" then
        cache.load_all()
        local gui = require("gui_settings")
        gui.open(cache)
        return

    elseif cmd == "reload" then
        cache.reload()
        respond("Aliases reloaded from database.")

    elseif cmd == "stop" then
        UpstreamHook.remove("alias_intercept")
        respond("Alias daemon stopped.")
        return

    else
        respond("Usage: ;alias <command>")
        respond("  list             Show all aliases")
        respond("  add <n> <p> <r>  Add alias [--global]")
        respond("  remove <name>    Remove alias [--global]")
        respond("  enable/disable   Toggle aliases on/off")
        respond("  setup            Open settings GUI")
        respond("  reload           Reload aliases from database")
        respond("  stop             Stop alias daemon")
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
