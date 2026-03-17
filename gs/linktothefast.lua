--- @revenant-script
--- name: linktothefast
--- version: 0.1.7
--- description: Convert links to highlights for Wrayth performance
--- game: gs

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
