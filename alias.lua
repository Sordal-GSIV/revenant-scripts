--- @revenant-script
--- name: alias
--- version: 0.1.0
--- author: Sordal
--- description: Command alias expansion via upstream hooks

-- alias.lua
-- Registers command aliases via UpstreamHook.
-- Set aliases: CharSettings["aliases"] = "alias1=expansion1;alias2=expansion2"

local function load_aliases()
    local aliases = {}
    local count = 0
    local setting = CharSettings["aliases"] or ""
    for pair in setting:gmatch("[^;]+") do
        local alias, expansion = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if alias and expansion and alias ~= "" then
            aliases[alias] = expansion
            count = count + 1
        end
    end
    return aliases, count
end

UpstreamHook.add("alias", function(cmd)
    local trimmed = cmd:match("^%s*(.-)%s*\n?$")
    local aliases = load_aliases()
    if aliases[trimmed] then
        return aliases[trimmed] .. "\n"
    end
    return cmd
end)

local _, count = load_aliases()
respond("[alias] loaded " .. count .. " aliases")
