--- @revenant-script
--- name: ecleanse
--- version: 2.2.8
--- author: Deysh
--- contributors: Tysong
--- game: gs
--- description: Cleric cleansing/purification automation - removes status effects, recovers disarmed weapons
--- tags: dispel,unpoison,undisease,disarmed,effects,cleansing
--- @lic-certified: complete 2026-03-18
---
--- Changelog (from Lich5):
---   v2.2.8 (2026-01-03): convert stunmaneuvers to CMan.use
---   v2.2.7 (2025-11-29): bugfix for silvery blue globe targeting
---   v2.2.6 (2025-11-11): bugfix in weapon recovery with TWC
---   v2.2.5 (2025-10-27): bugfix in hive apparatus trap disarm regex when no trap
---   v2.2.0 (2025-04-23): Escape Artist support, targetable web/globe/cloud detection
---   v2.1.0 (2024-11-04): hive trap handling, itchy curse cleansing
---
--- Usage:
---   ;ecleanse           - start monitoring (runs in background)
---   ;ecleanse setup     - configure settings (GUI/text)
---   ;ecleanse list      - list all settings
---   ;ecleanse load      - reload settings
---   ;ecleanse last disarm - show last disarm room
---   ;ecleanse help      - show help
---
--- Features:
---   - Remove poison (spell 114)
---   - Remove disease (spell 113)
---   - Remove stun (spell 1040, barkskin, berserk, stun maneuvers)
---   - Remove webs/bound (spell 1040, berserk, beseech, escape artist)
---   - Remove grounded/rooted (retreat, escape artist)
---   - Dispel magical debuffs (confusion, vertigo, etc.)
---   - Dispel clouds in room
---   - Avoid/dispel globes (silvery blue globe, spiraling rift, spatial anomaly)
---   - Avoid/dispel webs (room hazard web objects)
---   - CMan Spell Cleave / Spell Thieve as dispel alternatives
---   - Recover disarmed weapons (search, bonded weapon recall)
---   - Sanctum weapon recovery (clench creature)
---   - Telekinetic disarm recovery (dispel floating weapon)
---   - Hive trap handling (apparatus + ground search/disarm)
---   - Itchy curse handling (flee to town, wait, return)
---   - Sigil of Determination for casting while injured
---   - Weapon bonding wait, spirit servant recovery, ReadyList check

local Ecleanse = {}

---------------------------------------------------------------------------
-- CappedCollection: track IDs to avoid retrying dispel
---------------------------------------------------------------------------
local CappedCollection = {}
CappedCollection.__index = CappedCollection

function CappedCollection.new(max_size)
    local self = setmetatable({}, CappedCollection)
    self.list = {}
    self.max_size = max_size or 200
    return self
end

function CappedCollection:add(id)
    table.insert(self.list, id)
    while #self.list > self.max_size do
        table.remove(self.list, 1)
    end
end

function CappedCollection:includes(id)
    for _, v in ipairs(self.list) do
        if v == id then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Settings (CharSettings-based)
---------------------------------------------------------------------------
local default_settings = {
    cleanse_poison       = true,
    cleanse_disease      = true,
    cleanse_magical      = true,
    cleanse_grounded     = true,
    recover_disarmed     = true,
    avoid_webs           = true,
    dispel_clouds        = true,
    dispel_magic         = true,
    use_213              = true,   -- Minor Sanctuary
    use_1011             = true,   -- Song of Peace
    use_140              = false,  -- Wall of Force
    use_619              = false,  -- Mass Calm
    use_709              = false,  -- Grasp of the Grave
    use_919              = false,  -- Wizard's Shield
    use_9811             = false,  -- Sigil of Defense
    use_stunned1040      = true,   -- Troubadour's Rally
    use_stunned_barkskin = true,
    use_1635             = false,  -- Divine Intervention / Beseech
    use_berserk_stunned  = false,
    use_berserk_webbed   = false,
    use_stance1          = false,
    use_stance2          = false,
    use_flee             = false,
    use_hide             = false,
    determination        = false,  -- Sigil of Determination
    hive_traps_apparatus = false,
    hive_traps_ground    = false,
    itchy_curse          = false,
    safe_room            = "",
    stop_scripts         = "",
    script_list          = {},     -- Scripts to pause during actions
}

local settings = {}
local event_stack = {}
local did_something = false
local recover_stuff = {}    -- {noun = room_id}
local creature = nil        -- For sanctum recovery
local hive_trap_room = nil
local bad_targets = CappedCollection.new(200)

-- Spell references (resolved at load time)
local dispel_spell = nil       -- Best known dispel: 417, 1218, or 119
local web_dispel_spell = nil   -- Best known web dispel: 209, 417, 1218, or 119
local escape_artist_available = false

-- Room hazard targets found in main_loop
local cloud_target = nil
local globe_target = nil
local web_target = nil

-- Invalid clouds (should not be dispelled)
local invalid_clouds = {
    "cloud of acidic mist",
    "cloud of thick ethereal fog",
}

-- Magic globes pattern
local magic_globe_names = {
    "silvery blue globe",
    "spiraling ghostly rift",
    "chaotic spatial anomaly",
}

-- Dispellable debuffs
local dispellable_debuffs = {
    "Confusion", "Vertigo", "Sounds", "Thought Lash",
    "Mindwipe", "Pious Trial", "Powersink"
}

local function load_settings()
    settings = {}
    for k, v in pairs(default_settings) do
        local saved = CharSettings["ecleanse_" .. k]
        if saved ~= nil and saved ~= "" then
            if type(v) == "boolean" then
                settings[k] = (saved == "true")
            elseif type(v) == "table" then
                local ok, decoded = pcall(Json.decode, saved)
                if ok and type(decoded) == "table" then
                    settings[k] = decoded
                else
                    settings[k] = v
                end
            else
                settings[k] = saved
            end
        else
            settings[k] = v
        end
    end

    -- Build script_list from stop_scripts string
    if type(settings.stop_scripts) == "string" and settings.stop_scripts ~= "" then
        settings.script_list = {}
        for script_name in string.gmatch(settings.stop_scripts, "([^,]+)") do
            table.insert(settings.script_list, script_name:match("^%s*(.-)%s*$"))
        end
    end
    -- Always include go2
    local has_go2 = false
    for _, s in ipairs(settings.script_list or {}) do
        if s == "go2" then has_go2 = true; break end
    end
    if not has_go2 then
        table.insert(settings.script_list, "go2")
    end

    -- Resolve best known dispel spells: 417 (Dispel Magic), 1218 (??), 119 (Dispel Invisibility)
    dispel_spell = nil
    for _, num in ipairs({417, 1218, 119}) do
        if Spell[num] and Spell[num].known then
            dispel_spell = num
            break
        end
    end

    web_dispel_spell = nil
    for _, num in ipairs({209, 417, 1218, 119}) do
        if Spell[num] and Spell[num].known then
            web_dispel_spell = num
            break
        end
    end

    -- Check Escape Artist availability
    escape_artist_available = false
    if Feat.known_p("escapeartist") then
        escape_artist_available = true
    end
end

local function save_settings()
    for k, v in pairs(settings) do
        if type(v) == "boolean" then
            CharSettings["ecleanse_" .. k] = tostring(v)
        elseif type(v) == "table" then
            CharSettings["ecleanse_" .. k] = Json.encode(v)
        else
            CharSettings["ecleanse_" .. k] = tostring(v)
        end
    end
end

---------------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------------
local function wait_rt()
    pause(0.2)
    waitcastrt()
    waitrt()
    pause(0.2)
end

local function scripts_pause()
    for _, script_name in ipairs(settings.script_list or {}) do
        if running(script_name) then
            Script.pause(script_name)
        end
    end
    did_something = true
end

local function scripts_resume()
    for _, script_name in ipairs(settings.script_list or {}) do
        Script.unpause(script_name)
    end
    did_something = false
end

local function able_to_cast()
    -- Check for severe injuries that prevent casting
    -- nsys rank 2+ or head rank 2+ prevents casting
    if Wounds.nsys >= 2 or Scars.nsys >= 2 then return false end
    if Wounds.head >= 2 or Scars.head >= 2 then return false end

    local left_wound = (Wounds.leftArm or 0) + (Wounds.leftHand or 0)
    local right_wound = (Wounds.rightArm or 0) + (Wounds.rightHand or 0)
    if left_wound >= 2 or right_wound >= 2 then return false end

    local left_scar = (Scars.leftArm or 0) + (Scars.leftHand or 0)
    local right_scar = (Scars.rightArm or 0) + (Scars.rightHand or 0)
    if left_scar >= 2 or right_scar >= 2 then return false end

    return true
end

local function check_determination()
    if not settings.determination then return false end
    if not Spell["Sigil of Determination"] or not Spell["Sigil of Determination"].known then return false end
    if not Spell["Sigil of Determination"]:affordable() then return false end

    -- Cast sigil if not already active (matches Lich5 behavior)
    if not Effects.Buffs.active("Sigil of Determination") then
        fput("incant 9806")
        wait_rt()
    end

    -- With determination, threshold is rank 3 (not 2)
    local left_wound = (Wounds.leftArm or 0) + (Wounds.leftHand or 0)
    local right_wound = (Wounds.rightArm or 0) + (Wounds.rightHand or 0)
    local left_scar = (Scars.leftArm or 0) + (Scars.leftHand or 0)
    local right_scar = (Scars.rightArm or 0) + (Scars.rightHand or 0)

    if left_wound > 2 or right_wound > 2 then return false end
    if left_scar > 2 or right_scar > 2 then return false end

    -- Check for rank 3 wounds/scars (determination can't fix those)
    for _, area in ipairs({"nsys", "head", "leftArm", "rightArm", "leftHand", "rightHand", "leftEye", "rightEye"}) do
        if (Wounds[area] or 0) > 2 or (Scars[area] or 0) > 2 then
            return false
        end
    end

    return true
end

local function able_to_cast_with_determination()
    if able_to_cast() then return true end
    return check_determination()
end

local function mana_pulse(spell_num)
    if not Spell[spell_num] or not Spell[spell_num].known then return end
    if Spell[spell_num]:affordable() then return end
    fput("mana pulse")
    pause(0.2)
end

local function change_stance(value)
    if dead() then return end
    if Effects.Debuffs.active("Frenzy") then return end
    local current = GameState.stance_value
    if current == value then return end
    if value == 100 and current and current >= 80 then return end

    local stances = {
        [0]   = "offensive",
        [20]  = "advanced",
        [40]  = "forward",
        [60]  = "neutral",
        [80]  = "guarded",
        [100] = "defensive",
    }
    local cmd
    if stances[value] then
        cmd = "stance " .. stances[value]
    else
        cmd = "stance defensive"
    end
    fput(cmd)
end

local function empty_hands()
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if rh then fput("stow right") end
    if lh then fput("stow left") end
end

local function fill_hands()
    -- Use ReadyList if available (loaded by GS init), else fallback to ready command
    if ReadyList and ReadyList.valid and not ReadyList.valid() then
        ReadyList.check({ silent = true, quiet = true })
    else
        fput("ready")
    end
end

local function has_event(name)
    for _, e in ipairs(event_stack) do
        if e == name then return true end
    end
    return false
end

local function push_event(name)
    if not has_event(name) then
        table.insert(event_stack, name)
    end
end

local function item_in_hands(noun)
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    return (rh and rh.noun == noun) or (lh and lh.noun == noun)
end

---------------------------------------------------------------------------
-- Target regex matching: check if we can target a hazard
---------------------------------------------------------------------------
local function can_target_hazard(id)
    fput("target #" .. tostring(id))
    local line = waitforre("You can only target|Usage:  TARGET|You are now targeting|You are unable to discern|You discern that you are the origin|Suspecting that .+ is the origin")
    if line and line:find("Suspecting that") then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Action: Dispel Cloud
---------------------------------------------------------------------------
local function dispel_cloud()
    if not settings.dispel_clouds then return end
    if not cloud_target then return end

    local cloud_dispel_ready = dispel_spell and able_to_cast_with_determination()
    local spell_cleave_ready = CMan.known_p("Spell Cleave") and Char.stamina >= 10
    local spell_thieve_ready = CMan.known_p("Spell Thieve") and Char.stamina >= 10

    if not (cloud_dispel_ready or spell_cleave_ready or spell_thieve_ready) then return end

    -- Check if targetable
    if not can_target_hazard(cloud_target.id) then
        bad_targets:add(cloud_target.id)
        cloud_target = nil
        return
    end

    scripts_pause()

    if cloud_dispel_ready then
        mana_pulse(dispel_spell)
        if Spell[dispel_spell]:affordable() then
            fput("incant " .. tostring(dispel_spell) .. " at #" .. cloud_target.id)
        end
    elseif spell_cleave_ready then
        fput("cman scleave #" .. cloud_target.id)
    elseif spell_thieve_ready then
        fput("cman sthieve #" .. cloud_target.id)
    end
    cloud_target = nil
end

---------------------------------------------------------------------------
-- Action: Avoid Globe (silvery blue globe, spiraling rift, spatial anomaly)
---------------------------------------------------------------------------
local function avoid_globe()
    if not settings.dispel_magic then return end
    if not globe_target then return end

    local globe_dispel_ready = dispel_spell and able_to_cast_with_determination()
    local spell_cleave_ready = CMan.known_p("Spell Cleave") and Char.stamina >= 10
    local spell_thieve_ready = CMan.known_p("Spell Thieve") and Char.stamina >= 10

    if not (globe_dispel_ready or spell_cleave_ready or spell_thieve_ready) then return end

    -- Silvery blue globe and spiraling ghostly rift can be cast at directly
    -- (no need to target first). Others need targeting.
    local name_lower = string.lower(globe_target.name or "")
    local direct_cast = name_lower:find("silvery blue globe") or name_lower:find("spiraling ghostly rift")

    if not direct_cast then
        if not can_target_hazard(globe_target.id) then
            bad_targets:add(globe_target.id)
            globe_target = nil
            return
        end
    end

    scripts_pause()

    if globe_dispel_ready then
        mana_pulse(dispel_spell)
        if Spell[dispel_spell]:affordable() then
            fput("incant " .. tostring(dispel_spell) .. " at #" .. globe_target.id)
        end
    elseif spell_cleave_ready then
        fput("cman scleave #" .. globe_target.id)
    elseif spell_thieve_ready then
        fput("cman sthieve #" .. globe_target.id)
    end
    globe_target = nil
end

---------------------------------------------------------------------------
-- Action: Avoid Webs (room hazard web objects)
---------------------------------------------------------------------------
local function avoid_webs()
    if not settings.avoid_webs then return end
    if not web_target then return end

    local web_dispel_ready = web_dispel_spell and able_to_cast_with_determination()
    local spell_cleave_ready = CMan.known_p("Spell Cleave") and Char.stamina >= 10
    local spell_thieve_ready = CMan.known_p("Spell Thieve") and Char.stamina >= 10
    local ea_ready = escape_artist_available and Char.stamina >= 15

    if not (web_dispel_ready or spell_cleave_ready or spell_thieve_ready or ea_ready) then return end

    -- Check if targetable
    if not can_target_hazard(web_target.id) then
        bad_targets:add(web_target.id)
        web_target = nil
        return
    end

    scripts_pause()

    if web_dispel_ready then
        mana_pulse(web_dispel_spell)
        if Spell[web_dispel_spell]:affordable() then
            fput("incant " .. tostring(web_dispel_spell) .. " at #" .. web_target.id)
        end
    elseif spell_cleave_ready then
        fput("cman scleave #" .. web_target.id)
    elseif spell_thieve_ready then
        fput("cman sthieve #" .. web_target.id)
    end
    web_target = nil
end

---------------------------------------------------------------------------
-- Action: Remove Poison
---------------------------------------------------------------------------
local function remove_poison()
    if not settings.cleanse_poison then return end
    if not Spell[114] or not Spell[114].known then return end
    if not able_to_cast_with_determination() then return end

    mana_pulse(114)
    if not Spell[114]:affordable() then return end

    scripts_pause()
    local thorns_re = Regex.new("Wall of Thorns Poison")
    while (poisoned() or Effects.Debuffs.active(thorns_re)) and Spell[114]:affordable() do
        fput("incant 114")
        wait_rt()
    end
end

---------------------------------------------------------------------------
-- Action: Remove Disease
---------------------------------------------------------------------------
local function remove_disease()
    if not settings.cleanse_disease then return end
    if not Spell[113] or not Spell[113].known then return end
    if not able_to_cast_with_determination() then return end

    mana_pulse(113)
    if not Spell[113]:affordable() then return end

    scripts_pause()
    while diseased() and Spell[113]:affordable() do
        fput("incant 113")
        wait_rt()
    end
end

---------------------------------------------------------------------------
-- Action: Stun Maneuver helpers
---------------------------------------------------------------------------
local function stunman_stand()
    while not standing() and stunned() do
        if CMan and CMan.use then
            CMan.use("stunman", "stand")
        else
            fput("cman stunman stand")
        end
        wait_rt()
    end
end

local function stunman_perform(maneuver_type)
    stunman_stand()

    if maneuver_type == "stance1" or maneuver_type == "stance2" then
        if CMan and CMan.use then
            CMan.use("stunman", maneuver_type)
        else
            fput("cman stunman " .. maneuver_type)
        end
    elseif maneuver_type == "flee" then
        local current_room = GameState.room_id
        while GameState.room_id == current_room and stunned() do
            stunman_stand()
            if CMan and CMan.use then
                CMan.use("stunman", "flee")
            else
                fput("cman stunman flee")
            end
            pause(0.5)
        end
        -- After fleeing, try stance2 to recover
        if CMan and CMan.use then
            CMan.use("stunman", "stance2")
        else
            fput("cman stunman stance2")
        end
    elseif maneuver_type == "hide" then
        while not hidden() and stunned() do
            stunman_stand()
            if CMan and CMan.use then
                CMan.use("stunman", "hide")
            else
                fput("cman stunman hide")
            end
            wait_rt()
        end
    end

    -- Wait for stun to clear
    local timeout = os.time() + 30
    while stunned() and os.time() < timeout do
        pause(0.1)
    end
end

---------------------------------------------------------------------------
-- Action: Remove Stun
---------------------------------------------------------------------------
local function remove_stun()
    local stunned1040 = false
    local barkskin = false
    local beseech_1635 = false
    local berserk = false
    local stance1 = false
    local stance2 = false
    local flee_maneuver = false
    local hide_maneuver = false

    -- Check if we're in a room we shouldn't escape from (belly/innards)
    local room_name = GameState.room_name or ""
    local not_escape_rooms = not room_name:find("The Belly of the Beast") and not room_name:find("Ooze, Innards")

    if settings.use_stunned1040 and Spell[1040] and Spell[1040].known then
        mana_pulse(1040)
        stunned1040 = Spell[1040]:affordable() or false
    end

    if settings.use_stunned_barkskin and Spell[605] and Spell[605].known
            and not Effects.Cooldowns.active("Barkskin: Commune")
            and not Effects.Cooldowns.active("Barkskin")
            and not Spell[605].active
            and Skills.spiritual_lore_blessings >= 15 then
        mana_pulse(605)
        barkskin = Spell[605]:affordable() or false
    end

    if settings.use_1635 and Spell[1635] and Spell[1635].known then
        mana_pulse(1635)
        beseech_1635 = Spell[1635]:affordable() or false
    end

    if not_escape_rooms then
        berserk = settings.use_berserk_stunned and CMan.known_p("Berserk")
        stance1 = settings.use_stance1
        stance2 = settings.use_stance2
        flee_maneuver = settings.use_flee
        hide_maneuver = settings.use_hide and not hidden()
    end

    if not (barkskin or berserk or stunned1040 or stance1 or stance2
            or flee_maneuver or hide_maneuver or beseech_1635) then
        return
    end

    scripts_pause()

    if barkskin then
        wait_rt()
        if stunned() then fput("commune barkskin") end
        wait_until(function() return not stunned() end)
    elseif berserk then
        fput("berserk")
        pause(1)
        wait_until(function() return not stunned() end)
    elseif stunned1040 then
        fput("shout 1040")
    elseif beseech_1635 then
        fput("beseech")
    elseif stance1 then
        stunman_perform("stance1")
    elseif stance2 then
        stunman_perform("stance2")
    elseif flee_maneuver then
        stunman_perform("flee")
    elseif hide_maneuver then
        stunman_perform("hide")
    end
end

---------------------------------------------------------------------------
-- Action: Remove Web/Bound
---------------------------------------------------------------------------
local function remove_web_bound()
    if not (settings.avoid_webs or settings.use_berserk_webbed) then return end

    if Spell[1040] and Spell[1040].known then
        mana_pulse(1040)
    end

    local spell_1040_ready = Spell[1040] and Spell[1040].known and Spell[1040]:affordable()
    local berserk_ready = settings.use_berserk_webbed and CMan.known_p("Berserk") and Char.stamina >= 21
    local beseech_ready = settings.use_1635 and Spell[1635] and Spell[1635].known and Spell[1635]:affordable()
    local ea_ready = escape_artist_available and Char.stamina >= 15

    if not (spell_1040_ready or berserk_ready or beseech_ready or ea_ready) then return end

    scripts_pause()

    if spell_1040_ready then
        fput("shout 1040")
    elseif berserk_ready then
        fput("berserk")
        pause(1)
    elseif beseech_ready then
        fput("beseech")
    elseif ea_ready then
        fput("feat escapeartist")
    end
end

---------------------------------------------------------------------------
-- Action: Remove Grounded (Rooted/Pressed)
---------------------------------------------------------------------------
local function remove_grounded()
    if not settings.cleanse_grounded then return end

    -- Try CMan Retreat if available
    local retreat_available = CMan.known_p("Retreat") and Char.stamina >= 11

    if retreat_available then
        scripts_pause()
        wait_rt()
        if not standing() then fput("stand") end
        wait_rt()
        local saved_target = GameState.current_target_id
        fput("target clear")
        fput("cman retreat")
        if saved_target and saved_target ~= "" and saved_target ~= "0" then
            fput("target #" .. saved_target)
        end
    elseif escape_artist_available and Char.stamina >= 15
            and Effects.Debuffs.active("Rooted") then
        -- Escape Artist only removes Rooted, not Pressed
        scripts_pause()
        fput("feat escapeartist")
    end
end

---------------------------------------------------------------------------
-- Action: Remove Magical Debuffs
---------------------------------------------------------------------------
local function remove_magical()
    if not settings.cleanse_magical then return end
    if not able_to_cast_with_determination() then return end
    if not dispel_spell then return end

    mana_pulse(dispel_spell)
    if not Spell[dispel_spell]:affordable() then return end

    scripts_pause()
    if not standing() then fput("stand") end
    wait_rt()
    fput("incant " .. tostring(dispel_spell) .. " channel open")
end

---------------------------------------------------------------------------
-- Action: Use Sigil of Determination
---------------------------------------------------------------------------
local function use_determination()
    if not settings.determination then return end
    if not Spell["Sigil of Determination"] or not Spell["Sigil of Determination"].known then return end
    if not Spell["Sigil of Determination"]:affordable() then return end

    scripts_pause()
    fput("incant 9806")
end

---------------------------------------------------------------------------
-- Action: Settle Room (make room safer when recovering weapons)
---------------------------------------------------------------------------
local function settle_room()
    local npcs = GameObj.npcs()
    if not npcs or #npcs == 0 then return end
    if not able_to_cast_with_determination() then return end

    if settings.use_140 and Spell[140] and Spell[140].known
            and not Effects.Buffs.active("Wall of Force")
            and not Effects.Cooldowns.active("Wall of Force") then
        mana_pulse(140)
        if Spell[140]:affordable() then fput("incant 140") end
    elseif settings.use_619 and Spell[619] and Spell[619].known then
        mana_pulse(619)
        if Spell[619]:affordable() then fput("incant 619") end
    elseif settings.use_709 and Spell[709] and Spell[709].known then
        -- Don't cast Grasp of the Grave against limb/appendage NPCs (ineffective)
        local limb_re = Regex.new("^(?:arm|appendage|claw|limb|pincer|tentacle)s?$|^(?:palpus|palpi)$")
        local has_limbs = false
        for _, npc in ipairs(npcs) do
            if npc.name and limb_re:test(npc.name:lower()) then
                has_limbs = true; break
            end
        end
        if not has_limbs then
            mana_pulse(709)
            if Spell[709]:affordable() then fput("incant 709") end
        end
    elseif settings.use_919 and Spell[919] and Spell[919].known
            and not Effects.Buffs.active("Wizard's Shield")
            and not Effects.Cooldowns.active("Wizard's Shield") then
        mana_pulse(919)
        if Spell[919]:affordable() then fput("incant 919") end
    elseif settings.use_9811 and Spell[9811] and Spell[9811].known then
        fput("incant 9811")
    end
end

---------------------------------------------------------------------------
-- Action: Recover Disarmed Weapon
---------------------------------------------------------------------------
local function recover()
    if not settings.recover_disarmed then return end

    local item_noun, room_id = next(recover_stuff)
    if not item_noun then return end
    recover_stuff[item_noun] = nil

    local stop_213 = false
    local stop_1011 = false

    scripts_pause()

    echo("DISARMED! Looking for: " .. item_noun .. " in room " .. tostring(room_id))
    UserVars.last_disarm = tostring(room_id)

    -- Navigate to room
    Map.go2(tostring(room_id))
    wait_while(function() return running("go2") end)

    wait_rt()

    -- Cast protective spells
    if able_to_cast_with_determination() then
        if settings.use_213 and Spell[213] and Spell[213].known then
            mana_pulse(213)
            if Spell[213]:affordable() then
                fput("incant 213")
                stop_213 = true
            end
        end
        if settings.use_1011 and Spell[1011] and Spell[1011].known then
            mana_pulse(1011)
            if Spell[1011]:affordable() then
                fput("incant 1011")
                stop_1011 = true
            end
        end
        wait_rt()
    end

    -- Check for spirit servant recovery (spell 218 active)
    if Spell[218] and Spell[218].active then
        -- Wait for servant to appear
        for _ = 1, 15 do
            local npcs = GameObj.npcs()
            local found = false
            if npcs then
                for _, npc in ipairs(npcs) do
                    if npc.noun and npc.noun:lower():find("spirit") then
                        found = true
                        break
                    end
                end
            end
            if found then break end
            pause(0.1)
        end

        fput("tell servant recover")
        local line = waitforre("flickers for a moment and manifests|has no personal recollection")
        if line and line:find("flickers for a moment and manifests") then
            -- Servant recovered the weapon
            if stop_213 then fput("stop 213") end
            return
        end
    end

    -- Settle room
    settle_room()
    scripts_pause()

    -- Defensive stance
    change_stance(100)

    -- Wait for bonded weapon recall
    if Spell[1625] and Spell[1625].known then
        local wait_time = os.time() + 10
        while not item_in_hands(item_noun) and os.time() < wait_time do
            wait_rt()
            pause(0.5)
        end
    end

    -- If weapon not yet recovered, search for it
    if not item_in_hands(item_noun) then
        empty_hands()

        local search_count = 0
        while search_count < 10 do
            if not kneeling() then
                fput("kneel")
            end
            wait_rt()

            fput("recover item")
            local line = waitforre("You spy|You continue to intently search|In order to recover|You find nothing recoverable|not in any condition")
            if not line then break end

            if line:find("You spy") or item_in_hands(item_noun) then
                break
            end

            if line:find("not in any condition") then
                echo("Unable to search. Exiting ecleanse.")
                echo(item_noun .. " is in room " .. tostring(room_id))
                if not standing() then fput("stand") end
                scripts_resume()
                return
            end

            if line:find("In order to recover") then
                empty_hands()
            end

            search_count = search_count + 1
        end

        wait_rt()
    end

    if not standing() then fput("stand") end
    wait_rt()
    fill_hands()

    if stop_213 then fput("stop 213") end
    if stop_1011 then fput("stop 1011") end
end

---------------------------------------------------------------------------
-- Action: Recover Weapon Webbing (pry weapon free from web)
---------------------------------------------------------------------------
local function recover_weapon_webbing()
    if not settings.recover_disarmed then return end

    local item_noun = next(recover_stuff)
    if not item_noun then return end
    recover_stuff[item_noun] = nil

    local stop_213 = false
    local stop_1011 = false

    scripts_pause()
    wait_rt()

    if able_to_cast_with_determination() then
        if settings.use_213 and Spell[213] and Spell[213].known then
            mana_pulse(213)
            if Spell[213]:affordable() then
                fput("incant 213")
                stop_213 = true
            end
        end
        if settings.use_1011 and Spell[1011] and Spell[1011].known then
            mana_pulse(1011)
            if Spell[1011]:affordable() then
                fput("incant 1011")
                stop_1011 = true
            end
        end
        wait_rt()
    end

    settle_room()
    scripts_pause()
    change_stance(100)

    local pry_count = 0
    while pry_count < 10 do
        fput("pry my " .. item_noun)
        local line = waitforre("Pry what|You try to pry|You pry your.*free")
        if line and (line:find("You pry your") or line:find("Pry what")) then
            break
        end
        pry_count = pry_count + 1
    end

    wait_rt()

    if stop_213 then fput("stop 213") end
    if stop_1011 then fput("stop 1011") end
end

---------------------------------------------------------------------------
-- Action: Sanctum Recovery (clench creature noun)
---------------------------------------------------------------------------
local function sanctum_recover()
    if not settings.recover_disarmed then return end

    scripts_pause()
    wait_rt()

    settle_room()
    scripts_pause()
    change_stance(100)

    if creature then
        for _ = 1, 20 do
            fput("clench " .. creature)
            wait_rt()
            local line = waitforre("You reach up and grab|I could not find what you were referring to")
            if line and (line:find("You reach up and grab") or line:find("I could not find")) then
                break
            end
        end
    end
end

---------------------------------------------------------------------------
-- Action: Telekinetic Disarm Recovery (dispel floating weapon)
---------------------------------------------------------------------------
local function telekinetic_recover()
    if not settings.recover_disarmed then return end

    local item_noun = next(recover_stuff)
    if not item_noun then return end
    recover_stuff[item_noun] = nil

    scripts_pause()

    settle_room()
    scripts_pause()
    change_stance(100)

    -- Try to dispel or grab the floating weapon
    for _ = 1, 10 do
        if item_in_hands(item_noun) then break end

        if dispel_spell then
            mana_pulse(dispel_spell)
            if Spell[dispel_spell]:affordable() then
                fput("incant " .. tostring(dispel_spell) .. " at " .. item_noun)
            end
        else
            fput("get " .. item_noun)
        end

        -- Check hands
        fput("glance")
        local line = waitforre("You glance")
        if line and line:find(item_noun) then break end

        wait_rt()
    end
    wait_rt()
end

---------------------------------------------------------------------------
-- Action: Hive Traps - Apparatus
---------------------------------------------------------------------------
local function hive_traps_apparatus()
    if not settings.hive_traps_apparatus then return end
    if running("go2") then return end
    if hive_trap_room ~= GameState.room_id then return end

    scripts_pause()

    -- Search for the trap
    local search_count = 0
    while search_count < 10 do
        wait_rt()
        fput("search")
        local line = waitforre("d100|Failure|Success|You don't find anything of interest")
        search_count = search_count + 1
        if line then
            if line:find("Success") or line:find("You don't find anything") then break end
        end
    end

    wait_rt()

    -- Disarm the apparatus
    search_count = 0
    while search_count < 10 do
        fput("disarm apparatus")
        local line = waitforre("d100|Success|You want to disarm what")
        if line then
            if line:find("Success") or line:find("You want to disarm what") then break end
        end
        search_count = search_count + 1
        wait_rt()
    end

    wait_rt()
end

---------------------------------------------------------------------------
-- Action: Hive Traps - Ground
---------------------------------------------------------------------------
local function hive_traps_ground()
    if not settings.hive_traps_ground then return end
    if running("go2") then return end
    if hive_trap_room ~= GameState.room_id then return end

    scripts_pause()

    local search_count = 0
    while search_count < 10 do
        wait_rt()
        fput("search")
        local line = waitforre("d100|Failure|Success|You don't find anything of interest")
        search_count = search_count + 1
        if line then
            if line:find("Failure") then goto continue end
            if line:find("Success") or line:find("You don't find anything") then break end
        end
        ::continue::
    end

    wait_rt()
end

---------------------------------------------------------------------------
-- Action: Itchy Curse (flee to town, wait, return)
---------------------------------------------------------------------------
local function itchy_curse()
    if not settings.itchy_curse then return end

    local cursed_room = GameState.room_id

    -- Determine safe place
    local safe_place = nil
    if settings.safe_room and settings.safe_room ~= "" then
        safe_place = settings.safe_room
    else
        -- Find nearest town or sanctuary
        local town = Room.find_nearest_by_tag and Room.find_nearest_by_tag("town")
        local sanctuary = Room.find_nearest_by_tag and Room.find_nearest_by_tag("sanctuary")

        if town and sanctuary then
            -- Pick whichever is closer
            safe_place = town.id or sanctuary.id
        elseif town then
            safe_place = town.id
        elseif sanctuary then
            safe_place = sanctuary.id
        end
    end

    if not safe_place then
        echo("Cannot find a safe room for itchy curse!")
        return
    end

    scripts_pause()
    if running("go2") then Script.kill("go2") end

    Map.go2(tostring(safe_place))
    wait_while(function() return running("go2") end)

    empty_hands()

    -- Wait for curse to clear (up to 3 minutes)
    local timeout = os.time() + 180
    while os.time() < timeout do
        local lines = reget(50)
        local cleared = false
        if lines then
            for _, line in ipairs(lines) do
                if line:find("You no longer feel so defenseless and the rash seems to disappear") then
                    cleared = true
                    break
                end
            end
        end
        if cleared then break end
        pause(1)
    end

    fill_hands()

    -- Return to original room
    Map.go2(tostring(cursed_room))
    wait_while(function() return running("go2") end)
end

---------------------------------------------------------------------------
-- Action: Use Vat (Sanctum lurk bite/spit cleansing)
---------------------------------------------------------------------------
-- Sanctum vat room UID (4216054). Cache the resolved integer room ID at first use.
local _vat_room_id = nil
local function get_vat_room_id()
    if _vat_room_id then return _vat_room_id end
    -- Search all rooms for the Sanctum vat UID
    local rooms = Map.list()
    if rooms then
        for _, rid in ipairs(rooms) do
            local r = Map.find_room(rid)
            if r and r.uid then
                local uid = r.uid
                -- uid may be a table or string depending on map data
                local uid_str = type(uid) == "table" and table.concat(uid, ",") or tostring(uid)
                if uid_str:find("4216054") then
                    _vat_room_id = rid
                    return rid
                end
            end
        end
    end
    return nil
end

local function use_vat()
    scripts_pause()

    local current_room = GameState.room_id
    local vat_room = get_vat_room_id()

    if vat_room then
        Map.go2(tostring(vat_room))
        wait_while(function() return running("go2") end)
    end

    fput("clean vat")
    wait_rt()

    if current_room then
        Map.go2(tostring(current_room))
        wait_while(function() return running("go2") end)
    end
end

---------------------------------------------------------------------------
-- Downstream hook for event detection
---------------------------------------------------------------------------
local function ecleanse_hook(line)
    if not line then return line end

    -- Weapon knocked from grasp (standard disarm)
    if line:find("is knocked from your grasp") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            recover_stuff[noun] = GameState.room_id
            push_event("recover")
        end
    end

    -- Weapon wrenched from hand (bony protrusions, hisska)
    if line:find("wrenched from your") or line:find("is wrenched out of your grasp") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            recover_stuff[noun] = GameState.room_id
            push_event("recover")
        end
    end

    -- Telekinetic disarm (weapon floats away)
    if line:find("tears free from your hands and floats") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            recover_stuff[noun] = GameState.room_id
            push_event("telekinetic_recover")
        end
    end

    -- Sanctum Unholy Quickening (creature transforms weapon)
    if line:find("kindling it into an unholy semblance of life") then
        local noun = line:match('noun="([^"]+)"')
        if noun then
            creature = noun
            push_event("sanctum_recover")
        end
    end

    -- Sanctum disease (lurk bite/spit)
    if line:find("The flesh around the wound feels hot and cold at the same time") then
        push_event("use_vat")
    end

    -- Webbing entangles weapon
    if line:find("webbing entangles your") or line:find("rendering it useless") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            recover_stuff[noun] = GameState.room_id
            push_event("recover_weapon_webbing")
        end
    end

    -- Hive trap: apparatus
    if line:find("You notice a flickering glint in the shadows") or
       line:find("The apparatus flickers with deadly radiance") then
        hive_trap_room = GameState.room_id
        push_event("hive_traps_apparatus")
    end

    -- Hive trap: ground
    if line:find("The ground churns violently") or
       line:find("flashes of chitin jut from its depths") or
       line:find("chitinous mandibles flash") or
       line:find("Hindered by the churning terrain") then
        hive_trap_room = GameState.room_id
        push_event("hive_traps_ground")
    end

    -- Itchy curse
    if line:find("You shiver slightly as an invisible rash covers your body") then
        push_event("itchy_curse")
    end

    -- Unseen force entangles (web/bound)
    if line:find("An unseen force entangles you") then
        push_event("remove_web_bound")
    end

    return line
end

---------------------------------------------------------------------------
-- Action dispatch
---------------------------------------------------------------------------
local action_map = {
    remove_poison          = remove_poison,
    remove_disease         = remove_disease,
    remove_stun            = remove_stun,
    remove_web_bound       = remove_web_bound,
    remove_grounded        = remove_grounded,
    remove_magical         = remove_magical,
    dispel_cloud           = dispel_cloud,
    avoid_globe            = avoid_globe,
    avoid_webs             = avoid_webs,
    recover                = recover,
    recover_weapon_webbing = recover_weapon_webbing,
    sanctum_recover        = sanctum_recover,
    telekinetic_recover    = telekinetic_recover,
    hive_traps_apparatus   = hive_traps_apparatus,
    hive_traps_ground      = hive_traps_ground,
    itchy_curse            = itchy_curse,
    use_vat                = use_vat,
    determination          = use_determination,
    settle_room            = settle_room,
}

---------------------------------------------------------------------------
-- GUI Setup
---------------------------------------------------------------------------
local function gui_setup()
    local win = Gui.window("ECleanse Setup v2.2.8", { width = 650, height = 675, resizable = true })
    local root = Gui.vbox()

    -- Scripts to pause
    local scripts_card = Gui.card({ title = "Scripts" })
    local scripts_box = Gui.hbox()
    scripts_box:add(Gui.label("Scripts to Pause:"))
    local scripts_input = Gui.input({
        placeholder = "list of scripts to pause, eg: bigshot, eloot, go2",
        text = settings.stop_scripts or ""
    })
    scripts_box:add(scripts_input)
    scripts_card:add(scripts_box)
    root:add(scripts_card)

    -- Misc options
    local misc_card = Gui.card({ title = "Misc" })
    local misc_box = Gui.vbox()

    local cb_recover     = Gui.checkbox("Recover Disarmed Weapons", settings.recover_disarmed)
    local cb_berserk_web = Gui.checkbox("Use Berserk when Webbed", settings.use_berserk_webbed)
    local cb_disease     = Gui.checkbox("Cure Disease", settings.cleanse_disease)
    local cb_poison      = Gui.checkbox("Cure Poison", settings.cleanse_poison)
    local cb_grounded    = Gui.checkbox("Cleanse Grounded", settings.cleanse_grounded)
    local cb_magical     = Gui.checkbox("Cleanse Magical", settings.cleanse_magical)
    local cb_clouds      = Gui.checkbox("Dispel Clouds", settings.dispel_clouds)
    local cb_magic       = Gui.checkbox("Dispel Magic (globes)", settings.dispel_magic)
    local cb_webs        = Gui.checkbox("Dispel Webs", settings.avoid_webs)
    local cb_determ      = Gui.checkbox("Use Sigil of Determination", settings.determination)
    local cb_hive_app    = Gui.checkbox("Disarm Hive Apparatus", settings.hive_traps_apparatus or false)
    local cb_hive_gnd    = Gui.checkbox("Disarm Hive Ground", settings.hive_traps_ground or false)
    local cb_itchy       = Gui.checkbox("Manage Itchy Curse", settings.itchy_curse)

    misc_box:add(cb_recover)
    misc_box:add(cb_berserk_web)
    misc_box:add(cb_disease)
    misc_box:add(cb_poison)
    misc_box:add(cb_grounded)
    misc_box:add(cb_magical)
    misc_box:add(cb_clouds)
    misc_box:add(cb_magic)
    misc_box:add(cb_webs)
    misc_box:add(cb_determ)
    misc_box:add(cb_hive_app)
    misc_box:add(cb_hive_gnd)
    misc_box:add(cb_itchy)

    local safe_box = Gui.hbox()
    safe_box:add(Gui.label("Itchy Curse Safe Room:"))
    local safe_input = Gui.input({ placeholder = "Room ID (blank = nearest town/sanctuary)", text = settings.safe_room or "" })
    safe_box:add(safe_input)
    misc_box:add(safe_box)

    misc_card:add(misc_box)
    root:add(misc_card)

    -- Stun recovery
    local stun_card = Gui.card({ title = "Stun Recovery" })
    local stun_box = Gui.vbox()

    local cb_barkskin    = Gui.checkbox("Barkskin (605)", settings.use_stunned_barkskin)
    local cb_berserk_st  = Gui.checkbox("Berserk", settings.use_berserk_stunned)
    local cb_1040        = Gui.checkbox("Troubadour's Rally (1040)", settings.use_stunned1040)
    local cb_1635        = Gui.checkbox("Divine Intervention (1635)", settings.use_1635)
    local cb_stance1     = Gui.checkbox("Stunman Stance1", settings.use_stance1)
    local cb_stance2     = Gui.checkbox("Stunman Stance2", settings.use_stance2)
    local cb_flee        = Gui.checkbox("Stunman Flee", settings.use_flee)
    local cb_hide        = Gui.checkbox("Stunman Hide", settings.use_hide)

    stun_box:add(cb_barkskin)
    stun_box:add(cb_berserk_st)
    stun_box:add(cb_1040)
    stun_box:add(cb_1635)
    stun_box:add(cb_stance1)
    stun_box:add(cb_stance2)
    stun_box:add(cb_flee)
    stun_box:add(cb_hide)
    stun_card:add(stun_box)
    root:add(stun_card)

    -- Room safety spells
    local room_card = Gui.card({ title = "Cast in Room when Disarmed" })
    local room_box = Gui.vbox()

    local cb_709  = Gui.checkbox("Grasp of the Grave (709)", settings.use_709)
    local cb_619  = Gui.checkbox("Mass Calm (619)", settings.use_619)
    local cb_1011_cb = Gui.checkbox("Song of Peace (1011)", settings.use_1011)
    local cb_9811 = Gui.checkbox("Symbol of Sleep (9811)", settings.use_9811)
    local cb_213  = Gui.checkbox("Minor Sanctuary (213)", settings.use_213)
    local cb_140  = Gui.checkbox("Wall of Force (140)", settings.use_140)
    local cb_919  = Gui.checkbox("Wizard's Shield (919)", settings.use_919)

    room_box:add(cb_709)
    room_box:add(cb_619)
    room_box:add(cb_1011_cb)
    room_box:add(cb_9811)
    room_box:add(cb_213)
    room_box:add(cb_140)
    room_box:add(cb_919)
    room_card:add(room_box)
    root:add(room_card)

    -- Save/Close button
    local close_btn = Gui.button("Save & Close")
    close_btn:on_click(function()
        settings.stop_scripts         = scripts_input:get_text()
        settings.recover_disarmed     = cb_recover:get_checked()
        settings.use_berserk_webbed   = cb_berserk_web:get_checked()
        settings.cleanse_disease      = cb_disease:get_checked()
        settings.cleanse_poison       = cb_poison:get_checked()
        settings.cleanse_grounded     = cb_grounded:get_checked()
        settings.cleanse_magical      = cb_magical:get_checked()
        settings.dispel_clouds        = cb_clouds:get_checked()
        settings.dispel_magic         = cb_magic:get_checked()
        settings.avoid_webs           = cb_webs:get_checked()
        settings.determination        = cb_determ:get_checked()
        settings.hive_traps_apparatus = cb_hive_app:get_checked()
        settings.hive_traps_ground    = cb_hive_gnd:get_checked()
        settings.itchy_curse          = cb_itchy:get_checked()
        settings.safe_room            = safe_input:get_text()
        settings.use_stunned_barkskin = cb_barkskin:get_checked()
        settings.use_berserk_stunned  = cb_berserk_st:get_checked()
        settings.use_stunned1040      = cb_1040:get_checked()
        settings.use_1635             = cb_1635:get_checked()
        settings.use_stance1          = cb_stance1:get_checked()
        settings.use_stance2          = cb_stance2:get_checked()
        settings.use_flee             = cb_flee:get_checked()
        settings.use_hide             = cb_hide:get_checked()
        settings.use_709              = cb_709:get_checked()
        settings.use_619              = cb_619:get_checked()
        settings.use_1011             = cb_1011_cb:get_checked()
        settings.use_9811             = cb_9811:get_checked()
        settings.use_213              = cb_213:get_checked()
        settings.use_140              = cb_140:get_checked()
        settings.use_919              = cb_919:get_checked()

        save_settings()
        load_settings()
        echo("Settings saved.")
        win:close()
    end)
    root:add(close_btn)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

---------------------------------------------------------------------------
-- Settings display
---------------------------------------------------------------------------
local function show_settings()
    respond("")
    respond("ECleanse Settings:")
    respond(string.rep("=", 50))
    for k, v in pairs(settings) do
        if type(v) == "table" then
            respond(string.format("  %-25s = %s", k, table.concat(v, ", ")))
        else
            respond(string.format("  %-25s = %s", k, tostring(v)))
        end
    end
    respond("")
end

local function show_help()
    respond([[

ECleanse v2.2.8 - Status Effect Removal Automation

Usage:
  ;ecleanse           Start monitoring (runs in background)
  ;ecleanse setup     Configure settings (GUI)
  ;ecleanse list      List all settings
  ;ecleanse load      Reload settings
  ;ecleanse last disarm   Show last disarm room
  ;ecleanse help      Show this help

Features:
  - Remove poison (spell 114)
  - Remove disease (spell 113)
  - Remove stun (1040, barkskin, berserk, CMan stun maneuvers)
  - Remove webs/bound (1040, berserk, beseech, Escape Artist)
  - Remove grounded/rooted (CMan retreat, Escape Artist)
  - Dispel magical debuffs (confusion, vertigo, etc.)
  - Dispel clouds, globes, web hazards (spells or CMan Spell Cleave/Thieve)
  - Recover disarmed weapons (search, bonded weapon, spirit servant)
  - Sanctum weapon recovery (clench creature)
  - Telekinetic disarm recovery (dispel floating weapon)
  - Hive trap handling (apparatus + ground search/disarm)
  - Itchy curse handling (flee to town, wait, return)
  - Sigil of Determination for casting while injured
    ]])
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function main_loop()
    while true do
        -- Kill script on death (matches Lich5 deadmans_switch behavior)
        if dead() then
            echo("ECleanse: character died, stopping.")
            scripts_resume()
            return
        end

        -- Process event stack
        while #event_stack > 0 do
            local current_event = table.remove(event_stack, 1)
            local action = action_map[current_event]
            if action then
                action()
            end
        end

        -- Check conditions and enqueue events
        if poisoned() then push_event("remove_poison") end
        if diseased() then push_event("remove_disease") end
        if stunned() then push_event("remove_stun") end
        if webbed() or bound() then push_event("remove_web_bound") end

        -- Grounded (Rooted/Pressed debuffs)
        if settings.cleanse_grounded then
            if Effects.Debuffs.active("Rooted") or Effects.Debuffs.active("Pressed") then
                push_event("remove_grounded")
            end
        end

        -- Magical debuffs (Confusion, Vertigo, Sounds, Thought Lash, etc.)
        if settings.cleanse_magical then
            local dispellable = { "Confusion", "Vertigo", "Sounds", "Thought Lash", "Mindwipe", "Pious Trial", "Powersink" }
            for _, debuff in ipairs(dispellable) do
                if Effects.Debuffs.active(debuff) then
                    push_event("remove_magical")
                    break
                end
            end
        end

        -- Check for room hazards: clouds, globes, webs
        local loot = GameObj.loot()
        if loot then
            -- Clouds
            cloud_target = nil
            for _, item in ipairs(loot) do
                local name_lower = string.lower(item.name or "")
                if name_lower:find("cloud") then
                    -- Exclude invalid clouds and gems with "cloud" in name
                    local is_invalid = false
                    for _, ic in ipairs(invalid_clouds) do
                        if name_lower == ic then is_invalid = true; break end
                    end
                    local item_type = item.type or ""
                    if string.lower(item_type):find("gem") then is_invalid = true end
                    if not is_invalid and not bad_targets:includes(item.id) then
                        cloud_target = item
                        break
                    end
                end
            end
            if cloud_target then push_event("dispel_cloud") end

            -- Globes
            globe_target = nil
            for _, item in ipairs(loot) do
                local name_lower = string.lower(item.name or "")
                for _, pattern in ipairs(magic_globe_names) do
                    if name_lower:find(pattern) and not bad_targets:includes(item.id) then
                        globe_target = item
                        break
                    end
                end
                if globe_target then break end
            end
            if globe_target then push_event("avoid_globe") end

            -- Webs (room objects)
            web_target = nil
            for _, item in ipairs(loot) do
                local noun_lower = string.lower(item.noun or "")
                if noun_lower:find("web") and not bad_targets:includes(item.id) then
                    web_target = item
                    break
                end
            end
            if web_target then push_event("avoid_webs") end
        end

        -- Check for determination-worthy injuries
        if settings.determination then
            local injury_locations = {"leftHand", "rightHand", "leftArm", "rightArm", "leftEye", "rightEye", "nsys", "head"}
            for _, limb in ipairs(injury_locations) do
                if (Wounds[limb] or 0) > 1 then
                    push_event("determination")
                    break
                end
            end
        end

        if did_something then
            scripts_resume()
        end

        pause(0.2)
    end
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------
load_settings()

local cmd = Script.vars[0]
if cmd then cmd = cmd:lower():match("^%s*(.-)%s*$") end

if cmd == "setup" then
    gui_setup()
elseif cmd == "load" then
    load_settings()
    echo("Settings reloaded.")
elseif cmd == "list" then
    show_settings()
elseif cmd == "last disarm" then
    local last = UserVars.last_disarm
    if last then
        echo("Last recorded disarm: Room " .. tostring(last))
    else
        echo("No disarm recorded.")
    end
elseif cmd == "help" then
    show_help()
elseif not cmd or cmd == "" then
    -- Start monitoring
    did_something = false
    event_stack = {}

    -- Register hook
    DownstreamHook.add("ecleanse_status", ecleanse_hook)

    before_dying(function()
        DownstreamHook.remove("ecleanse_status")
        scripts_resume()
    end)

    echo("ECleanse v2.2.8 monitoring started.")
    main_loop()
else
    show_help()
end
