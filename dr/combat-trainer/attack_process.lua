--- AttackProcess — melee, thrown, aimed, backstab, ambush, charged maneuvers,
--- dance, aim queue, powershot, repeating crossbow, whirlwind.
--- Ported from AttackProcess class in combat-trainer.lic (elanthia-online).
--- Original authors: Multiple community contributors (see combat-trainer.lic CHANGELOG).

local M = {}
M.__index = M

-- Ammo noun list for ranged-ammo flag pattern.
-- IMPORTANT: 'stone shard' must precede both 'shard' and 'stone' so multi-word
-- nouns match correctly (e.g. "senci stone shard").
local AMMO_NOUNS = table.concat({
    "arrow", "bolt", "stone shard", "shard", "rock", "sphere", "clump",
    "coral", "fist", "holder", "lump", "patella", "pellet", "pulzone",
    "quadrello", "quarrel", "quill", "stone", "stopper", "verretto",
    "blowgun dart", "crumb", "spine", "mantrap spike", "tiny dragon",
    "icicle", "fang", "scale", "grey-black spike", "bacon strip", "page",
    "naga", "thorn", "fragment", "talon", "cork", "button", "core", "pebble",
    "geode", "stub", "pit", "thimble", "doorknob", "cone", "bell", "hunk",
    "piece", "present", "sleighbell", "sprig", "star", "toy", "spiral",
    "tile", "marble",
}, "|")

-- Action verb categories used when processing aim-filler commands.
local GET_ACTIONS  = { "get", "wield" }
local RT_ACTIONS   = { "gouge", "attack", "jab", "feint", "draw", "lunge", "slice", "lob", "throw" }
local STOW_ACTIONS = { "stow", "sheath", "put" }

local function tcontains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--- Create a new AttackProcess instance.
-- @param settings table  Character settings from get_settings()
function M.new(settings)
    local self = setmetatable({}, M)

    self._fatigue_regen_action             = settings.fatigue_regen_action
    self._stealth_attack_aimed_action      = settings.stealth_attack_aimed_action
    self._hide_type                        = settings.hide_type
    self._offhand_thrown                   = settings.offhand_thrown
    self._ambush_location                  = settings.ambush_location
    self._use_overrides_for_aiming_trainables = settings.use_overrides_for_aiming_trainables
    self._firing_delay                     = settings.firing_delay or 0
    self._firing_timer                     = os.time()
    self._firing_check                     = 0

    -- Build ammo pattern string (captures the ammo noun).
    local ammo_pattern = "(" .. AMMO_NOUNS .. ")s?"

    -- Detect ammo falling to ground after firing.
    -- Matches: "you fire an arrow at", "your grey-black spike passes through", etc.
    Flags.add("ct-ranged-ammo",
        "(you (fire|poach|snipe) an?|your) ([^%.!]*? )?" .. ammo_pattern .. "(.*?)? (at|passes through)")

    -- Detect powershot ammo ejected with a loud twang.
    Flags.add("ct-powershot-ammo",
        "With a loud twang, you let fly your " .. ammo_pattern .. "!")

    -- Detect that the ranged weapon is (or became) loaded.
    Flags.add("ct-ranged-loaded",
        "You reach into",
        "You load",
        "You carefully load",
        "already loaded",
        "in your hand")

    -- Detect repeating / self-loading crossbow variants.
    Flags.add("ct-using-repeating-crossbow",
        "Your repeating crossbow",
        "Your repeating arbalest",
        "Your marksman's arbalest",
        "Your assassin's crossbow",
        "Your riot crossbow",
        "You .* ammunition (chamber|store)",
        "already loaded with as much ammunition as it can hold",
        "You realize readying more than one")

    -- Detect aim being broken mid-combat.
    Flags.add("ct-aim-failed",
        "you stop aiming",
        "stop concentrating on aiming")

    -- Detect best-aim achieved.
    Flags.add("ct-ranged-ready",
        "You think you have your best shot possible now.")

    -- Detect "Face what?" prompt (no visible target when engaging).
    Flags.add("ct-face-what", "Face what")

    -- Barbarian War Stomp cooldown — starts as ready.
    Flags.add("war-stomp-ready",
        "You feel ready to perform another War Stomp")
    Flags["war-stomp-ready"] = true

    -- Barbarian Pounce cooldown — starts as ready.
    Flags.add("pounce-ready",
        "You think you have the strength to pounce upon prey once again.")
    Flags["pounce-ready"] = true

    -- Expert maneuver recovery (reduces cooldown).
    Flags.add("ct-maneuver-cooldown-reduced",
        "With expert skill you end the attack and maneuver into a better position")

    -- Out-of-range attack indicator.
    Flags.add("ct-attack-out-of-range",
        "You aren't close enough to attack")

    return self
end

---------------------------------------------------------------------------
-- Public entry point
---------------------------------------------------------------------------

--- Execute one cycle of attack logic.
-- @param game_state table  GameState instance
-- @return false  (never drives the outer loop to stop)
function M:execute(game_state)
    self:_check_face(game_state)

    -- Track per-mob stab eligibility.
    local npcs = game_state:npcs()
    local unique_npcs = self:_unique(npcs)
    if #unique_npcs == 1 and not game_state:stabbable(unique_npcs[1]) then
        game_state.no_stab_current_mob = true
    elseif game_state.mob_died and game_state.no_stab_current_mob then
        game_state.no_stab_current_mob = false
    end

    -- If dancing, targeted magic, or offense not allowed — dance or clean up.
    if game_state.dancing
        or game_state:weapon_skill() == "Targeted Magic"
        or not game_state:is_offense_allowed() then
        if game_state:finish_killing() then
            game_state:next_clean_up_step()
        else
            self:_dance(game_state)
        end
        return false
    end

    -- Pause to regenerate fatigue if critically low.
    if game_state:fatigue_low() then
        fput(self._fatigue_regen_action)
        return false
    end

    local charged_maneuver = game_state:determine_charged_maneuver()

    game_state:reset_barb_whirlwind_flags_if_needed()

    if game_state:thrown_skill() then
        game_state.loaded   = false
        self._firing_check  = 0
        self:_attack_thrown(game_state)
    elseif game_state:aimed_skill() then
        self:_attack_aimed(charged_maneuver, game_state)
    else
        game_state.loaded  = false
        self._firing_check = 0
        self:_attack_melee(charged_maneuver, game_state)
    end

    return false
end

---------------------------------------------------------------------------
-- Private helpers
---------------------------------------------------------------------------

--- Handle "Face what?" prompt by re-engaging the current target.
function M:_check_face(game_state)
    if not Flags["ct-face-what"] then return end
    game_state:engage()
    Flags.reset("ct-face-what")
end

--- Return a deduplicated copy of a list.
function M:_unique(t)
    local seen   = {}
    local result = {}
    for _, v in ipairs(t) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Melee attack
---------------------------------------------------------------------------

function M:_attack_melee(charged_maneuver, game_state)
    waitrt()

    local maneuver_success = false

    if charged_maneuver then
        -- Doublestrike requires a second weapon in the off hand.
        local offhand_weapon_name = nil
        local ds_skill = nil
        if charged_maneuver:lower() == "doublestrike" and DRC.left_hand() == nil then
            ds_skill = game_state:determine_doublestrike_skill()
            if ds_skill then
                offhand_weapon_name = game_state:wield_offhand_weapon(ds_skill)
            end
        end

        maneuver_success = game_state:use_charged_maneuver(charged_maneuver)

        if offhand_weapon_name then
            game_state:sheath_offhand_weapon(ds_skill)
        end
    end

    -- Fall back to normal attack if the maneuver was skipped or failed.
    if not maneuver_success then
        -- Hide before backstab / ambush / stealth attacks if configured.
        if game_state:backstab_p()
            or game_state:use_stealth_attack()
            or game_state:ambush_p()
            or game_state:ambush_stun_training() then
            DRC.hide(self._hide_type)
        end

        local verb    = game_state:melee_attack_verb()
        local command = game_state:offhand() and (verb .. " left") or verb

        -- Backstab / ambush verb override when successfully hidden.
        if (game_state:backstab_p() or game_state:ambush_p() or game_state:ambush_stun_training())
            and hiding() then
            if (game_state:backstab_p() and game_state.no_stab_current_mob)
                or (game_state:ambush_p() and not game_state:backstab_p()) then
                -- Ambush to a body location.
                command = command .. " " .. (self._ambush_location or "")
            elseif game_state:ambush_stun_training() then
                -- Replace the attack verb with "ambush stun".
                command = command:gsub(verb, "ambush stun", 1)
            else
                -- Plain backstab.
                command = command:gsub(verb, "backstab", 1)
            end
        end

        DRC.bput(command,
            "Wouldn't it be better if you used a melee weapon?",
            "You need two hands to wield this weapon",
            "You turn to face",
            "Face What?",
            "Roundtime",
            "You aren't close enough to attack",
            "It would help if you were closer",
            "There is nothing else to face!",
            "You must be hidden",
            "flying too high for you to attack",
            "You can't coldcock",
            "while it is flying",
            "Novel idea, but it's a ghost!",
            "Bumbling, you slip",
            "You can not slam with that",
            "You must be hidden or invisible to ambush",
            "You don't have enough focus",
            "You don't think you have enough focus",
            "is already out cold")
    end

    pause()
    waitrt()

    -- Target flew out of melee range — face the next available mob.
    if reget(5, "flying too high for you to attack") then
        local face_result = DRC.bput("face next",
            "There is nothing", "You turn to face", "Face what")
        if face_result:match("There is nothing") then
            pause(5)
        end
    end

    -- This mob cannot be backstabbed — remember it.
    if reget(5, "You can't backstab that") then
        local u = self:_unique(game_state:npcs())
        if #u == 1 then
            game_state:unstabbable(game_state:npcs()[1])
        else
            game_state.no_stab_current_mob = true
        end
    end

    -- Too far away — re-engage; otherwise count the action.
    if reget(5, "You aren't close enough to attack", "It would help if you were closer") then
        game_state:engage()
    else
        game_state:action_taken()
    end

    -- Two-handed weapon in off hand — stow the other item.
    if reget(5, "You need two hands") then
        local wname = game_state:weapon_name() or ""
        local lh = DRC.left_hand()
        local rh = DRC.right_hand()
        if lh and not lh:lower():match(wname:lower()) then
            fput("stow left")
        end
        if rh and not rh:lower():match(wname:lower()) then
            fput("stow right")
        end
    end
end

---------------------------------------------------------------------------
-- Thrown attack
---------------------------------------------------------------------------

function M:_attack_thrown(game_state)
    local attack_action = game_state:thrown_attack_verb()
    if game_state:offhand() then
        attack_action = attack_action .. " left"
    end

    DRC.bput(attack_action, "roundtime", "What are you trying to")
    waitrt()

    -- Whips do not need ammo retrieval.
    if attack_action:find("whip") then
        game_state:action_taken()
        return
    end

    -- Blade disc: stow all loose blades before retrieving the main one.
    if game_state:weapon_name() == "blades" then
        local blade_result = ""
        repeat
            blade_result = DRC.bput("stow blade",
                "Stow what", "You pick up .*blade", "You put your")
        until blade_result:match("Stow what") or blade_result:match("You put your")
    end

    local retrieve_action = game_state:thrown_retrieve_verb()

    -- Success patterns for bonded-weapon invoke.
    local bonded_success = {
        "reuniting you with your lost belonging",
        "In its place, you are left with your",
        "returning .* to your",
        "depositing .* back to the rightful owner",
        "Your .* appears within reach",
        "you are reunited with your",
        "You catch",
        "A tiny ripplegate gurgles into being near your",
    }

    local retrieve_patterns = {
        "You are already holding",
        "You pick up",
        "You get",
        "What were you",
        "You don't have any bonds to invoke",
    }
    for _, p in ipairs(bonded_success) do
        table.insert(retrieve_patterns, p)
    end

    local retrieve_result = DRC.bput(retrieve_action, table.unpack(retrieve_patterns))

    if retrieve_result:match("What were you") then
        -- Game bug: unblessed weapon thrown at incorporeal mob lands on ground,
        -- not in the at-feet slot, so "my" will not work.
        DRC.bput("get " .. game_state:weapon_name(), "You pick up", "You get")
    else
        -- Check if result matched a bonded invoke success.
        local was_bonded = false
        for _, p in ipairs(bonded_success) do
            if retrieve_result:match(p) then
                was_bonded = true
                break
            end
        end
        if was_bonded and game_state:offhand() then
            DRC.bput("swap", "You move", "You have nothing")
        end
    end

    game_state:action_taken()
end

---------------------------------------------------------------------------
-- Aimed attack (ranged weapons: bows, crossbows, slings)
---------------------------------------------------------------------------

function M:_attack_aimed(charged_maneuver, game_state)
    -- If aiming was interrupted, reset load state and try a fresh load next cycle.
    if Flags["ct-aim-failed"] then
        game_state.loaded  = false
        self._firing_check = 0
        Flags.reset("ct-aim-failed")
    end

    -- Branch 1: Weapon is loaded and the timer has expired (or best-aim flag set).
    if game_state.loaded
        and (os.time() >= self._firing_timer or Flags["ct-ranged-ready"]) then

        local command
        if game_state:use_stealth_ranged() and DRC.hide(self._hide_type) then
            command = self._stealth_attack_aimed_action
        elseif game_state:use_stealth_attack() and DRC.hide(self._hide_type) then
            command = self._stealth_attack_aimed_action
        else
            command = "shoot"
        end

        self:_shoot_aimed(command, game_state)
        game_state:clear_aim_queue()
        game_state.loaded  = false
        self._firing_check = 0
        waitrt()

    -- Branch 2: Weapon loaded, waiting to fire — train an offhand melee/thrown skill.
    elseif game_state.loaded and #game_state.aiming_trainables > 0 then
        local skill = game_state:determine_aiming_skill()
        if not skill then return end

        local weapon_name = game_state:wield_offhand_weapon(skill)

        -- Record baseline XP for offhand gain check.
        game_state.offhand_last_exp  = DRSkill.getxp(skill)
        game_state.last_offhand_skill = skill

        -- Choose the offhand attack action(s).
        local atk = nil
        local actions
        if skill == "Tactics" then
            -- Use shared tactics action list (defined in the main script).
            actions = _G.tactics_actions or { "bob", "weave", "circle" }
        elseif self._use_overrides_for_aiming_trainables then
            atk = game_state:attack_override(skill)
            actions = { atk .. " left", atk .. " left", atk .. " left" }
        elseif skill:find("Thrown") then
            actions = { "lob left", "lob left", "lob left" }
        elseif skill == "Brawling" then
            actions = { "gouge left", "gouge left", "gouge left" }
        else
            actions = { "jab left", "jab left", "jab left" }
        end

        for _, action in ipairs(actions) do
            if not self:_execute_aiming_action(action, game_state) then
                break
            end
            -- Whip snaps don't leave ammo on the ground.
            if atk and atk:find("whip") then
                -- nothing to retrieve
            elseif skill:find("Thrown") then
                -- Retrieve thrown offhand weapon.
                local retrieve_action
                if action:find("hurl") then
                    retrieve_action = "invoke"
                else
                    retrieve_action = "get my " .. (weapon_name or "")
                end
                local ret = DRC.bput(retrieve_action,
                    "You are already holding",
                    "You pick up",
                    "You get",
                    "You catch",
                    "What were you",
                    "You don't have any bonds to invoke")
                if ret:match("What were you") then
                    DRC.bput("get " .. (weapon_name or ""),
                        "You pick up", "You get", "What were")
                end
            end
        end

        game_state:sheath_offhand_weapon(skill)

    -- Branch 3: Weapon loaded, still inside firing timer — execute aim fillers.
    elseif game_state.loaded and os.time() <= self._firing_timer then
        local raw_actions = game_state:next_aim_action()
        if raw_actions and raw_actions ~= "" then
            local parts = {}
            for part in raw_actions:gmatch("[^;]+") do
                table.insert(parts, part)
            end
            for _, action in ipairs(parts) do
                local trimmed   = action:match("^%s*(.-)%s*$")
                local first_word = trimmed:match("^(%S+)"):lower()
                local matches

                if tcontains(GET_ACTIONS, first_word) then
                    matches = {
                        "You get", "You draw out", "You draw your", "You pick up",
                        "You're already holding that", "You are already holding that",
                    }
                elseif tcontains(RT_ACTIONS, first_word) then
                    matches = {
                        "Roundtime",
                        "You aren't close enough to attack",
                        "What are you",
                        "There is nothing",
                    }
                elseif tcontains(STOW_ACTIONS, first_word) then
                    matches = {
                        "You put", "You sheathe",
                        "Sheathing a", "Sheathing some",
                    }
                else
                    matches = { "You " }
                end

                DRC.bput(trimmed, table.unpack(matches))
                pause(0.25)
                waitrt()
            end
        end

    -- Branch 4: Not loaded — load the weapon, then either fire a maneuver or begin aiming.
    else
        local load_success = {
            "You reach into",
            "You load",
            "You carefully load",
            "already loaded",
            "in your hand",
            "A rapid series of clicks",
            "into firing position",
            "You realize readying",
            "As you draw back the string",
        }

        local load_failure = {
            "As you try to reach",
            "You don't have the proper ammunition",
            "You don't have enough .* to load two at once",
            "What weapon are you trying to load",
            "You can't do that .* because you aren't trained in the ways of magic",
            "you probably need to be more specific on what you are loading",
            "Such a feat would be impossible without the winds to guide",
            "but are unable to draw upon its majesty",
            "without steadier hands",
            "You can not load .* in your left hand",
            "You need to hold the .* in your right hand to load it",
            "You attempt to ready your",
            "Push what?",
            "It's best to hold",
            "pushing that would have any effect",
        }

        local all_load_patterns = {}
        for _, p in ipairs(load_success) do table.insert(all_load_patterns, p) end
        for _, p in ipairs(load_failure) do table.insert(all_load_patterns, p) end

        local dual_load = game_state:dual_load_p()

        -- Attempt dual-load first if configured.
        if dual_load then
            Flags.reset("ct-ranged-loaded")
            -- First attempt with a short timeout; retry if no output.
            local r1 = DRC.bput("load arrows",
                { timeout = 1, suppress_no_match = true },
                table.unpack(all_load_patterns))
            if not Flags["ct-ranged-loaded"] then
                r1 = DRC.bput("load arrows", table.unpack(all_load_patterns))
            end
            -- Check if the result was a failure pattern.
            local dual_failed = false
            for _, fp in ipairs(load_failure) do
                if r1:match(fp) then dual_failed = true; break end
            end
            if dual_failed then
                dual_load = false          -- fall through to single load
                game_state.loaded  = false
                self._firing_check = 0
            else
                game_state.loaded = true
            end
        end

        -- Single load (either primary path or dual-load fallback).
        if not dual_load then
            Flags.reset("ct-ranged-loaded")
            Flags.reset("ct-using-repeating-crossbow")

            local wname = game_state:weapon_name() or ""
            local r2 = DRC.bput("load my " .. wname,
                { timeout = 1, suppress_no_match = true },
                table.unpack(all_load_patterns))
            if not Flags["ct-ranged-loaded"] then
                r2 = DRC.bput("load my " .. wname, table.unpack(all_load_patterns))
            end
            waitrt()

            -- Check for load failure.
            local single_failed = false
            for _, fp in ipairs(load_failure) do
                if r2:match(fp) then single_failed = true; break end
            end

            if single_failed then
                self:_abort_attack_aimed(game_state)
                return
            end

            -- Load succeeded — handle repeating crossbow push-to-chamber step.
            if Flags["ct-using-repeating-crossbow"] then
                local push_result = DRC.bput("push my " .. wname,
                    table.unpack(all_load_patterns))
                local push_failed = false
                for _, fp in ipairs(load_failure) do
                    if push_result:match(fp) then push_failed = true; break end
                end
                if push_failed then
                    self:_abort_attack_aimed(game_state)
                    return
                end
            end

            game_state.loaded = true
        end

        waitrt()

        if game_state.loaded then
            if charged_maneuver and game_state:use_charged_maneuver(charged_maneuver) then
                -- Maneuver fired — handle powershot ammo stow.
                if Flags["ct-powershot-ammo"] and charged_maneuver == "powershot" then
                    local flag_val = Flags["ct-powershot-ammo"]
                    local ammo_noun
                    if type(flag_val) == "table" then
                        ammo_noun = flag_val[1] or flag_val.ammo
                    else
                        -- Extract first capture from raw string match.
                        ammo_noun = tostring(flag_val):match("(" .. AMMO_NOUNS .. ")s?")
                    end
                    if ammo_noun then
                        self:_stow_ammo(ammo_noun, 1)
                    end
                    Flags.reset("ct-powershot-ammo")
                    -- When dual-loading, powershot only fires one arrow — fire the second.
                    if game_state:dual_load_p() then
                        self:_shoot_aimed("shoot", game_state)
                    end
                    game_state.loaded  = false
                    self._firing_check = 0
                end
                game_state:action_taken()
            else
                -- Begin aiming sequence.
                game_state:set_aim_queue()
                self:_aim(game_state)
                Flags.reset("ct-ranged-ready")
            end
        end
    end
end

--- Abort the aimed attack path (out of ammo or unrecoverable load failure).
-- Switches to dancing until the weapon rotation moves on.
function M:_abort_attack_aimed(game_state)
    DRC.message("Unable to load " .. (game_state:weapon_name() or "weapon")
        .. ", you may be out of ammunition, dancing until can switch to next weapon")
    game_state.loaded  = false
    self._firing_check = 0
    game_state:clear_aim_queue()
    self:_dance(game_state)
    -- Advance action counter far enough to trigger a weapon switch.
    game_state:action_taken(99)
end

--- Execute a single offhand attack action during the aiming-trainables phase.
-- Returns true if the outer loop should continue, false to break.
function M:_execute_aiming_action(action, game_state)
    local result = DRC.bput(action,
        "Roundtime",
        "close enough",
        "What are you",
        "There is nothing",
        "must be closer",
        "Bumbling, you slip")

    if result:match("close enough") or result:match("must be closer") then
        if not game_state:can_engage() then return false end
        game_state:engage()
    elseif result:match("What are you") or result:match("There is nothing") then
        -- Whip can "miss" into thin air — face next instead of aborting.
        if not action:find("whip") then return false end
        fput("face next")
        return false
    end

    return true
end

---------------------------------------------------------------------------
-- Firing timer helpers
---------------------------------------------------------------------------

--- Advance the internal firing timer. Called after each successful aim.
-- The first aim after a fresh load sets @firing_timer = now + delay.
-- Each subsequent aim call decrements the timer by one second so that
-- additional aim fillers erode the delay as expected.
function M:_check_firing_time()
    self._firing_check = self._firing_check + 1
    if self._firing_check == 1 then
        self._firing_timer = os.time() + self._firing_delay
    end
    self._firing_timer = self._firing_timer - 1
end

---------------------------------------------------------------------------
-- Aim command
---------------------------------------------------------------------------

--- Issue the AIM command and handle all possible responses.
function M:_aim(game_state)
    local result = DRC.bput("aim",
        "You are already",
        "You begin to target",
        "You shift your target",
        "In one electrifying moment",   -- Syamelyo Kuniyo spell effect
        "In one frozen moment",          -- Syamelyo Kuniyo spell effect
        "isn't loaded",
        "You don't have a ranged weapon to aim with",
        "There is nothing else",
        "Face what",
        "Strangely, you don't feel like fighting right now",
        "You don't seem to be able to move to do that")

    if result:match("You are already")
        or result:match("You begin to target")
        or result:match("You shift your target")
        or result:match("In one .* moment") then
        game_state.loaded = true
        self:_check_firing_time()

    elseif result:match("isn't loaded")
        or result:match("You don't have a ranged weapon") then
        game_state.loaded  = false
        self._firing_check = 0

    elseif result:match("There is nothing else") or result:match("Face what") then
        game_state:clear_aim_queue()

    elseif result:match("Strangely") or result:match("You don't seem to be able to move") then
        pause(1)
        self:_aim(game_state)

    else
        game_state.loaded  = false
        self._firing_check = 0
    end
end

---------------------------------------------------------------------------
-- Shoot (execute the fire command)
---------------------------------------------------------------------------

--- Issue the fire/poach/snipe command and handle all responses.
function M:_shoot_aimed(command, game_state)
    Flags.reset("ct-ranged-ammo")

    local result = DRC.bput(command,
        "you (fire|poach|snipe)",
        "isn't loaded",
        "There is nothing",
        "But your",
        "I could not find",
        "with no effect and falls (to the ground|to your feet)",
        "Face what",
        "How can you (poach|snipe)",
        "you don't feel like fighting right now",
        "That weapon must be in your right hand to fire",
        "But you don't have a ranged weapon in your hand to fire with")
    waitrt()

    if result:match("How can you (poach|snipe)") then
        -- Fall back to plain shoot when poach/snipe is invalid here.
        self:_shoot_aimed("shoot", game_state)

    elseif result:match("That weapon must be in your right hand")
        or result:match("But you don't have a ranged weapon in your hand to fire with") then
        -- Explicitly use "swap right" so riste and similar weapons move hands,
        -- not switch modes.
        local swap_result = fput("swap right")
        if swap_result and swap_result:match("You (swap|move)") then
            self:_shoot_aimed(command, game_state)
        end

    elseif result:match("you don't feel like fighting right now") then
        pause(1)
        self:_shoot_aimed(command, game_state)

    elseif result:match("with no effect and falls") then
        -- Fired an unblessed weapon at an incorporeal undead — still counts as action.
        game_state:action_taken()

    elseif result:match("you (fire|poach|snipe)") then
        game_state:action_taken()
    end

    -- Stow any ammo that was not lodged in the target.
    if Flags["ct-ranged-ammo"] then
        local flag_val  = Flags["ct-ranged-ammo"]
        local ammo_noun
        if type(flag_val) == "table" then
            -- Captures stored as subtable; ammo is the 4th capture group
            -- (the full capture order: action, prefix, ammo, ...).
            ammo_noun = flag_val[3] or flag_val.ammo or flag_val[1]
        else
            ammo_noun = tostring(flag_val):match("(" .. AMMO_NOUNS .. ")s?")
        end
        if ammo_noun then
            self._firing_check = 0
            local qty = game_state:dual_load_p() and 2 or 1
            self:_stow_ammo(ammo_noun, qty)
        end
        Flags.reset("ct-ranged-ammo")
    end
end

---------------------------------------------------------------------------
-- Dance (filler movement when not attacking)
---------------------------------------------------------------------------

--- Perform one dance action. Engages if possible, otherwise waits.
function M:_dance(game_state)
    if game_state:can_engage() then
        game_state:set_dance_queue()
        local action = game_state:next_dance_action()
        if action then
            local result = DRC.bput(action,
                "You must be closer",
                "There is nothing else",
                "What are you trying",
                ".*")
            if result:match("You must be closer")
                or result:match("There is nothing else")
                or result:match("What are you trying") then
                game_state:engage()
            end
        end
    elseif not game_state:retreating_p() then
        pause(1)
    end
end

---------------------------------------------------------------------------
-- Ammo stow helper
---------------------------------------------------------------------------

--- Recursively stow ammo by noun until quantity is exhausted or no match.
-- @param ammo     string  The ammo noun (e.g. "bolt", "stone shard")
-- @param quantity number  How many to stow
function M:_stow_ammo(ammo, quantity)
    if not ammo then return end
    if not quantity or quantity <= 0 then return end

    -- For multi-word ammo names, use first + last word only so that adjectives
    -- (e.g. "matte indurium sphere") become "matte sphere".
    local parts = {}
    for word in ammo:gsub("^%s+", ""):gsub("%s+$", ""):gmatch("%S+") do
        table.insert(parts, word)
    end
    local ref
    if #parts <= 1 then
        ref = ammo
    elseif parts[1] == parts[#parts] then
        ref = parts[1]
    else
        ref = parts[1] .. " " .. parts[#parts]
    end

    local result = DRC.bput("stow my " .. ref,
        "You pick up",
        "You put your",
        "Stow what",
        "needs to be tended to be removed",
        "You need a free hand",
        "As you reach for a glowing")

    if result:match("You pick up") or result:match("You put your") then
        self:_stow_ammo(ref, quantity - 1)
    elseif result:match("Stow what") then
        -- Bug fix: game may print plural form (e.g. "arrows") when only one
        -- was fired. Strip the trailing 's' and retry.
        if ref:sub(-1) == "s" then
            self:_stow_ammo(ref:sub(1, -2), quantity)
        end
    end
end

return M
