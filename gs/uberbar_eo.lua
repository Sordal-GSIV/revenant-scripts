--- @revenant-script
--- name: uberbar_eo
--- version: 2.1.0
--- author: elanthia-online
--- contributors: Dantax, Tysong, Gibreficul, Bait, Xanlin, Khazaann, Dissonance
--- game: gs
--- description: Enhanced status bar display with vitals, wounds, experience, and resources
--- tags: uberbar,vitals,status,paperdoll
--- @lic-certified: complete 2026-03-18
---
--- Original: Based off uberbarv_d, which was a fork of uberbarv, which was a fork of uberbar
--- Integrates with ;bank or ;ledger script to display Silver gained during day (optional)
--- Integrates with ;bank or ;hud_bounty script to display Bounty points gained (optional)
---
--- Changelog (from Lich5):
---   v2.1.0 (2026-01-13): add Shadow Essence tracking bar for Sorcerers
---   v2.0.3 (2025-10-29): remove saving of XP history into UserVars
---   v2.0.2 (2025-09-24): update percent capped to use total experience
---   v2.0.1 (2025-07-04): allow for empath resource to work
---   v2.0.0 (2025-04-28): converted to module, togglable bars, configurable interval
---   v1.2.0 (2025-04-28): added rogue resources, tweaked % capped for empaths
---   v1.1.0 (2025-04-27): replaced deprecated calls with Char class, added % capped
---   v1.0.0 (2024-03-10): initial release, forked from uberbarv_d v2.1
---
--- Usage:
---   ;uberbar_eo                              - Start the status display
---   ;uberbar_eo help                         - Show help and settings
---   ;uberbar_eo list                         - Show current settings
---   ;uberbar_eo --display-silver=on          - Enable silver tracking
---   ;uberbar_eo --display-resources=off      - Disable resource bars
---   ;uberbar_eo --silent-check-interval=N    - Set check interval in seconds

no_kill_all()
no_pause_all()
hide_me()
silence_me()

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

local function debug_echo(msg)
    if settings.display_debug then
        echo(msg)
    end
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
    { key = "head",      name = "head" },
    { key = "rightFoot", name = "right foot" },
    { key = "leftFoot",  name = "left foot" },
    { key = "rightHand", name = "right hand" },
    { key = "leftHand",  name = "left hand" },
    { key = "rightEye",  name = "right eye" },
    { key = "leftEye",   name = "left eye" },
    { key = "back",      name = "back" },
    { key = "neck",      name = "neck" },
    { key = "chest",     name = "chest" },
    { key = "abdomen",   name = "abdomen" },
}

-- Wound severity labels
local WOUND_LABELS = { [0] = "-", [1] = "minor", [2] = "moderate", [3] = "severe" }
local SCAR_LABELS  = { [0] = "-", [1] = "minor", [2] = "moderate", [3] = "severe" }

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

local function is_voln_member()
    local status = Society.status or ""
    return status:find("Voln") ~= nil
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

--- Build a text-based paperdoll showing per-body-part wound/scar severity
local function build_wound_paperdoll()
    local lines = {}
    local any_injury = false
    for _, area in ipairs(BODY_AREAS) do
        local w = Wounds[area.key] or 0
        local s = Scars[area.key] or 0
        if w > 0 or s > 0 then
            any_injury = true
            local severity
            if w > 0 then
                severity = "W" .. w .. " (" .. WOUND_LABELS[w] .. ")"
            else
                severity = "S" .. s .. " (" .. SCAR_LABELS[s] .. ")"
            end
            table.insert(lines, string.format("  %-12s %s", area.name, severity))
        end
    end
    if not any_injury then
        return "  No injuries"
    end
    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- XP Tracking State
--------------------------------------------------------------------------------

local xp_state = {
    -- Per-pulse tracking
    last_experience    = nil,   -- GameState.experience at last check
    pulse_xp           = 0,     -- XP gained in most recent pulse

    -- Ascension XP tracking (separate from normal XP)
    last_axp           = nil,   -- Experience.axp at last check
    pulse_axp          = 0,     -- Ascension XP gained in most recent pulse

    -- Session tracking
    session_start_time = os.time(),
    session_start_xp   = nil,   -- GameState.experience at session start
    session_total_xp   = 0,     -- Total XP earned this session (normal + ascension)
    per_hour           = 0,     -- Calculated XP per hour

    -- Daily tracking (resets at 5AM)
    daily_xp           = 0,
    daily_reset_day    = nil,

    -- ATP tracking
    atp_total          = 0,
    atp_next           = 50000,
    atp_pulse          = 0,
    atp_last_exp       = 0,

    -- First pulse flag
    first_pulse        = true,
}

--- Initialize daily XP from saved state
local function init_daily_xp()
    local saved_day = CharSettings.uberbar_daily_day
    local saved_xp  = CharSettings.uberbar_daily_xp
    local now = os.date("*t")
    local current_day = now.yday

    if saved_day then
        saved_day = tonumber(saved_day)
    end
    if saved_xp then
        saved_xp = tonumber(saved_xp)
    end

    -- Reset if new day (after 5AM) or no saved data
    if not saved_day or not saved_xp then
        xp_state.daily_xp = 0
        xp_state.daily_reset_day = current_day
    elseif saved_day ~= current_day and now.hour >= 5 then
        xp_state.daily_xp = 0
        xp_state.daily_reset_day = current_day
    else
        xp_state.daily_xp = saved_xp
        xp_state.daily_reset_day = saved_day
    end
end

local function save_daily_xp()
    CharSettings.uberbar_daily_day = tostring(xp_state.daily_reset_day or os.date("*t").yday)
    CharSettings.uberbar_daily_xp  = tostring(xp_state.daily_xp)
end

--- Calculate XP per pulse by comparing GameState.experience between updates.
--- Also tracks ascension XP pulse via Experience.axp.
local function update_xp_tracking()
    local current_xp  = GameState.experience
    local current_axp = Experience.axp

    if not current_xp then return end

    if xp_state.first_pulse then
        xp_state.last_experience = current_xp
        xp_state.last_axp        = current_axp
        xp_state.session_start_xp = current_xp
        xp_state.session_start_time = os.time()
        xp_state.first_pulse = false
        xp_state.pulse_xp  = 0
        xp_state.pulse_axp = 0
        return
    end

    -- Normal XP pulse (experience in next_level terms; goes down as you progress toward level)
    -- GameState.experience tracks experience until next level, so gaining XP decreases it.
    -- We detect the change and compute a positive gained value.
    if xp_state.last_experience then
        local gained = current_xp - xp_state.last_experience
        -- XP until next level decreases as you gain; filter nonsensical jumps
        if gained < 0 and gained > -50000 then
            -- negative delta means we gained XP
            xp_state.pulse_xp = -gained
        elseif gained > 0 then
            -- XP until level increased (e.g. level-up or mind cleared) — track as 0
            xp_state.pulse_xp = 0
        else
            xp_state.pulse_xp = 0
        end
    end

    -- Ascension XP pulse
    xp_state.pulse_axp = 0
    if xp_state.last_axp and current_axp > xp_state.last_axp then
        xp_state.pulse_axp = current_axp - xp_state.last_axp
    end

    local total_gained = xp_state.pulse_xp + xp_state.pulse_axp

    if total_gained > 0 then
        xp_state.session_total_xp = xp_state.session_total_xp + total_gained
        xp_state.daily_xp = xp_state.daily_xp + total_gained

        -- Check for daily reset (5AM boundary)
        local now = os.date("*t")
        if xp_state.daily_reset_day ~= now.yday and now.hour >= 5 then
            xp_state.daily_xp = total_gained
            xp_state.daily_reset_day = now.yday
        end

        save_daily_xp()

        if settings.display_loudxp then
            echo(string.format("********  %d EXP Gained this Pulse ********* (%s)+",
                total_gained, os.date("%X")))
        end
    end

    xp_state.last_experience = current_xp
    xp_state.last_axp        = current_axp

    -- Calculate per-hour rate
    local elapsed = os.time() - xp_state.session_start_time
    if elapsed > 0 then
        xp_state.per_hour = math.floor(xp_state.session_total_xp / (elapsed / 3600))
    end
end

--------------------------------------------------------------------------------
-- ATP/Resource tracking via silent commands
--------------------------------------------------------------------------------

--- Send a silent 'experience' command and wait for it to complete.
--- Updates atp_next/atp_total from the infomon cache after the command returns.
local function check_experience_silent()
    put("experience")
    local timeout = os.time() + 5
    while os.time() < timeout do
        local line = get_noblock()
        if not line then
            pause(0.1)
        else
            if line:find("^>") or line:find("<prompt") then
                break
            end
        end
    end

    -- Pull updated values from infomon (infomon.rs parses them)
    local atp_next = Infomon.get_i("experience.ascension_experience")
    if atp_next and atp_next > 0 then
        xp_state.atp_next = atp_next
    end
    local atp_total = Infomon.get_i("experience.total_experience")
    if atp_total and atp_total > 0 then
        xp_state.atp_total = atp_total
    end
end

--- Send a silent 'resource' command and wait for it to complete.
--- The infomon cache is updated automatically as output is parsed.
local function check_resource_silent()
    put("resource")
    local timeout = os.time() + 5
    while os.time() < timeout do
        local line = get_noblock()
        if not line then
            pause(0.1)
        else
            if line:find("^>") or line:find("<prompt") then
                break
            end
        end
    end
end

--- Check if periodic silent checks are needed
local function needs_periodic_check()
    return settings.display_resources
        or settings.display_favor
        or settings.display_shadow_essence
        or settings.display_fxp
        or settings.display_atp
        or settings.display_tp
        or settings.display_percentcap
end

--------------------------------------------------------------------------------
-- Change detection state
--------------------------------------------------------------------------------

local prev_state = {
    health       = nil,
    max_health   = nil,
    mana         = nil,
    max_mana     = nil,
    stamina      = nil,
    max_stamina  = nil,
    spirit       = nil,
    max_spirit   = nil,
    mind         = nil,
    mind_value   = nil,
    stance       = nil,
    stance_value = nil,
    encumbrance  = nil,
    enc_value    = nil,
    room_id      = nil,
    experience   = nil,
    axp          = nil,
    wounds       = {},
}

--- Check if any tracked state has changed
local function state_changed()
    if prev_state.health     ~= Char.health then return true end
    if prev_state.max_health ~= Char.max_health then return true end
    if prev_state.mana       ~= Char.mana then return true end
    if prev_state.max_mana   ~= Char.max_mana then return true end
    if prev_state.stamina    ~= Char.stamina then return true end
    if prev_state.max_stamina ~= Char.max_stamina then return true end
    if prev_state.spirit     ~= Char.spirit then return true end
    if prev_state.max_spirit ~= Char.max_spirit then return true end
    if prev_state.mind       ~= GameState.mind then return true end
    if prev_state.mind_value ~= GameState.mind_value then return true end
    if prev_state.stance     ~= GameState.stance then return true end
    if prev_state.stance_value ~= GameState.stance_value then return true end
    if prev_state.encumbrance ~= GameState.encumbrance then return true end
    if prev_state.enc_value  ~= GameState.encumbrance_value then return true end
    if prev_state.experience ~= GameState.experience then return true end
    if prev_state.axp        ~= Experience.axp then return true end
    if settings.display_room and prev_state.room_id ~= GameState.room_id then return true end
    local new_wounds = get_wound_hash()
    if not wounds_equal(prev_state.wounds, new_wounds) then return true end
    return false
end

--- Snapshot current state
local function snapshot_state()
    prev_state.health      = Char.health
    prev_state.max_health  = Char.max_health
    prev_state.mana        = Char.mana
    prev_state.max_mana    = Char.max_mana
    prev_state.stamina     = Char.stamina
    prev_state.max_stamina = Char.max_stamina
    prev_state.spirit      = Char.spirit
    prev_state.max_spirit  = Char.max_spirit
    prev_state.mind        = GameState.mind
    prev_state.mind_value  = GameState.mind_value
    prev_state.stance      = GameState.stance
    prev_state.stance_value = GameState.stance_value
    prev_state.encumbrance = GameState.encumbrance
    prev_state.enc_value   = GameState.encumbrance_value
    prev_state.experience  = GameState.experience
    prev_state.axp         = Experience.axp
    prev_state.room_id     = GameState.room_id
    prev_state.wounds      = get_wound_hash()
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
    respond("  Disabling atp, tp, fxp, percentcap will prevent periodic EXPERIENCE checks")
    respond("  Disabling favor, resources, & shadow-essence will prevent periodic RESOURCE checks")
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
        else
            respond(Script.name .. ": unrecognized option --" .. key ..
                    "; see ;" .. Script.name .. " help")
        end
    end

    if changed then save_settings() end
    return changed
end

--------------------------------------------------------------------------------
-- GUI display
--------------------------------------------------------------------------------

local win = nil

--- Build the TP/TNL bar text and progress value
local function tp_display()
    local capped = (Stats.level == 100)
    local xp = GameState.experience or 0
    if capped then
        -- experience field counts XP within current ATP cycle (0–2499)
        local until_tp = ((math.floor(xp / 2500) + 1) * 2500) - xp
        local val = (2500 - until_tp) / 2500
        return with_commas(until_tp) .. " until TP", val
    else
        local nlv = GameState.mind_value or 0
        return string.format("Level: %d  %s TNL", Stats.level, with_commas(xp)), nlv / 100
    end
end

--- Build percent-capped display using total XP (includes ascension)
--- 7,572,500 = experience required to be 100% capped at level 100
local function pcap_display()
    local total_xp = Experience.txp
    if not total_xp or total_xp == 0 then
        -- Fall back to GameState.experience if txp not yet populated
        total_xp = GameState.experience or 0
    end
    local pct = (total_xp / 7572500) * 100
    if pct > 100 then pct = 100 end
    return string.format("%.2f%% Capped", pct), pct / 100
end

--- Build mind bar text (with optional field XP)
local function mind_display()
    local mind_text = GameState.mind or "clear"
    if settings.display_fxp then
        local fxp_cur = Experience.fxp_current
        local fxp_max = Experience.fxp_max
        if fxp_cur and fxp_max then
            mind_text = mind_text .. string.format(" (%d/%d)", fxp_cur, fxp_max)
        end
    end
    return mind_text, (GameState.mind_value or 0) / 100
end

local function build_gui()
    win = Gui.window("UberBar - " .. GameState.name, { width = 240, height = 550, resizable = true })
    local root = Gui.vbox()

    -- Header
    root:add(Gui.section_header(GameState.name .. "'s Status"))

    ---------------------------------------------------------------------------
    -- Vital bars
    ---------------------------------------------------------------------------
    local health_label  = Gui.label("Health: " .. Char.health .. "/" .. Char.max_health)
    local health_bar    = Gui.progress(Char.percent_health / 100)
    local mana_label    = Gui.label("Mana: " .. Char.mana .. "/" .. Char.max_mana)
    local mana_bar      = Gui.progress(Char.percent_mana / 100)
    local stamina_label = Gui.label("Stamina: " .. Char.stamina .. "/" .. Char.max_stamina)
    local stamina_bar   = Gui.progress(Char.percent_stamina / 100)
    local spirit_label  = Gui.label("Spirit: " .. Char.spirit .. "/" .. Char.max_spirit)
    local spirit_bar    = Gui.progress(Char.percent_spirit / 100)

    root:add(health_label)
    root:add(health_bar)
    root:add(mana_label)
    root:add(mana_bar)
    root:add(stamina_label)
    root:add(stamina_bar)
    root:add(spirit_label)
    root:add(spirit_bar)

    root:add(Gui.separator())

    ---------------------------------------------------------------------------
    -- Wound paperdoll (text-based)
    ---------------------------------------------------------------------------
    local wounds_header = Gui.label("-- Injuries --")
    local wounds_label  = Gui.label(build_wound_paperdoll())
    root:add(wounds_header)
    root:add(wounds_label)

    root:add(Gui.separator())

    ---------------------------------------------------------------------------
    -- Status bars: mind, stance, encumbrance
    ---------------------------------------------------------------------------
    local mind_text, mind_val = mind_display()
    local mind_label   = Gui.label("Mind: " .. mind_text)
    local mind_bar     = Gui.progress(mind_val)
    local stance_label = Gui.label("Stance: " .. (GameState.stance or ""))
    local stance_bar   = Gui.progress((GameState.stance_value or 0) / 100)
    local enc_label    = Gui.label("Enc: " .. (GameState.encumbrance or ""))
    local enc_bar      = Gui.progress((GameState.encumbrance_value or 0) / 100)

    root:add(mind_label)
    root:add(mind_bar)
    root:add(stance_label)
    root:add(stance_bar)
    root:add(enc_label)
    root:add(enc_bar)

    root:add(Gui.separator())

    ---------------------------------------------------------------------------
    -- TP/TNL progress bar
    ---------------------------------------------------------------------------
    local tp_bar         = nil
    local tp_label_widget = nil
    if settings.display_tp then
        local tp_text, tp_val = tp_display()
        tp_label_widget = Gui.label(tp_text)
        tp_bar = Gui.progress(tp_val)
        root:add(tp_label_widget)
        root:add(tp_bar)
    end

    ---------------------------------------------------------------------------
    -- ATP progress bar
    ---------------------------------------------------------------------------
    local atp_bar         = nil
    local atp_label_widget = nil
    if settings.display_atp then
        local progress = 1.0 - (xp_state.atp_next / 50000)
        if progress < 0 then progress = 0 end
        atp_label_widget = Gui.label(with_commas(xp_state.atp_next) .. " to ATP [" .. xp_state.atp_total .. "]")
        atp_bar = Gui.progress(progress)
        root:add(atp_label_widget)
        root:add(atp_bar)
    end

    ---------------------------------------------------------------------------
    -- Percent capped bar
    ---------------------------------------------------------------------------
    local pcap_bar         = nil
    local pcap_label_widget = nil
    if settings.display_percentcap then
        local pcap_text, pcap_val = pcap_display()
        pcap_label_widget = Gui.label(pcap_text)
        pcap_bar = Gui.progress(pcap_val)
        root:add(pcap_label_widget)
        root:add(pcap_bar)
    end

    root:add(Gui.separator())

    ---------------------------------------------------------------------------
    -- Room display
    ---------------------------------------------------------------------------
    local room_label = nil
    if settings.display_room then
        room_label = Gui.label("Room: " .. tostring(GameState.room_id or "?"))
        root:add(room_label)
    end

    ---------------------------------------------------------------------------
    -- XP tracking labels
    ---------------------------------------------------------------------------
    local pulse_label = Gui.label("Pulse: 0")
    local hour_label  = Gui.label("Avg/Hr: 0")
    local today_label = Gui.label("Today: " .. with_commas(xp_state.daily_xp))
    root:add(Gui.separator())
    root:add(pulse_label)
    root:add(hour_label)
    root:add(today_label)

    ---------------------------------------------------------------------------
    -- Silver / Bounty labels (optional)
    ---------------------------------------------------------------------------
    local silver_label = nil
    if settings.display_silver then
        silver_label = Gui.label("Silver: 0")
        root:add(silver_label)
    end

    local bounty_label = nil
    if settings.display_bounty then
        bounty_label = Gui.label("Bounty: 0")
        root:add(bounty_label)
    end

    ---------------------------------------------------------------------------
    -- Favor display (Voln only, optional)
    ---------------------------------------------------------------------------
    local favor_label = nil
    if settings.display_favor and is_voln_member() then
        favor_label = Gui.label("Favor: " .. with_commas(Resources.voln_favor))
        root:add(favor_label)
    end

    ---------------------------------------------------------------------------
    -- Resource bars (optional, profession-dependent): weekly + total
    ---------------------------------------------------------------------------
    local resource_weekly_label = nil
    local resource_weekly_bar   = nil
    local resource_total_label  = nil
    local resource_total_bar    = nil
    if settings.display_resources and profession_has_resources() then
        local rtype   = Resources.type or "Resource"
        local weekly  = Resources.weekly  or 0
        local total   = Resources.total   or 0
        local wpct = weekly / 50000
        if wpct > 1 then wpct = 1 end
        local tpct = total / 200000
        if tpct > 1 then tpct = 1 end
        resource_weekly_label = Gui.label(rtype .. " (weekly): " .. with_commas(weekly) .. "/50,000")
        resource_weekly_bar   = Gui.progress(wpct)
        resource_total_label  = Gui.label(rtype .. " (total): " .. with_commas(total) .. "/200,000")
        resource_total_bar    = Gui.progress(tpct)
        root:add(resource_weekly_label)
        root:add(resource_weekly_bar)
        root:add(resource_total_label)
        root:add(resource_total_bar)
    end

    ---------------------------------------------------------------------------
    -- Shadow Essence (optional, Sorcerer only)
    ---------------------------------------------------------------------------
    local essence_label = nil
    local essence_bar   = nil
    if settings.display_shadow_essence and Stats.prof == "Sorcerer" then
        local essence = Resources.shadow_essence or 0
        local epct = essence / 5
        if epct > 1 then epct = 1 end
        essence_label = Gui.label("Shadow Essence: " .. essence .. "/5")
        essence_bar   = Gui.progress(epct)
        root:add(essence_label)
        root:add(essence_bar)
    end

    win:set_root(Gui.scroll(root))
    win:show()

    ---------------------------------------------------------------------------
    -- Initialize state tracking
    ---------------------------------------------------------------------------
    local old_wounds = get_wound_hash()
    snapshot_state()
    init_daily_xp()

    -- Track last periodic check time
    local last_periodic_check = os.time()
    local check_interval = settings.silent_check_interval or 120

    -- Track last displayed resource/favor/essence values for change detection
    local last_silver  = -1
    local last_bounty  = -1
    local last_favor   = -1
    local last_weekly  = -1
    local last_total   = -1
    local last_essence = -1

    ---------------------------------------------------------------------------
    -- Main update loop
    ---------------------------------------------------------------------------
    while true do
        -- Wait until state changes or timeout (efficient change detection)
        local update_timeout = os.time() + 5
        while not state_changed() and os.time() < update_timeout do
            pause(0.5)
        end

        -- Update XP tracking
        update_xp_tracking()

        -----------------------------------------------------------------------
        -- Update vitals (only when changed)
        -----------------------------------------------------------------------
        if prev_state.health ~= Char.health or prev_state.max_health ~= Char.max_health then
            debug_echo("updated health")
            health_label:set_text("Health: " .. Char.health .. "/" .. Char.max_health)
            health_bar:set_value(Char.percent_health / 100)
        end

        if prev_state.mana ~= Char.mana or prev_state.max_mana ~= Char.max_mana then
            debug_echo("updated mana")
            mana_label:set_text("Mana: " .. Char.mana .. "/" .. Char.max_mana)
            mana_bar:set_value(Char.percent_mana / 100)
        end

        if prev_state.stamina ~= Char.stamina or prev_state.max_stamina ~= Char.max_stamina then
            debug_echo("updated stamina")
            stamina_label:set_text("Stamina: " .. Char.stamina .. "/" .. Char.max_stamina)
            stamina_bar:set_value(Char.percent_stamina / 100)
        end

        if prev_state.spirit ~= Char.spirit or prev_state.max_spirit ~= Char.max_spirit then
            debug_echo("updated spirit")
            spirit_label:set_text("Spirit: " .. Char.spirit .. "/" .. Char.max_spirit)
            spirit_bar:set_value(Char.percent_spirit / 100)
        end

        -----------------------------------------------------------------------
        -- Update mind/stance/encumbrance bars (only when changed)
        -----------------------------------------------------------------------
        if prev_state.mind ~= GameState.mind or prev_state.mind_value ~= GameState.mind_value then
            debug_echo("updated mind")
            local mt, mv = mind_display()
            mind_label:set_text("Mind: " .. mt)
            mind_bar:set_value(mv)
        end

        if prev_state.stance ~= GameState.stance or prev_state.stance_value ~= GameState.stance_value then
            debug_echo("updated stance")
            stance_label:set_text("Stance: " .. (GameState.stance or ""))
            stance_bar:set_value((GameState.stance_value or 0) / 100)
        end

        if prev_state.encumbrance ~= GameState.encumbrance or prev_state.enc_value ~= GameState.encumbrance_value then
            debug_echo("updated encumbrance")
            enc_label:set_text("Enc: " .. (GameState.encumbrance or ""))
            enc_bar:set_value((GameState.encumbrance_value or 0) / 100)
        end

        -----------------------------------------------------------------------
        -- Update room
        -----------------------------------------------------------------------
        if room_label and settings.display_room and prev_state.room_id ~= GameState.room_id then
            debug_echo("updated room")
            room_label:set_text("Room: " .. tostring(GameState.room_id or "?"))
        end

        -----------------------------------------------------------------------
        -- Update wound paperdoll (only when changed)
        -----------------------------------------------------------------------
        local new_wounds = get_wound_hash()
        if not wounds_equal(old_wounds, new_wounds) then
            debug_echo("updated injuries")
            wounds_label:set_text(build_wound_paperdoll())
            old_wounds = new_wounds
        end

        -----------------------------------------------------------------------
        -- Update XP displays
        -----------------------------------------------------------------------
        if prev_state.experience ~= GameState.experience or prev_state.axp ~= Experience.axp then
            debug_echo("updated experience")

            local total_pulse = xp_state.pulse_xp + xp_state.pulse_axp
            pulse_label:set_text("Pulse: " .. with_commas(total_pulse))
            hour_label:set_text("Avg/Hr: " .. with_commas(xp_state.per_hour))
            today_label:set_text("Today: " .. with_commas(xp_state.daily_xp))

            -- Update TP/TNL bar
            if tp_bar and tp_label_widget and settings.display_tp then
                local tp_text, tp_val = tp_display()
                tp_bar:set_value(tp_val)
                tp_label_widget:set_text(tp_text)
            end

            -- Update percent capped bar
            if pcap_bar and pcap_label_widget and settings.display_percentcap then
                local pcap_text, pcap_val = pcap_display()
                pcap_bar:set_value(pcap_val)
                pcap_label_widget:set_text(pcap_text)
            end

            -- Update mind bar FXP (FXP changes with XP pulse)
            if settings.display_fxp then
                local mt, mv = mind_display()
                mind_label:set_text("Mind: " .. mt)
                mind_bar:set_value(mv)
            end
        end

        -----------------------------------------------------------------------
        -- Periodic silent checks (exp/resource) at configurable intervals
        -----------------------------------------------------------------------
        if needs_periodic_check() and (os.time() - last_periodic_check) > check_interval then
            last_periodic_check = os.time()

            -- Silent EXP check for ATP data + percent capped
            if settings.display_atp or settings.display_tp or settings.display_fxp or settings.display_percentcap then
                check_experience_silent()
                -- Update ATP bar
                if atp_bar and atp_label_widget then
                    local progress = 1.0 - (xp_state.atp_next / 50000)
                    if progress < 0 then progress = 0 end
                    atp_bar:set_value(progress)
                    atp_label_widget:set_text(with_commas(xp_state.atp_next) .. " to ATP [" .. xp_state.atp_total .. "]")
                end
                -- Refresh percent capped with latest txp
                if pcap_bar and pcap_label_widget and settings.display_percentcap then
                    local pcap_text, pcap_val = pcap_display()
                    pcap_bar:set_value(pcap_val)
                    pcap_label_widget:set_text(pcap_text)
                end
                -- Refresh mind FXP
                if settings.display_fxp then
                    local mt, mv = mind_display()
                    mind_label:set_text("Mind: " .. mt)
                    mind_bar:set_value(mv)
                end
            end

            -- Silent RESOURCE check
            if settings.display_resources or settings.display_favor or settings.display_shadow_essence then
                check_resource_silent()
            end
        end

        -----------------------------------------------------------------------
        -- Update silver / bounty (from external scripts via UserVars)
        -----------------------------------------------------------------------
        if silver_label and settings.display_silver then
            local daily_silver = tonumber(UserVars.bank_silver_per_day) or 0
            if daily_silver ~= last_silver then
                last_silver = daily_silver
                silver_label:set_text("Silver: " .. with_commas(daily_silver))
            end
        end

        if bounty_label and settings.display_bounty then
            local bp = tonumber(UserVars.bank_bounty_per_day) or 0
            if bp ~= last_bounty then
                last_bounty = bp
                bounty_label:set_text("Bounty: " .. with_commas(bp))
            end
        end

        -----------------------------------------------------------------------
        -- Update Voln favor (from Resources.voln_favor, updated by resource check)
        -----------------------------------------------------------------------
        if favor_label and settings.display_favor then
            local fav = Resources.voln_favor or 0
            if fav ~= last_favor then
                debug_echo("updated favor")
                last_favor = fav
                favor_label:set_text("Favor: " .. with_commas(fav))
            end
        end

        -----------------------------------------------------------------------
        -- Update resource bars (weekly + total)
        -----------------------------------------------------------------------
        if settings.display_resources and profession_has_resources() then
            local weekly = Resources.weekly  or 0
            local total  = Resources.total   or 0
            local rtype  = Resources.type    or "Resource"
            if weekly ~= last_weekly or total ~= last_total then
                debug_echo("updated resources")
                last_weekly = weekly
                last_total  = total
                if resource_weekly_label then
                    local wpct = weekly / 50000
                    if wpct > 1 then wpct = 1 end
                    resource_weekly_label:set_text(rtype .. " (weekly): " .. with_commas(weekly) .. "/50,000")
                    resource_weekly_bar:set_value(wpct)
                    resource_total_label:set_text(rtype .. " (total): " .. with_commas(total) .. "/200,000")
                    local tpct = total / 200000
                    if tpct > 1 then tpct = 1 end
                    resource_total_bar:set_value(tpct)
                end
            end
        end

        -----------------------------------------------------------------------
        -- Update Shadow Essence (Sorcerers)
        -----------------------------------------------------------------------
        if essence_label and settings.display_shadow_essence and Stats.prof == "Sorcerer" then
            local essence = Resources.shadow_essence or 0
            if essence ~= last_essence then
                debug_echo("updated shadow essence")
                last_essence = essence
                local epct = essence / 5
                if epct > 1 then epct = 1 end
                essence_label:set_text("Shadow Essence: " .. essence .. "/5")
                essence_bar:set_value(epct)
            end
        end

        -- Snapshot new state for next comparison
        snapshot_state()
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- Save settings and clean up on exit
before_dying(function()
    save_settings()
    save_daily_xp()
    if win then
        win:close()
        win = nil
    end
end)

-- Handle CLI
if Script.vars[1] and string.find(string.lower(Script.vars[1]), "help") then
    show_help()
elseif Script.vars[1] and string.find(string.lower(Script.vars[1]), "list") then
    respond(Json.encode(settings))
elseif Script.vars[1] and string.find(Script.vars[1], "%-%-") then
    apply_cli_settings()
    build_gui()
else
    apply_cli_settings()
    build_gui()
end
