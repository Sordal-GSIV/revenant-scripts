-- huntpro/group.lua — Group management, following, leader coordination
-- @revenant-script
-- @lic-certified: complete 2026-03-18
-- Original: huntpro.lic by Jara — group setup, hold_group, group_kill_scripts,
-- follow mode, whisper coordination, mana sharing (lines ~5306-5615, 11024-11065)

local Group = {}

---------------------------------------------------------------------------
-- Initialize group from settings
---------------------------------------------------------------------------
function Group.setup(hp)
    hp.group_members = {}
    hp.group_ai = "0"

    if not hp.leader or hp.leader == "0" then return end

    hp.captain = hp.leader

    if hp.captain == Char.name then
        hp.group_ai = "1"  -- We are the leader
    else
        hp.group_ai = "2"  -- We are a follower
    end

    -- Build member list
    local member_keys = {
        "group_one", "group_two", "group_three", "group_four", "group_five",
        "group_six", "group_seven", "group_eight", "group_nine"
    }

    for i, key in ipairs(member_keys) do
        local name = hp[key]
        if name and name ~= "0" then
            table.insert(hp.group_members, name)
            hp["group_member" .. i] = name
        end
    end
end

---------------------------------------------------------------------------
-- Hold all group members (leader issues HOLD commands)
---------------------------------------------------------------------------
function Group.hold_group(hp)
    for _, name in ipairs(hp.group_members or {}) do
        fput("hold " .. name)
    end
end

---------------------------------------------------------------------------
-- Wait for all group members to arrive then hold
---------------------------------------------------------------------------
function Group.wait_for_members(hp)
    if hp.group_ai ~= "1" then return end  -- only leader waits

    for _, name in ipairs(hp.group_members or {}) do
        local timeout = 0
        while timeout < 60 do
            local pcs = GameObj.pcs and GameObj.pcs() or {}
            local found = false
            for _, pc in ipairs(pcs) do
                if pc.name == name then
                    found = true
                    break
                end
            end
            if found then break end
            respond("Waiting for " .. name .. "...")
            pause(1)
            timeout = timeout + 1
        end
        fput("hold " .. name)
    end
end

---------------------------------------------------------------------------
-- End group hunting — disband, tell followers to stop
---------------------------------------------------------------------------
function Group.end_hunt(hp)
    if hp.group_ai == "0" then return end

    waitrt()

    if not hp.recent_death then
        Group.wait_for_members(hp)
    else
        pause(3)
        Group.hold_group(hp)
    end

    fput("whisper ooc group End")
end

---------------------------------------------------------------------------
-- Group mana sharing — whisper request for mana
---------------------------------------------------------------------------
function Group.request_mana(hp)
    if hp.group_ai ~= "1" then return end
    if not hp.group_sharemana or hp.group_sharemana == "0" then return end

    local mana_pct = Char.percent_mana or 100
    if mana_pct >= 25 and mana_pct <= 49 then
        if (hp.mana_cooldown or 0) == 0 then
            hp.mana_cooldown = 25
            if not hp.disable_mana then
                fput("whisper group " .. Char.name .. " MANA")
            end
            pause(0.5)
        else
            hp.mana_cooldown = hp.mana_cooldown - 1
        end
    end
end

---------------------------------------------------------------------------
-- Follow mode — follower listens for leader commands
---------------------------------------------------------------------------
function Group.follow_mode(hp)
    if hp.group_ai ~= "2" and not hp.follow_mode then return end

    respond("Huntpro follow mode active. Following " .. (hp.captain or "leader") .. ".")
    respond("Waiting for combat triggers...")

    -- Register a downstream hook for whisper commands from leader
    DownstreamHook.add("huntpro_group_listen", function(line)
        if not line then return line end

        -- Listen for combat end signal
        if line:find("whispers.*End") then
            hp.action = 99
            hp.return_why = "Leader signaled hunt end."
        end

        -- Listen for mana request
        if line:find("whispers.*MANA") then
            local target_match = line:match("whispers.*(%w+)%s+MANA")
            if target_match and (Char.percent_mana or 0) >= 50 then
                -- Share mana via 120 if known
                if Spell[120] and Spell[120].known and Spell[120].affordable then
                    fput("prep 120")
                    fput("cast " .. target_match)
                end
            end
        end

        return line
    end)

    -- Main follow loop — combat when targets appear
    while hp.action ~= 99 do
        local targets = GameObj.targets and GameObj.targets() or {}
        if #targets > 0 then
            local Combat = require("gs.huntpro.combat")
            Combat.scan_targets(hp)
            local result = Combat.execute_round(hp)

            if result == "cast" then
                local SpellMod = require("gs.huntpro.spells")
                local spell = SpellMod.choose_spell(hp)
                SpellMod.cast_at_target(hp, spell)
            end

            -- Don't auto-loot in follow mode (leader loots)
        end
        pause(0.5)
    end

    DownstreamHook.remove("huntpro_group_listen")
end

---------------------------------------------------------------------------
-- Kill companion scripts on exit
---------------------------------------------------------------------------
function Group.kill_scripts(hp)
    local scripts_to_kill = {
        hp.script_one, hp.script_two, hp.script_three,
        "child2", "betazzherb2", "song-manager", "symbolz",
        "isigns", "isigils", "reactive", "spellactive", "signore"
    }

    for _, name in ipairs(scripts_to_kill) do
        if name and name ~= "0" and Script.running(name) then
            Script.kill(name)
        end
    end

    -- Stop Bard songs
    if Spell.active_p(1018) then
        fput("stop 1018")
    end
end

return Group
