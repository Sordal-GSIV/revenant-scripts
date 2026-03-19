--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: linktothefast
--- version: 0.1.7
--- author: elanthia-online
--- contributors: LostRanger
--- description: Wrap links with preset colors for Wrayth performance
--- game: gs
---
--- Wrayth performance is negatively affected by links, but it handles highlights
--- just fine. linktothefast wraps all links with XML that says to use the
--- link-colored preset, so you still get the benefits of link colors even while
--- links are turned off. Then you can turn links off (default: Alt+L) to gain
--- better performance in Wrayth and just toggle them on if needed.
---
--- ;autostart add --global linktothefast
---
--- Changelog (from Lich5):
---   v0.1.7 (2026-03-17)
---     - Change Stormfront to Wrayth (renamed by Simu)
---   v0.1.6 (2023-10-05)
---     - Fix nested <d> and <a> xml components
---   v0.1.5 (2023-06-04)
---     - Remove $SAFE references
---   v0.1.4 (2019-09-27)
---     - Fix assorted issues when multiple linkables are within a preset,
---       like when people talk to animals.
---   v0.1.3 (2019-09-27)
---     - Now prompts for trust on Ruby installs BEFORE breaking things.
---   v0.1.2 (2019-09-25)
---     - Now prompts for trust on Ruby installs that need it.
---     - Handles cases where multiple links existed within one preset
---       (i.e. directed speech)
---   v0.1.1 (2019-09-25)
---     - Approximately 94% less broken
---     - Supports recolor.
---   v0.1.0 (2019-09-25)
---     - Initial release

-- Check for XML-supporting frontend
if not Frontend.supports_xml() then
    echo("Wait, this isn't Wrayth.  I'm probably only useful with Wrayth, but you're welcome to try...")
end

-- Register cleanup hook to remove our downstream hook when killed
before_dying(function()
    DownstreamHook.remove("linktothefast")
end)

--- Process a game line: wrap <a> and <d> link tags with <preset id='link'>,
--- then strip those wrappers inside bold blocks and nested presets.
--- This replicates the full algorithm from the Ruby original by LostRanger.
local function process_line(server_string)
    if not server_string then
        return server_string
    end

    -- Bail early if no link-like tags exist
    if not server_string:find("<a[ >]") and not server_string:find("<d[ >]") then
        return server_string
    end

    -- Wrap all <a ...>...</a> tags with <preset id='link'>...</preset>
    server_string = server_string:gsub("(<a[^>]*>.-</a>)", "<preset id='link'>%1</preset>")

    -- Wrap all <d[^>]*>...</d> tags with <preset id='link'>...</preset>
    server_string = server_string:gsub("(<d[^>]*>.-</d>)", "<preset id='link'>%1</preset>")

    -- Strip our link presets inside <pushBold/>...<popBold/> blocks.
    -- In Wrayth, bolded links use bold formatting rather than a mix, and that
    -- ceases to be true if a preset is applied.
    server_string = server_string:gsub("(<pushBold%s*/>.-<popBold%s*/>)", function(s)
        return s:gsub("<preset id='link'>(.-)</preset>", "%1")
    end)

    -- Same for regular <b>...</b> bold text
    server_string = server_string:gsub("(<b%s*>.-</b%s*>)", function(s)
        return s:gsub("<preset id='link'>(.-)</preset>", "%1")
    end)

    -- Nested preset handling with bitwise stack.
    --
    -- Recolor and speech use presets. We use presets. Links within a preset normally
    -- follow the preset color, so we need to strip any link presets we added that
    -- are nested inside another preset.
    --
    -- We use an integer as a stack of booleans (one bit per nesting level).
    -- Opening <preset ...> tag:
    --   - Shift stack left (push)
    --   - If stack was empty (0) or tag is NOT our link preset, set bit 0 to 1
    --     (keep the tag) and emit the tag
    --   - Otherwise strip the tag (bit 0 stays 0)
    -- Closing </preset> tag:
    --   - If stack is 0, underflow: pass through
    --   - If bit 0 is 1, tag was kept: emit and pop
    --   - If bit 0 is 0, tag was stripped: emit nothing and pop
    local result = {}
    local pos = 1
    local stack = 0
    local len = #server_string

    while pos <= len do
        -- Find the next preset tag (opening or closing)
        local tag_start, tag_end, slash, attrs = server_string:find("<(/?)(preset[^>]*)>", pos)
        if not tag_start then
            -- No more preset tags; append the rest
            result[#result + 1] = server_string:sub(pos)
            break
        end

        -- Append everything before this tag
        if tag_start > pos then
            result[#result + 1] = server_string:sub(pos, tag_start - 1)
        end

        local full_tag = server_string:sub(tag_start, tag_end)

        if slash == "" then
            -- Opening <preset ...> tag
            local tag_attrs = attrs:sub(7) -- strip "preset", leaving " id='link'" etc.
            stack = stack * 2  -- shift left by 1 (push)
            if stack == 0 or tag_attrs ~= " id='link'" then
                -- Stack was empty before push, or it's not our link preset: keep it
                stack = stack + 1  -- set bit 0
                result[#result + 1] = full_tag
            end
            -- else: Nested inside another preset AND it IS our link preset: strip it
        else
            -- Closing </preset> tag
            if stack == 0 then
                -- Stack underflow, pass through silently
                result[#result + 1] = full_tag
            elseif stack % 2 == 1 then
                -- bit 0 is 1: this tag was kept
                stack = math.floor(stack / 2)  -- shift right (pop)
                result[#result + 1] = full_tag
            else
                -- bit 0 is 0: this tag was stripped
                stack = math.floor(stack / 2)  -- shift right (pop)
                -- emit nothing
            end
        end

        pos = tag_end + 1
    end

    return table.concat(result)
end

-- Register the downstream hook
DownstreamHook.add("linktothefast", process_line)

echo("version 0.1.7 (2026-03-17) started.  Stop me with ;kill linktothefast")
hide_me()

-- Keep running until killed
while true do
    pause(60)
end
