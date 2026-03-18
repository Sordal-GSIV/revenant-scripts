local config = require("config")

local M = {}

local CLOTTING_SPELL = 9909
local STAUNCHING_SPELL = 9905
local TROLLS_BLOOD_SPELL = 1125
local EXERTION_SPELL = 1107

local function debug_msg(settings, msg)
    if settings.debug then
        respond("[ECure DEBUG] " .. msg)
    end
end

-- Maps appraisal body-part text back to the WOUND_KEY_MAP keys used by Wounds/Scars
local APPRAISE_PART_TO_KEY = {
    ["right eye"]  = "rightEye",  ["left eye"]  = "leftEye",
    ["right arm"]  = "rightArm",  ["left arm"]  = "leftArm",
    ["right hand"] = "rightHand", ["left hand"] = "leftHand",
    ["right leg"]  = "rightLeg",  ["left leg"]  = "leftLeg",
    head = "head", neck = "neck", chest = "chest", back = "back",
    abdomen = "abdomen", ["abdominal area"] = "abdomen",
    nerves = "nsys", exertion = "exertion",
}

-- Maps appraisal body-part text to the ecure config part names
local APPRAISE_PART_TO_ECURE = {
    ["right eye"]  = "righteye",  ["left eye"]  = "lefteye",
    ["right arm"]  = "rightarm",  ["left arm"]  = "leftarm",
    ["right hand"] = "righthand", ["left hand"] = "lefthand",
    ["right leg"]  = "rightleg",  ["left leg"]  = "leftleg",
    head = "head", neck = "neck", chest = "chest", back = "back",
    abdomen = "abdomen", ["abdominal area"] = "abdomen",
    nerves = "nerves", exertion = "exertion",
}

--- Strip XML tags from a string
local function strip_xml(s)
    return s:gsub("<[^>]+>", "")
end

--- Clean a wound description line by normalising grammar and removing XML
local function clean_wound_line(line)
    line = line:gsub("arm and", "arm, ")
    line = line:gsub('<d cmd[^>]*>', "")
    line = line:gsub('</d[^>]*>', "")
    return line
end

--- Extract wound phrase fragments from a cleaned wound description line.
--- Returns a table of raw wound phrase strings.
local function extract_wound_array(line)
    local results = {}
    -- All the wound/scar patterns from the original Ruby regex
    local patterns = {
        "a [%w%-]+%s+[lr][ie][gf][hg]t%s+eye",
        "a [%w%-]+%s+left%s+eye",
        "severe bruises and swelling around%s+[lr][ie][gf][hg]t%s+eye",
        "severe bruises and swelling around%s+left%s+eye",
        "old battle scars? on%s+%w+%s+[lr][ie][gf][hg]t%s+%w+",
        "old battle scars? on%s+%w+%s+left%s+%w+",
        "old battle scar across%s+%w+%s+%w+",
        "several painful%-looking scars across%s+%w+%s+%w+",
        "terrible, permanent mutilation of%s+%w+%s+%w+",
        "mangled%s+[lr][ie][gf][hg]t%s+%w+",
        "mangled%s+left%s+%w+",
        "missing%s+[lr][ie][gf][hg]t%s+%w+",
        "missing%s+left%s+%w+",
        "deep lacerations across%s+%w+%s+%w+",
        "deep gashes and serious bleeding%s+%w+%s+%w+%s+%w+",
        "minor cuts and bruises on%s+%w+%s+[lr][ie][gf][hg]t%s+%w+",
        "minor cuts and bruises on%s+%w+%s+left%s+%w+",
        "minor cuts and bruises on%s+%w+%s+%w+",
        "a fractured and bleeding%s+[lr][ie][gf][hg]t%s+%w+",
        "a fractured and bleeding%s+left%s+%w+",
        "a completely severed%s+[lr][ie][gf][hg]t%s+%w+",
        "a completely severed%s+left%s+%w+",
        "moderate bleeding from%s+%w+%s+neck",
        "snapped bones and serious bleeding from the neck",
        "minor bruises on%s+%w+%s+neck",
        "scar across%s+%w+%s+neck",
        "some old neck wounds",
        "terrible scars from some serious neck injury",
        "minor bruises about the head",
        "minor lacerations about the head",
        "severe head trauma and bleeding from the ears",
        "scar across%s+%w+%s+face",
        "several facial scars",
        "old mutilation wounds about%s+%w+%s+head",
        "strange case of muscle twitching",
        "case of sporadic convulsions",
        "case of uncontrollable convulsions",
        "developed slurred speech",
        "constant muscle spasms",
        "a very difficult time with muscle control",
        "overexerted",
    }
    for _, pat in ipairs(patterns) do
        local s, e = line:find(pat)
        while s do
            table.insert(results, line:sub(s, e))
            s, e = line:find(pat, e + 1)
        end
    end
    return results
end

--- Map a single wound phrase to a body part name (matches Ruby parse_body_parts).
--- Returns the body part string used by the transfer command, or nil.
local function wound_phrase_to_part(wound)
    -- Left/right limb/eye patterns
    local rl, bp = wound:match("(%w+)%s+(%w+)%s*$")
    if rl and (rl == "right" or rl == "left") then
        return rl .. " " .. bp
    end
    -- Chest/back/abdominal scar/wound patterns
    if wound:find("chest") then return "chest" end
    if wound:find("back") then return "back" end
    if wound:find("abdom") then return "abdomen" end
    -- Neck
    if wound:find("neck") then return "neck" end
    -- Head
    if wound:find("head") or wound:find("face") or wound:find("facial") or wound:find("ears") then return "head" end
    -- Nerves
    if wound:find("muscle") or wound:find("convulsion") or wound:find("slurred") then return "nerves" end
    -- Exertion
    if wound:find("overexerted") then return "exertion" end
    return nil
end

--- Appraise a target up to 3 times, parsing wound descriptions.
--- Returns (heal_target_name, body_parts_table, wound_description_string) or (nil, {}, "")
local function appraise_target(settings, target_name)
    local wounds_raw = {}
    local heal_target = nil

    for attempt = 1, 3 do
        debug_msg(settings, "Appraising " .. target_name .. " (attempt " .. attempt .. "/3)")
        waitrt()

        -- Install a downstream hook to capture the appraisal output
        local captured = {}
        local capture_done = false
        DownstreamHook.add("Appraising", function(line)
            if not capture_done then
                table.insert(captured, line)
            end
            return line
        end)

        fput("appraise " .. target_name)
        pause(1)
        capture_done = true
        DownstreamHook.remove("Appraising")

        -- Also check reget for the appraisal output
        local lines = reget(20)
        for _, rawline in ipairs(lines) do
            local line = strip_xml(rawline)
            -- "You take a quick appraisal of <name> and find that he/she has <wounds>."
            local appraised, detected = line:match("You take a quick appraisal of (%w+) and find that %w+ has (.+)%.")
            if appraised and detected then
                table.insert(wounds_raw, strip_xml(detected))
                heal_target = appraised
            end
            -- Scar line: "He/She has <scars>."
            if heal_target and (Skills.mltransference or 0) >= 50 then
                local scars = line:match("^%s*[HS][eh]e? has (.+)%.$")
                if scars and not scars:find("appraisal") then
                    table.insert(wounds_raw, strip_xml(scars))
                end
            end
            -- Overexertion: "appears to have overexerted"
            if line:find("appears to have.*overexerted") then
                table.insert(wounds_raw, "overexerted")
            end
            -- "appears somewhat haggard" / "appears to be very tired"
            if line:find("appears somewhat haggard") or line:find("appears to be very tired") then
                table.insert(wounds_raw, "overexerted")
            end
            -- Error cases
            if line:find("Appraise what") or line:find("^Usage:") then
                heal_target = target_name
                table.insert(wounds_raw, line)
            end
        end

        debug_msg(settings, "Appraise result - target=" .. tostring(heal_target) .. " wounds=" .. table.concat(wounds_raw, "; "))
        if heal_target then break end
    end

    if not heal_target then
        return nil, {}, ""
    end

    -- Join all wound fragments
    local wound_line = table.concat(wounds_raw, ", ")

    -- Check for "no apparent injuries"
    if wound_line:find("no apparent injuries") or wound_line:find("no apparent wounds$") then
        if not wound_line:find("overexerted") then
            return heal_target, {}, wound_line
        end
    end

    -- Parse into body parts
    local cleaned = clean_wound_line(wound_line)
    local wound_phrases = extract_wound_array(cleaned)
    local body_parts = {}
    local seen = {}
    for _, phrase in ipairs(wound_phrases) do
        local part = wound_phrase_to_part(phrase)
        if part and not seen[part] then
            seen[part] = true
            table.insert(body_parts, part)
        end
    end

    debug_msg(settings, "Parsed body parts: " .. table.concat(body_parts, ", "))
    return heal_target, body_parts, wound_line
end

-- Spell hindrance retry wrapper
local function attempt_with_hindrance_retry(settings, action)
    local max_attempts = 3
    for attempt = 1, max_attempts do
        local result = action(attempt, max_attempts)
        if result and result:find("^Cast") then
            break
        elseif result and result:find("^%[Spell") then
            respond("Spell hindrance detected (attempt " .. attempt .. "/" .. max_attempts .. "), retrying...")
            if attempt >= max_attempts then
                respond("Failed after " .. max_attempts .. " attempts due to spell hindrance")
                break
            end
            pause(1 + attempt)
        else
            if attempt < max_attempts then
                respond("Command timeout (attempt " .. attempt .. "/" .. max_attempts .. "), retrying...")
                pause(1)
            else
                respond("Command failed after " .. max_attempts .. " attempts")
                break
            end
        end
    end
    pause(0.5)
    waitcastrt()
    waitrt()
end

local function wait_for_mana(settings, required)
    if Char.mana >= required then return end
    debug_msg(settings, "Waiting for mana: need " .. required .. ", have " .. Char.mana)
    respond("Waiting for mana...")
    wait_until(function() return Char.mana >= required end)
end

local function check_signs(settings)
    if not settings.use_signs then return end
    local sign_spell = nil
    if Spell.known_p(CLOTTING_SPELL) then
        sign_spell = CLOTTING_SPELL
    elseif Spell.known_p(STAUNCHING_SPELL) then
        sign_spell = STAUNCHING_SPELL
    end
    if not sign_spell then return end
    if Spell.active_p(sign_spell) then return end
    debug_msg(settings, "Casting sign spell " .. sign_spell)
    wait_until(function() return Char.mana >= (Spell[sign_spell].mana_cost or 5) end)
    fput("incant " .. sign_spell)
    waitcastrt()
end

local function cast_trolls_blood(settings)
    if not settings.use_trolls_blood then return end
    if not Spell.known_p(TROLLS_BLOOD_SPELL) then return end
    if Spell.active_p(TROLLS_BLOOD_SPELL) then return end
    debug_msg(settings, "Casting Troll's Blood (1125)")
    local cost = Spell[TROLLS_BLOOD_SPELL].mana_cost or 25
    wait_for_mana(settings, cost)
    fput("incant 1125")
    waitcastrt()
end

local function restore_health(settings)
    while Char.percent_health < 90 do
        debug_msg(settings, "Restoring health: " .. Char.health .. " (" .. Char.percent_health .. "%)")
        attempt_with_hindrance_retry(settings, function(attempt, max)
            wait_for_mana(settings, 1)
            waitrt()
            waitcastrt()
            debug_msg(settings, "cure blood (attempt " .. attempt .. "/" .. max .. ", mana=" .. Char.mana .. ")")
            return dothistimeout("cure blood", 2, "^%[Spell Hindrance", "^Cast")
        end)
    end
end

local function calculate_mana_cost(base_cost, severe, is_scar)
    local cost = base_cost
    if severe then cost = cost + 5 end
    if is_scar then cost = cost + 9 end
    return cost
end

local function heal_body_part(settings, part, severe, is_scar)
    check_signs(settings)
    restore_health(settings)

    local base_cost = config.cost_for(part)
    local mana_cost = calculate_mana_cost(base_cost, severe, is_scar)
    local formatted = config.format_for_command(part)

    debug_msg(settings, "cure " .. formatted .. " - est. mana: " .. mana_cost ..
        " (severe=" .. tostring(severe) .. " scar=" .. tostring(is_scar) .. ")")

    attempt_with_hindrance_retry(settings, function(attempt, max)
        wait_for_mana(settings, mana_cost)
        waitrt()
        waitcastrt()
        debug_msg(settings, "Executing 'cure " .. formatted .. "' (attempt " .. attempt .. "/" .. max ..
            ", mana=" .. Char.mana .. ")")
        return dothistimeout("cure " .. formatted, 2, "^%[Spell Hindrance", "^Cast")
    end)
end

local function heal_to_scar_level(settings, part, target_level)
    local key = config.wound_key(part)
    while (Scars[key] or 0) > target_level do
        while (Wounds[key] or 0) > 0 do
            heal_body_part(settings, part, (Wounds[key] or 0) > 1, false)
        end
        heal_body_part(settings, part, false, true)
    end
end

-- Main self-heal cycle
function M.heal_self(settings)
    debug_msg(settings, "Starting self-heal. health=" .. Char.health ..
        " (" .. Char.percent_health .. "%) mana=" .. Char.mana .. " mode=" .. (settings.mode or "heal"))

    -- Heal exertion
    if Effects and Effects.Debuffs and Effects.Debuffs.active("Overexerted") then
        attempt_with_hindrance_retry(settings, function(attempt, max)
            wait_for_mana(settings, 7)
            waitrt()
            waitcastrt()
            debug_msg(settings, "Casting exertion cure (attempt " .. attempt .. "/" .. max .. ")")
            return dothistimeout("incant 1107", 2, "^%[Spell Hindrance", "^Cast")
        end)
    end

    cast_trolls_blood(settings)

    -- Heal wounds, highest severity first (3 → 0)
    for level = 3, 0, -1 do
        for _, part in ipairs(config.BODY_PARTS) do
            if part ~= "nerves" then -- nerves handled below
                local key = config.wound_key(part)
                local current = Wounds[key] or 0
                local target = config.wound_level(settings, part)
                if current == level and current > target then
                    -- Handle critical parts priority
                    local is_critical = false
                    for _, cp in ipairs(config.CRITICAL_PARTS) do
                        if cp == part then is_critical = true; break end
                    end
                    if is_critical and settings.head_nerve_priority then
                        debug_msg(settings, part .. " is critical - priority heal-down")
                        heal_to_scar_level(settings, part, 1)
                    end
                    debug_msg(settings, "Healing wound on " .. part .. " (level " .. current .. ")")
                    heal_body_part(settings, part, current > 1, false)
                end
            end
        end
        -- Nerves
        local nsys_current = Wounds.nsys or 0
        local nsys_target = config.wound_level(settings, "nerves")
        if nsys_current == level and nsys_current > nsys_target then
            if settings.head_nerve_priority then
                heal_to_scar_level(settings, "nerves", 1)
            end
            heal_body_part(settings, "nerves", nsys_current > 1, false)
        end
    end

    -- Heal scars, highest severity first (3 → 0)
    for level = 3, 0, -1 do
        for _, part in ipairs(config.BODY_PARTS) do
            local key = config.wound_key(part)
            local current_scar = Scars[key] or 0
            local current_wound = Wounds[key] or 0
            local target = config.scar_level(settings, part)
            if current_scar == level and current_wound == 0 and current_scar > target then
                debug_msg(settings, "Healing scar on " .. part .. " (level " .. current_scar .. ")")
                heal_body_part(settings, part, current_scar > 1, true)
            end
        end
    end

    restore_health(settings)

    -- Done verb
    if settings.done_verb and settings.done_verb ~= "" then
        fput(settings.done_verb)
    end
end

--- Transfer a single wound from the target, pre-healing own level-3 wound on that part first.
--- @param settings table
--- @param heal_target string the resolved target noun
--- @param part string body part name as returned by appraise parser (e.g. "right arm", "nerves")
local function transfer_wound(settings, heal_target, part)
    debug_msg(settings, "Transferring " .. part .. " from " .. heal_target)

    -- Map the appraise part name to an ecure config key so we can check our own wounds
    local ecure_key = APPRAISE_PART_TO_ECURE[part]
    local wound_key = APPRAISE_PART_TO_KEY[part]

    if part == "exertion" then
        -- Heal our own overexertion first if present
        if Effects and Effects.Debuffs and Effects.Debuffs.active("Overexerted") then
            attempt_with_hindrance_retry(settings, function(attempt, max)
                wait_for_mana(settings, 7)
                waitrt()
                waitcastrt()
                debug_msg(settings, "Casting exertion cure before transfer (attempt " .. attempt .. "/" .. max .. ")")
                return dothistimeout("incant 1107", 2, "^%[Spell Hindrance", "^Cast")
            end)
        end
        fput("transfer " .. heal_target .. " exertion")
        return
    end

    -- If we have a level 3 wound on the same body part, pre-heal it first
    if ecure_key and wound_key then
        local our_wound = Wounds[wound_key] or 0
        if our_wound >= 3 then
            debug_msg(settings, "Pre-healing own " .. part .. " (level " .. our_wound .. ") before transfer")
            heal_body_part(settings, ecure_key, our_wound > 1, false)
        end
    end

    fput("transfer " .. heal_target .. " " .. part)
    if part == "abdomen" or part == "nerves" then
        pause(1)
    end
end

-- Heal a specific target by appraising and transferring per-body-part wounds
function M.heal_target(settings, target_name)
    debug_msg(settings, "Healing target: " .. target_name)
    check_signs(settings)

    -- Appraise the target to find specific wounds
    local heal_target, body_parts, wound_description = appraise_target(settings, target_name)

    if not heal_target then
        respond("Couldn't find or appraise " .. target_name .. "!")
        return
    end

    if #body_parts == 0 then
        if wound_description:find("Appraise what") or wound_description:find("^Usage:") then
            respond("Couldn't find or no injuries on " .. target_name .. "!")
        else
            respond(heal_target .. " does not appear to be injured.")
        end
        return
    end

    debug_msg(settings, "Healing target " .. heal_target .. ": " .. wound_description)

    -- Transfer each detected body part individually
    for _, part in ipairs(body_parts) do
        transfer_wound(settings, heal_target, part)
    end

    -- Follow up with untargeted transfer loop to catch remaining HP damage
    local pre_health = Char.health
    local post_health = 0
    local total_healed = 0

    while pre_health ~= post_health do
        if Char.health <= 75 or Char.percent_health < 51 then
            debug_msg(settings, "Health too low during transfer loop (" .. Char.health .. "/" .. Char.percent_health .. "%) - restoring")
            restore_health(settings)
        end
        pre_health = Char.health
        fput("transfer " .. heal_target)
        post_health = Char.health
        total_healed = total_healed + (pre_health - post_health)
        debug_msg(settings, "Transfer tick: pre=" .. pre_health .. " post=" .. post_health .. " total_healed=" .. total_healed)
        if pre_health == post_health then break end
    end

    -- Report with wound descriptions
    if total_healed > 0 then
        respond("You healed " .. heal_target .. " of " .. wound_description .. " along with " .. total_healed .. " hitpoints.")
    else
        respond("You healed " .. heal_target .. " of " .. wound_description .. ".")
    end
    restore_health(settings)
end

function M.heal_group(settings)
    local members = Group.members or {}
    debug_msg(settings, "Group members to heal: " .. #members)
    for _, member in ipairs(members) do
        if member ~= GameState.name and member ~= "You" then
            M.heal_target(settings, member)
        end
    end
end

function M.heal_room(settings)
    local pcs = GameObj.pcs()
    debug_msg(settings, "Room PCs to heal: " .. #pcs)
    for _, pc in ipairs(pcs) do
        M.heal_target(settings, pc.noun)
    end
end

return M
