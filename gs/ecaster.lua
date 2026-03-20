--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: ecaster
--- version: 1.2.2
--- author: elanthia-online
--- contributors: Selandriel
--- game: gs
--- description: Spell casting automation with aliases, stances, and verb overrides
--- tags: magic,spell,casting
---
--- Changelog (from Lich5):
---   v1.2.2 - Remove mantle stuff, use spellactive.lic instead
---   v1.2.1 - Fix mantle method variable name typo
---   v1.2.0 - Switch to Spell.force_<type> command logic
---   v1.1.4 - Use GameObj.targets instead of npcs
---   v1.1.3 - Change CharSettings.save to Settings.save
---   v1.1.2 - Fix hide_me variable name conflict
---   v1.1.0 - Hide after casting from hide list
---   v1.0.0 - Forked and renamed as ecaster from voodoo

-- Check for conflicting script
if running("voodoo") then
    echo("You already have 'voodoo' running, which will conflict.")
    echo("Please ;kill voodoo and try again.")
    return
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_json_setting(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json_setting(key, val)
    CharSettings[key] = Json.encode(val)
end

local options = load_json_setting("options", {
    channel = false, conserve = false, safety = false, stance = false, hide = false,
})

local hide_list = load_json_setting("hide_list", {})
local stance_map = load_json_setting("stance_map", {})
local alias_map = load_json_setting("alias_map", {})
local verb_map = load_json_setting("verb_map", {})

local ORDINALS = {"first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh"}
local STANCES = {"offensive", "advance", "forward", "neutral", "guarded", "defensive"}
local VALID_VERBS = {"cast", "channel", "evoke"}

local STANCE_RX = Regex.new("You are now in an? \\w+ stance\\.|Cast Roundtime in effect:  Setting stance to \\w+\\.")
local CAST_RX = Regex.new("(?:Cast|Channel|Evoke) at what\\?|You do not currently have a target\\.|You (?:gesture|cast|channel|evoke)|(?:\\.\\.\\.)?[Ww]ait \\d+ [Ss]ec(?:onds)?\\.|You are unable to do that right now\\.|You can't make that dextrous of a move!")

local UPSTREAM_HOOK_ID = Script.name .. "_upstream_hook"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

local function table_remove_value(t, val)
    for i = #t, 1, -1 do
        if t[i] == val then table.remove(t, i) end
    end
end

local function send_to_client(message)
    respond(message)
end

--------------------------------------------------------------------------------
-- Command handlers
--------------------------------------------------------------------------------

local function show_help()
    respond("<output class=\"mono\"/>")
    send_to_client("")
    send_to_client(" ECaster helps you cast your spells!")
    send_to_client("")
    send_to_client(" Usage:")
    send_to_client("  ;ec alias {spell} {name}     -- set an alias for a spell number")
    send_to_client("  ;ec alias clear {name}        -- remove an alias")
    send_to_client("")
    send_to_client("  ;ec verb {spell} {verb}       -- force a specific verb for a spell")
    send_to_client("  ;ec verb {spell} clear         -- remove verb override")
    send_to_client("    -- force ecaster to use a specific verb for a given spell")
    send_to_client("")
    send_to_client("  ;ec stance {spell} {stance}   -- stance before casting")
    send_to_client("    -- change stance to {stance} (default 'offensive') before casting {spell}")
    send_to_client("        will stance back to guarded after cast")
    send_to_client("")
    send_to_client("  ;ec hide {spell}              -- toggle hide after casting")
    send_to_client("    -- add or remove a given spell to your hide list")
    send_to_client("        ecaster will attempt to hide after casting these spells")
    send_to_client("")
    send_to_client("  ;ec set {option} on|off")
    send_to_client("    channel  -- attempt to use channel verb for supported spells")
    send_to_client("    safety   -- prevent casting offensive spells without valid target in room")
    send_to_client("    stance   -- attempt to change stance for aimed spells only")
    send_to_client("     hide    -- attempt to hide after casting a spell from the hide list")
    send_to_client("")
    send_to_client("    conserve -- do not cast spell if insufficient mana or if specific target is not valid")
    send_to_client("")
    send_to_client(" Options: " .. Json.encode(options))
    send_to_client("")
    send_to_client(" Stances: " .. Json.encode(stance_map))
    send_to_client("")
    send_to_client(" Alias: " .. Json.encode(alias_map))
    send_to_client("")
    send_to_client(" Verbs: " .. Json.encode(verb_map))
    send_to_client("")
    send_to_client(" Hide: " .. Json.encode(hide_list))
    send_to_client("")
    respond("<output class=\"\"/>")
end

local function handle_hide(spell_number)
    if not spell_number or spell_number == "" then
        send_to_client("You must specify a valid spell number.")
        return
    end
    local num = tonumber(spell_number)
    if not num or not Spell[num] then
        send_to_client("You must specify a valid spell number.")
        return
    end
    if table_contains(hide_list, num) then
        table_remove_value(hide_list, num)
        send_to_client(num .. " has been removed from your hide list.")
    else
        hide_list[#hide_list + 1] = num
        send_to_client(num .. " has been added to your hide list.")
    end
    save_json_setting("hide_list", hide_list)
end

local function handle_verb(spell, verb)
    local valid_verbs_message = "Valid verbs include: incant, channel, evoke"
    if not spell or not verb then
        send_to_client("You must specify a valid spell number and verb.  " .. valid_verbs_message)
        return
    end
    if verb == "clear" then
        verb_map[spell] = nil
        send_to_client("Removed verb for spell " .. spell .. ".")
    else
        if not table_contains(VALID_VERBS, verb) then
            send_to_client("The specified verb '" .. verb .. "' is invalid.  " .. valid_verbs_message)
            return
        end
        local old = verb_map[spell]
        verb_map[spell] = verb
        if old then
            send_to_client("Spell " .. spell .. " was set to use the '" .. old .. "' verb, changing to '" .. verb .. "'.")
        else
            send_to_client("Spell " .. spell .. " will now use " .. verb .. " verb.")
        end
    end
    save_json_setting("verb_map", verb_map)
end

local function handle_alias(spell, command)
    if not spell or not command then
        send_to_client("You must specify a valid spell number and alias name.")
        return
    end
    if spell == "clear" then
        alias_map[command] = nil
        send_to_client("Removed alias '" .. command .. "'.")
    else
        local old = alias_map[command]
        alias_map[command] = spell
        if old then
            send_to_client("Alias '" .. command .. "' was set to spell " .. old .. ", changing to " .. spell .. ".")
        else
            send_to_client("Created alias '" .. command .. "' for spell " .. spell .. ".")
        end
    end
    save_json_setting("alias_map", alias_map)
end

local function handle_stance(spell, stance)
    if not spell or not stance then
        send_to_client("You must specify a valid spell number and stance.")
        return
    end
    if stance == "clear" then
        stance_map[spell] = nil
        send_to_client("Removed stance for spell " .. spell .. ".")
    else
        if not table_contains(STANCES, stance) then
            send_to_client("Specified stance '" .. stance .. "' is not recognized.")
            send_to_client("Valid options include: " .. table.concat(STANCES, ", "))
            return
        end
        local old = stance_map[spell]
        stance_map[spell] = stance
        if old then
            send_to_client("Stance for spell " .. spell .. " was '" .. old .. ", changing to '" .. stance .. "'.")
        else
            send_to_client("Set spell " .. spell .. " to use stance '" .. stance .. "'.")
        end
    end
    save_json_setting("stance_map", stance_map)
end

local function handle_option(opt, value)
    if not opt or not value then
        send_to_client("You must specify a valid option and value.")
        send_to_client("Valid options include: channel conserve safety stance hide")
        return
    end
    if options[opt] == nil then
        send_to_client("Specified option '" .. opt .. "' is not valid.")
        send_to_client("Current options are: " .. Json.encode(options))
        return
    end
    options[opt] = (value == "on")
    save_json_setting("options", options)
    send_to_client("Set option '" .. opt .. "' to " .. tostring(options[opt]) .. ".")
end

local function handle_command(args)
    if not args or args == "" then
        show_help()
        return
    end

    local parts = {}
    for word in args:gmatch("%S+") do
        parts[#parts + 1] = word
    end

    local action = parts[1]
    local first = parts[2]
    local second = parts[3]

    if action == "help" then
        show_help()
    elseif action == "stance" then
        handle_stance(first, second)
    elseif action == "alias" then
        handle_alias(first, second)
    elseif action == "verb" then
        handle_verb(first, second)
    elseif action == "set" then
        handle_option(first, second)
    elseif action == "hide" then
        handle_hide(first)
    else
        show_help()
    end
end

--------------------------------------------------------------------------------
-- Casting
--------------------------------------------------------------------------------

--- Count live (non-dead, non-gone) targets in the room.
--- Matches Lich5: GameObj.targets.count { |t| t.status !~ /dead|gone/ }
local function valid_targets_count()
    local targets = GameObj.targets()
    local count = 0
    for _, t in ipairs(targets) do
        if not t.status or not (t.status:find("dead") or t.status:find("gone")) then
            count = count + 1
        end
    end
    return count
end

--- Check if a specific target string resolves to a valid (alive) target.
--- Handles ordinals: "second troll", "other kobold", "third dark troll"
--- Matches Lich5 ECaster.valid_target? using GameObj.targets
local function valid_target(target_str)
    if not target_str then return false end
    local targets = GameObj.targets()
    local lower = target_str:lower()

    local words = {}
    for w in lower:gmatch("%S+") do
        words[#words + 1] = w
    end

    -- Map "other" to "second" (Lich5 behavior)
    if words[1] == "other" then words[1] = "second" end

    -- Check if first word is an ordinal
    local ordinal_index = nil
    for i, ord in ipairs(ORDINALS) do
        if words[1] == ord then
            ordinal_index = i
            break
        end
    end

    -- Build search terms (remaining words after ordinal, or all words)
    local search_start = 1
    if ordinal_index then
        search_start = 2
    else
        ordinal_index = 1
    end

    -- Build regex pattern matching Lich5: /word1(?:.+?)word2/ or /word1/
    local search_words = {}
    for i = search_start, #words do
        search_words[#search_words + 1] = words[i]
    end
    if #search_words == 0 then return false end

    local pattern
    if #search_words >= 2 then
        -- Multi-word: first_word(?:.+?)last_word (Lich5 builds regex with intervening .+?)
        pattern = Regex.new(search_words[1] .. "(?:.+?)" .. search_words[#search_words])
    else
        pattern = Regex.new(search_words[1])
    end

    -- Find the nth matching target
    local match_count = 0
    for _, t in ipairs(targets) do
        if t.name and pattern:test(t.name:lower()) then
            if not t.status or not (t.status:find("dead") or t.status:find("gone")) then
                match_count = match_count + 1
                if match_count == ordinal_index then
                    return true
                end
            end
        end
    end
    return false
end

--- Affordability check matching Lich5 ECaster.affordable?
local function affordable(spell, count)
    -- Spell 516 (Locate Person) always costs 1 mana regardless
    if spell.num == 516 and Char.mana >= 1 then
        return true
    elseif spell.num == 516 then
        return false
    end
    local cost = spell.mana_cost or 0
    if count then
        return Char.mana >= (cost * tonumber(count))
    else
        return Char.mana >= cost
    end
end

local function do_cast(input)
    local spell_number = input.number
    local spell_target = input.target
    local spell_alias = input.alias_name
    local count = input.count

    -- If target looks like a number, it's actually a count (Lich5 behavior)
    if spell_target and tostring(tonumber(spell_target)) == spell_target then
        count = spell_target
        spell_target = nil
    end

    local spell_num = tonumber(spell_number)
    local spell = Spell[spell_num]

    if not spell then
        send_to_client("Spell number " .. tostring(spell_number) .. " is not a known spell.")
        return
    end

    if not spell.known then
        send_to_client("You do not know the " .. spell.name .. " spell!")
        return
    end

    -- Conserve mode checks
    if options.conserve then
        if not affordable(spell, count) then
            send_to_client("Insufficient mana to cast " .. spell.name .. ".")
            return
        end
        if spell.type == "attack" and spell_target and not valid_target(spell_target) then
            send_to_client("Could not find valid target matching '" .. spell_target .. "'.")
            return
        end
    end

    -- Safety check: no offensive spells without valid targets
    if options.safety and spell.type == "attack" and valid_targets_count() == 0 then
        send_to_client("No valid targets available to safely cast " .. spell.name .. ".")
        return
    end

    -- Hide after cast?
    local hide_after = options.hide and table_contains(hide_list, spell_num)

    -- Wait for cast roundtime
    if checkcastrt() > 0 then
        echo("Waiting for cast roundtime...")
        while checkcastrt() > 0 do
            waitcastrt()
        end
    end

    -- Stance change before cast
    local pre_stance = (spell_alias and stance_map[spell_alias]) or stance_map[tostring(spell_number)]
    if not pre_stance and options.stance and spell.stance then
        pre_stance = "offensive"
    end
    if pre_stance then
        if GameState.stance ~= pre_stance and not dead() then
            local result
            repeat
                result = dothistimeout("stance " .. pre_stance, 2, STANCE_RX)
            until result and STANCE_RX:test(result)
        end
    end

    -- Determine verb
    local verb = (spell_alias and verb_map[spell_alias]) or verb_map[tostring(spell_number)] or "cast"
    local should_channel = spell.channel and options.channel
    if should_channel and verb == "evoke" then
        verb = "channel evoke"
    end

    -- Execute the cast using Spell force methods (matches Lich5 v1.2.0+)
    if spell_target then
        if verb == "cast" then
            -- Lich5: Spell[num].force_cast(target, count)
            spell:force_cast(spell_target, count)
        else
            -- Lich5: put "target #{target}"; Spell[num].force_incant("#{verb} #{count}")
            put("target " .. spell_target)
            local incant_args = verb
            if count and count ~= "" then
                incant_args = incant_args .. " " .. count
            end
            spell:force_incant(incant_args)
        end
    else
        if verb ~= "cast" then
            -- Lich5: Spell[num].force_incant("#{verb} #{count}")
            local incant_args = verb
            if count and count ~= "" then
                incant_args = incant_args .. " " .. count
            end
            spell:force_incant(incant_args)
        else
            -- Lich5: Spell[num].force_incant("#{count}")
            spell:force_incant(count or "")
        end
    end

    -- Stance back to guarded after cast
    if pre_stance then
        waitrt()
        local result
        repeat
            result = dothistimeout("stance guarded", 2, STANCE_RX)
        until result and STANCE_RX:test(result)
    end

    -- Hide after cast
    if hide_after then
        put("hide")
    end
end

--------------------------------------------------------------------------------
-- Upstream hook: intercept spell numbers and aliases
--------------------------------------------------------------------------------

local SPELL_PATTERN = Regex.new("^(?:<c>)?(\\d{3,4})\\s?(.+?)?\\s?(\\d+)?$")
local ALIAS_PATTERN = Regex.new("^(?:<c>)?(\\w+)\\s?(.+?)?\\s?(\\d+)?$")
local CMD_PATTERN = Regex.new("^(?:<c>)?;(?:" .. Script.name .. "|ec)(?:\\s(.*))?$")

local spell_queue = {}
local cmd_queue = {}

UpstreamHook.add(UPSTREAM_HOOK_ID, function(command)
    -- Check for ecaster commands first
    local cmd_caps = CMD_PATTERN:captures(command)
    if cmd_caps then
        cmd_queue[#cmd_queue + 1] = cmd_caps[1] or ""
        return nil
    end

    -- Check for spell number input (3-4 digit number)
    local spell_caps = SPELL_PATTERN:captures(command)
    if spell_caps then
        local num = spell_caps[1]
        -- Only intercept if it's a known spell
        if Spell[tonumber(num)] then
            spell_queue[#spell_queue + 1] = {
                number = num,
                target = spell_caps[2],
                count = spell_caps[3],
            }
            return nil
        end
    end

    -- Check for alias input
    local alias_caps = ALIAS_PATTERN:captures(command)
    if alias_caps then
        local alias_name = alias_caps[1]:lower()
        if alias_map[alias_name] then
            spell_queue[#spell_queue + 1] = {
                number = alias_map[alias_name],
                target = alias_caps[2],
                count = alias_caps[3],
                alias_name = alias_name,
            }
            return nil
        end
    end

    return command
end)

before_dying(function()
    UpstreamHook.remove(UPSTREAM_HOOK_ID)
end)

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

echo("Type ;ec for options.")

while true do
    if #spell_queue > 0 then
        local spell = table.remove(spell_queue, 1)
        spell_queue = {}  -- clear remaining (Lich5: SPELL_QUEUE.clear)
        do_cast(spell)
    end
    if #cmd_queue > 0 then
        local cmd = table.remove(cmd_queue, 1)
        cmd_queue = {}
        handle_command(cmd)
    end
    pause(0.1)
end
