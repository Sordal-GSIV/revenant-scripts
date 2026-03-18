--- @revenant-script
--- name: safety
--- version: 1.0
--- author: Alastir
--- game: dr
--- description: Help disable creatures based upon Profession and chances of success
--- tags: combat, disable, safety, creatures
---
--- Converted from safety.lic (Lich5) to Revenant Lua
---
--- Checks room danger level and executes profession-specific disabling
--- routines against priority targets (GS4 / Lich5 combat system).
---
--- Usage: ;safety

if not Safety then Safety = {} end

-- Global disabled rooms tracker
if not _G.disabled_rooms then _G.disabled_rooms = {} end

--- Determine how dangerous the room creature setup is
function Safety.unsafe()
    local targets = GameObj.targets() or {}
    local count = #targets
    local danger = 0

    if count >= 3 then
        danger = count
    end

    local room_id = Room.id or 0
    if danger > 0 then
        if Lich and Lich.Messaging then
            Lich.Messaging.stream_window("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Danger!", "speech")
        else
            echo("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Danger!")
        end
        return true
    else
        if Lich and Lich.Messaging then
            Lich.Messaging.stream_window("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Threat level acceptable.", "speech")
        else
            echo("Room: " .. room_id .. " -- Creatures: " .. count .. " -- Threat level acceptable.")
        end
        return false
    end
end

--- Switch to offensive stance
function Safety.stance_offensive()
    while not checkstance("offensive") do
        waitrt()
        fput("stance offensive")
        pause(0.3)
    end
end

--- Song of Depression (Bard 1015) - open cast warding, reduces TD by 20
function Safety.depress()
    local room_id = Room.id or 0
    for _, r in ipairs(_G.disabled_rooms) do
        if r == room_id then return end
    end
    _G.disabled_rooms = {}
    waitrt()
    waitcastrt()
    local result = dothistimeout("renew 1015", 3,
        'Renewing "Song of Depression" for 6 mana.|But you are not singing that spellsong.')
    if result and result:find('Renewing "Song of Depression"') then
        table.insert(_G.disabled_rooms, room_id)
    elseif result and result:find("But you are not singing that spellsong") then
        if Spell and Spell[1015] and Spell[1015].affordable() then
            Spell[1015].force_incant()
        end
        table.insert(_G.disabled_rooms, room_id)
    end
    waitrt()
    waitcastrt()
end

--- Sonic Disruption (Bard 1030) - targeted sonic attack
function Safety.disruption()
    waitrt()
    waitcastrt()
    if Spell and Spell[1030] and Spell[1030].affordable() then
        local result = dothistimeout("incant 1030 open", 3,
            "reels under the force|evanescent shield|armor prevents|magic fails to find")
        if result then
            if result:find("evanescent shield") or result:find("armor prevents") then
                Safety.disruption()
            end
            -- If target reels or no target found, we're done
        end
    else
        kill_script("safety")
    end
end

--- Song of Holding (Bard 1001) - reduces DS by 10%
function Safety.hold()
    waitrt()
    waitcastrt()
    if Spell and Spell[1001] and Spell[1001].affordable() then
        Spell[1001].force_incant()
    end
    fput("stop 1001")
end

--- Song of Rage (Bard 1016) - forces offensive stance, can prone
function Safety.rage()
    waitrt()
    waitcastrt()
    if Spell and Spell[1016] and Spell[1016].affordable() then
        Spell[1016].force_incant()
    end
    waitcastrt()
    fput("stop 1016")
end

--- Song of Unraveling (Bard 1013) - targeted dispel / mana drain
function Safety.unravel(current_creature, cmd)
    local target = nil
    local npcs = GameObj.npcs()
    if npcs then
        for _, npc in ipairs(npcs) do
            if npc.name and npc.name:find(tostring(current_creature)) then
                target = npc
                break
            end
        end
    end
    if not target then return end

    waitrt()
    waitcastrt()
    local cast_target = "#" .. target.id
    local cast_cmd = cmd or ""
    local result = dothistimeout("cast 1013 " .. cast_target .. " " .. cast_cmd, 5,
        "already singing|evanescent shield|pulling at the threads|silvery tendril|You gain.*mana|vast empty chamber|thread.*fades|concentration.*broken|little bit late|What were you referring")

    if result then
        if result:find("already singing") then
            fput("stop 1013")
        elseif result:find("pulling at the threads") or result:find("You gain") then
            waitrt()
            waitcastrt()
            fput("stop 1013")
        elseif result:find("silvery tendril") then
            fput("stop 1013")
        elseif result:find("concentration.*broken") or result:find("vast empty chamber") then
            fput("stop 1013")
        elseif result:find("What were you referring") or result:find("little bit late") then
            fput("release")
        end
    end
end

--- Grasp of the Grave (Sorcerer 709)
function Safety.grasp()
    local room_id = Room.id or 0
    for _, r in ipairs(_G.disabled_rooms) do
        if r == room_id then return end
    end
    _G.disabled_rooms = {}

    waitrt()
    waitcastrt()
    local result = dothistimeout("incant 709", 3,
        "grotesque limbs|evanescent shield|wait %d+ seconds")
    if result then
        table.insert(_G.disabled_rooms, room_id)
    end
end

--- Warcry (Warrior)
function Safety.warcry(target)
    if not target then return end

    if Effects and Effects.Spells and not Effects.Spells.active("Griffin's Voice") then
        if checkstamina and checkstamina(30) then
            fput("cman griffin")
        end
    end

    waitrt()
    waitcastrt()

    local targets = GameObj.targets() or {}
    if #targets > 2 then
        pause(0.5)
        if checkstamina and checkstamina(30) then
            fput("warcry cry all")
        end
    elseif #targets == 1 then
        local result = dothistimeout("warcry cry " .. tostring(target), 3, "SSR result: (%d+)|is unaffected!")
        if result then
            local total_str = result:match("SSR result: (%d+)")
            if total_str then
                local total = tonumber(total_str)
                if total < 100 then
                    Safety.warcry(target)
                end
            elseif result:find("is unaffected!") then
                Safety.warcry(target)
            end
        end
    end
end

--- Earthquake Stomp (Wizard 909) - multiple targets
function Safety.multi_stomp()
    waitrt()
    waitcastrt()
    if Spell and Spell[909] and Spell[909].active and Spell[909].active() then
        local result = dothistimeout("stomp", 2, "evanescent shield|loses.*balance and falls over|magic fails to find")
        if result and result:find("evanescent shield") then
            Safety.stomp()
        end
    else
        if Spell and Spell[909] and Spell[909].affordable() then
            Spell[909].force_incant()
        end
        Safety.stomp()
    end
end

--- Single-target Stomp (Wizard 909)
function Safety.stomp()
    local room_id = Room.id or 0
    for _, r in ipairs(_G.disabled_rooms) do
        if r == room_id then return end
    end
    _G.disabled_rooms = {}

    waitrt()
    waitcastrt()
    if Spell and Spell[909] and Spell[909].active and Spell[909].active() then
        local result = dothistimeout("stomp", 2, "evanescent shield|loses.*balance and falls over|magic fails to find")
        if result and result:find("evanescent shield") then
            Safety.stomp()
        elseif result then
            table.insert(_G.disabled_rooms, room_id)
        end
    else
        if Spell and Spell[909] and Spell[909].affordable() then
            Spell[909].force_incant()
        end
        Safety.stomp()
    end
end

-- Helper: find matching targets from priority list
local function find_matching_targets(priority_targets, baddies_list)
    local targets = GameObj.targets() or {}
    local results = {}
    for _, name in ipairs(priority_targets) do
        for _, npc in ipairs(targets) do
            if npc.name and npc.name:find(name) and (not npc.status or not npc.status:find("dead") and not npc.status:find("gone")) then
                table.insert(results, {name = name, target = npc})
            end
        end
    end
    return results
end

local function npc_status_matches(npc, pattern)
    return npc.status and npc.status:find(pattern)
end

local function stream_msg(msg)
    local room_id = Room.id or 0
    if Lich and Lich.Messaging then
        Lich.Messaging.stream_window(msg, "speech")
    else
        echo(msg)
    end
end

--- Check initial danger
Safety.unsafe()

--- Main profession-based combat logic
local prof = Char and Char.prof and Char.prof() or (DRStats and DRStats.guild) or "Unknown"
local room_id = Room.id or 0

if prof == "Bard" and Group and Group.leader and Group.leader() then
    local priority_targets = {"disciple", "disir", "draugr", "valravn", "angargeist", "mutant", "warg", "skald", "shield-maiden", "golem"}
    local matches = find_matching_targets(priority_targets)
    for _, m in ipairs(matches) do
        local t = m.target
        stream_msg("Room:" .. room_id .. " - (" .. tostring(t) .. ") - (" .. t.id .. ")")
        fput("target #" .. t.id)
        stream_msg("Room:" .. room_id .. " - Disabling: (" .. tostring(t) .. ") - (" .. t.id .. ").")

        if m.name == "disciple" and not npc_status_matches(t, "dead|gone|prone|lying down") then
            waitrt(); waitcastrt(); Safety.stance_offensive()
            if CMan then CMan.use("hamstring", t) end
        elseif (m.name == "disir" or m.name == "draugr") and not npc_status_matches(t, "dead|gone|prone|lying down") then
            waitrt(); waitcastrt(); Safety.stance_offensive()
            if CMan then CMan.use("hamstring", t) end
        elseif m.name == "valravn" and not npc_status_matches(t, "dead|gone") then
            waitrt(); waitcastrt(); Safety.stance_offensive()
            if CMan then CMan.use("feint", t) end
        elseif m.name == "mutant" and not npc_status_matches(t, "dead|gone") then
            waitrt(); waitcastrt()
            Safety.unravel(t, "1214")
        elseif (m.name == "golem" or m.name == "shield-maiden" or m.name == "skald" or m.name == "warg")
            and not npc_status_matches(t, "dead|gone|prone|lying down|sleeping") then
            waitrt(); waitcastrt(); Safety.stance_offensive()
            if CMan then CMan.use("hamstring", t) end
        end
    end

elseif prof == "Cleric" then
    local priority_targets = {"disciple", "disir", "draugr", "valravn", "angargeist", "mutant", "warg", "skald", "shield-maiden", "golem", "shaper", "lurk", "sentinel", "fanatic"}
    local matches = find_matching_targets(priority_targets)
    for _, m in ipairs(matches) do
        local t = m.target
        stream_msg("Room:" .. room_id .. " - Disabling: (" .. tostring(t) .. ") - (" .. t.id .. ").")
        fput("target #" .. t.id)
        waitrt(); waitcastrt()

        if m.name == "disciple" and not npc_status_matches(t, "dead|gone") then
            if Spell[240] and not Spell[240].active() and Spell[240].affordable() then Spell[240].force_incant() end
            if Spell[217] and Spell[217].affordable() then Spell[217].force_incant() end
            waitcastrt()
            if Spell[317] and Spell[317].affordable() then Spell[317].force_incant() end
            waitcastrt()
        elseif (m.name == "disir" or m.name == "draugr") and not npc_status_matches(t, "dead|gone|stunned") then
            if Spell[316] and Spell[316].affordable() then Spell[316].force_incant() end
        elseif (m.name == "angargeist" or m.name == "valravn") and not npc_status_matches(t, "dead|gone") then
            if Spell[118] and Spell[118].affordable() then Spell[118].force_incant() end
        elseif m.name == "mutant" and not npc_status_matches(t, "dead|gone") then
            if Spell[119] and Spell[119].affordable() then Spell[119].force_incant() end
        elseif (m.name == "golem" or m.name == "shield-maiden" or m.name == "skald" or m.name == "warg")
            and not npc_status_matches(t, "dead|gone|stunned") then
            if Spell[316] and Spell[316].affordable() then Spell[316].force_incant() end
        elseif m.name == "shaper" and not npc_status_matches(t, "dead|gone") then
            if Spell[210] and Spell[210].affordable() then Spell[210].force_incant() end
            waitcastrt()
        end
    end

elseif prof == "Sorcerer" then
    local priority_targets = {"disciple", "disir", "draugr", "valravn", "angargeist", "mutant", "warg", "skald", "shield-maiden", "golem", "shaper", "lurk", "sentinel", "fanatic"}
    local matches = find_matching_targets(priority_targets)
    for _, m in ipairs(matches) do
        local t = m.target
        stream_msg("Room:" .. room_id .. " - Disabling: (" .. tostring(t) .. ") - (" .. t.id .. ").")
        fput("target #" .. t.id)
        waitrt(); waitcastrt()

        if m.name == "disciple" and not npc_status_matches(t, "dead|gone") then
            if Spell[119] and Spell[119].affordable() then Spell[119].force_incant() end
            waitcastrt()
            if Spell[703] and Spell[703].affordable() then Spell[703].force_incant() end
        elseif (m.name == "disir" or m.name == "draugr") and not npc_status_matches(t, "dead|gone|lying down|prone|stunned") then
            if Spell[709] and Spell[709].affordable() then Safety.grasp() end
        elseif m.name == "valravn" and not npc_status_matches(t, "dead|gone") then
            if Spell[118] and Spell[118].affordable() then Spell[118].force_incant() end
        elseif m.name == "angargeist" and not npc_status_matches(t, "dead|gone") then
            if Spell[704] and Spell[704].affordable() then Spell[704].force_cast("#" .. t.id) end
        elseif m.name == "mutant" and not npc_status_matches(t, "dead|gone") then
            if Spell[119] and Spell[119].affordable() then Spell[119].force_incant() end
        elseif m.name == "shaper" and not npc_status_matches(t, "dead|gone") then
            if Spell[703] and Spell[703].affordable() then Spell[703].force_incant() end
        end
    end

elseif prof == "Warrior" then
    local priority_targets = {"disciple", "disir", "draugr", "valravn", "angargeist", "mutant", "warg", "skald", "shield-maiden", "golem", "shaper", "lurk", "sentinel", "fanatic"}
    local matches = find_matching_targets(priority_targets)
    for _, m in ipairs(matches) do
        local t = m.target
        stream_msg("Room:" .. room_id .. " - Disabling: (" .. tostring(t) .. ") - (" .. t.id .. ").")
        fput("target #" .. t.id)

        if (m.name == "disciple" or m.name == "disir" or m.name == "draugr" or m.name == "mutant" or m.name == "shaper" or m.name == "sentinel" or m.name == "lurk")
            and not npc_status_matches(t, "dead|gone|prone|lying down") then
            waitrt(); waitcastrt()
            Safety.warcry(t)
            waitrt()
            Safety.stance_offensive()
            if not npc_status_matches(t, "dead|gone|prone|lying down|sleeping") then
                if CMan then CMan.use("hamstring", t) end
            end
        elseif m.name == "valravn" then
            waitrt(); waitcastrt()
            Safety.warcry(t)
            waitrt()
            Safety.stance_offensive()
            if CMan then CMan.use("feint", t) end
        elseif (m.name == "fanatic" or m.name == "golem" or m.name == "shield-maiden" or m.name == "skald" or m.name == "warg")
            and not npc_status_matches(t, "dead|gone|prone|lying down") then
            waitrt(); waitcastrt()
            Safety.stance_offensive()
            if not npc_status_matches(t, "dead|gone|prone|lying down|sleeping") then
                if CMan then CMan.use("hamstring", t) end
            end
        end
    end

elseif prof == "Wizard" then
    local priority_targets = {"disciple", "disir", "draugr", "valravn", "angargeist", "mutant", "berserker", "cannibal", "hinterboar", "shield-maiden", "skald", "warg", "wendigo", "shaper", "lurk", "sentinel", "fanatic"}
    local matches = find_matching_targets(priority_targets)
    for _, m in ipairs(matches) do
        local t = m.target
        stream_msg("Room:" .. room_id .. " - Disabling: (" .. tostring(t) .. ") - (" .. t.id .. ").")
        fput("target #" .. t.id)

        if (m.name == "disciple" or m.name == "mutant") and not npc_status_matches(t, "dead|gone") then
            if Spell[417] and Spell[417].affordable() then Spell[417].force_incant() end
        elseif (m.name == "disir" or m.name == "draugr" or m.name == "valravn" or m.name == "angargeist")
            and not npc_status_matches(t, "dead|gone|prone|lying down|stunned|webbed") then
            if Spell[912] and Spell[912].affordable() then Spell[912].force_incant() end
        elseif (m.name == "berserker" or m.name == "cannibal" or m.name == "golem" or m.name == "hinterboar"
            or m.name == "shield-maiden" or m.name == "skald" or m.name == "warg" or m.name == "wendigo")
            and not npc_status_matches(t, "dead|gone|prone|lying down|stunned|webbed") then
            Safety.multi_stomp()
        elseif (m.name == "shaper" or m.name == "sentinel" or m.name == "lurk" or m.name == "fanatic")
            and not npc_status_matches(t, "dead|gone|prone|lying down|stunned|webbed") then
            if Group and Group.leader and Group.leader() then
                if Spell[912] and Spell[912].affordable() then Spell[912].force_incant() end
            else
                Safety.stomp()
            end
        end
    end
end
