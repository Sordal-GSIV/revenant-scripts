--- @revenant-script
--- name: linktothefast
--- version: 0.1.7
--- author: elanthia-online
--- contributors: LostRanger
--- description: Convert links to highlights for Wrayth performance
--- game: gs
---
--- Changelog (from Lich5):
---   v0.1.7 (2026-03-17)
---     - Change Stormfront to Wrayth (renamed by Simu)
---   v0.1.6 (2023-10-05)
---     - Fix nested <d> and <a> xml components
---   v0.1.5 (2023-06-04)
---     - Remove $SAFE references
---   v0.1.4 (2019-09-27)
---     - Fix assorted issues when multiple linkables are within a preset
---   v0.1.3 (2019-09-27)
---     - Now prompts for trust on Ruby installs BEFORE breaking things
---   v0.1.2 (2019-09-25)
---     - Now prompts for trust on Ruby installs that need it
---     - Handles cases where multiple links existed within one preset
---   v0.1.1 (2019-09-25)
---     - Approximately 94% less broken
---     - Supports recolor
---   v0.1.0 (2019-09-25)
---     - Initial release

-- Check frontend
if not Frontend.supports_xml() then
    echo("This script is designed for XML frontends (Wrayth). Your frontend may not benefit.")
end

-- The core hook: replace <a> link tags with colored preset text
DownstreamHook.add("linktothefast", function(line)
    -- Replace <a exist="..." noun="...">text</a> with colored text
    -- Also handle nested <d cmd="...">text</d> inside links
    line = line:gsub('<a exist="[^"]*" noun="[^"]*">(.-)</a>', function(inner)
        -- Strip any <d> tags inside, keep the text
        local text = inner:gsub('<d[^>]*>(.-)</d>', '%1')
        return '<preset id="speech">' .. text .. '</preset>'
    end)
    return line
end)

echo("version 0.1.7 started. Stop me with ;kill linktothefast")
hide_me()

-- Keep running until killed
while true do
    pause(60)
end
