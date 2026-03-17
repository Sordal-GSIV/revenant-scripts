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

-- Heal a specific target by transferring wounds
function M.heal_target(settings, target_name)
    debug_msg(settings, "Healing target: " .. target_name)
    check_signs(settings)

    -- Transfer wounds
    local pre_health = Char.health
    local post_health = 0
    local total_healed = 0

    -- Transfer loop
    while pre_health ~= post_health do
        if Char.health <= 75 or Char.percent_health < 51 then
            debug_msg(settings, "Health too low during transfer (" .. Char.health .. ") - restoring")
            restore_health(settings)
        end
        pre_health = Char.health
        fput("transfer " .. target_name)
        pause(0.5)
        post_health = Char.health
        total_healed = total_healed + (pre_health - post_health)
        debug_msg(settings, "Transfer tick: pre=" .. pre_health .. " post=" .. post_health)
        if pre_health == post_health then break end
    end

    if total_healed > 0 then
        respond("You healed " .. target_name .. " of " .. total_healed .. " hitpoints.")
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
