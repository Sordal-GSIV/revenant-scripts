--- @revenant-script
--- name: tdusk
--- version: 1.26.6
--- author: Tysong (horibu on PC), original Nylis
--- game: gs
--- description: Automatic Duskruin arena script
--- tags: duskruin,arena,tdusk
---
--- Changelog (from Lich5):
---   v1.26.6 - Update help for duskattack with link to samples
---   v1.26.5 - Bugfix for endless swarm
---   v1.26.4 - Completely remove token system
---   v1.26.3 - Add bypass option for redeemed entries
---
--- Usage:
---   ;tdusk         -- start script outside arena entrance
---   ;tdusk help    -- show help and settings
---   ;toggletdusk   -- toggle pause_me setting while script is running
---
--- @lic-certified: complete 2026-03-20

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_setting(key, default)
    local raw = CharSettings[key]
    if raw == nil or raw == "" then return default end
    if raw == "true" then return true end
    if raw == "false" then return false end
    local num = tonumber(raw)
    if num then return num end
    return raw
end

local function save_setting(key, value)
    CharSettings[key] = tostring(value)
end

local cfg = {
    active_scripts  = load_setting("tdusk_active_scripts", "stand"),
    waggle_me       = load_setting("tdusk_waggle_me", true),
    waggle_script   = load_setting("tdusk_waggle_script", "ewaggle"),
    pause_me        = load_setting("tdusk_pause_me", true),
    enhancive_me    = load_setting("tdusk_enhancive_me", false),
    attack_script   = load_setting("tdusk_attack_script", false),
    broadcast       = load_setting("tdusk_broadcast", true),
    lootpackage     = load_setting("tdusk_lootpackage", true),
    open_lootsack   = load_setting("tdusk_open_lootsack", false),
    maxvitals       = load_setting("tdusk_maxvitals", false),
    experience      = load_setting("tdusk_experience", false),
    bardnode        = load_setting("tdusk_bardnode", true),
    node            = load_setting("tdusk_node", true),
    opener515       = load_setting("tdusk_opener515", false),
    opener909       = load_setting("tdusk_opener909", false),
    opener240       = load_setting("tdusk_opener240", false),
    girdstore       = load_setting("tdusk_girdstore", true),
    reentry         = load_setting("tdusk_reentry", true),
}

-- Parse active scripts list
local active_scripts_list = {}
if type(cfg.active_scripts) == "string" then
    for s in string.gmatch(cfg.active_scripts, "[^,]+") do
        table.insert(active_scripts_list, s:match("^%s*(.-)%s*$"))
    end
else
    active_scripts_list = { "stand" }
end

local wave_number = 0
local start_time  = 0
local total_time  = 0
local prev_total  = 0
local avg_reg     = 0
local avg_champ   = 0
local group_size  = 1
local ARENA_ROOM  = 24550

-- Champion wave set (waves 5,10,15,20,25 are bosses)
local CHAMP = { [5]=true, [10]=true, [15]=true, [20]=true, [25]=true }

--------------------------------------------------------------------------------
-- PCRE patterns (require Regex.new for alternation, same as arenatimer.lua)
--------------------------------------------------------------------------------

local RE_INTRO  = Regex.new([=[^An announcer shouts, "Introducing (?:.*)"]=])
local RE_FIGHT  = Regex.new([=[^An announcer shouts, "FIGHT!"  An iron portcullis is raised and .* (?:enter|enters) the arena!]=])
local RE_PORTC  = Regex.new([=[^An announcer shouts, "(?:.*)"  An iron portcullis is raised and .* (?:enter|enters) the arena!]=])
local RE_WIN    = Regex.new([=[^An announcer boasts, "(?:.*) defeating all those that opposed .* The overwhelming sound of applauding echoes throughout the stands!]=])
local RE_ESCORT = Regex.new([=[^An arena guard escorts you from the dueling sands]=])

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Write to familiar window for stream-capable frontends; fall back to respond()
-- Mirrors arenatimer.lua fam() helper
local function fam(text)
    if Frontend.supports_streams() then
        put('<pushStream id="familiar" ifClosedStyle="watching"/>' .. text .. "\r\n<popStream/>\r\n")
    else
        respond(text)
    end
end

-- Format seconds as MM:SS (matches Ruby Time.at(secs).strftime("%M:%S"))
local function fmt_mmss(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

-- Which network chat script to broadcast through (0net takes priority over lnet)
local function chat_script()
    if running("0net") then return "0net" end
    if running("lnet") then return "lnet" end
    return nil
end

-- Retry enhancive off with dothistimeout (mirrors Lich5 loop)
local function enhancive_off()
    local pat = [=[You are no longer accepting|nothing seems to happen|already are not accepting]=]
    while true do
        local result = dothistimeout("inventory enhancive off", 3,
            pat .. [=[|cannot turn off enhancives while in combat]=])
        if result and Regex.test(result, pat) then break end
        pause(5)
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond([[

    SYNTAX - ;tdusk
    Start script outside of entrance with your hands empty.
    Uses READY LIST set weapons/shield settings to store/ready between runs.

    Settings are stored in CharSettings. Examples:
      CharSettings["tdusk_waggle_me"]       = "true"/"false"
      CharSettings["tdusk_waggle_script"]   = "ewaggle"
      CharSettings["tdusk_pause_me"]        = "true"/"false"
      CharSettings["tdusk_enhancive_me"]    = "true"/"false"
      CharSettings["tdusk_bardnode"]        = "true"/"false"
      CharSettings["tdusk_node"]            = "true"/"false"
      CharSettings["tdusk_opener515"]       = "true"/"false"
      CharSettings["tdusk_opener909"]       = "true"/"false"
      CharSettings["tdusk_opener240"]       = "true"/"false"
      CharSettings["tdusk_attack_script"]   = "true"/"false"
      CharSettings["tdusk_girdstore"]       = "true"/"false"
      CharSettings["tdusk_lootpackage"]     = "true"/"false"
      CharSettings["tdusk_open_lootsack"]   = "true"/"false"
      CharSettings["tdusk_maxvitals"]       = "true"/"false"
      CharSettings["tdusk_experience"]      = number or "false"
      CharSettings["tdusk_reentry"]         = "true"/"false"
      CharSettings["tdusk_active_scripts"]  = "stand,script1,script2"
      CharSettings["tdusk_broadcast"]       = "true"/"false"

    Uses bigshot quick for default hunting logic if no custom attack script.
      Hunting Tab  - quickhunt targets: (?:.*)
      Commands Tab - quick hunting commands: fill with your attack sequence

    Custom attack script: CharSettings["tdusk_attack_script"] = "true"
      Create CHARNAME-duskattack.lua with your routine.
      Sample routines: https://github.com/mrhoribu/GS4-Stuff/tree/main/Duskruin

    ;toggletdusk — toggle pause_me on/off while script is running

    Broadcasts run time to DUSKRUIN lnet/0net channel when done.
    ]])
end

if Script.vars and Script.vars[1] and Script.vars[1]:lower() == "help" then
    show_help()
    return
end

--------------------------------------------------------------------------------
-- Validate custom attack script exists if configured
--------------------------------------------------------------------------------

if cfg.attack_script then
    local script_name = GameState.name .. "-duskattack"
    if not Script.exists(script_name) then
        echo("You have attack_script turned on.")
        echo("But no " .. script_name .. ".lua script was found.")
        echo("Please create a " .. script_name .. ".lua script with your routine.")
        echo('Or: CharSettings["tdusk_attack_script"] = "false"')
        echo("Sample routines: https://github.com/mrhoribu/GS4-Stuff/tree/main/Duskruin")
        return
    end
end

--------------------------------------------------------------------------------
-- Attack Logic
--------------------------------------------------------------------------------

local function attack()
    if cfg.attack_script then
        local script_name = GameState.name .. "-duskattack"
        if running(script_name) then
            Script.kill(script_name)
            pause(0.1)
        end
        Script.run(script_name)
        return
    end

    -- Default: use bigshot quick
    local targets = GameObj.targets() or {}
    local alive = {}
    for _, npc in ipairs(targets) do
        if not npc.status or not Regex.test(npc.status, "dead|gone") then
            table.insert(alive, npc)
        end
    end

    if #alive > 0 then
        if running("bigshot") then
            Script.kill("bigshot")
            pause(0.1)
        end
        Script.run("bigshot", "quick")
    end
end

--------------------------------------------------------------------------------
-- Loot Handling
--------------------------------------------------------------------------------

local function loot_package(package_line)
    waitrt()
    if cfg.girdstore then fput("store all") end
    pause(1)

    -- Pick up package if on ground or handed to us
    if package_line and Regex.test(package_line, "at your feet|hands an arena winnings package to you") then
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        while (not rh or rh.noun ~= "package") and (not lh or lh.noun ~= "package") do
            fput("get package")
            pause(1)
            rh = GameObj.right_hand()
            lh = GameObj.left_hand()
        end
    end

    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local has_package = (rh and rh.noun == "package") or (lh and lh.noun == "package")

    if cfg.lootpackage and has_package then
        fput("open my package")
        fput("look in my package")
        if cfg.open_lootsack then
            fput("open my " .. (Vars.lootsack or "backpack"))
        end
        local line = dothistimeout(
            "empty my package into my " .. (Vars.lootsack or "backpack"),
            5,
            [=[everything falls in quite nicely|but nothing comes out|leaving the rest|but nothing will fit]=]
        )
        if line and Regex.test(line, "everything falls in quite nicely|but nothing comes out") then
            -- emptied fine
        else
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("or something bad happened, you should check the package!")
            return false
        end
        pause(1)
        waitrt()

        -- Only drop package if it is truly empty
        rh = GameObj.right_hand()
        lh = GameObj.left_hand()
        local holding_empty = false
        if rh and rh.noun == "package" and (not rh.contents or #rh.contents == 0) then
            holding_empty = true
        elseif lh and lh.noun == "package" and (not lh.contents or #lh.contents == 0) then
            holding_empty = true
        end

        if holding_empty then
            pause(0.5)
            waitrt()
            fput("drop my package")
        else
            respond("package not empty")
            respond("package not empty")
            respond("package not empty")
            pause_script()
        end

    elseif has_package then
        fput("put my package into my " .. (Vars.lootsack or "backpack"))
        pause(1)
        -- Check if still holding (container full)
        rh = GameObj.right_hand()
        lh = GameObj.left_hand()
        if (rh and rh.noun == "package") or (lh and lh.noun == "package") then
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("or something bad happened, you should check the package!")
            return false
        end
    end

    -- Navigate out (solo: go2 23780; grouped: wait then go2 26387 if no longer grouped)
    if group_size == 1 then
        Script.run("go2", "23780")
        wait_while(function() return running("go2") end)
    else
        if not grouped() then
            pause(4)
            Script.run("go2", "26387")
            wait_while(function() return running("go2") end)
        end
    end

    -- Turn off enhancives with retry loop
    if cfg.enhancive_me then
        enhancive_off()
    end

    -- Run waggle script
    if cfg.waggle_me then
        Script.run(cfg.waggle_script)
    end

    -- Pause between runs
    if cfg.pause_me then
        echo("PAUSING SCRIPT")
        echo(";u tdusk TO CONTINUE")
        pause_script()
    end

    -- Wait for max vitals
    if cfg.maxvitals then
        while GameState.health < GameState.max_health or
              GameState.mana < GameState.max_mana or
              GameState.stamina < GameState.max_stamina or
              GameState.spirit < GameState.max_spirit do
            pause(1)
        end
    end

    -- Wait for experience to drain below threshold
    if cfg.experience and type(cfg.experience) == "number" then
        while GameState.percentmind and GameState.percentmind > cfg.experience do
            pause(1)
        end
    end

    -- Re-enter arena (only when not grouped, same as Lich5)
    pause(1)
    if not grouped() then
        pause(2)
        if cfg.reentry then
            while Room.id ~= ARENA_ROOM do
                local result = dothistimeout("go entrance", 3,
                    [=[\[Duskruin Arena, Dueling Sands\]]=])
                if result and Regex.test(result, [=[\[Duskruin Arena, Dueling Sands\]]=]) then
                    break
                end
                if Room.id == ARENA_ROOM then break end
                pause(math.random(30, 60))
            end
        else
            fput("go entrance")
        end
    end

    -- Wait until in arena
    while Room.id ~= ARENA_ROOM do
        pause(1)
    end

    return true
end

--------------------------------------------------------------------------------
-- UpstreamHook: ;toggletdusk  (toggles pause_me without restarting)
--------------------------------------------------------------------------------

local function tdusk_hook(client_string)
    if Regex.test(client_string, [=[^(?:<c>)?;?toggletdusk$]=]) then
        cfg.pause_me = not cfg.pause_me
        save_setting("tdusk_pause_me", cfg.pause_me)
        respond("[tdusk] pause_me = " .. tostring(cfg.pause_me))
        return nil
    end
    return client_string
end

UpstreamHook.add("tdusk_hook", tdusk_hook)

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

Script.at_exit(function()
    UpstreamHook.remove("tdusk_hook")
    for _, script_name in ipairs(active_scripts_list) do
        if running(script_name) then
            Script.kill(script_name)
        end
    end
end)

--------------------------------------------------------------------------------
-- Main Loop
--------------------------------------------------------------------------------

-- Initial entry (only if not grouped, mirrors Lich5)
if cfg.girdstore then fput("store all") end
pause(1)
if not grouped() then
    fput("go entrance")
end

-- Wait until in arena
while Room.id ~= ARENA_ROOM do
    pause(1)
end

while true do
    local line = get()

    -- Arena introduction: prepare for combat
    if RE_INTRO:test(line) then
        if cfg.girdstore then fput("gird") end

        -- Start or unpause active scripts
        for _, script_name in ipairs(active_scripts_list) do
            if Script.exists(script_name) then
                if not running(script_name) then
                    Script.run(script_name)
                elseif Script.is_paused(script_name) then
                    Script.unpause(script_name)
                end
            end
        end

        fam("DR-Starting Arena")

        -- Reset run state
        wave_number = 0
        start_time  = 0
        total_time  = 0
        prev_total  = 0
        avg_reg     = 0
        avg_champ   = 0
        group_size  = 1
        local pcs = GameObj.pcs()
        if pcs then group_size = #pcs + 1 end

        -- Opener spells
        if Regex.test(Stats.prof, "Wizard") and cfg.opener515 then
            waitcastrt()
            if Spell[515]:affordable() and not Spell[599]:active() and not Spell[597]:active() then
                Spell[515]:cast()
            end
        end
        if Regex.test(Stats.prof, "Empath|Cleric") and cfg.opener240 then
            waitcastrt()
            if Spell[240]:affordable() and not Spell[240]:active() then
                Spell[240]:cast()
            end
        end
        if Regex.test(Stats.prof, "Bard") and cfg.bardnode then
            waitcastrt()
            Spell[1018]:cast()
        end
        if Regex.test(Stats.prof, "Wizard|Sorcerer") and cfg.node then
            waitcastrt()
            Spell[418]:cast()
        end
        if Regex.test(Stats.prof, "Wizard") and cfg.opener909 then
            waitcastrt()
            if Spell[909]:affordable() and Spell[909]:timeleft() < 112 then
                fput("incant 909 channel")
            end
        end

        if cfg.enhancive_me then put("inventory enhancive on") end
        if group_size == 1 then put("shout") end

    -- Portcullis raise / wave start: track timing and attack
    elseif RE_PORTC:test(line) then
        -- Set start_time on FIGHT! or the first portcullis event
        if RE_FIGHT:test(line) or start_time == 0 then
            start_time = os.time()
        end

        prev_total = total_time
        total_time = os.time() - start_time
        local kill_delta = total_time - prev_total

        if not CHAMP[wave_number] then
            avg_reg = avg_reg + kill_delta
        else
            avg_champ = avg_champ + kill_delta
        end

        fam(string.format("%dv%d DR-Kills: %d, Total Time %s, Kill Time: %s",
            group_size, group_size, wave_number, fmt_mmss(total_time), fmt_mmss(kill_delta)))

        wave_number = wave_number + 1
        attack()

    -- Alive targets with no active attack logic running
    elseif Room.id == ARENA_ROOM and wave_number > 0 and not cfg.attack_script then
        local targets = GameObj.targets() or {}
        local alive_count = 0
        for _, npc in ipairs(targets) do
            if not npc.status or not Regex.test(npc.status, "dead|gone") then
                alive_count = alive_count + 1
            end
        end
        if alive_count > 0 and not running("bigshot") then
            attack()
        end

    -- Victory
    elseif RE_WIN:test(line) then
        prev_total = total_time
        total_time = os.time() - start_time
        local kill_delta = total_time - prev_total

        -- Kill attack scripts
        local custom_script = GameState.name .. "-duskattack"
        if running(custom_script) then Script.kill(custom_script) end
        if Regex.test(Stats.prof, "Bard") then put("STOP 1018") end

        if not CHAMP[wave_number] then
            avg_reg = avg_reg + kill_delta
        else
            avg_champ = avg_champ + kill_delta
        end

        local avg_r = avg_reg   > 0 and (avg_reg   / 20) or 0
        local avg_c = avg_champ > 0 and (avg_champ / 5)  or 0

        fam(string.format("%dv%d DR-Kills: %d, Total Time %s, Kill Time: %s",
            group_size, group_size, wave_number, fmt_mmss(total_time), fmt_mmss(kill_delta)))
        fam(string.format("DR-Winning Time: %s", fmt_mmss(total_time)))
        fam(string.format("DR-Avg Reg Kill: %s, Avg Champ Kill: %s",
            fmt_mmss(avg_r), fmt_mmss(avg_c)))

        if cfg.broadcast then
            local net = chat_script()
            if net then
                send_to_script(net, string.format(
                    "chat on DUSKRUIN %dv%d Finished: %s, Avg Reg Kill: %s, Avg Champ Kill: %s",
                    group_size, group_size,
                    fmt_mmss(total_time), fmt_mmss(avg_r), fmt_mmss(avg_c)))
            end
        end

    -- Escorted out (looting phase begins)
    elseif RE_ESCORT:test(line) then
        local custom_script = GameState.name .. "-duskattack"
        if running(custom_script) then Script.kill(custom_script) end
        if Regex.test(Stats.prof, "Bard") then put("STOP 1018") end

        for _, script_name in ipairs(active_scripts_list) do
            if running(script_name) and not Script.is_paused(script_name) then
                Script.pause(script_name)
            end
        end

    -- Package / winnings
    elseif string.find(line, "Here are your winnings, " .. GameState.name) then
        wave_number = 0
        start_time  = 0
        total_time  = 0
        prev_total  = 0
        avg_reg     = 0
        avg_champ   = 0

        if not loot_package(line) then
            return
        end

    -- Death
    elseif string.find(line, "drags you out of the arena") or GameState.dead then
        respond("[tdusk] DEAD!")
        if cfg.enhancive_me then
            enhancive_off()
        end
        return
    end
end
