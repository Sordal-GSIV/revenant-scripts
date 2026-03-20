--- @revenant-script
--- name: target_numbers
--- version: 2.3.6
--- author: Ensayn
--- game: gs
--- description: Adds numbered identifiers to monsters in game output for easier targeting
--- tags: targeting, combat, UI
--- @lic-certified: complete 2026-03-20
---
--- Revision History:
---   v2.3.6 - 2025-09-24 - Fixed monster_id capture using match() instead of $1 global variable - action lines now work!
---   v2.3.5 - 2025-09-24 - Fixed critical regex bug - added missing quotes around monster_id in Pattern 1
---   v2.3.4 - 2025-09-24 - Simplified action line XML replacement using ID-based matching for better precision
---   v2.3.3 - 2025-09-24 - Fixed action line numbering - creatures now show numbers in combat actions
---   v2.3.2 - 2025-09-24 - Fixed duplicate ID handling - same creature ID gets same number across all occurrences
---   v2.3.1 - 2025-09-24 - Fixed to use GameObj.targets as filter, parse XML exist attributes for actual IDs/positioning
---   v2.3.0 - 2025-09-24 - Switched to GameObj.targets for monster detection, no IDs by default, per-type numbering
---   v2.2.0 - 2025-09-24 - Changed default to show IDs, added lynx and animal support, per-type numbering
---   v2.1.7 - 2025-09-24 - Added debug mode switch - IDs only shown when launched with 'debug' parameter
---   v2.1.6 - 2025-09-24 - Fixed room description target indicator to use ID matching instead of name+position
---   v2.1.5 - 2025-09-23 - Improved fallback to handle action lines with and without exist attributes
---   v2.1.4 - 2025-09-23 - Fixed room descriptions and added simple fallback for action lines
---   v2.1.3 - 2025-09-23 - Skip articles in regex matching for cleaner monster name handling
---   v2.1.2 - 2025-09-23 - Fixed pushBold regex to handle capital A properly
---   v2.1.1 - 2025-09-23 - Fixed regex to match pushBold XML structure properly
---   v2.1.0 - 2025-09-23 - Added GameObj ID display alongside numbers (number)(ID:xxxxx) format
---   v2.0.3 - 2025-09-23 - Fixed PC numbering and improved double numbering prevention
---   v2.0.2 - 2025-09-23 - Fixed double numbering in action lines
---   v2.0.1 - 2025-09-23 - Fixed numbering to reset properly and track IDs from room descriptions
---   v2.0.0 - 2025-09-23 - Rewritten to scan monsters as they appear, not rely on GameObj.targets
---   v1.2.0 - 2025-09-23 - Added ID display for tracking (number:id) format
---   v1.1.2 - 2025-09-23 - Dead monsters now keep their numbers until gone from room
---   v1.1.1 - 2025-09-23 - Fixed numbering to exclude dead monsters, reassign properly
---   v1.1.0 - 2025-09-23 - Added (tgt) indicator for currently targeted monster
---   v1.0.2 - 2025-09-23 - Fixed double numbering by separating room vs action processing
---   v1.0.1 - 2025-09-23 - Fixed duplicate numbering in room descriptions
---   v1.0.0 - 2025-09-23 - Initial implementation with DownstreamHook
---
--- Usage:
---   ;target_numbers         - Start numbering (IDs hidden by default)
---   ;target_numbers debug   - Start with GameObj IDs shown
---   ;target_numbers help    - Show help
---   ;kill target_numbers    - Stop numbering

local debug_mode = false

-- Parse command line arguments
for i = 1, #Script.vars do
    local arg = Script.vars[i]
    if arg:lower() == "help" then
        respond("\nUSAGE: ;target_numbers [help]\n")
        respond("DESCRIPTION:")
        respond("  Adds numbered identifiers to monsters in game output")
        respond("  for easier targeting. Numbers monsters as they appear.")
        respond("")
        respond("EXAMPLES:")
        respond("  A black-winged daggerbeak becomes:")
        respond("  A black-winged daggerbeak(1)")
        respond("")
        respond("COMMANDS:")
        respond("  ;target_numbers         Start numbering (IDs hidden by default)")
        respond("  ;target_numbers debug   Start with GameObj IDs shown")
        respond("  ;target_numbers help    Show this help")
        respond("  ;kill target_numbers    Stop numbering")
        exit()
    elseif arg:lower() == "debug" then
        debug_mode = true
        echo("Debug mode enabled - showing GameObj IDs")
    end
end

-- Track monster assignments by ID if we have it
local monster_assignments = {}  -- {id => {noun, number}}
local noun_counters = {}        -- {noun => next_number}

echo("Target Numbers started - adding numbered identifiers to monsters...")
echo("Use ;kill target_numbers to stop")

DownstreamHook.add("target_numbers", function(xml)
    -- Clear counters when entering a new room (detect room title: [Room Name] (u#12345))
    if xml:match("^%[.-%]%s+%([u#]%d+%)") then
        noun_counters = {}
        monster_assignments = {}
        return xml
    end

    -- Process "You also see" lines — number monsters in room descriptions
    if xml:match("You also see") then
        local modified = xml

        -- Build set of valid target IDs from GameObj
        local targets = GameObj.targets() or {}
        local target_ids = {}
        for _, t in ipairs(targets) do
            target_ids[t.id] = true
        end

        -- Extract creature IDs, nouns, and names from exist attributes in order of appearance
        local creatures_in_xml = {}
        local seen_ids = {}
        for id, noun, name in xml:gmatch('exist="(%d+)"[^>]*noun="([^"]+)"[^>]*>([^<]+)<') do
            if not seen_ids[id] then
                table.insert(creatures_in_xml, {
                    id   = id,
                    noun = noun,
                    name = name:match("^%s*(.-)%s*$"),
                })
                seen_ids[id] = true
            end
        end

        -- First pass: assign numbers to targetable creatures in appearance order
        local noun_numbers = {}
        for _, creature in ipairs(creatures_in_xml) do
            if target_ids[creature.id] then
                noun_numbers[creature.noun] = (noun_numbers[creature.noun] or 0) + 1
                local num = noun_numbers[creature.noun]
                monster_assignments[creature.id] = { noun = creature.noun, number = num }

                local suffix
                if debug_mode then
                    suffix = "(" .. num .. ")(ID:" .. creature.id .. ")"
                else
                    suffix = "(" .. num .. ")"
                end

                local current_target = GameObj.target()
                if current_target and current_target.id == creature.id then
                    suffix = suffix .. "(tgt)"
                end

                -- Replace all occurrences of this creature ID in the XML
                local escaped = creature.name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                modified = modified:gsub(
                    'exist="' .. creature.id .. '"[^>]*>' .. escaped .. '</a>',
                    'exist="' .. creature.id .. '">' .. creature.name .. suffix .. '</a>'
                )
            end
        end

        -- Second pass: replace any remaining unprocessed instances of known creatures
        for _, creature in ipairs(creatures_in_xml) do
            if target_ids[creature.id] and monster_assignments[creature.id] then
                local assignment = monster_assignments[creature.id]
                local suffix
                if debug_mode then
                    suffix = "(" .. assignment.number .. ")(ID:" .. creature.id .. ")"
                else
                    suffix = "(" .. assignment.number .. ")"
                end

                local current_target = GameObj.target()
                if current_target and current_target.id == creature.id then
                    suffix = suffix .. "(tgt)"
                end

                local escaped = creature.name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                modified = modified:gsub(
                    'exist="' .. creature.id .. '"[^>]*>' .. escaped .. '</a>',
                    'exist="' .. creature.id .. '">' .. creature.name .. suffix .. '</a>'
                )
            end
        end

        -- Store noun counts for use in subsequent action lines
        noun_counters = noun_numbers

        return modified
    end

    -- Process exist attributes for action lines (attacks, movements, etc.)
    local monster_id = xml:match('exist="(%d+)"')
    if monster_id then
        local modified = xml

        -- Try to extract monster noun and name from the XML
        local noun, full_name

        -- Pattern 1: <a exist="id" ... noun="noun" ...>name</a>
        noun, full_name = xml:match(
            '<a exist="' .. monster_id .. '"[^>]*noun="([^"]+)"[^>]*>([^<]+)</a>'
        )
        if full_name then
            full_name = full_name:match("^%s*(.-)%s*$")
        end

        -- Pattern 2: <pushBold/>Article <a exist="id" ... noun="noun" ...>name</a><popBold/>
        if not noun then
            noun, full_name = xml:match(
                '<pushBold/>%a+ <a exist="' .. monster_id .. '"[^>]*noun="([^"]+)"[^>]*>([^<]+)</a><popBold/>'
            )
            if full_name then
                full_name = full_name:match("^%s*(.-)%s*$")
            end
        end

        if noun and full_name then
            -- Skip if already numbered
            if not full_name:match("%(%d+%)") then
                -- Look up this creature in our room assignments
                if monster_assignments[monster_id] then
                    local number = monster_assignments[monster_id].number

                    local suffix
                    if debug_mode then
                        suffix = "(" .. number .. ")(ID:" .. monster_id .. ")"
                    else
                        suffix = "(" .. number .. ")"
                    end

                    local current_target = GameObj.target()
                    if current_target and current_target.id == monster_id then
                        suffix = suffix .. "(tgt)"
                    end

                    -- Insert the number into the XML using ID-based replacement
                    local escaped = full_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    modified = modified:gsub(
                        '<a exist="' .. monster_id .. '"[^>]*>' .. escaped .. '</a>',
                        '<a exist="' .. monster_id .. '">' .. full_name .. suffix .. '</a>'
                    )
                    return modified
                end
            end
        end
    end

    -- Pass through unchanged if no processing occurred
    return xml
end)

before_dying(function()
    DownstreamHook.remove("target_numbers")
    echo("Target Numbers stopped - monster numbering disabled")
end)

while true do pause(1) end
