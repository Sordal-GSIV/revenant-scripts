--- @revenant-script
--- name: safety
--- version: 2.0.0
--- author: Alastir
--- game: gs
--- description: Room safety assessment and profession-specific creature disabling.
---   Provides the Safety module with unsafe(), stance_offensive(), depress(),
---   disruption(), hold(), rage(), unravel(), grasp(), warcry(), multi_stomp(),
---   and stomp(). Runs a profession-dispatch loop targeting priority creatures.
--- tags: combat, safety, utility
--- @lic-certified: complete 2026-03-19
---
--- Converted from lib/safety.lic by Alastir (11/23/25).
--- Original: Lich5 GemStone IV room-safety / creature-disabling module.

-- Per-call room-disable tracker (reset at the start of each non-disabled invocation,
-- then the current room is added on completion — prevents double-casting in one room).
local disabled_rooms = {}

-- ---------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------

local function status_has(npc, ...)
    local s = npc.status or ""
    for _, pat in ipairs({...}) do
        if string.find(s, pat, 1, true) then return true end
    end
    return false
end

local function is_dead_or_gone(npc)
    return status_has(npc, "dead", "gone")
end

local function is_incapacitated(npc)
    return status_has(npc, "dead", "gone", "prone", "lying down", "sleeping")
end

local function npc_matches(npc, patterns)
    for _, pat in ipairs(patterns) do
        if string.find(npc.name, pat) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Safety module
-- ---------------------------------------------------------------------------

local Safety = {}

--- unsafe() — returns true if the room has 3+ live targets.
function Safety.unsafe()
    local targets = GameObj.targets()
    local count = #targets
    local room_id = Room.id or "?"
    if count >= 3 then
        echo("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Danger!")
        return true
    else
        echo("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Threat level acceptable.")
        return false
    end
end

--- stance_offensive() — loops until stance is confirmed offensive.
function Safety.stance_offensive()
    while GameState.stance ~= "offensive" do
        waitrt()
        fput("stance offensive")
        pause(0.3)
    end
end

-- ---------------------------------------------------------------------------
-- Bard routines
-- ---------------------------------------------------------------------------

--- depress() — Renew or cast Song of Depression (1015), reducing TD by 20.
--- Skips if the current room was already processed this invocation.
function Safety.depress()
    local room_id = Room.id
    if disabled_rooms[room_id] then return end
    disabled_rooms = {}

    waitrt()
    waitcastrt()

    local result = dothistimeout("renew 1015", 3,
        'Renewing "Song of Depression" for 6 mana.',
        "But you are not singing that spellsong.")

    if result and string.find(result, 'Renewing "Song of Depression"') then
        disabled_rooms[room_id] = true
    elseif result and string.find(result, "But you are not singing that spellsong.") then
        if Spell[1015]:affordable() then
            Spell[1015]:incant()
        end
        disabled_rooms[room_id] = true
    end

    waitrt()
    waitcastrt()
end

--- disruption() — Song of Disruption (1030), open-cast sonic attack.
--- Retries on shield absorption or armor interference.
--- Kills 'safety' script if mana runs out.
function Safety.disruption()
    waitrt()
    waitcastrt()

    if not Spell[1030]:affordable() then
        Script.kill("safety")
        return
    end

    for _ = 1, 5 do
        local result = dothistimeout("incant 1030 open", 3,
            "reels under the force of the sonic vibrations!",
            "evanescent shield shrouding",
            "Your armor prevents the song from working correctly.",
            "Your magic fails to find a target.")

        if not result then break end

        if string.find(result, "reels under the force") then
            break  -- success
        elseif string.find(result, "Your magic fails to find a target") then
            break  -- no valid target
        elseif string.find(result, "evanescent shield") or
               string.find(result, "armor prevents") then
            waitrt()
            waitcastrt()
            if not Spell[1030]:affordable() then break end
            -- continue loop → retry
        else
            break
        end
    end
end

--- hold() — Song of Holding (1001), reduces DS by 10%.
function Safety.hold()
    waitrt()
    waitcastrt()
    if Spell[1001]:affordable() then
        Spell[1001]:incant()
        fput("stop 1001")
    end
end

--- rage() — Song of Rage (1016), forces offensive stance; high endrolls can prone.
function Safety.rage()
    waitrt()
    waitcastrt()
    if Spell[1016]:affordable() then
        Spell[1016]:incant()
        waitcastrt()
        fput("stop 1016")
    end
end

--- unravel(target, extra_cmd) — Song of Unraveling (1013), single-target mana drain.
--- target: LuaGameObj to drain.
--- extra_cmd: optional string appended to cast command (or nil).
function Safety.unravel(target, extra_cmd)
    waitrt()
    waitcastrt()

    fput("prep 1013")

    -- Wait for spell preparation confirmation
    for _ = 1, 50 do
        local line = get()
        if string.find(line, "Your spell") or
           string.find(line, "You already have a spell readied") or
           string.find(line, "You can't think clearly") or
           string.find(line, "But you don't have any mana") or
           string.find(line, "you are not singing") then
            break
        end
    end

    local cast_cmd = "cast #" .. target.id
    if extra_cmd and extra_cmd ~= "" then
        cast_cmd = cast_cmd .. " " .. extra_cmd
    end

    local result = dothistimeout(cast_cmd, 3,
        "You are already singing that spellsong.",
        "evanescent shield shrouding",
        "You feel your song resonate around",
        "The silvery tendril continues",
        "You gain %d+ mana!",
        "You feel your song echo around",
        "The serpentine thread stretching between",
        "Your concentration on unravelling",
        "A little bit late for that",
        "What were you referring to%?")

    if not result then return end

    if string.find(result, "You are already singing") then
        fput("stop 1013")
    elseif string.find(result, "You feel your song resonate") or
           string.find(result, "You gain") then
        waitrt()
        waitcastrt()
        fput("stop 1013")
    elseif string.find(result, "The silvery tendril") then
        fput("stop 1013")
    elseif string.find(result, "Your concentration on unravelling") or
           string.find(result, "You feel your song echo around") then
        fput("stop 1013")
    elseif string.find(result, "What were you referring to") or
           string.find(result, "A little bit late") then
        fput("release")
    end
end

-- ---------------------------------------------------------------------------
-- Sorcerer routines
-- ---------------------------------------------------------------------------

--- grasp() — Grasp of the Grave (709), AoE immobilize via spectral limbs.
--- Skips if the current room was already processed this invocation.
function Safety.grasp()
    local room_id = Room.id
    if disabled_rooms[room_id] then return end
    disabled_rooms = {}

    waitrt()
    waitcastrt()

    local result = dothistimeout("incant 709", 3,
        "Numerous grotesque limbs in varying states of decay",
        "evanescent shield",
        "%.%.%.wait %d+ seconds%.")

    if result then
        disabled_rooms[room_id] = true
    end
end

-- ---------------------------------------------------------------------------
-- Warrior routines
-- ---------------------------------------------------------------------------

--- warcry(target) — Griffin's Voice + Warcry at one or all targets.
--- target: LuaGameObj (used for single-target cry) or nil.
function Safety.warcry(target)
    if not Effects.Spells.active("Griffin's Voice") and GameState.stamina >= 30 then
        fput("cman griffin")
    end

    waitrt()
    waitcastrt()

    local targets = GameObj.targets()
    if #targets > 2 then
        pause(0.5)
        if GameState.stamina >= 30 then
            fput("warcry cry all")
        end
    elseif #targets == 1 then
        if not target then return end
        for _ = 1, 5 do
            local result = dothistimeout("warcry cry #" .. target.id, 3,
                "SSR result: %d+",
                "is unaffected!")
            if not result then break end
            local total_str = string.match(result, "SSR result: (%d+)")
            if total_str then
                if tonumber(total_str) >= 100 then break end
                -- target not sufficiently affected — retry
                waitrt()
                waitcastrt()
            elseif string.find(result, "is unaffected!") then
                waitrt()
                waitcastrt()
            else
                break
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wizard routines
-- ---------------------------------------------------------------------------

--- multi_stomp() — Tremors (909) stomping in multi-creature rooms.
--- Redirects to stomp() when a shield absorbs the AoE.
function Safety.multi_stomp()
    waitrt()
    waitcastrt()

    if Spell[909].active then
        local result = dothistimeout("stomp", 2,
            "evanescent shield",
            "loses .* balance and falls over%.",
            "Your magic fails to find a target%.")
        if result and string.find(result, "evanescent shield") then
            Safety.stomp()
        end
        -- success or no-target: done
    else
        if Spell[909]:affordable() then
            Spell[909]:incant()
        end
        Safety.stomp()
    end
end

--- stomp() — Tremors (909) single-target stomp; retries through shield absorption.
--- Skips if the current room was already processed this invocation.
function Safety.stomp()
    local room_id = Room.id
    if disabled_rooms[room_id] then return end
    disabled_rooms = {}

    waitrt()
    waitcastrt()

    -- Ensure Tremors (909) is active before stomping
    if not Spell[909].active then
        if Spell[909]:affordable() then
            Spell[909]:incant()
        end
        waitcastrt()
    end

    if not Spell[909].active then return end

    -- Attempt stomp, retrying up to 3 times on shield absorption
    for _ = 1, 3 do
        local result = dothistimeout("stomp", 2,
            "evanescent shield",
            "loses .* balance and falls over%.",
            "Your magic fails to find a target%.")
        if not result then break end
        if string.find(result, "evanescent shield") then
            waitrt()
            waitcastrt()
            -- continue loop → retry
        else
            disabled_rooms[room_id] = true
            break
        end
    end
end

-- ---------------------------------------------------------------------------
-- Initial safety assessment
-- ---------------------------------------------------------------------------

Safety.unsafe()

-- ---------------------------------------------------------------------------
-- Profession-specific creature-disabling main loop
-- ---------------------------------------------------------------------------

local function find_live_targets(name_pattern)
    local results = {}
    for _, npc in ipairs(GameObj.targets()) do
        if string.find(npc.name, name_pattern) and not is_dead_or_gone(npc) then
            results[#results + 1] = npc
        end
    end
    return results
end

-- Bard: hamstring/feint/unravel priority targets
if Char.prof == "Bard" and Group.leader == Char.name then
    local priority = {
        "disciple", "disir", "draugr", "valravn", "angargeist",
        "mutant", "warg", "skald", "shield%-maiden", "golem"
    }

    for _, pattern in ipairs(priority) do
        for _, npc in ipairs(find_live_targets(pattern)) do
            echo("Room:" .. (Room.id or "?") .. " - (" .. npc.name .. ") - (" .. npc.id .. ")")
            fput("target #" .. npc.id)
            echo("Room:" .. (Room.id or "?") .. " - Disabling: (" .. npc.name .. ") - (" .. npc.id .. ").")

            if string.find(npc.name, "disciple") and not is_incapacitated(npc) then
                waitrt()
                waitcastrt()
                Safety.stance_offensive()
                if not is_incapacitated(npc) then
                    CMan.use("hamstring", "#" .. npc.id)
                end
            elseif (string.find(npc.name, "disir") or string.find(npc.name, "draugr")) then
                waitrt()
                waitcastrt()
                Safety.stance_offensive()
                if not is_incapacitated(npc) then
                    CMan.use("hamstring", "#" .. npc.id)
                end
            elseif string.find(npc.name, "valravn") then
                waitrt()
                waitcastrt()
                Safety.stance_offensive()
                if not is_dead_or_gone(npc) then
                    CMan.use("feint", "#" .. npc.id)
                end
            elseif string.find(npc.name, "mutant") then
                waitrt()
                waitcastrt()
                if not is_dead_or_gone(npc) then
                    Safety.unravel(npc, "1214")
                end
            elseif (string.find(npc.name, "golem") or string.find(npc.name, "shield%-maiden") or
                    string.find(npc.name, "skald") or string.find(npc.name, "warg")) and
                   not is_incapacitated(npc) then
                waitrt()
                waitcastrt()
                Safety.stance_offensive()
                if not is_incapacitated(npc) then
                    CMan.use("hamstring", "#" .. npc.id)
                end
            end
        end
    end
end

-- Cleric: spells 240/217/317/316/118/119/210 per creature type
if Char.prof == "Cleric" then
    local priority = {
        "disciple", "disir", "draugr", "valravn", "angargeist",
        "mutant", "warg", "skald", "shield%-maiden", "golem",
        "shaper", "lurk", "sentinel", "fanatic"
    }

    for _, pattern in ipairs(priority) do
        for _, npc in ipairs(find_live_targets(pattern)) do
            echo("Room:" .. (Room.id or "?") .. " - (" .. npc.name .. ") - (" .. npc.id .. ")")
            fput("target #" .. npc.id)
            echo("Room:" .. (Room.id or "?") .. " - Disabling: (" .. npc.name .. ") - (" .. npc.id .. ").")

            waitrt()
            waitcastrt()

            if string.find(npc.name, "disciple") and not is_dead_or_gone(npc) then
                if not Spell[240].active and Spell[240]:affordable() then
                    Spell[240]:incant()
                end
                if Spell[217]:affordable() then Spell[217]:incant() end
                waitcastrt()
                if Spell[317]:affordable() then Spell[317]:incant() end
                waitcastrt()
            elseif (string.find(npc.name, "disir") or string.find(npc.name, "draugr")) and
                   not status_has(npc, "dead", "gone", "stunned") then
                if Spell[316]:affordable() then Spell[316]:incant() end
            elseif (string.find(npc.name, "angargeist") or string.find(npc.name, "valravn")) and
                   not is_dead_or_gone(npc) then
                if Spell[118]:affordable() then Spell[118]:incant() end
            elseif string.find(npc.name, "mutant") and not is_dead_or_gone(npc) then
                if Spell[119]:affordable() then Spell[119]:incant() end
            elseif (string.find(npc.name, "golem") or string.find(npc.name, "shield%-maiden") or
                    string.find(npc.name, "skald") or string.find(npc.name, "warg")) and
                   not status_has(npc, "dead", "gone", "stunned") then
                if Spell[316]:affordable() then Spell[316]:incant() end
            elseif string.find(npc.name, "shaper") and not is_dead_or_gone(npc) then
                if Spell[210]:affordable() then Spell[210]:incant() end
                waitcastrt()
            end
        end
    end
end

-- Sorcerer: spells 119/703/709/118/704 per creature type
if Char.prof == "Sorcerer" then
    local priority = {
        "disciple", "disir", "draugr", "valravn", "angargeist",
        "mutant", "warg", "skald", "shield%-maiden", "golem",
        "shaper", "lurk", "sentinel", "fanatic"
    }

    for _, pattern in ipairs(priority) do
        for _, npc in ipairs(find_live_targets(pattern)) do
            echo("Room:" .. (Room.id or "?") .. " - (" .. npc.name .. ") - (" .. npc.id .. ")")
            fput("target #" .. npc.id)
            echo("Room:" .. (Room.id or "?") .. " - Disabling: (" .. npc.name .. ") - (" .. npc.id .. ").")

            waitrt()
            waitcastrt()

            if string.find(npc.name, "disciple") and not is_dead_or_gone(npc) then
                if Spell[119]:affordable() then Spell[119]:incant() end
                waitcastrt()
                if Spell[703]:affordable() then Spell[703]:incant() end
            elseif (string.find(npc.name, "disir") or string.find(npc.name, "draugr")) and
                   not status_has(npc, "dead", "gone", "lying down", "prone", "stunned") then
                if Spell[709]:affordable() then Safety.grasp() end
            elseif string.find(npc.name, "valravn") and not is_dead_or_gone(npc) then
                if Spell[118]:affordable() then Spell[118]:incant() end
            elseif string.find(npc.name, "angargeist") and not is_dead_or_gone(npc) then
                if Spell[704]:affordable() then Spell[704]:cast("#" .. npc.id, {force = true}) end
            elseif string.find(npc.name, "mutant") and not is_dead_or_gone(npc) then
                if Spell[119]:affordable() then Spell[119]:incant() end
            elseif string.find(npc.name, "shaper") and not is_dead_or_gone(npc) then
                if Spell[703]:affordable() then Spell[703]:incant() end
            end
            -- golem/shield-maiden/skald/warg/berserker/hinterboar/wendigo: no sorcerer action (commented out in original)
        end
    end
end

-- Warrior: warcry + hamstring/feint per creature type
if Char.prof == "Warrior" then
    local priority = {
        "disciple", "disir", "draugr", "valravn", "angargeist",
        "mutant", "warg", "skald", "shield%-maiden", "golem",
        "shaper", "lurk", "sentinel", "fanatic"
    }

    for _, pattern in ipairs(priority) do
        for _, npc in ipairs(find_live_targets(pattern)) do
            echo("Room:" .. (Room.id or "?") .. " - (" .. npc.name .. ") - (" .. npc.id .. ")")
            fput("target #" .. npc.id)
            echo("Room:" .. (Room.id or "?") .. " - Disabling: (" .. npc.name .. ") - (" .. npc.id .. ").")

            if (string.find(npc.name, "disciple") or string.find(npc.name, "disir") or
                string.find(npc.name, "draugr") or string.find(npc.name, "mutant") or
                string.find(npc.name, "shaper") or string.find(npc.name, "sentinel") or
                string.find(npc.name, "lurk")) and
               not status_has(npc, "dead", "gone", "prone", "lying down") then
                waitrt()
                waitcastrt()
                Safety.warcry(npc)
                waitrt()
                Safety.stance_offensive()
                if not is_incapacitated(npc) then
                    CMan.use("hamstring", "#" .. npc.id)
                end
            elseif string.find(npc.name, "valravn") then
                waitrt()
                waitcastrt()
                Safety.warcry(npc)
                waitrt()
                Safety.stance_offensive()
                CMan.use("feint", "#" .. npc.id)
            elseif (string.find(npc.name, "fanatic") or string.find(npc.name, "golem") or
                    string.find(npc.name, "shield%-maiden") or string.find(npc.name, "skald") or
                    string.find(npc.name, "warg")) and
                   not status_has(npc, "dead", "gone", "prone", "lying down") then
                waitrt()
                waitcastrt()
                Safety.stance_offensive()
                if not is_incapacitated(npc) then
                    CMan.use("hamstring", "#" .. npc.id)
                end
            end
        end
    end
end

-- Wizard: dispel/Call Wind/stomp per creature type
if Char.prof == "Wizard" then
    local priority = {
        "disciple", "disir", "draugr", "valravn", "angargeist",
        "mutant", "berserker", "cannibal", "hinterboar", "shield%-maiden",
        "skald", "warg", "wendigo", "shaper", "lurk", "sentinel", "fanatic"
    }

    for _, pattern in ipairs(priority) do
        for _, npc in ipairs(find_live_targets(pattern)) do
            echo("Room:" .. (Room.id or "?") .. " - (" .. npc.name .. ") - (" .. npc.id .. ")")
            fput("target #" .. npc.id)
            echo("Room:" .. (Room.id or "?") .. " - Disabling: (" .. npc.name .. ") - (" .. npc.id .. ").")

            if (string.find(npc.name, "disciple") or string.find(npc.name, "mutant")) and
               not is_dead_or_gone(npc) then
                -- Dispel the Arcane Barrier (1720 via spell 417)
                if Spell[417]:affordable() then Spell[417]:incant() end
            elseif (string.find(npc.name, "disir") or string.find(npc.name, "draugr") or
                    string.find(npc.name, "valravn") or string.find(npc.name, "angargeist")) and
                   not status_has(npc, "dead", "gone", "prone", "lying down", "stunned", "webbed") then
                -- Call Wind (912)
                if Spell[912]:affordable() then Spell[912]:incant() end
            elseif (string.find(npc.name, "berserker") or string.find(npc.name, "cannibal") or
                    string.find(npc.name, "golem") or string.find(npc.name, "hinterboar") or
                    string.find(npc.name, "shield%-maiden") or string.find(npc.name, "skald") or
                    string.find(npc.name, "warg") or string.find(npc.name, "wendigo")) and
                   not status_has(npc, "dead", "gone", "prone", "lying down", "stunned", "webbed") then
                Safety.multi_stomp()
            elseif (string.find(npc.name, "shaper") or string.find(npc.name, "sentinel") or
                    string.find(npc.name, "lurk") or string.find(npc.name, "fanatic")) and
                   not status_has(npc, "dead", "gone", "prone", "lying down", "stunned", "webbed") then
                if Group.leader == Char.name then
                    if Spell[912]:affordable() then Spell[912]:incant() end
                else
                    Safety.stomp()
                end
            end
        end
    end
end

return Safety
