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

    local enh = Stats.enhanced_aur
    local base = Stats.aur
    if enh and base and enh[1] < base[1] then
        return false, "Recovering from Death"
    end

    local btask = Bounty.task or ""
    if btask:find("Come back in about") then
        return false, "Bounty cooldown"
    end

    local now = os.time()
    if now - (util.state.info_time or 0) >= 60 then
        put("info")
        util.state.info_time = now
        pause(0.5)
    end

    if GameState.mind == "saturated" and st.exp_pause then
        return false, "Mind saturated"
    end

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
            util.msg("yellow", "Elapsed: " .. util.elapsed())
            last_msg = now
        end
        pause(0.5)
        ready, reason = M.should_hunt()
    end
end

function M.set_eval()
    local st = util.state.settings
    local info = Bounty.parse()
    if not info then return end

    local bt = info.type or "none"

    if bt == "skin" and info.number then
        util.state.remaining_skins = (info.number or 1) + (st.extra_skin or 0)
        util.state.skin = info.skin
    end

    if bt == "gem" and info.number then
        util.state.remaining_gems = info.number or 1
        util.state.gem = info.gem
    end

    if st.exp_pause then
        util.state.complete_mind = "saturated"
    else
        util.state.complete_mind = nil
    end
end

function M.keep_hunting()
    util.msg("debug", "keep_hunting loop")
    local original = Bounty.task or ""
    while true do
        local ok, _ = M.should_hunt()
        if not ok then break end
        Script.run("bigshot", "single")
        pause(1)
        if (Bounty.task or "") ~= original then break end
        if (Bounty.task or ""):find("succeeded") then break end
        if (Bounty.task or ""):find("not currently assigned") then break end
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

    M.set_eval()

    local creature = util.state.creature
    local st = util.state.settings

    if creature == "bandits" then
        local bandit_args = "bounty"
        if util.state.location_start then
            bandit_args = bandit_args .. " --hunting-room " .. tostring(util.state.location_start)
        end
        if util.state.location_boundaries then
            bandit_args = bandit_args .. " --boundaries " .. util.state.location_boundaries
        end
        if st.wander_wait and st.wander_wait > 0 then
            bandit_args = bandit_args .. " --wander-wait " .. tostring(st.wander_wait)
        end
        Script.run("bigshot", bandit_args)
    elseif creature and st.ranger_track then
        local last_word = creature:match("(%S+)$") or creature
        Script.run("bigshot", "bounty " .. last_word)
    else
        Script.run("bigshot", "bounty")
    end
end

return M
