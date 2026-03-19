-- osacombat/combat.lua — Combat module for OSACombat
-- Ported from osacombat.lic (OSA — GemStone IV automated combat).
-- Handles: stance management, targeting, setup/special/aoe/assault attacks,
--          UAC chains, mstrike, chicken attacks, reactive weapons, hiding,
--          smart command sending (osa_put), and all combat maneuver dispatch.

local M = {}

---------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------
local uac_current_attack = "jab"
local mstrike_focus = 0
local mstrike_open  = 0

---------------------------------------------------------------------------
-- M.can_act() — returns true if not stunned/webbed/bound/dead
---------------------------------------------------------------------------
function M.can_act()
    return not stunned() and not webbed() and not bound() and not dead()
end

---------------------------------------------------------------------------
-- M.wait_rt() — drain roundtime then cast roundtime
---------------------------------------------------------------------------
function M.wait_rt()
    waitrt()
    waitcastrt()
end

---------------------------------------------------------------------------
-- M.wait_castrt() — drain roundtime then cast roundtime
---------------------------------------------------------------------------
function M.wait_castrt()
    waitrt()
    waitcastrt()
end

---------------------------------------------------------------------------
-- M.change_stance(new_stance, force)
-- Translates numeric stance values (10/20 -> advance, 30/40 -> forward,
-- 50/60 -> neutral, 70/80 -> guarded, 90/100 -> defensive).
-- Uses CMan Stance Perfection when force=true and numeric stance provided.
-- Skips if Spell[216] active or character is dead.
---------------------------------------------------------------------------
function M.change_stance(new_stance, force)
    if force == nil then force = true end

    if Spell[216].active or dead() then
        return
    end

    local perfect_stance = nil
    if type(new_stance) == "string" and new_stance:match("^%d+$") then
        local n = tonumber(new_stance)
        perfect_stance = new_stance
        if n == 10 or n == 20 then
            new_stance = "advance"
        elseif n == 30 or n == 40 then
            new_stance = "forward"
        elseif n == 50 or n == 60 then
            new_stance = "neutral"
        elseif n == 70 or n == 80 then
            new_stance = "guarded"
        elseif n == 90 or n == 100 then
            new_stance = "defensive"
        end
    end

    -- Normalize stance name for comparison
    local stance_lower = type(new_stance) == "string" and new_stance:lower() or ""
    local current = (GameState.stance or ""):lower()

    if current:find(stance_lower, 1, true) then
        return
    end

    -- If cast RT running and we want defensive, guarded is acceptable
    if checkcastrt() > 0 and stance_lower:find("def") then
        if current == "guarded" then
            return
        end
    end

    local response = "You are now|You move into|You fall back|Cast Roundtime|unable to change"

    if force and perfect_stance and CMan and CMan.known and CMan.known("Stance Perfection") then
        dothistimeout("cman stance " .. perfect_stance, 3, response)
    elseif force then
        dothistimeout("stance " .. new_stance, 3, response)
    else
        fput("stance " .. new_stance)
    end
end

---------------------------------------------------------------------------
-- M.stance_defensive(cfg) — switch to defending stance if stance_dance on
---------------------------------------------------------------------------
function M.stance_defensive(cfg)
    if not cfg.get_bool("stance_dance") then return end
    local cc = cfg.creature_type and cfg.creature_type() or nil
    local stance = "defensive"
    if cc and cc.defending_stance then
        stance = cc.defending_stance
    end
    M.wait_rt()
    M.change_stance(stance)
end

---------------------------------------------------------------------------
-- M.stance_offensive(cfg) — switch to attacking stance if stance_dance on
---------------------------------------------------------------------------
function M.stance_offensive(cfg)
    if not cfg.get_bool("stance_dance") then return end
    local cc = cfg.creature_type and cfg.creature_type() or nil
    local stance = "offensive"
    if cc and cc.attack_stance then
        stance = cc.attack_stance
    end
    M.wait_rt()
    M.change_stance(stance)
end

---------------------------------------------------------------------------
-- M.stance_guarded(cfg) — switch to guarded if stance_dance on
---------------------------------------------------------------------------
function M.stance_guarded(cfg)
    if not cfg.get_bool("stance_dance") then return end
    M.wait_rt()
    M.change_stance("guarded")
end

---------------------------------------------------------------------------
-- M.stand_check() — stand if not standing
---------------------------------------------------------------------------
function M.stand_check()
    if not GameState.standing then
        fput("stand")
        pause(0.25)
        waitrt()
    end
end

---------------------------------------------------------------------------
-- M.get_target() — target random if no current target
---------------------------------------------------------------------------
function M.get_target()
    if not GameObj.target() then
        fput("target random")
        pause(0.3)
    end
end

---------------------------------------------------------------------------
-- M.hide_time() — hide if targets present and not already hidden
---------------------------------------------------------------------------
function M.hide_time()
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    if GameState.hidden then return end
    fput("hide")
    waitrt()
end

---------------------------------------------------------------------------
-- M.osa_put(message) — smart command sender with retry on wait/stun,
-- handles struggle/stand automatically.
---------------------------------------------------------------------------
function M.osa_put(message)
    local timeout_at = os.time() + 10
    while os.time() < timeout_at do
        if dead() then return end

        if stunned() then
            pause(0.5)
        elseif webbed() then
            fput("struggle")
            waitrt()
        elseif bound() then
            fput("struggle")
            waitrt()
        elseif not GameState.standing then
            fput("stand")
            pause(0.25)
            waitrt()
        else
            local result = dothistimeout(message, 5,
                "%.%.%.wait", "Roundtime", "Cast Roundtime",
                "You can't do that", "What were you",
                "could not find", "You don't seem",
                "already dead", "You are stunned",
                "You are still stunned", "can't seem to",
                "You are unable")

            if not result then
                return
            end

            if result:find("%.%.%.wait") then
                pause(0.5)
                waitrt()
            elseif result:find("You are stunned") or result:find("still stunned") then
                pause(0.5)
            else
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.prep_reset() — release prepared spell if any
---------------------------------------------------------------------------
function M.prep_reset()
    if checkprep() ~= "None" then
        fput("release")
    end
end

---------------------------------------------------------------------------
-- M.kneel_check() — kneel if not already kneeling
---------------------------------------------------------------------------
function M.kneel_check()
    if not GameState.kneeling then
        fput("kneel")
        pause(0.25)
        waitrt()
    end
end

---------------------------------------------------------------------------
-- Helper: dispatch_attack — common pattern for all attack dispatch fns.
-- Checks can_act, targets in range, stamina/mana mins, then calls handler.
---------------------------------------------------------------------------
local function dispatch_attack(cfg, cc, attack_key, dispatch_table)
    if not M.can_act() then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end

    local attack_name = cc[attack_key]
    if not attack_name or attack_name == "None" or attack_name == "" then return end

    local stam_min  = cc[attack_key .. "_stam_min"]  or 0
    local man_min   = cc[attack_key .. "_man_min"]    or 0
    local enemy_min = cc[attack_key .. "_enemy_min"]  or 1
    local enemy_max = cc[attack_key .. "_enemy_max"]  or 10

    if Char.stamina < stam_min then return end
    if Char.mana < man_min then return end
    if #targets < enemy_min then return end
    if #targets > enemy_max then return end

    local handler = dispatch_table[attack_name]
    if handler then
        handler(cfg, cc)
    end
end

---------------------------------------------------------------------------
-- Helper: do_cman — execute a combat maneuver with stance changes
---------------------------------------------------------------------------
local function do_cman(cfg, cman_name, cmd)
    if not CMan.available(cman_name) then return end
    M.stance_offensive(cfg)
    fput(cmd)
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- Helper: do_weapon — execute a weapon technique with stance changes
---------------------------------------------------------------------------
local function do_weapon(cfg, weapon_name, cmd)
    if not Weapon.available(weapon_name) then return end
    M.stance_offensive(cfg)
    fput(cmd)
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- Helper: do_shield — execute a shield technique with stance changes
---------------------------------------------------------------------------
local function do_shield(cfg, shield_name, cmd)
    if not Shield.available(shield_name) then return end
    M.stance_offensive(cfg)
    fput(cmd)
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- Energy Wings dispatch tables
---------------------------------------------------------------------------
local dark_wings_actions = {
    ["Dark Energy Wings: Shadow Barb"] = { cooldown = "Shadow Barb", verb = "turn" },
    ["Dark Energy Wings: Barbed Sweep"] = { cooldown = "Barbed Sweep", verb = "knock" },
    ["Dark Energy Wings: Rain of Thorns"] = { cooldown = "Rain of Thorns", verb = "fold" },
    ["Dark Energy Wings: Shadow Mantle"] = { cooldown = "Shadow Mantle", verb = "tap" },
    ["Dark Energy Wings: Crawling Shadow"] = { cooldown = "Crawling Shadow", verb = "pull" },
    ["Dark Energy Wings: Carrion Guard"] = { cooldown = "Carrion Guard", verb = "push" },
}

local light_wings_actions = {
    ["Light Energy Wings: Radiant Pulse"] = { cooldown = "Radiant Pulse", verb = "turn" },
    ["Light Energy Wings: Blast of Brilliance"] = { cooldown = "Blast of Brilliance", verb = "knock" },
    ["Light Energy Wings: Blinding Reprisal"] = { cooldown = "Blinding Reprisal", verb = "fold" },
    ["Light Energy Wings: Luminous Flight"] = { cooldown = "Luminous Flight", verb = "tap" },
    ["Light Energy Wings: Prismatic Aegis"] = { cooldown = "Prismatic Aegis", verb = "pull" },
    ["Light Energy Wings: Wings of Warding"] = { cooldown = "Wings of Warding", verb = "push" },
}

--- Execute energy wings action by name
local function do_wings(cfg, name)
    local info = dark_wings_actions[name] or light_wings_actions[name]
    if not info then return end
    if Effects.Cooldowns.active(info.cooldown) then return end
    local noun = cfg.get("energy_wings_noun") or ""
    if noun == "" then return end
    M.stance_offensive(cfg)
    fput(info.verb .. " my " .. noun)
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- SETUP ATTACKS dispatch table
-- Maps config names to handler functions
---------------------------------------------------------------------------
local setup_attacks = {}

-- CMan-based setup attacks
local cman_setups = {
    ["Berserk"]         = { name = "Berserk",        cmd = "cman berserk" },
    ["Bull Rush"]       = { name = "Bull Rush",       cmd = "cman bullrush" },
    ["Crowd Press"]     = { name = "Crowd Press",     cmd = "cman cpress" },
    ["Cutthroat"]       = { name = "Cutthroat",       cmd = "cman cutthroat" },
    ["Dirtkick"]        = { name = "Dirtkick",        cmd = "cman dirtkick" },
    ["Disarm Weapon"]   = { name = "Disarm Weapon",   cmd = "cman disarm" },
    ["Dislodge"]        = { name = "Dislodge",        cmd = "cman dislodge" },
    ["Eviscerate"]      = { name = "Eviscerate",      cmd = "cman eviscerate" },
    ["Excoriate"]       = { name = "Excoriate",       cmd = "cman excoriate" },
    ["Eyepoke"]         = { name = "Eyepoke",         cmd = "cman eyepoke" },
    ["Feint"]           = { name = "Feint",           cmd = "cman feint" },
    ["Footstomp"]       = { name = "Footstomp",       cmd = "cman footstomp" },
    ["Groin Kick"]      = { name = "Groin Kick",      cmd = "cman gkick" },
    ["Hamstring"]       = { name = "Hamstring",        cmd = "cman hamstring" },
    ["Haymaker"]        = { name = "Haymaker",         cmd = "cman haymaker" },
    ["Headbutt"]        = { name = "Headbutt",         cmd = "cman headbutt" },
    ["Kneebash"]        = { name = "Kneebash",         cmd = "cman kneebash" },
    ["Mighty Blow"]     = { name = "Mighty Blow",      cmd = "cman mblow" },
    ["Mug"]             = { name = "Mug",              cmd = "cman mug" },
    ["Nosetweak"]       = { name = "Nosetweak",        cmd = "cman nosetweak" },
    ["Spell Cleave"]    = { name = "Spell Cleave",     cmd = "cman scleave" },
    ["Subdue"]          = { name = "Subdue",           cmd = "cman subdue" },
    ["Sunder Shield"]   = { name = "Sunder Shield",    cmd = "cman sunder" },
    ["Sweep"]           = { name = "Sweep",            cmd = "cman sweep" },
    ["Swiftkick"]       = { name = "Swiftkick",        cmd = "cman swiftkick" },
    ["Tackle"]          = { name = "Tackle",           cmd = "cman tackle" },
    ["Templeshot"]      = { name = "Templeshot",       cmd = "cman templeshot" },
    ["Throatchop"]      = { name = "Throatchop",       cmd = "cman throatchop" },
    ["Trip"]            = { name = "Trip",             cmd = "cman trip" },
    ["Vault Kick"]      = { name = "Vault Kick",       cmd = "cman vaultkick" },
}

for label, info in pairs(cman_setups) do
    setup_attacks[label] = function(cfg, cc)
        do_cman(cfg, info.name, info.cmd)
    end
end

-- Weapon-based setup attacks
local weapon_setups = {
    ["Charge (Polearm)"]          = { name = "Charge",           cmd = "weapon charge" },
    ["Cripple (Edged)"]           = { name = "Cripple",          cmd = "weapon cripple" },
    ["Dizzying Swing (Blunt)"]    = { name = "Dizzying Swing",   cmd = "weapon dizzyingswing" },
    ["Twin Hammerfists (Brawling)"] = { name = "Twin Hammerfists", cmd = "weapon twinhammer" },
}

for label, info in pairs(weapon_setups) do
    setup_attacks[label] = function(cfg, cc)
        do_weapon(cfg, info.name, info.cmd)
    end
end

-- Shield-based setup attacks
local shield_setups = {
    ["Shield Bash"]    = { name = "Shield Bash",    cmd = "shield bash" },
    ["Shield Charge"]  = { name = "Shield Charge",  cmd = "shield charge" },
    ["Shield Push"]    = { name = "Shield Push",    cmd = "shield push" },
    ["Shield Throw"]   = { name = "Shield Throw",   cmd = "shield throw" },
    ["Shield Trample"] = { name = "Shield Trample", cmd = "shield trample" },
}

for label, info in pairs(shield_setups) do
    setup_attacks[label] = function(cfg, cc)
        do_shield(cfg, info.name, info.cmd)
    end
end

-- Warcry-based setup attacks
local warcry_setups = {
    ["Bertrandt's Bellow (Single Target)"] = { warcry = "Bellow" },
    ["Bertrandt's Bellow (Open)"]          = { warcry = "Bellow", open = true },
    ["Carn's Cry (Single Target)"]         = { warcry = "Cry" },
    ["Carn's Cry (Open)"]                  = { warcry = "Cry", open = true },
    ["Garrelle's Growl (Single Target)"]   = { warcry = "Growl" },
    ["Garrelle's Growl (Open)"]            = { warcry = "Growl", open = true },
}

for label, info in pairs(warcry_setups) do
    setup_attacks[label] = function(cfg, cc)
        M.stance_offensive(cfg)
        local target = GameObj.target()
        if info.open then
            Warcry.use(info.warcry, "All")
        else
            if target then
                Warcry.use(info.warcry, target)
            else
                Warcry.use(info.warcry)
            end
        end
        M.wait_rt()
        M.stance_defensive(cfg)
    end
end

-- Voln Sleep
setup_attacks["Voln Sleep"] = function(cfg, cc)
    M.stance_offensive(cfg)
    fput("symbol of sleep")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Energy Wings setup attacks
local wings_setup_names = {
    "Dark Energy Wings: Shadow Barb",
    "Dark Energy Wings: Barbed Sweep",
    "Dark Energy Wings: Rain of Thorns",
    "Light Energy Wings: Radiant Pulse",
    "Light Energy Wings: Blast of Brilliance",
    "Light Energy Wings: Blinding Reprisal",
}

for _, name in ipairs(wings_setup_names) do
    setup_attacks[name] = function(cfg, cc)
        do_wings(cfg, name)
    end
end

---------------------------------------------------------------------------
-- SPECIAL ATTACKS dispatch table
---------------------------------------------------------------------------
local special_attacks = {}

-- Bearhug: waits for Concentrating buff to clear
special_attacks["Bearhug"] = function(cfg, cc)
    if not CMan.available("Bearhug") then return end
    -- Wait for Concentrating buff to clear before attempting
    local wait_count = 0
    while Effects.Buffs.active("Concentrating") and wait_count < 20 do
        pause(0.5)
        wait_count = wait_count + 1
    end
    if Effects.Buffs.active("Concentrating") then return end
    M.stance_offensive(cfg)
    fput("cman bearhug")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Chastise: checks stamina >= 10 and cooldown
special_attacks["Chastise"] = function(cfg, cc)
    if Char.stamina < 10 then return end
    if Effects.Cooldowns.active("Chastise") then return end
    M.stance_offensive(cfg)
    fput("chastise")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Excoriate: checks mana >= 10 and cooldown
special_attacks["Excoriate"] = function(cfg, cc)
    if Char.mana < 10 then return end
    if Effects.Cooldowns.active("Excoriate") then return end
    M.stance_offensive(cfg)
    fput("cman excoriate")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Exsanguinate
special_attacks["Exsanguinate"] = function(cfg, cc)
    if not CMan.available("Exsanguinate") then return end
    M.stance_offensive(cfg)
    fput("cman exsanguinate")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Leap Attack
special_attacks["Leap Attack"] = function(cfg, cc)
    if not CMan.available("Leap Attack") then return end
    M.stance_offensive(cfg)
    fput("cman leapattack")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Shield Strike
special_attacks["Shield Strike"] = function(cfg, cc)
    if not Shield.available("Shield Strike") then return end
    M.stance_offensive(cfg)
    fput("shield strike")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Spin Attack
special_attacks["Spin Attack"] = function(cfg, cc)
    if not CMan.available("Spin Attack") then return end
    M.stance_offensive(cfg)
    fput("cman sattack")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Staggering Blow
special_attacks["Staggering Blow"] = function(cfg, cc)
    if not CMan.available("Staggering Blow") then return end
    M.stance_offensive(cfg)
    fput("cman sblow")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- True Strike
special_attacks["True Strike"] = function(cfg, cc)
    if not CMan.available("True Strike") then return end
    M.stance_offensive(cfg)
    fput("cman truestrike")
    M.wait_rt()
    M.stance_defensive(cfg)
end

-- Dark Energy Wings specials
local dark_wings_special_names = {
    "Dark Energy Wings: Shadow Barb",
    "Dark Energy Wings: Barbed Sweep",
    "Dark Energy Wings: Rain of Thorns",
}
for _, name in ipairs(dark_wings_special_names) do
    special_attacks[name] = function(cfg, cc)
        do_wings(cfg, name)
    end
end

-- Light Energy Wings specials
local light_wings_special_names = {
    "Light Energy Wings: Radiant Pulse",
    "Light Energy Wings: Blast of Brilliance",
    "Light Energy Wings: Blinding Reprisal",
}
for _, name in ipairs(light_wings_special_names) do
    special_attacks[name] = function(cfg, cc)
        do_wings(cfg, name)
    end
end

---------------------------------------------------------------------------
-- ASSAULT ATTACKS dispatch table
-- Each uses dothistimeout with 15s timeout and long result pattern
---------------------------------------------------------------------------
local assault_attacks = {}

local assault_result_pattern = "You complete your assault|to the ready, your assault complete|"
    .. "Upon firing your last|With a final, explosive breath|"
    .. "recentering yourself for the fight|With a final snap|"
    .. "don't seem to be able to move|too injured|already dead|"
    .. "little bit late|could not find|You can't reach|"
    .. "Roundtime|Your mind clouds"

local assault_map = {
    ["Barrage (Ranged)"]          = { name = "Barrage",          cmd = "weapon barrage" },
    ["Flurry (Edged)"]            = { name = "Flurry",           cmd = "weapon flurry" },
    ["Fury (Brawling)"]           = { name = "Fury",             cmd = "weapon fury" },
    ["Guardant Thrusts (Polearm)"] = { name = "Guardant Thrusts", cmd = "weapon gthrusts" },
    ["Pummel (Blunt)"]            = { name = "Pummel",           cmd = "weapon pummel" },
    ["Thrash (Two-Handed)"]       = { name = "Thrash",           cmd = "weapon thrash" },
}

for label, info in pairs(assault_map) do
    assault_attacks[label] = function(cfg, cc)
        if not Weapon.available(info.name) then return end
        M.stance_offensive(cfg)
        dothistimeout(info.cmd, 15, assault_result_pattern)
        M.wait_rt()
        M.stance_defensive(cfg)
    end
end

---------------------------------------------------------------------------
-- AOE ATTACKS dispatch table
---------------------------------------------------------------------------
local aoe_attacks = {}

-- CMan-based AOE
local aoe_cman_map = {
    ["Bull Rush"] = { name = "Bull Rush", cmd = "cman bullrush" },
}

for label, info in pairs(aoe_cman_map) do
    aoe_attacks[label] = function(cfg, cc)
        do_cman(cfg, info.name, info.cmd)
    end
end

-- Weapon-based AOE
local aoe_weapon_map = {
    ["Clash (Brawling)"]         = { name = "Clash",         cmd = "weapon clash" },
    ["Cyclone (Polearm)"]        = { name = "Cyclone",       cmd = "weapon cyclone" },
    ["Pin Down (Ranged)"]        = { name = "Pin Down",      cmd = "weapon pindown" },
    ["Pulverize (Blunt)"]        = { name = "Pulverize",     cmd = "weapon pulverize" },
    ["Whirling Blade (Edged)"]   = { name = "Whirling Blade", cmd = "weapon wblade" },
    ["Whirlwind (Two-Handed)"]   = { name = "Whirlwind",     cmd = "weapon whirlwind" },
    ["Volley (Ranged)"]          = { name = "Volley",         cmd = "weapon volley" },
}

for label, info in pairs(aoe_weapon_map) do
    aoe_attacks[label] = function(cfg, cc)
        do_weapon(cfg, info.name, info.cmd)
    end
end

-- Shield-based AOE
local aoe_shield_map = {
    ["Shield Throw"]   = { name = "Shield Throw",   cmd = "shield throw" },
    ["Shield Trample"] = { name = "Shield Trample", cmd = "shield trample" },
}

for label, info in pairs(aoe_shield_map) do
    aoe_attacks[label] = function(cfg, cc)
        do_shield(cfg, info.name, info.cmd)
    end
end

-- Flare Gloves AOE (Pound)
aoe_attacks["Pound (Flare Gloves)"] = function(cfg, cc)
    local noun = cfg.get("flareglovesnoun") or ""
    if noun == "" then return end
    M.stance_offensive(cfg)
    fput("pound my " .. noun)
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- Dispatch entry points for attack categories
---------------------------------------------------------------------------

-- M.att_openers(cfg, cc)  — dispatch setup_attack with thresholds
function M.att_openers(cfg, cc)
    dispatch_attack(cfg, cc, "setup_attack", setup_attacks)
end

-- M.att_openers2(cfg, cc) — dispatch setup_attack2
function M.att_openers2(cfg, cc)
    dispatch_attack(cfg, cc, "setup_attack2", setup_attacks)
end

-- M.special_att(cfg, cc) — dispatch special_attack
function M.special_att(cfg, cc)
    dispatch_attack(cfg, cc, "special_attack", special_attacks)
end

-- M.secondspecial_att(cfg, cc) — dispatch special_attack2
function M.secondspecial_att(cfg, cc)
    dispatch_attack(cfg, cc, "special_attack2", special_attacks)
end

-- M.aoe_att(cfg, cc) — dispatch aoe_attack
function M.aoe_att(cfg, cc)
    dispatch_attack(cfg, cc, "aoe_attack", aoe_attacks)
end

-- M.aoe_att2(cfg, cc) — dispatch aoe_attack2
function M.aoe_att2(cfg, cc)
    dispatch_attack(cfg, cc, "aoe_attack2", aoe_attacks)
end

-- M.assault_att(cfg, cc) — dispatch assault
function M.assault_att(cfg, cc)
    dispatch_attack(cfg, cc, "assault", assault_attacks)
end

-- M.assault_att2(cfg, cc) — dispatch assault2
function M.assault_att2(cfg, cc)
    dispatch_attack(cfg, cc, "assault2", assault_attacks)
end

---------------------------------------------------------------------------
-- M.uac_round(cfg) — UAC combat rotation
-- Cycles through jab/punch/grapple/kick based on game feedback
---------------------------------------------------------------------------
function M.uac_round(cfg)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    if not M.can_act() then return end

    if not uac_current_attack or uac_current_attack == "" then
        uac_current_attack = "jab"
    end

    M.stance_offensive(cfg)

    local result = dothistimeout(uac_current_attack, 2,
        "excellent positioning", "followup jab", "followup punch",
        "followup grapple", "followup kick", "Roundtime")

    if result then
        if result:find("excellent positioning") then
            uac_current_attack = "kick"
        elseif result:find("followup jab") then
            uac_current_attack = "jab"
        elseif result:find("followup punch") then
            uac_current_attack = "punch"
        elseif result:find("followup grapple") then
            uac_current_attack = "grapple"
        elseif result:find("followup kick") then
            uac_current_attack = "kick"
        elseif result:find("Roundtime") then
            uac_current_attack = "jab"
        end
    end

    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- M.chicken_attack(cfg) — basic melee attack/waylay if noattack enabled
---------------------------------------------------------------------------
function M.chicken_attack(cfg)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    if not M.can_act() then return end

    M.stance_offensive(cfg)

    if cfg.get_bool("use_waylay") and GameState.hidden then
        fput("waylay")
    else
        fput("attack")
    end

    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- M.chicken_fire(cfg) — basic ranged fire if archer enabled
---------------------------------------------------------------------------
function M.chicken_fire(cfg)
    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end
    if not M.can_act() then return end

    M.stance_offensive(cfg)
    fput("fire")
    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- M.mstrike_setup(cfg) — configure mstrike based on MOC skill ranks
---------------------------------------------------------------------------
function M.mstrike_setup(cfg)
    local moc = Skills.multi_opponent_combat or 0

    if     moc >= 190 then mstrike_focus = 6; mstrike_open = 7
    elseif moc >= 155 then mstrike_focus = 5; mstrike_open = 7
    elseif moc >= 135 then mstrike_focus = 5; mstrike_open = 6
    elseif moc >= 100 then mstrike_focus = 4; mstrike_open = 6
    elseif moc >=  90 then mstrike_focus = 4; mstrike_open = 5
    elseif moc >=  60 then mstrike_focus = 3; mstrike_open = 5
    elseif moc >=  55 then mstrike_focus = 3; mstrike_open = 4
    elseif moc >=  35 then mstrike_focus = 2; mstrike_open = 4
    elseif moc >=  30 then mstrike_focus = 2; mstrike_open = 3
    elseif moc >=  15 then mstrike_focus = 0; mstrike_open = 3
    elseif moc >=   5 then mstrike_focus = 0; mstrike_open = 2
    else return end

    fput("mstrike set recovery off")
    fput("mstrike set focus " .. mstrike_focus)
    fput("mstrike set open " .. mstrike_open)

    -- Set default attack type based on combat mode
    if cfg.get_bool("osaarcher") then
        fput("mstrike set default fire")
    else
        fput("mstrike set default attack")
    end
end

---------------------------------------------------------------------------
-- M.mstrike_routine(cfg) — execute mstrike if available, >=2 targets,
-- >=50% stamina
---------------------------------------------------------------------------
function M.mstrike_routine(cfg)
    if not cfg.get_bool("use_mstrike") then return end
    if not M.can_act() then return end

    local moc = Skills.multi_opponent_combat or 0
    if moc < 5 then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 2 then return end

    local stamina_pct = Char.percent_stamina or 100
    if stamina_pct < 50 then return end

    M.stance_offensive(cfg)

    if #targets >= 2 and mstrike_open >= 1 then
        fput("mstrike")
    end

    M.wait_rt()
    M.stance_defensive(cfg)
end

---------------------------------------------------------------------------
-- M.reactive(cfg) — handle reactive weapon attacks
-- Reactive weapons auto-fire when certain conditions are met; this
-- ensures stance is appropriate when a reactive attack is pending.
---------------------------------------------------------------------------
function M.reactive(cfg)
    if not cfg.get_bool("use_reactive") then return end
    if not M.can_act() then return end

    local targets = GameObj.targets and GameObj.targets() or {}
    if #targets < 1 then return end

    -- Check for reactive weapon cooldown
    if Effects.Cooldowns.active("Reactive") then return end

    M.stance_offensive(cfg)

    -- Reactive weapons fire automatically on the next attack action
    fput("attack")
    M.wait_rt()
    M.stance_defensive(cfg)
end

return M
