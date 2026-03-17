--- @revenant-script
--- name: target_numbers
--- version: 2.3.6
--- author: Ensayn
--- game: gs
--- description: Adds numbered identifiers to monsters in game output for targeting
--- tags: targeting, combat, UI
---
--- Usage:
---   ;target_numbers         - Start numbering
---   ;target_numbers debug   - Start with GameObj IDs shown
---   ;target_numbers help    - Show help

local debug_mode = false

if script.vars[1] and script.vars[1]:lower() == "help" then
    respond("USAGE: ;target_numbers [debug|help]")
    respond("Adds numbered identifiers to monsters for targeting.")
    respond(";kill target_numbers to stop")
    exit()
elseif script.vars[1] and script.vars[1]:lower() == "debug" then
    debug_mode = true
    echo("Debug mode enabled - showing GameObj IDs")
end

local monster_assignments = {}
local noun_counters = {}

echo("Target Numbers started - adding numbered identifiers to monsters...")
echo("Use ;kill target_numbers to stop")

add_hook("downstream", "target_numbers", function(xml)
    -- Clear on room change
    if xml:match("^%[.*%]%s+%(") then
        noun_counters = {}
        monster_assignments = {}
    end

    -- Process "You also see" lines
    if xml:match("You also see") then
        local modified = xml
        local targets = GameObj.targets or {}
        local target_ids = {}
        for _, t in ipairs(targets) do target_ids[t.id] = true end

        for id, noun, name in xml:gmatch('exist="(%d+)"[^>]*noun="([^"]+)"[^>]*>([^<]+)') do
            if target_ids[id] then
                noun_counters[noun] = (noun_counters[noun] or 0) + 1
                local num = noun_counters[noun]
                monster_assignments[id] = {noun = noun, number = num}
                local suffix = debug_mode and ("(" .. num .. ")(ID:" .. id .. ")") or ("(" .. num .. ")")
                if GameObj.target and GameObj.target.id == id then
                    suffix = suffix .. "(tgt)"
                end
                local escaped = name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                modified = modified:gsub('exist="' .. id .. '"[^>]*>' .. escaped .. '</a>',
                    'exist="' .. id .. '">' .. name .. suffix .. '</a>')
            end
        end
        return modified
    end

    return xml
end)

before_dying(function()
    remove_hook("downstream", "target_numbers")
    echo("Target Numbers stopped")
end)

while true do pause(1) end
