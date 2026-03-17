--- @revenant-script
--- name: ejoustsmart
--- version: 2.0.2
--- author: elanthia-online
--- contributors: Tovklar, Elkiros, Rjex, Tysong, Dissonance
--- game: gs
--- description: Jousting automation for Rumor Woods -- pattern recognition
--- tags: jousting,rumor woods
---
--- Changelog (from Lich5):
---   v2.0.2 (2025-04-19) - Pouch drop fix, unhide before moving
---   v2.0.1 (2025-04-18) - Minor optimization, closest node for XP absorb
---   v2.0.0 (2025-04-15) - Refactored, XP absorb support, faction settings

--------------------------------------------------------------------------------
-- Faction Configuration (update yearly)
--------------------------------------------------------------------------------

local FACTION_YEAR = "2025"
local FACTION_1_NAME = "bee"
local FACTION_1_ROOM = 8208002
local FACTION_2_NAME = "bear"
local FACTION_2_ROOM = 8208001

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

UserVars.ignore_jousting_xp = UserVars.ignore_jousting_xp or "yes"
UserVars.stop_jousting = UserVars.stop_jousting or "no"

--------------------------------------------------------------------------------
-- RPS and Model logic
--------------------------------------------------------------------------------

local RPS = { left = "right", center = "left", right = "center" }

local MODEL1 = {
    centerleft = "left", centerright = "left",
    leftcenter = "right", leftright = "right",
    rightleft = "center", rightcenter = "center",
}

local MODEL2 = {
    centerleft = "center", centerright = "left",
    leftcenter = "right", leftright = "left",
    rightleft = "center", rightcenter = "right",
}

local MODEL3 = {
    centerleft = "left", centerright = "left",
    leftcenter = "left", leftright = "left",
    rightleft = "center", rightcenter = "left",
}

local function detect_model(model, lm2, lkm2, score)
    return model[lm2 .. lkm2] and score < 2
end

local function switch_model(model, current_model, lm2, lkm2, lm3, lkm3, lkm)
    return current_model ~= model and model[lm2 .. lkm2] == lkm and model[lm3 .. lkm3] == lkm2
end

local function knight_logic(joust, lm, lm2, lm3, lkm, lkm2, lkm3)
    if lkm == lkm2 and lkm2 == lkm3 then
        return RPS[lkm]
    elseif joust.score == 1 then
        return lm
    elseif joust.model_found then
        if joust.score == 2 and not joust.randoming then
            return RPS[joust.knight_mode[lm .. lkm]]
        elseif switch_model(MODEL3, joust.knight_mode, lm2, lkm2, lm3, lkm3, lkm) then
            joust.knight_mode = MODEL3
            return RPS[joust.knight_mode[lm .. lkm]]
        elseif switch_model(MODEL2, joust.knight_mode, lm2, lkm2, lm3, lkm3, lkm) then
            joust.knight_mode = MODEL2
            return RPS[joust.knight_mode[lm .. lkm]]
        elseif switch_model(MODEL1, joust.knight_mode, lm2, lkm2, lm3, lkm3, lkm) then
            joust.knight_mode = MODEL1
            return RPS[joust.knight_mode[lm .. lkm]]
        else
            joust.randoming = true
            local choices = { "left", "center", "right" }
            return choices[math.random(#choices)]
        end
    else
        if detect_model(MODEL2, lm2, lkm2, joust.score) then
            joust.knight_mode = MODEL2
            joust.model_found = true
        elseif detect_model(MODEL3, lm2, lkm2, joust.score) then
            joust.knight_mode = MODEL3
            joust.model_found = true
        elseif detect_model(MODEL1, lm2, lkm2, joust.score) then
            joust.knight_mode = MODEL1
            joust.model_found = true
        end
        return RPS[joust.knight_mode[lm .. lkm]]
    end
end

--------------------------------------------------------------------------------
-- Tourney loop
--------------------------------------------------------------------------------

local function tourney_loop(faction)
    local AIM_RX = Regex.new("AIM LEFT, AIM CENTER, or AIM RIGHT")
    local KNIGHT_RX = Regex.new("appears to be aiming.+?to the (right|left|center) of your")
    local SCORE_RX = Regex.new("A jousting herald announces.+?(0|1|2)")
    local ATTENDANT_RX = Regex.new("A jousting attendant says")

    while true do
        -- Check for markers
        if not dothistimeout("look at my marker", 2, { "Bearer entitled to entry into Rumor Woods." }) then
            echo("You are out of markers!")
            return
        end

        -- XP absorb check
        if UserVars.ignore_jousting_xp ~= "yes" and percentmind() > 90 then
            echo("Mind " .. percentmind() .. "%; going to node to wait.")
            pause(3)
            Script.run("go2", "u8208812")
            wait_while(function() return running("go2") end)
            while percentmind() > 90 do pause(1) end
        end

        -- Travel to faction room
        if hidden() then fput("unhide") end
        Script.run("go2", "u" .. tostring(faction))
        wait_while(function() return running("go2") end)

        -- Get marker
        dothistimeout("get marker", 2, { "You remove a", "You already have that" })

        -- Reset joust state
        local joust = {
            knight_mode = MODEL1,
            model_found = false,
            randoming = false,
            score = 0,
        }

        local moves = { current = "left", prev1 = "left", prev2 = "left" }
        local knight_moves = { current = "unknown", prev1 = "unknown", prev2 = "unknown" }

        -- Enter
        fput("go entry table")
        if UserVars.inv then
            fput("put my marker in my " .. UserVars.inv)
        else
            fput("stow my marker")
        end
        fput("glance")
        pause(2)

        -- Get equipment from paddock/rack/display
        fput("go entry table")
        waitfor("Tourney")
        fput("shout")

        -- Jousting loop
        while true do
            local result = waitfor("AIM LEFT, AIM CENTER, or AIM RIGHT", "A jousting attendant says", "appears to be aiming")
            if not result then break end

            local km = KNIGHT_RX:match(result)
            if km then
                local score_line = waitfor("A jousting herald announces")
                local sm = SCORE_RX:match(score_line or "")
                if sm then joust.score = tonumber(sm[1]) end

                moves.prev2 = moves.prev1
                moves.prev1 = moves.current
                knight_moves.prev2 = knight_moves.prev1
                knight_moves.prev1 = knight_moves.current
                knight_moves.current = km[1]

                moves.current = knight_logic(joust,
                    moves.current, moves.prev1, moves.prev2,
                    knight_moves.current, knight_moves.prev1, knight_moves.prev2)
            elseif AIM_RX:test(result) then
                fput("aim " .. moves.current)
            elseif ATTENDANT_RX:test(result) then
                -- End of joust, collect prizes
                fput("open my pouch")
                fput("look in my pouch")
                pause(2)
                fput("empty my pouch in my " .. (UserVars.lootsack or "backpack"))
                waitrt()
                fput("drop my pouch")
                break
            end
        end

        -- Check stop flag
        if UserVars.stop_jousting == "yes" then
            echo("Var stop_jousting set to yes, resetting and exiting.")
            UserVars.stop_jousting = "no"
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("** Jousting ** Version 2.0.2")
    respond("")
    respond("Factions for " .. FACTION_YEAR .. ": " .. FACTION_1_NAME .. " and " .. FACTION_2_NAME)
    respond("USAGE: ;ejoustsmart " .. FACTION_1_NAME .. "  or  ;ejoustsmart " .. FACTION_2_NAME)
    respond("")
    respond("  ;ejoustsmart help             - Show this help")
    respond("  ;ejoustsmart ignore_jousting_xp  - Ignore mind state")
    respond("  ;ejoustsmart absorb_xp_first     - Wait for XP absorption")
    respond("")
    respond("To stop after current run: ;vars set stop_jousting=yes")
    respond("Prizes go to lootsack: " .. (UserVars.lootsack or "(not set)"))
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]
if not arg1 or arg1 == "" then
    show_help()
    return
end

local a = arg1:lower()
if a == FACTION_1_NAME:lower() then
    tourney_loop(FACTION_1_ROOM)
elseif a == FACTION_2_NAME:lower() then
    tourney_loop(FACTION_2_ROOM)
elseif a:find("help") then
    show_help()
elseif a:find("ignore_jousting_xp") then
    UserVars.ignore_jousting_xp = "yes"
    echo("Jousting will continue and XP status will be ignored.")
elseif a:find("absorb_xp_first") then
    UserVars.ignore_jousting_xp = "no"
    echo("XP will be absorbed before continuing jousting.")
else
    show_help()
end
