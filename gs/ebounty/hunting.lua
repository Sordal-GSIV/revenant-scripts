local util = require("util")

local M = {}

function M.should_hunt()
    local st = util.state.settings

    if Char.percent_mana < 20 then
        return false, "Mana too low"
    end

    if Char.spirit < 5 then
        return false, "Spirit too low"
    end

    -- Death recovery check
    local enh = Stats.enhanced_aur
    local base = Stats.aur
    if enh and base and enh[1] < base[1] then
        return false, "Recovering from Death"
    end

    if GameState.mind == "saturated" and st.exp_pause then
        return false, "Mind saturated"
    end

    local btask = Bounty.task or ""
    if btask:find("succeeded") and GameState.mind == "saturated"
       and not st.keep_hunting then
        return false, "Bounty complete but mind saturated"
    end

    return true, ""
end

function M.wait_for_ready()
    local ready, reason = M.should_hunt()
    if not ready then util.go2_rest() end

    local last_msg = 0
    while not ready do
        util.check_health()
        local now = os.time()
        if now - last_msg >= 60 then
            util.msg("yellow", "Not Hunting: " .. reason)
            util.msg("yellow", "Elapsed: " .. util.duration(os.time() - util.state.start_time))
            last_msg = now
        end
        pause(0.5)
        ready, reason = M.should_hunt()
    end
end

function M.pre_hunt(hunt_type)
    util.msg("debug", "pre_hunt: " .. hunt_type)
    local st = util.state.settings
    local commands, scripts

    if hunt_type == "forage" then
        commands, scripts = st.forage_prep_commands, st.forage_prep_scripts
    elseif hunt_type == "heirloom" then
        commands, scripts = st.heirloom_prep_commands, st.heirloom_prep_scripts
    elseif hunt_type == "escort" then
        commands, scripts = st.escort_prep_commands, st.escort_prep_scripts
    else
        commands, scripts = "", ""
    end

    if commands and commands ~= "" then
        for cmd in commands:gmatch("[^,]+") do
            fput(cmd:match("^%s*(.-)%s*$"))
            pause(0.3)
        end
    end
    if scripts and scripts ~= "" then util.run_scripts(scripts) end
end

function M.post_hunt(hunt_type)
    util.msg("debug", "post_hunt: " .. hunt_type)
    local st = util.state.settings
    local kill_scripts, commands, scripts

    if hunt_type == "forage" then
        kill_scripts = st.forage_prep_scripts
        commands, scripts = st.forage_post_commands, st.forage_post_scripts
    elseif hunt_type == "heirloom" then
        kill_scripts = st.heirloom_prep_scripts
        commands, scripts = st.heirloom_post_commands, st.heirloom_post_scripts
    elseif hunt_type == "escort" then
        kill_scripts = st.escort_prep_scripts
        commands, scripts = st.escort_post_commands, st.escort_post_scripts
    else
        kill_scripts, commands, scripts = "", "", ""
    end

    if kill_scripts and kill_scripts ~= "" then
        for entry in kill_scripts:gmatch("[^,]+") do
            local name = entry:match("^%s*(%S+)")
            if name and Script.running(name) then Script.kill(name) end
        end
    end
    if commands and commands ~= "" then
        for cmd in commands:gmatch("[^,]+") do
            fput(cmd:match("^%s*(.-)%s*$"))
            pause(0.3)
        end
    end
    if scripts and scripts ~= "" then util.run_scripts(scripts) end
end

function M.go_hunting()
    util.msg("debug", "go_hunting")
    M.wait_for_ready()

    local btask = Bounty.task or ""
    if btask:find("You are not currently assigned") then return end
    if btask:find("succeeded") and GameState.mind ~= "saturated" then return end

    -- Run bigshot for actual hunting
    local creature = util.state.creature
    if creature and util.state.settings.ranger_track then
        local last_word = creature:match("(%S+)$") or creature
        Script.run("bigshot", "bounty " .. last_word)
    else
        Script.run("bigshot", "bounty")
    end
end

return M
