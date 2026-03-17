--- @revenant-script
--- name: star_watch
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Annotates "Also here:" lines so alt characters show as "Alt (Main)"
--- tags: alts, star, watch, also here
---
--- Companion for ;star-alt. Called by ;star-alt; no need to run manually.

local function build_alt_map()
    local map = {}
    local ok, alts = pcall(function()
        return CharSettings.main_alts or {}
    end)
    if ok and type(alts) == "table" then
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
    end
    return map
end

local ALT_MAP_LC = build_alt_map()

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

        -- Split on ", "
        local parts = {}
        for part in rest:gmatch("[^,]+") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end

        local new_parts = {}
        for _, pc in ipairs(parts) do
            -- Try to match anchor tag with noun
            local pre, anchor, noun, post = pc:match("(.-)(<%a[^>]*noun=['\"]([^'\"]+)['\"][^>]*>.-</%a>)(.*)")
            if noun then
                local main = ALT_MAP_LC[noun:lower()]
                if main then
                    table.insert(new_parts, pre .. anchor .. " (" .. main .. ")" .. post)
                else
                    table.insert(new_parts, pc)
                end
            else
                -- Try plain text matching
                local altered = pc
                for alt_key, main in pairs(ALT_MAP_LC) do
                    -- Case-insensitive word boundary match
                    local pattern = "(%f[%a])" .. alt_key .. "(%f[%A])"
                    if altered:lower():find(alt_key, 1, true) then
                        -- Only annotate if not already annotated
                        if not altered:find("%(") then
                            altered = altered:gsub("([%a]+)", function(m)
                                if m:lower() == alt_key then
                                    return m .. " (" .. main .. ")"
                                end
                                return m
                            end, 1)
                            break
                        end
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
    pause(1)
end
