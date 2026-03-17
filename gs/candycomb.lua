--- @revenant-script
--- name: candycomb
--- version: 1.0.0
--- author: Lucullan
--- game: gs
--- description: Automate combining candy in your bag by bundling every three pieces
--- tags: candy,combine,bundle
---
--- Usage:
---   ;candycomb <total_candy>   Bundles candy (every 3 pieces)
---   ;candycomb --help          Show help
---
--- Notes:
---   - Each bundle uses a sequence of pull and put to combine three pieces.
---   - Be sure you're holding your bag and have enough candy inside.

local arg = Script.vars[0] or ""

if arg == "" or arg == "--help" or arg == "help" then
    echo("author: Lucullan")
    echo("date: 10/11/2025")
    echo("")
    echo("Usage:")
    echo("  ;candycomb <total_candy>")
    echo("")
    echo("Description:")
    echo("  Automates combining candy in your bag by bundling every three pieces.")
    echo("  Only affects the slot currently turned to.")
    echo("")
    echo("Arguments:")
    echo("  total_candy   The total number of candy pieces you have.")
    echo("")
    echo("Examples:")
    echo("  ;candycomb 27   # Bundles candy 9 times")
    echo("  ;candycomb 5    # Bundles candy once")
    echo("")
    echo("Notes:")
    echo("  - Each bundle uses a sequence of pull and put to combine three pieces.")
    echo("  - Be sure you're holding your bag and have enough candy inside.")
    return
end

local total_candy = tonumber(arg)
if not total_candy or total_candy < 3 then
    echo("Need at least 3 candy pieces. Usage: ;candycomb <total_candy>")
    return
end

echo("Total candy: " .. total_candy)

local bundles = math.floor(total_candy / 3)
for _ = 1, bundles do
    put("pull my bag")
    put("pull my bag")
    fput("bundle")
    fput("pull my bag")
    fput("bundle")
    fput("put right in my bag")
end
