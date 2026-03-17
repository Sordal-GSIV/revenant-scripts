local data = require("data")

local M = {}

-- state reference, set by init.lua
M.state = nil

function M.msg(msg_type, text)
    if msg_type == "debug" then
        if not (M.state and M.state.settings and M.state.settings.debug) then return end
    end
    respond("[ebounty] " .. (text or ""))
end

function M.wait_rt()
    pause(0.2)
    waitcastrt()
    waitrt()
    pause(0.2)
end

function M.run_scripts(scripts_str)
    if not scripts_str or scripts_str == "" then return end
    for entry in scripts_str:gmatch("[^,]+") do
        entry = entry:match("^%s*(.-)%s*$")
        local parts = {}
        for word in entry:gmatch("%S+") do parts[#parts + 1] = word end
        if #parts > 1 then
            Script.run(parts[1], table.concat(parts, " ", 2))
        elseif #parts == 1 then
            Script.run(parts[1])
        end
    end
end

function M.go2(place)
    M.msg("debug", "go2: " .. tostring(place))
    if hidden() or invisible() then fput("unhide") end
    local current = Map.current_room()
    if current and tostring(current) == tostring(place) then return end
    Script.run("go2", tostring(place) .. " --disable-confirm")
end

function M.go2_rest()
    local st = M.state.settings
    local current_room = tostring(Map.current_room() or "")
    local where_to

    if st.bigshot_rest then
        where_to = current_room
    elseif st.custom_rest and st.resting_room ~= "" then
        local rooms = {}
        for r in st.resting_room:gmatch("[^,%s]+") do rooms[#rooms + 1] = r end
        local in_list = false
        for _, r in ipairs(rooms) do
            if r == current_room then in_list = true; break end
        end
        where_to = in_list and current_room or rooms[math.random(#rooms)]
    elseif st.table_rest then
        where_to = "table"
    elseif st.use_script and st.use_script_name ~= "" then
        M.run_scripts(st.use_script_name)
        return
    else
        where_to = "town"
    end

    if where_to == "table" then
        M.go2("table")
        fput("go table")
    elseif where_to then
        M.go2(where_to)
    end

    M.wait_rt()

    if st.join_player and st.join_list ~= "" then
        for pc in st.join_list:gmatch("[^,]+") do
            pc = pc:match("^%s*(.-)%s*$")
            local pcs = GameObj.pcs()
            for _, p in ipairs(pcs) do
                if p.name == pc then fput("join " .. pc); break end
            end
        end
    end

    if st.use_buff_script and st.buff_script ~= "" then
        M.run_scripts(st.buff_script)
    end
end

function M.change_stance(target)
    if dead() then return end
    local current = GameState.stance_value
    if current == target then return end
    if target == 100 and current and current >= 80 then return end
    local name = data.stance_names[target] or "defensive"
    for _ = 1, 5 do
        fput("stance " .. name)
        M.wait_rt()
        if GameState.stance_value == target then break end
    end
end

function M.check_health()
    if M.state.settings.skip_healing then return end
    local dominated = {
        "head","neck","chest","abdomen","back",
        "leftArm","rightArm","leftHand","rightHand",
        "leftLeg","rightLeg","leftFoot","rightFoot",
        "leftEye","rightEye","nsys",
    }
    local need_heal = false
    for _, part in ipairs(dominated) do
        if Wounds[part] > 0 or Scars[part] > 1 then need_heal = true; break end
    end
    if not need_heal and Char.percent_health >= 95 then return end
    local healing = M.state.settings.healing_script ~= "" and M.state.settings.healing_script or "eherbs"
    Script.run(healing)
end

function M.fog()
    local st = M.state.settings
    if not st or st.basic then return end
    M.wait_rt()

    -- Spirit Guide (130)
    if Spell[130].known and Spell[130].affordable then
        put("incant 130"); M.wait_rt(); return
    end
    -- Symbol of Return (9825)
    if Spell[9825].known then
        fput("symbol of return"); pause(0.5); return
    end
    -- Traveler's Song (1020)
    if Spell[1020].known and Spell[1020].affordable then
        put("incant 1020"); M.wait_rt(); return
    end
    -- Sigil of Escape (9720)
    if Spell[9720].known and Spell[9720].affordable then
        put("incant 9720"); M.wait_rt(); return
    end
    -- Familiar Gate (930)
    if Spell[930].known and Spell[930].affordable then
        put("incant 930"); fput("go portal"); M.wait_rt(); return
    end
end

function M.silver_deposit()
    M.go2("bank")
    fput("deposit all")
end

function M.bounty_change(original)
    for _ = 1, 15 do
        if (Bounty.task or "") ~= original then return true end
        pause(0.2)
    end
    return false
end

function M.duration(elapsed)
    local rest = math.floor(elapsed)
    local secs = rest % 60; rest = math.floor(rest / 60)
    local mins = rest % 60; rest = math.floor(rest / 60)
    local hours = rest % 24; local days = math.floor(rest / 24)
    local parts = {}
    if days > 0 then parts[#parts + 1] = days .. " Days" end
    if hours > 0 then parts[#parts + 1] = hours .. " Hours" end
    if mins > 0 then parts[#parts + 1] = mins .. " Minutes" end
    if secs > 0 then parts[#parts + 1] = secs .. " Seconds" end
    return table.concat(parts, " ")
end

return M
