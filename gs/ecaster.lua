--- @revenant-script
--- @lic-audit: validated 2026-03-17
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
    -- Escape XML entities for Stormfront/Wrayth frontends
    message = message:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    respond(message .. "\r\n")
end

local function send_prompt()
    -- No-op in Revenant; prompt is managed by the engine
end

--------------------------------------------------------------------------------
-- Command handlers
--------------------------------------------------------------------------------

local function show_help()
    respond("<output class=\"mono\"/>\r\n")
    send_to_client("")
    send_to_client(" ECaster helps you cast your spells!")
    send_to_client("")
    send_to_client(" Usage:")
    send_to_client("  ;ec alias {spell} {name}     -- set an alias for a spell number")
    send_to_client("  ;ec alias clear {name}        -- remove an alias")
    send_to_client("  ;ec verb {spell} {verb}       -- force a specific verb for a spell")
    send_to_client("  ;ec verb {spell} clear         -- remove verb override")
    send_to_client("  ;ec stance {spell} {stance}   -- stance before casting")
    send_to_client("  ;ec hide {spell}              -- toggle hide after casting")
    send_to_client("  ;ec set {option} on|off")
    send_to_client("    channel  -- attempt to use channel verb")
    send_to_client("    safety   -- prevent casting without valid target")
    send_to_client("    stance   -- change stance for aimed spells")
    send_to_client("    hide     -- hide after casting from hide list")
    send_to_client("    conserve -- skip cast if insufficient mana")
    send_to_client("")
    send_to_client(" Options: " .. Json.encode(options))
    send_to_client(" Stances: " .. Json.encode(stance_map))
    send_to_client(" Aliases: " .. Json.encode(alias_map))
    send_to_client(" Verbs: " .. Json.encode(verb_map))
    send_to_client(" Hide: " .. Json.encode(hide_list))
    send_to_client("")
    respond("<output class=\"\"/>\r\n")
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
    if not spell or not verb then
        send_to_client("You must specify a valid spell number and verb.")
        return
    end
    if verb == "clear" then
        verb_map[spell] = nil
        send_to_client("Removed verb for spell " .. spell .. ".")
    else
        if not table_contains(VALID_VERBS, verb) then
            send_to_client("Invalid verb '" .. verb .. "'. Valid: cast, channel, evoke")
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
            send_to_client("Invalid stance '" .. stance .. "'. Valid: " .. table.concat(STANCES, ", "))
            return
        end
        local old = stance_map[spell]
        stance_map[spell] = stance
        if old then
            send_to_client("Spell " .. spell .. " was set to stance '" .. old .. "', changing to '" .. stance .. "'.")
        else
            send_to_client("Set spell " .. spell .. " to stance '" .. stance .. "'.")
        end
    end
    save_json_setting("stance_map", stance_map)
end

local function handle_option(opt, value)
    if not opt or not value then
        send_to_client("You must specify a valid option and value.")
        return
    end
    if options[opt] == nil then
        send_to_client("Invalid option '" .. opt .. "'.")
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

local function get_hostile_npcs()
    local npcs = GameObj.npcs()
    local hostiles = {}
    for _, npc in ipairs(npcs) do
        if not npc.status or not (npc.status:find("dead") or npc.status:find("gone")) then
            hostiles[#hostiles + 1] = npc
        end
    end
    return hostiles
end

local function valid_target(target_str)
    if not target_str then return false end
    local npcs = get_hostile_npcs()
    local lower = target_str:lower()

    -- Parse ordinal prefix (e.g., "second troll", "other kobold", "third dark troll")
    local words = {}
    for w in lower:gmatch("%S+") do
        words[#words + 1] = w
    end

    -- Map "other" to "second"
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
    local search_words
    if ordinal_index then
        search_words = {}
        for i = 2, #words do
            search_words[#search_words + 1] = words[i]
        end
    else
        ordinal_index = 1  -- default to first match
        search_words = words
    end

    if #search_words == 0 then return false end

    -- Match NPCs: for multi-word targets like "dark troll", each word must appear
    -- in the NPC name in order (with possible intervening text)
    local match_count = 0
    for _, npc in ipairs(npcs) do
        if npc.name then
            local name_lower = npc.name:lower()
            local matched = true
            local search_pos = 1
            for _, sw in ipairs(search_words) do
                local found = name_lower:find(sw, search_pos, true)
                if not found then
                    matched = false
                    break
                end
                search_pos = found + #sw
            end
            if matched then
                match_count = match_count + 1
                if match_count == ordinal_index then
                    return true
                end
            end
        end
    end
    return false
end

local function do_cast(input)
    local spell_number = input.number
    local spell_target = input.target
    local spell_alias = input.alias_name
    local count = input.count

    -- If target looks like a number, it's actually a count
    if spell_target and tonumber(spell_target) then
        count = spell_target
        spell_target = nil
    end

    local spell = Spell[spell_number]
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
        -- Spell 516 (Locate Person) always costs 1 mana regardless of mana_cost
        if spell.num == 516 then
            if Char.mana < 1 then
                send_to_client("Insufficient mana to cast " .. spell.name .. ".")
                return
            end
        else
            local cost = spell.mana_cost or 0
            local total = count and (cost * tonumber(count)) or cost
            if Char.mana < total then
                send_to_client("Insufficient mana to cast " .. spell.name .. ".")
                return
            end
        end
        if spell.type == "attack" and spell_target and not valid_target(spell_target) then
            send_to_client("Could not find valid target matching '" .. spell_target .. "'.")
            return
        end
    end

    -- Safety check
    if options.safety and spell.type == "attack" and #get_hostile_npcs() == 0 then
        send_to_client("No valid targets available to safely cast " .. spell.name .. ".")
        return
    end

    -- Hide after cast?
    local hide_after = options.hide and table_contains(hide_list, tonumber(spell_number))

    -- Wait for cast roundtime
    if checkcastrt() > 0 then
        echo("Waiting for cast roundtime...")
        waitcastrt()
    end

    -- Stance change before cast
    local pre_stance = stance_map[spell_alias] or stance_map[tostring(spell_number)]
    if not pre_stance and options.stance and spell.stance then
        pre_stance = "offensive"
    end
    if pre_stance then
        if GameState.stance ~= pre_stance and not dead() then
            for attempt = 1, 5 do
                local result = dothistimeout("stance " .. pre_stance, 2, STANCE_RX)
                if result then break end
                pause(0.2)
            end
        end
    end

    -- Determine verb
    local verb = verb_map[spell_alias] or verb_map[tostring(spell_number)] or "cast"
    if spell.channel and options.channel and verb == "evoke" then
        verb = "channel evoke"
    end

    -- Execute the cast
    local count_str = count and (" " .. count) or ""
    if spell_target then
        if verb == "cast" then
            fput("prepare " .. spell_number)
            waitcastrt()
            fput("cast at " .. spell_target)
        else
            put("target " .. spell_target)
            fput("incant " .. spell_number .. " " .. verb .. count_str)
        end
    else
        if verb ~= "cast" then
            fput("incant " .. spell_number .. " " .. verb .. count_str)
        else
            fput("incant " .. spell_number .. count_str)
        end
    end

    -- Stance back to guarded after cast
    if pre_stance then
        waitrt()
        for attempt = 1, 5 do
            local result = dothistimeout("stance guarded", 2, STANCE_RX)
            if result then break end
            pause(0.2)
        end
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
    local cmd_match = CMD_PATTERN:match(command)
    if cmd_match then
        cmd_queue[#cmd_queue + 1] = cmd_match[1] or ""
        return nil
    end

    -- Check for spell number input
    local spell_match = SPELL_PATTERN:match(command)
    if spell_match then
        local num = spell_match[1]
        -- Only intercept if it's a known spell
        if Spell[tonumber(num)] then
            spell_queue[#spell_queue + 1] = {
                number = num,
                target = spell_match[2],
                count = spell_match[3],
            }
            return nil
        end
    end

    -- Check for alias input
    local alias_match = ALIAS_PATTERN:match(command)
    if alias_match then
        local alias_name = alias_match[1]:lower()
        if alias_map[alias_name] then
            spell_queue[#spell_queue + 1] = {
                number = alias_map[alias_name],
                target = alias_match[2],
                count = alias_match[3],
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
        spell_queue = {}  -- clear remaining
        do_cast(spell)
    end
    if #cmd_queue > 0 then
        local cmd = table.remove(cmd_queue, 1)
        cmd_queue = {}
        handle_command(cmd)
    end
    pause(0.1)
end
