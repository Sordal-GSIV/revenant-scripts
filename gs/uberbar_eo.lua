--- @revenant-script
--- name: uberbar_eo
--- version: 2.1.0
--- author: elanthia-online
--- contributors: Dantax, Tysong, Gibreficul, Bait, Xanlin, Khazaann, Dissonance
--- game: gs
--- description: Enhanced status bar display with vitals, wounds, experience, and resources
--- tags: uberbar,vitals,status,paperdoll

--------------------------------------------------------------------------------
-- UberBar EO - Enhanced status bar display
--
-- Creates a GUI window showing health/mana/stamina/spirit bars, wound status,
-- experience tracking, profession resources, and other character data.
--
-- Usage:
--   ;uberbar_eo                           - Start the status display
--   ;uberbar_eo help                      - Show help and settings
--   ;uberbar_eo --display-silver=on       - Enable silver tracking
--   ;uberbar_eo --display-resources=off   - Disable resource bars
--   ;uberbar_eo --silent-check-interval=N - Set check interval in seconds
--------------------------------------------------------------------------------

no_kill_all()
no_pause_all()

local VERSION = "2.1.0"

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    display_silver         = true,
    display_bounty         = true,
    display_room           = true,
    display_favor          = true,
    display_atp            = true,
    display_tp             = true,
    display_fxp            = true,
    display_resources      = true,
    display_shadow_essence = false,
    display_percentcap     = true,
    display_loudxp         = false,
    display_debug          = false,
    silent_check_interval  = 120,
}

-- Load saved settings
local raw_settings = CharSettings.uberbar_eo_settings
local settings = {}
if raw_settings then
    local ok, saved = pcall(Json.decode, raw_settings)
    if ok and type(saved) == "table" then
        settings = saved
    end
end
-- Apply defaults for missing keys
for k, v in pairs(DEFAULT_SETTINGS) do
    if settings[k] == nil then
        settings[k] = v
    end
end

local function save_settings()
    CharSettings.uberbar_eo_settings = Json.encode(settings)
end

--------------------------------------------------------------------------------
-- Body area definitions for wounds/scars
--------------------------------------------------------------------------------

local BODY_AREAS = {
    { key = "nsys",      name = "nerves" },
    { key = "leftArm",   name = "left arm" },
    { key = "rightArm",  name = "right arm" },
    { key = "rightLeg",  name = "right leg" },
    { key = "leftLeg",   name = "left leg" },
    { key = "head",       name = "head" },
    { key = "rightFoot",  name = "right foot" },
    { key = "leftFoot",   name = "left foot" },
    { key = "rightHand",  name = "right hand" },
    { key = "leftHand",   name = "left hand" },
    { key = "rightEye",   name = "right eye" },
    { key = "leftEye",    name = "left eye" },
    { key = "back",       name = "back" },
    { key = "neck",       name = "neck" },
    { key = "chest",      name = "chest" },
    { key = "abdomen",    name = "abdomen" },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function with_commas(num)
    local s = tostring(num)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function profession_has_resources()
    local prof = Stats.prof
    if prof == "Bard"     then return Spell[1030] and Spell[1030].known end
    if prof == "Cleric"   then return Spell[330] and Spell[330].known end
    if prof == "Empath"   then return Spell[1135] and Spell[1135].known end
    if prof == "Monk"     then return Stats.level >= 20 end
    if prof == "Paladin"  then return Spell[1620] and Spell[1620].known end
    if prof == "Ranger"   then return Spell[620] and Spell[620].known end
    if prof == "Rogue"    then return Stats.level >= 20 end
    if prof == "Sorcerer" then return Spell[735] and Spell[735].known end
    if prof == "Warrior"  then return Stats.level >= 20 end
    if prof == "Wizard"   then return Spell[925] and Spell[925].known end
    return false
end

local function get_wound_hash()
    local hash = {}
    for _, area in ipairs(BODY_AREAS) do
        local w = Wounds[area.key] or 0
        local s = Scars[area.key] or 0
        table.insert(hash, w * 10 + s)
    end
    return hash
end

local function wounds_equal(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Help command
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("UberBar EO v" .. VERSION .. " - Enhanced Status Bar Display")
    respond("=====================================================")
    respond("")
    respond("  Creates a GUI window with vitals, wounds, experience, and resources.")
    respond("")
    respond("  Configuration (pass as arguments):")
    respond("")
    respond("    --display-silver=on|off          Silver tracker (needs ;bank or ;ledger)")
    respond("    --display-bounty=on|off          Bounty point tracker")
    respond("    --display-room=on|off            Room number display")
    respond("    --display-favor=on|off           Voln favor display")
    respond("    --display-atp=on|off             ATP progress bar")
    respond("    --display-tp=on|off              TP/TNL progress bar")
    respond("    --display-fxp=on|off             Field XP in mind bar")
    respond("    --display-resources=on|off       Profession resource bars")
    respond("    --display-shadow-essence=on|off  Shadow Essence (Sorcerers)")
    respond("    --display-percentcap=on|off      Percent capped bar")
    respond("    --display-loudxp=on|off          Loud XP pulse echo")
    respond("    --display-debug=on|off           Debug messages")
    respond("    --silent-check-interval=N        Seconds between EXP/RESOURCE checks")
    respond("")
end

--------------------------------------------------------------------------------
-- Parse command-line settings
--------------------------------------------------------------------------------

local function apply_cli_settings()
    local args_str = Script.vars[0] or ""
    if args_str == "" then return false end

    local changed = false
    for key, val in string.gmatch(args_str, "%-%-([%w%-]+)=(%S+)") do
        local lua_key = string.gsub(key, "%-", "_")
        local bool_map = { on = true, off = false, yes = true, no = false, ["true"] = true, ["false"] = false }

        if DEFAULT_SETTINGS[lua_key] ~= nil then
            if type(DEFAULT_SETTINGS[lua_key]) == "boolean" then
                local bval = bool_map[string.lower(val)]
                if bval ~= nil then
                    echo("  " .. key .. " = " .. tostring(bval))
                    settings[lua_key] = bval
                    changed = true
                end
            elseif type(DEFAULT_SETTINGS[lua_key]) == "number" then
                local nval = tonumber(val)
                if nval then
                    echo("  " .. key .. " = " .. tostring(nval))
                    settings[lua_key] = nval
                    changed = true
                end
            end
        end
    end

    if changed then save_settings() end
    return changed
end

--------------------------------------------------------------------------------
-- GUI display
--------------------------------------------------------------------------------

local win = nil

local function build_gui()
    win = Gui.window("UberBar - " .. GameState.name, { width = 220, height = 400, resizable = true })
    local root = Gui.vbox()

    -- Header
    root:add(Gui.section_header(GameState.name .. "'s Status"))

    -- Vital bars
    local health_bar = Gui.progress(Char.percent_health / 100)
    local mana_bar = Gui.progress(Char.percent_mana / 100)
    local stamina_bar = Gui.progress(Char.percent_stamina / 100)
    local spirit_bar = Gui.progress(Char.percent_spirit / 100)

    root:add(Gui.label("Health: " .. Char.health .. "/" .. Char.max_health))
    root:add(health_bar)
    root:add(Gui.label("Mana: " .. Char.mana .. "/" .. Char.max_mana))
    root:add(mana_bar)
    root:add(Gui.label("Stamina: " .. Char.stamina .. "/" .. Char.max_stamina))
    root:add(stamina_bar)
    root:add(Gui.label("Spirit: " .. Char.spirit .. "/" .. Char.max_spirit))
    root:add(spirit_bar)

    root:add(Gui.separator())

    -- Wounds display
    local wounds_label = Gui.label("Wounds: checking...")
    root:add(wounds_label)

    -- Experience tracking labels
    local xp_label = Gui.label("Level: " .. Stats.level)
    local mind_label = Gui.label("Mind: " .. (GameState.mind or "clear"))
    local stance_label = Gui.label("Stance: " .. (GameState.stance or ""))
    local enc_label = Gui.label("Enc: " .. (GameState.encumbrance or ""))

    root:add(Gui.separator())
    root:add(xp_label)
    root:add(mind_label)
    root:add(stance_label)
    root:add(enc_label)

    -- Room display
    local room_label = nil
    if settings.display_room then
        room_label = Gui.label("Room: " .. (GameState.room_id or "?"))
        root:add(room_label)
    end

    -- XP tracking state
    local total_xp_gained = 0
    local start_time = os.time()
    local last_xp = 0
    local pulse_xp = 0

    -- Pulse/hour labels
    root:add(Gui.separator())
    local pulse_label = Gui.label("Pulse: 0")
    local hour_label = Gui.label("Avg/Hr: 0")
    local today_label = Gui.label("Today: 0")
    root:add(pulse_label)
    root:add(hour_label)
    root:add(today_label)

    win:set_root(Gui.scroll(root))
    win:show()

    -- Save old wound state
    local old_wounds = get_wound_hash()

    -- Update loop
    while true do
        pause(2)

        -- Update vitals
        health_bar:set_value(Char.percent_health / 100)
        mana_bar:set_value(Char.percent_mana / 100)
        stamina_bar:set_value(Char.percent_stamina / 100)
        spirit_bar:set_value(Char.percent_spirit / 100)

        -- Update labels
        mind_label:set_text("Mind: " .. (GameState.mind or "clear"))
        stance_label:set_text("Stance: " .. (GameState.stance or ""))
        enc_label:set_text("Enc: " .. (GameState.encumbrance or ""))

        -- Room
        if room_label and settings.display_room then
            room_label:set_text("Room: " .. (GameState.room_id or "?"))
        end

        -- Wounds check
        local new_wounds = get_wound_hash()
        if not wounds_equal(old_wounds, new_wounds) then
            local wound_parts = {}
            for i, area in ipairs(BODY_AREAS) do
                local w = Wounds[area.key] or 0
                local s = Scars[area.key] or 0
                if w > 0 then
                    table.insert(wound_parts, area.name .. " W" .. w)
                elseif s > 0 then
                    table.insert(wound_parts, area.name .. " S" .. s)
                end
            end
            if #wound_parts > 0 then
                wounds_label:set_text("Wounds: " .. table.concat(wound_parts, ", "))
            else
                wounds_label:set_text("Wounds: none")
            end
            old_wounds = new_wounds
        end

        -- XP tracking
        local elapsed = os.time() - start_time
        if elapsed > 0 then
            hour_label:set_text("Avg/Hr: " .. with_commas(math.floor(total_xp_gained / (elapsed / 3600))))
        end
        today_label:set_text("Today: " .. with_commas(total_xp_gained))
        pulse_label:set_text("Pulse: " .. with_commas(pulse_xp))
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Save settings on exit
before_dying(function()
    save_settings()
    if win then
        win:close()
    end
end)

-- Handle CLI
if Script.vars[1] and string.find(string.lower(Script.vars[1]), "help") then
    show_help()
elseif Script.vars[1] and string.find(Script.vars[1], "%-%-") then
    apply_cli_settings()
    build_gui()
elseif Script.vars[1] and string.find(string.lower(Script.vars[1]), "list") then
    respond(Json.encode(settings))
else
    apply_cli_settings()
    build_gui()
end
