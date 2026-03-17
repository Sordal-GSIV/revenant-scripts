--- @revenant-script
--- name: ecleanse
--- version: 2.2.8
--- author: Deysh
--- contributors: Tysong
--- game: gs
--- description: Cleric cleansing/purification automation - removes status effects, recovers disarmed weapons
--- tags: dispel,unpoison,undisease,disarmed,effects,cleansing
---
--- Changelog (from Lich5):
---   v2.2.8 (2026-01-03): convert stunmaneuvers to CMan.use
---   v2.2.7 (2025-11-29): bugfix for silvery blue globe targeting
---   v2.2.6 (2025-11-11): bugfix in weapon recovery with TWC
---   v2.2.5 (2025-10-27): bugfix in hive apparatus trap disarm regex
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
---   - Remove webs/bound (spell 1040, berserk, beseech)
---   - Remove grounded/rooted (retreat, escape artist)
---   - Dispel magical debuffs (confusion, vertigo, etc.)
---   - Recover disarmed weapons (search, bonded weapon recall)
---   - Avoid webs, globes, clouds in room
---   - Hive trap handling
---   - Sanctum weapon recovery
---   - Telekinetic disarm recovery
---   - Sigil of Determination for casting while injured

local Ecleanse = {}

---------------------------------------------------------------------------
-- Settings (CharSettings-based)
---------------------------------------------------------------------------
local default_settings = {
    cleanse_poison    = true,
    cleanse_disease   = true,
    cleanse_magical   = true,
    cleanse_grounded  = true,
    recover_disarmed  = true,
    avoid_webs        = true,
    use_213           = true,   -- Untrammel
    use_1011          = true,   -- Bravery
    use_140           = false,  -- Wall of Force
    use_619           = false,  -- Spiritual Warding
    use_709           = false,  -- Grasp of the Grave
    use_919           = false,  -- Wizard's Shield
    use_9811          = false,  -- Sigil of Defense
    use_stunned1040   = true,   -- Sonic Weapon Song
    use_stunned_barkskin = true,
    use_1635          = false,  -- Beseech
    use_berserk_stunned  = false,
    use_berserk_webbed   = false,
    use_stance1       = false,
    use_stance2       = false,
    use_flee          = false,
    use_hide          = false,
    determination     = false,  -- Sigil of Determination
    script_list       = {},     -- Scripts to pause during actions
}

local settings = {}
local event_stack = {}
local did_something = false
local recover_stuff = {}    -- {noun = room_data}
local creature = nil        -- For sanctum recovery
local hive_trap_room = nil
local bad_targets = {}      -- IDs of targets we've already tried to dispel

local function load_settings()
    settings = {}
    for k, v in pairs(default_settings) do
        local saved = CharSettings["ecleanse_" .. k]
        if saved ~= nil and saved ~= "" then
            if type(v) == "boolean" then
                settings[k] = (saved == "true")
            elseif type(v) == "table" then
                -- Decode JSON list
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
    -- Stacked arm/hand wounds rank 2+ prevent casting
    if Wounds.nsys >= 2 or Scars.nsys >= 2 then return false end
    if Wounds.head >= 2 or Scars.head >= 2 then return false end

    local left_total = (Wounds.leftArm or 0) + (Wounds.leftHand or 0)
    local right_total = (Wounds.rightArm or 0) + (Wounds.rightHand or 0)
    if left_total >= 2 or right_total >= 2 then return false end

    local left_scar = (Scars.leftArm or 0) + (Scars.leftHand or 0)
    local right_scar = (Scars.rightArm or 0) + (Scars.rightHand or 0)
    if left_scar >= 2 or right_scar >= 2 then return false end

    return true
end

local function mana_pulse(spell_num)
    if not Spell[spell_num] or not Spell[spell_num].known then return end
    if Spell[spell_num].affordable then return end
    fput("mana pulse")
    pause(0.2)
end

local function change_stance(value)
    fput("stance " .. tostring(value))
end

---------------------------------------------------------------------------
-- Action: Remove Poison
---------------------------------------------------------------------------
local function remove_poison()
    if not settings.cleanse_poison then return end
    if not Spell[114] or not Spell[114].known then return end
    if not able_to_cast() then return end

    mana_pulse(114)
    if not Spell[114].affordable then return end

    scripts_pause()
    while poisoned() and Spell[114].affordable do
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
    if not able_to_cast() then return end

    mana_pulse(113)
    if not Spell[113].affordable then return end

    scripts_pause()
    while diseased() and Spell[113].affordable do
        fput("incant 113")
        wait_rt()
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

    if settings.use_stunned1040 and Spell[1040] and Spell[1040].known then
        mana_pulse(1040)
        stunned1040 = Spell[1040].affordable or false
    end

    if settings.use_stunned_barkskin and Spell[605] and Spell[605].known then
        mana_pulse(605)
        barkskin = Spell[605].affordable or false
    end

    if settings.use_1635 and Spell[1635] and Spell[1635].known then
        mana_pulse(1635)
        beseech_1635 = Spell[1635].affordable or false
    end

    berserk = settings.use_berserk_stunned

    if not (stunned1040 or barkskin or beseech_1635 or berserk) then return end

    scripts_pause()

    if barkskin then
        wait_rt()
        if stunned() then fput("commune barkskin") end
        wait_until(function() return not stunned() end)
    elseif berserk then
        fput("berserk")
        pause(1)
    elseif stunned1040 then
        fput("shout 1040")
    elseif beseech_1635 then
        fput("beseech")
    end
end

---------------------------------------------------------------------------
-- Action: Remove Web/Bound
---------------------------------------------------------------------------
local function remove_web_bound()
    if not (settings.avoid_webs or settings.use_berserk_webbed) then return end

    local spell_1040_ready = Spell[1040] and Spell[1040].known and Spell[1040].affordable
    local berserk_ready = settings.use_berserk_webbed
    local beseech_ready = settings.use_1635 and Spell[1635] and Spell[1635].known and Spell[1635].affordable

    if not (spell_1040_ready or berserk_ready or beseech_ready) then return end

    scripts_pause()

    if spell_1040_ready then
        fput("shout 1040")
    elseif berserk_ready then
        fput("berserk")
        pause(1)
    elseif beseech_ready then
        fput("beseech")
    end
end

---------------------------------------------------------------------------
-- Action: Remove Grounded (Rooted/Pressed)
---------------------------------------------------------------------------
local function remove_grounded()
    if not settings.cleanse_grounded then return end

    -- Try retreat if available
    scripts_pause()
    wait_rt()
    if not standing() then fput("stand") end
    wait_rt()
    fput("cman retreat")
end

---------------------------------------------------------------------------
-- Action: Remove Magical Debuffs
---------------------------------------------------------------------------
local function remove_magical()
    if not settings.cleanse_magical then return end
    if not able_to_cast() then return end

    -- Try dispel magic (various spells the character might know)
    local dispel_spells = {119, 417}
    local dispel = nil
    for _, num in ipairs(dispel_spells) do
        if Spell[num] and Spell[num].known then
            dispel = num
            break
        end
    end
    if not dispel then return end

    mana_pulse(dispel)
    if not Spell[dispel].affordable then return end

    scripts_pause()
    if not standing() then fput("stand") end
    wait_rt()
    fput("incant " .. tostring(dispel) .. " channel open")
end

---------------------------------------------------------------------------
-- Action: Recover Disarmed Weapon
---------------------------------------------------------------------------
local function recover()
    if not settings.recover_disarmed then return end

    -- Get first pending recovery
    local item_noun, room_data = next(recover_stuff)
    if not item_noun then return end
    recover_stuff[item_noun] = nil

    scripts_pause()

    local room_id = room_data

    echo("DISARMED! Looking for: " .. item_noun .. " in room " .. tostring(room_id))
    UserVars.last_disarm = tostring(room_id)

    -- Navigate to room if needed
    Map.go2(tostring(room_id))
    wait_while(function() return running("go2") end)

    wait_rt()

    -- Try protective spells
    if able_to_cast() then
        if settings.use_213 and Spell[213] and Spell[213].known then
            mana_pulse(213)
            if Spell[213].affordable then fput("incant 213") end
        end
        if settings.use_1011 and Spell[1011] and Spell[1011].known then
            mana_pulse(1011)
            if Spell[1011].affordable then fput("incant 1011") end
        end
        wait_rt()
    end

    -- Check if weapon bonded and returned automatically
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if (rh and rh.noun == item_noun) or (lh and lh.noun == item_noun) then
        echo("Weapon recovered (bonded/automatic)!")
        return
    end

    -- Defensive stance
    change_stance(100)

    -- Search for weapon
    local search_count = 0
    while search_count < 10 do
        if not kneeling() then
            fput("kneel")
        end
        wait_rt()

        fput("recover item")
        local line = waitforre("You spy|You continue to intently search|In order to recover|You find nothing recoverable")
        if not line then break end

        if line:find("You spy") then
            echo("Weapon recovered!")
            break
        end

        if line:find("In order to recover") then
            -- Need empty hands
            fput("stow right")
            fput("stow left")
        end

        search_count = search_count + 1
    end

    wait_rt()
    if not standing() then fput("stand") end
    wait_rt()
end

---------------------------------------------------------------------------
-- Action: Settle Room (make room safer)
---------------------------------------------------------------------------
local function settle_room()
    local npcs = GameObj.npcs()
    if not npcs or #npcs == 0 then return end
    if not able_to_cast() then return end

    if settings.use_140 and Spell[140] and Spell[140].known then
        mana_pulse(140)
        if Spell[140].affordable then fput("incant 140") end
    elseif settings.use_619 and Spell[619] and Spell[619].known then
        mana_pulse(619)
        if Spell[619].affordable then fput("incant 619") end
    elseif settings.use_709 and Spell[709] and Spell[709].known then
        mana_pulse(709)
        if Spell[709].affordable then fput("incant 709") end
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
            local room = Room.current()
            recover_stuff[noun] = room and room.id or GameState.room_id
            table.insert(event_stack, "recover")
        end
    end

    -- Weapon wrenched from hand
    if line:find("wrenched from your") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            local room = Room.current()
            recover_stuff[noun] = room and room.id or GameState.room_id
            table.insert(event_stack, "recover")
        end
    end

    -- Telekinetic disarm (weapon floats away)
    if line:find("tears free from your hands and floats") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            local room = Room.current()
            recover_stuff[noun] = room and room.id or GameState.room_id
            table.insert(event_stack, "recover")
        end
    end

    -- Webbing entangles weapon
    if line:find("webbing entangles your") then
        local noun = line:match('noun="([^"]+)"')
        if noun and not recover_stuff[noun] then
            local room = Room.current()
            recover_stuff[noun] = room and room.id or GameState.room_id
            table.insert(event_stack, "recover_web")
        end
    end

    -- Unseen force entangles (web/bound)
    if line:find("An unseen force entangles you") then
        local found = false
        for _, e in ipairs(event_stack) do
            if e == "remove_web_bound" then found = true; break end
        end
        if not found then
            table.insert(event_stack, "remove_web_bound")
        end
    end

    return line
end

---------------------------------------------------------------------------
-- Action dispatch
---------------------------------------------------------------------------
local action_map = {
    remove_poison    = remove_poison,
    remove_disease   = remove_disease,
    remove_stun      = remove_stun,
    remove_web_bound = remove_web_bound,
    remove_grounded  = remove_grounded,
    remove_magical   = remove_magical,
    recover          = recover,
    recover_web      = function()
        if not settings.recover_disarmed then return end
        local item_noun = next(recover_stuff)
        if not item_noun then return end
        recover_stuff[item_noun] = nil
        scripts_pause()
        wait_rt()
        change_stance(100)
        for _ = 1, 10 do
            fput("pry my " .. item_noun)
            local line = waitforre("Pry what|You try to pry|You pry your.*free")
            if line and (line:find("You pry your") or line:find("Pry what")) then
                break
            end
        end
        wait_rt()
    end,
    settle_room      = settle_room,
}

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

ECleanse - Status Effect Removal Automation

Usage:
  ;ecleanse           Start monitoring (runs in background)
  ;ecleanse setup     Configure settings
  ;ecleanse list      List all settings
  ;ecleanse load      Reload settings
  ;ecleanse last disarm   Show last disarm room
  ;ecleanse help      Show this help

Features:
  - Remove poison (spell 114)
  - Remove disease (spell 113)
  - Remove stun (1040, barkskin, berserk, stun maneuvers)
  - Remove webs/bound (1040, berserk, beseech)
  - Remove grounded/rooted (retreat, escape artist)
  - Dispel magical debuffs
  - Recover disarmed weapons
  - Avoid webs, globes, clouds in room
    ]])
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function main_loop()
    while true do
        -- Process event stack
        while #event_stack > 0 do
            local current_event = table.remove(event_stack, 1)
            local action = action_map[current_event]
            if action then
                action()
            end
        end

        -- Check conditions
        if poisoned() then
            local found = false
            for _, e in ipairs(event_stack) do if e == "remove_poison" then found = true end end
            if not found then table.insert(event_stack, "remove_poison") end
        end

        if diseased() then
            local found = false
            for _, e in ipairs(event_stack) do if e == "remove_disease" then found = true end end
            if not found then table.insert(event_stack, "remove_disease") end
        end

        if stunned() then
            local found = false
            for _, e in ipairs(event_stack) do if e == "remove_stun" then found = true end end
            if not found then table.insert(event_stack, "remove_stun") end
        end

        if webbed() or bound() then
            local found = false
            for _, e in ipairs(event_stack) do if e == "remove_web_bound" then found = true end end
            if not found then table.insert(event_stack, "remove_web_bound") end
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
if cmd then cmd = cmd:lower() end

if cmd == "setup" then
    -- Simple text-based setup
    respond("ECleanse Setup - Edit settings via ;" .. Script.name .. " list")
    respond("To change a setting: ;e CharSettings.ecleanse_<key> = 'true'")
    respond("Then: ;" .. Script.name .. " load")
    show_settings()
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

    -- Dead man's switch: kill script if dead
    -- (In Revenant, handled by the runtime)

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
