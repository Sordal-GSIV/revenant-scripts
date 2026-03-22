--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: star_watch
--- version: 1.1.0
--- author: unknown
--- game: gs
--- description: Annotates "Also here:" lines so alt characters show as "Alt (Main)"
--- tags: alts, star, watch, also here
---
--- Companion for ;star-alt. Called by ;star-alt; no need to run manually.
--- CharSettings.main_alts must be a JSON object: {"MainChar": ["Alt1", "Alt2"]}

-- Escape regex metacharacters in a string for use in Regex.new()
local function regex_escape(s)
    return (s:gsub("([%.%+%*%?%(%)%[%]%^%$%|%{%}\\])", "\\%1"))
end

local function build_alt_map()
    local map = {}
    local raw = CharSettings.main_alts
    if not raw or raw == "" then return map end
    local ok, alts = pcall(Json.decode, raw)
    if not ok or type(alts) ~= "table" then
        echo("star-watch: couldn't parse main_alts from CharSettings: " .. tostring(alts))
        return map
    end
    for main, list in pairs(alts) do
        if type(list) == "table" then
            for _, alt in ipairs(list) do
                local a = tostring(alt):match("^%s*(.-)%s*$")
                if a and #a > 0 then
                    map[a:lower()] = main
                end
            end
        elseif type(list) == "string" then
            local a = list:match("^%s*(.-)%s*$")
            if a and #a > 0 then
                map[a:lower()] = main
            end
        end
    end
    return map
end

local ALT_MAP_LC = build_alt_map()

-- Pre-compile word-boundary regexes for each alt key (mirrors Ruby \b..\b(?!\s*\())
local ALT_REGEXES = {}
for alt_key, main in pairs(ALT_MAP_LC) do
    local ok, re = pcall(Regex.new, "(?i)\\b(" .. regex_escape(alt_key) .. ")\\b(?!\\s*\\()")
    if ok then
        ALT_REGEXES[alt_key] = { re = re, main = main }
    end
end

local HOOK_ID = "star_watch_alt_annotator"

DownstreamHook.add(HOOK_ID, function(server_string)
    local ok, result = pcall(function()
        if not server_string or not server_string:find("Also here:") then
            return server_string
        end

        local prefix, rest = server_string:match("^(.-Also here:%s*)(.*)")
        if not prefix or not rest then
            return server_string
        end

        local had_nl = server_string:sub(-1) == "\n"

        -- Split on ", " (comma + any surrounding whitespace)
        local parts = {}
        for part in rest:gmatch("[^,]+") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end

        local new_parts = {}
        for _, pc in ipairs(parts) do
            -- Try to match XML anchor tag: <a ... noun='NAME' ...>...</a>
            local pre, anchor, noun, post = pc:match("(.-)(<%a[^>]*noun=['\"]([^'\"]+)['\"][^>]*>.-</%a>)(.*)")
            if noun then
                local main = ALT_MAP_LC[noun:lower()]
                if main then
                    table.insert(new_parts, pre .. anchor .. " (" .. main .. ")" .. post)
                else
                    table.insert(new_parts, pc)
                end
            else
                -- Plain text: word-boundary match, skip if already annotated (mirrors Ruby \b..\b(?!\s*\())
                local altered = pc
                for _, entry in pairs(ALT_REGEXES) do
                    if entry.re:test(altered) then
                        altered = entry.re:replace(altered, "$1 (" .. entry.main .. ")")
                        break
                    end
                end
                table.insert(new_parts, altered)
            end
        end

        local out = prefix .. table.concat(new_parts, ", ")
        if had_nl and out:sub(-1) ~= "\n" then
            out = out .. "\n"
        end
        return out
    end)

    if ok then return result end
    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
end)

echo("star-watch: running. Alts will show as 'Alt (Main)' in 'Also here:' lines. Use ;kill star_watch to stop.")

while true do
    wait()
end
