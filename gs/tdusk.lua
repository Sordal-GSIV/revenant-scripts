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

local wave_number = 0
local high_ds = false
local start_time = 0
local total_time = 0
local kill_time = 0
local avg_reg = 0
local avg_champ = 0
local group_size = 0
local ARENA_ROOM = 24550

-- Parse active scripts list
local active_scripts_list = {}
if type(cfg.active_scripts) == "string" then
    for s in string.gmatch(cfg.active_scripts, "[^,]+") do
        table.insert(active_scripts_list, s:match("^%s*(.-)%s*$"))
    end
else
    active_scripts_list = { "stand" }
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
      CharSettings["tdusk_waggle_me"] = "true"/"false"
      CharSettings["tdusk_waggle_script"] = "ewaggle"
      CharSettings["tdusk_pause_me"] = "true"/"false"
      CharSettings["tdusk_enhancive_me"] = "true"/"false"
      CharSettings["tdusk_bardnode"] = "true"/"false"
      CharSettings["tdusk_node"] = "true"/"false"
      CharSettings["tdusk_opener515"] = "true"/"false"
      CharSettings["tdusk_opener909"] = "true"/"false"
      CharSettings["tdusk_opener240"] = "true"/"false"
      CharSettings["tdusk_attack_script"] = "true"/"false"
      CharSettings["tdusk_girdstore"] = "true"/"false"
      CharSettings["tdusk_lootpackage"] = "true"/"false"
      CharSettings["tdusk_open_lootsack"] = "true"/"false"
      CharSettings["tdusk_maxvitals"] = "true"/"false"
      CharSettings["tdusk_experience"] = number or "false"
      CharSettings["tdusk_reentry"] = "true"/"false"
      CharSettings["tdusk_active_scripts"] = "stand,script1,script2"

    Uses bigshot quick for default hunting logic if no custom attack script.
    ]])
end

if Script.args and Script.args[1] and Script.args[1]:lower() == "help" then
    show_help()
    return
end

--------------------------------------------------------------------------------
-- Attack Logic
--------------------------------------------------------------------------------

local function is_champion_wave()
    return wave_number == 5 or wave_number == 10 or wave_number == 15 or
           wave_number == 20 or wave_number == 25
end

local function attack()
    if cfg.attack_script then
        -- Use custom character-specific attack script
        local script_name = GameState.char_name .. "-duskattack"
        if running(script_name) then
            kill_script(script_name)
            pause(0.1)
        end
        run_script_background(script_name)
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
            kill_script("bigshot")
            pause(0.1)
        end
        run_script_background("bigshot", { "quick" })
    end
end

--------------------------------------------------------------------------------
-- Loot Handling
--------------------------------------------------------------------------------

local function loot_package(package_line)
    waitrt()
    if cfg.girdstore then fput("store all") end
    pause(1)

    -- Pick up package if on ground
    if package_line and string.find(package_line, "at your feet") then
        local attempts = 0
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        while not rh or rh.noun ~= "package" do
            if lh and lh.noun == "package" then break end
            fput("get package")
            pause(1)
            attempts = attempts + 1
            if attempts > 5 then break end
            rh = GameObj.right_hand()
            lh = GameObj.left_hand()
        end
    end

    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    local has_package = (rh and rh.noun == "package") or
                        (lh and lh.noun == "package")

    if cfg.lootpackage and has_package then
        fput("open my package")
        fput("look in my package")
        if cfg.open_lootsack then
            fput("open my " .. (CharSettings["lootsack"] or "backpack"))
        end
        local line = fput("empty my package into my " .. (CharSettings["lootsack"] or "backpack"))
        if line and (string.find(line, "everything falls in quite nicely") or string.find(line, "but nothing comes out")) then
            -- Emptied fine
        else
            echo("CONTAINER FULL, TIME TO EMPTY!")
            echo("or something bad happened, you should check the package!")
            return false
        end
        pause(1)
        waitrt()
        fput("drop my package")
    elseif has_package then
        fput("put my package into my " .. (CharSettings["lootsack"] or "backpack"))
        pause(1)
    end

    -- Navigate out
    if group_size == 1 then
        run_script("go2", { "23780" })
    else
        pause(4)
        run_script("go2", { "26387" })
    end

    -- Turn off enhancives
    if cfg.enhancive_me then
        local attempts = 0
        while attempts < 5 do
            local result = fput("inventory enhancive off")
            if result and (string.find(result, "no longer accepting") or
                          string.find(result, "nothing seems to happen") or
                          string.find(result, "already are not accepting")) then
                break
            end
            pause(5)
            attempts = attempts + 1
        end
    end

    -- Run waggle script
    if cfg.waggle_me then
        run_script(cfg.waggle_script)
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

    -- Wait for experience to drain
    if cfg.experience and type(cfg.experience) == "number" then
        while GameState.percentmind and GameState.percentmind > cfg.experience do
            pause(1)
        end
    end

    -- Re-enter arena
    pause(1)
    if cfg.reentry then
        local in_arena = false
        while not in_arena do
            local line = fput("go entrance")
            if line and string.find(line, "Duskruin Arena, Dueling Sands") then
                in_arena = true
            else
                pause(math.random(30, 60))
            end
            if Room.id == ARENA_ROOM then
                in_arena = true
            end
        end
    else
        fput("go entrance")
    end

    -- Wait until in arena
    while Room.id ~= ARENA_ROOM do
        pause(1)
    end

    return true
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

on_exit(function()
    for _, script_name in ipairs(active_scripts_list) do
        if running(script_name) then
            kill_script(script_name)
        end
    end
end)

--------------------------------------------------------------------------------
-- Main Loop
--------------------------------------------------------------------------------

-- Initial entry
if cfg.girdstore then fput("store all") end
pause(1)
fput("go entrance")

-- Wait until in arena
while Room.id ~= ARENA_ROOM do
    pause(1)
end

while true do
    local line = get()

    -- Arena introduction - prepare for combat
    if Regex.test(line, "^An announcer shouts, \"Introducing ") then
        if cfg.girdstore then fput("gird") end

        -- Start active scripts
        for _, script_name in ipairs(active_scripts_list) do
            if not running(script_name) then
                run_script_background(script_name)
            end
        end

        wave_number = 0
        group_size = 1
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

        if cfg.enhancive_me then
            put("inventory enhancive on")
        end
        if group_size == 1 then put("shout") end

    -- Wave fight
    elseif Regex.test(line, "^An announcer shouts, \"FIGHT!\"") or
           (Regex.test(line, "^An announcer shouts") and
            string.find(line, "enter the arena") or string.find(line, "enters the arena")) then

        if start_time == 0 then start_time = os.time() end

        kill_time = total_time
        total_time = os.time() - start_time
        kill_time = total_time - (kill_time or 0)

        if not is_champion_wave() then avg_reg = avg_reg + kill_time end
        if is_champion_wave() then avg_champ = avg_champ + kill_time end

        wave_number = wave_number + 1

        respond(string.format("[tdusk] %dv%d Wave: %d, Total: %ds, Kill: %ds",
            group_size, group_size, wave_number, total_time, kill_time))

        attack()

    -- Also attack if targets are alive and we have no attack script running
    elseif Room.id == ARENA_ROOM and wave_number > 0 then
        local targets = GameObj.targets() or {}
        local alive_count = 0
        for _, npc in ipairs(targets) do
            if not npc.status or not Regex.test(npc.status, "dead|gone") then
                alive_count = alive_count + 1
            end
        end
        if alive_count > 0 and not cfg.attack_script and not running("bigshot") then
            attack()
        end

    -- Victory
    elseif Regex.test(line, "^An announcer boasts.*defeating all those that opposed") then
        kill_time = total_time
        total_time = os.time() - start_time
        kill_time = total_time - (kill_time or 0)

        -- Kill custom attack script
        local custom_script = GameState.char_name .. "-duskattack"
        if running(custom_script) then kill_script(custom_script) end
        if Regex.test(Stats.prof, "Bard") then put("STOP 1018") end

        if not is_champion_wave() then avg_reg = avg_reg + kill_time end
        if is_champion_wave() then avg_champ = avg_champ + kill_time end

        local avg_r = avg_reg > 0 and avg_reg / 20 or 0
        local avg_c = avg_champ > 0 and avg_champ / 5 or 0

        respond(string.format("[tdusk] %dv%d VICTORY! Total: %ds, Avg Reg: %.1fs, Avg Champ: %.1fs",
            group_size, group_size, total_time, avg_r, avg_c))

    -- Escorted out (looting)
    elseif Regex.test(line, "^An arena guard escorts you from the dueling sands") then
        local custom_script = GameState.char_name .. "-duskattack"
        if running(custom_script) then kill_script(custom_script) end
        if Regex.test(Stats.prof, "Bard") then put("STOP 1018") end

        for _, script_name in ipairs(active_scripts_list) do
            if running(script_name) then
                pause_script(script_name)
            end
        end

    -- Package / winnings
    elseif string.find(line, "Here are your winnings") then
        start_time = 0
        total_time = 0
        kill_time = 0
        avg_reg = 0
        avg_champ = 0
        wave_number = 0

        if not loot_package(line) then
            return
        end

    -- Death
    elseif string.find(line, "drags you out of the arena") or GameState.dead then
        respond("[tdusk] DEAD!")
        if cfg.enhancive_me then
            fput("inventory enhancive off")
        end
        return
    end
end
