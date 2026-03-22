--- TrainerProcess — passive skill training for combat-trainer.
-- Ported from TrainerProcess class in combat-trainer.lic
-- Original authors: Ondreian and elanthia-online community contributors
-- Handles: meditate, pray, hide, teach, appraisal, astro, favor orb,
--          almanac, tessera, summoning domains, barbarian research/berserks,
--          khri prowess, ambush, analyze, tactics, recall, collect, smite,
--          moon mage perception, locksmithing, and more.

local defs = require("defs")

local TrainerProcess = {}
TrainerProcess.__index = TrainerProcess

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function TrainerProcess.new(settings, equipment_manager)
    local self = setmetatable({}, TrainerProcess)

    self._equip_mgr = equipment_manager

    -- Core settings
    self.combat_training_abilities          = settings.combat_training_abilities or {}
    self.combat_training_abilities_target   = settings.combat_training_abilities_target or 34
    self.stun_skill                         = settings.stun_skill or "Stealth"
    self.favor_god                          = settings.favor_god
    self.favor_orb                          = settings.favor_orb
    self.combat_teaching_skill              = settings.combat_teaching_skill
    self.forage_item                        = settings.forage_item
    self.inner_fire_threshold               = settings.inner_fire_threshold or 25
    self.berserk_inner_fire_threshold       = settings.berserk_inner_fire_threshold or 25
    self.npc_to_recall                      = settings.npc_to_recall
    self.lunar_magic_enabled                = settings.lunar_magic_enabled or false

    -- Moon mage prediction settings
    self.predict_events                     = settings.predict_events or {}
    self.check_heavens_verbs                = settings.check_heavens_verbs or {"glance"}
    self.determine_time_enabled             = settings.determine_time_enabled or false

    -- Almanac settings
    self.almanac_abilities                  = settings.almanac_abilities or {}
    self.almanac_container                  = settings.almanac_container
    self.almanac_pouch                      = settings.almanac_pouch

    -- Tessera settings
    self.tessera_currency                   = settings.tessera_currency or "lirums"
    self.tessera_amounts                    = settings.tessera_amounts or {1, 5, 10, 20}
    self.tessera_target                     = settings.tessera_target
    self.tessera_container                  = settings.tessera_container

    -- Summoning domain settings
    self.summoning_domains                  = settings.summoning_domains or {}

    -- Barbarian settings
    self.barb_research_interval             = settings.barb_research_interval or 60
    self._last_barb_research                = {}

    -- Khri settings
    self.khri_prowess_type                  = settings.khri_prowess_type or "prowess"

    -- Smite settings (Paladin Conviction)
    self.smite_target                       = settings.smite_target

    -- Prayer mat settings
    self.pray_mat_prayer                    = settings.pray_mat_prayer
    self.pray_mat_noun                      = settings.pray_mat_noun or "mat"

    -- Appraisal settings
    self.app_quick_enabled                  = settings.app_quick or false
    self.app_careful_enabled                = settings.app_careful or false
    self.app_pouch_noun                     = settings.app_pouch_noun or "pouch"
    self.app_bundle_noun                    = settings.app_bundle_noun or "bundle"

    -- Skill map: ability name → DR skill name for XP checking
    self.skill_map = {
        ["Almanac"]               = "Anything",
        ["Ambush Choke"]          = "Debilitation",
        ["Ambush Stun"]           = self.stun_skill,
        ["Analyze"]               = "Tactics",
        ["App Bundle"]            = "Appraisal",
        ["App Careful"]           = "Appraisal",
        ["App Pouch"]             = "Appraisal",
        ["App Quick"]             = "Appraisal",
        ["App"]                   = "Appraisal",
        ["Astro"]                 = "Astrology",
        ["Barb Research Augmentation"] = "Augmentation",
        ["Barb Research Utility"] = "Utility",
        ["Barb Research Warding"] = "Warding",
        ["Berserk Landslide"]     = "Warding",
        ["Berserk Avalanche"]     = "Utility",
        ["Charged Maneuver"]      = "Expertise",
        ["Collect"]               = "Outdoorsmanship",
        ["Favor Orb"]             = "Anything",
        ["Flee"]                  = "Athletics",
        ["Hunt"]                  = "Perception",
        ["Khri Prowess"]          = "Debilitation",
        ["Meraud"]                = "Theurgy",
        ["Perc Health"]           = "Empathy",
        ["Perc"]                  = "Attunement",
        ["PercMana"]              = "Attunement",
        ["Pray"]                  = "Theurgy",
        ["PrayerMat"]             = "Theurgy",
        ["Recall"]                = "Scholarship",
        ["Scream"]                = "Bardic Lore",
        ["Smite"]                 = "Conviction",
        ["Stealth"]               = "Stealth",
        ["Tactics"]               = "Tactics",
        ["Teach"]                 = "Scholarship",
        ["Tessera"]               = "Trading",
        ["Locksmithing"]          = "Locksmithing",
    }

    -- Rangers track Hunt for Perception AND Instinct
    if DRStats.ranger then
        self.skill_map["Hunt"] = "Perception"  -- primary; instinct checked separately
        self._hunt_ranger = true
    end

    -- Cooldown timers for rate-limited abilities
    self._cooldown_timers = {}

    return self
end

-- ---------------------------------------------------------------------------
-- Public entry point
-- ---------------------------------------------------------------------------

--- Execute one round of passive training.
-- Called each loop iteration. Returns false (does not own the loop).
-- @param game_state table  GameState instance
function TrainerProcess:execute(game_state)
    if game_state.danger then return false end

    local ability = self:select_ability(game_state)
    if not ability then return false end

    self:_dispatch(ability, game_state)

    waitrt()
    return false
end

-- ---------------------------------------------------------------------------
-- Ability selection
-- ---------------------------------------------------------------------------

--- Choose the next passive ability to train.
-- Returns ability name string or nil if nothing is ready.
function TrainerProcess:select_ability(game_state)
    for _, ability in ipairs(self.combat_training_abilities) do
        if self:check_ability(ability, game_state) then
            return ability
        end
    end
    return nil
end

--- Return true if the given ability should be trained right now.
function TrainerProcess:check_ability(ability, game_state)
    -- PercMana (Moon Mage perc) skipped while casting
    if ability == "PercMana" and game_state.casting then
        return false
    end

    -- App Careful skipped while casting
    if ability == "App Careful" and game_state.casting then
        return false
    end

    -- Berserk abilities require sufficient inner fire
    if string.match(ability, "^Berserk") then
        local threshold = self.berserk_inner_fire_threshold
        if DRStats.inner_fire and DRStats.inner_fire < threshold then
            return false
        end
    end

    -- Barbarian research needs enough inner fire
    if string.match(ability, "^Barb Research") then
        local threshold = self.inner_fire_threshold
        if DRStats.inner_fire and DRStats.inner_fire < threshold then
            return false
        end
        -- Also check time since last research attempt
        local last = self._last_barb_research[ability]
        if last and (os.time() - last) < self.barb_research_interval then
            return false
        end
    end

    -- Cooldown check via game_state.cooldown_timers
    local cooldown = game_state.cooldown_timers and game_state.cooldown_timers[ability]
    if cooldown then
        local elapsed = os.time() - cooldown
        local required = self:_ability_cooldown(ability)
        if elapsed < required then
            return false
        end
    end

    -- XP check: only train if skill has room to grow
    local skill = self:_resolve_skill(ability)
    if skill and skill ~= "Anything" then
        -- For ranger Hunt, check both Perception and Instinct
        if ability == "Hunt" and self._hunt_ranger then
            local perc_xp    = DRSkill.getxp("Perception") or 34
            local instinct_xp = DRSkill.getxp("Instinct") or 34
            if perc_xp >= self.combat_training_abilities_target
               and instinct_xp >= self.combat_training_abilities_target then
                return false
            end
        else
            local xp = DRSkill.getxp(skill) or 34
            if xp >= self.combat_training_abilities_target then
                return false
            end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Action dispatch
-- ---------------------------------------------------------------------------

--- Route ability name to the appropriate handler.
function TrainerProcess:_dispatch(ability, game_state)
    -- Moon Mage mana perception
    if ability == "PercMana" then
        self:moon_mage_perc(game_state)

    -- Standard attunement perception
    elseif ability == "Perc" then
        DRC.bput("perc",
            "you sense", "You sense", "You perceive", "pulsing energy",
            "flows through you", "hum of",
            "nothing special", "You don't sense")
        waitrt()

    -- Empathy / health perception
    elseif ability == "Perc Health" then
        DRC.bput("perc heal",
            "You sense", "You perceive", "nothing",
            "You are not currently")
        waitrt()

    -- Astrology
    elseif ability == "Astro" then
        self:astrology(game_state)

    -- Flee/Athletics training
    elseif ability == "Flee" then
        local result = DRC.bput("flee",
            "You run", "You flee", "You scramble",
            "You don't seem to be", "Where do you think",
            "You bluff", "attempting to flee",
            "Roundtime")
        waitrt()
        if result and (result:match("You run") or result:match("You flee")
                       or result:match("You scramble") or result:match("You bluff")) then
            -- Bluff or actual flee — re-engage
            game_state:engage()
        end

    -- Standard appraisal (object in hand or nearby)
    elseif ability == "App" then
        self:appraise(game_state, "")

    -- Quick appraisal
    elseif ability == "App Quick" then
        self:appraise(game_state, "quick")

    -- Careful appraisal
    elseif ability == "App Careful" then
        self:appraise(game_state, "careful")

    -- Appraise gem pouch
    elseif ability == "App Pouch" then
        local result = DRC.bput("appraise my " .. self.app_pouch_noun,
            "You carefully inspect",
            "appraise what", "You don't seem",
            "Roundtime")
        waitrt()
        _ = result  -- suppress unused warning

    -- Appraise bundle
    elseif ability == "App Bundle" then
        local result = DRC.bput("appraise my " .. self.app_bundle_noun,
            "You carefully inspect",
            "appraise what", "You don't seem",
            "Roundtime")
        waitrt()
        _ = result

    -- Summon elemental domain
    elseif string.match(ability, "Summon .* Domain") or string.match(ability, "summoning domain") then
        local domain_name = string.match(ability, "Summon (.*) Domain")
                         or string.match(ability, "summoning domain (.*)")
                         or ability
        DRC.bput("summon " .. domain_name .. " domain",
            "You gesture", "You attempt", "You call", "already summoned",
            "You must be", "Roundtime")
        waitrt()

    -- Tactics actions (bob/weave/circle)
    elseif ability == "Tactics" then
        local actions = defs.TACTICS_ACTIONS
        local action = actions[math.random(#actions)]
        DRC.bput(action,
            "You bob", "You weave", "You circle",
            "Roundtime", "You can't do that")
        waitrt()

    -- Analyze (Barbarian/Tactics)
    elseif ability == "Analyze" then
        self:analyze(game_state)

    -- Hunt
    elseif ability == "Hunt" then
        DRC.bput("hunt",
            "You scan", "You search", "You look around",
            "You don't notice", "Roundtime")
        waitrt()

    -- Teach combat skill to friends
    elseif ability == "Teach" then
        self:_teach_action(game_state)

    -- Pray to favor god
    elseif ability == "Pray" then
        self:_pray_action(game_state)

    -- Bard scream
    elseif ability == "Scream" then
        DRC.bput("Scream conc",
            "You let out", "You open your mouth", "You focus",
            "Roundtime", "You are not")
        waitrt()

    -- Thief khri prowess
    elseif ability == "Khri Prowess" then
        self:_khri_prowess_action(game_state)

    -- Standard stealth hide
    elseif ability == "Stealth" then
        self:hide_action(game_state)

    -- Retreat then hide
    elseif ability == "Ret Stealth" or ability == "Retreat Stealth" then
        DRC.bput("retreat",
            "You begin to retreat", "You are already retreating",
            "You slip away", "Roundtime",
            "There is nothing", "you can't retreat")
        waitrt()
        self:hide_action(game_state)

    -- Ambush stun
    elseif ability == "Ambush Stun" then
        self:ambush_stun(game_state)

    -- Ambush choke
    elseif ability == "Ambush Choke" then
        self:ambush_choke(game_state)

    -- Favor orb
    elseif ability == "Favor Orb" then
        local orb_noun = self.favor_orb or "orb"
        DRC.bput("rub my " .. orb_noun,
            "You rub", "The orb glows", "You hold",
            "orb to be empty", "You don't have",
            "Roundtime")
        waitrt()

    -- Charged maneuvers (signal to use next combat round)
    elseif ability == "Charged Maneuver" then
        game_state.use_charged_maneuvers = true

    -- Meraud commune (cleric)
    elseif ability == "Meraud" then
        self:meraud_commune(game_state)

    -- Prayer mat
    elseif ability == "PrayerMat" then
        self:pray_mat(game_state)

    -- Recall NPC
    elseif ability == "Recall" then
        local target = self.npc_to_recall
        if target then
            DRC.bput("recall " .. target,
                "You recall", "You think", "You remember",
                "recall what", "Roundtime")
            waitrt()
        end

    -- Barbarian research: Augmentation → monkey
    elseif ability == "Barb Research Augmentation" then
        self._last_barb_research[ability] = os.time()
        DRC.bput("meditate research monkey",
            "You begin", "You continue", "already meditating",
            "You must be", "Roundtime")
        waitrt()

    -- Barbarian research: Warding → turtle
    elseif ability == "Barb Research Warding" then
        self._last_barb_research[ability] = os.time()
        DRC.bput("meditate research turtle",
            "You begin", "You continue", "already meditating",
            "You must be", "Roundtime")
        waitrt()

    -- Barbarian research: Utility → prediction
    elseif ability == "Barb Research Utility" then
        self._last_barb_research[ability] = os.time()
        DRC.bput("meditate research prediction",
            "You begin", "You continue", "already meditating",
            "You must be", "Roundtime")
        waitrt()

    -- Berserk Landslide
    elseif ability == "Berserk Landslide" then
        DRCA.activate_barb_buff("Landslide")

    -- Berserk Avalanche
    elseif ability == "Berserk Avalanche" then
        DRCA.activate_barb_buff("Avalanche")

    -- Collect foraged item
    elseif ability == "Collect" then
        self:_collect_action(game_state)

    -- Almanac trading skill
    elseif ability == "Almanac" then
        self:use_almanac(game_state)

    -- Locksmithing delegation
    elseif ability == "Locksmithing" then
        DRC.wait_for_script_to_complete("locksmithing", {"once"})

    -- Paladin smite
    elseif ability == "Smite" then
        self:smite(game_state)

    -- Herbs / healing
    elseif ability == "Herbs" then
        DRC.wait_for_script_to_complete("heal-remedy")

    -- Tessera investing
    elseif ability == "Tessera" then
        self:invest_in_tessera(game_state)

    else
        echo("TrainerProcess: unknown ability '" .. tostring(ability) .. "'")
    end
end

-- ---------------------------------------------------------------------------
-- hide_action
-- ---------------------------------------------------------------------------

--- Attempt to hide. Handles already-hidden case and position checks.
function TrainerProcess:hide_action(game_state)
    if hidden() then return end

    local result = DRC.bput("hide",
        "You slip into",
        "You settle into",
        "You are already hidden",
        "You can't hide",
        "You duck behind",
        "You press yourself",
        "Roundtime")
    waitrt()

    -- If we couldn't hide, no further action needed
    _ = result
end

-- ---------------------------------------------------------------------------
-- almanac helpers
-- ---------------------------------------------------------------------------

--- Sort almanac abilities: lowest learning rate first, then lowest rank.
-- Mirrors almanac_sort_by_rate_then_rank in Ruby.
function TrainerProcess:almanac_sort_by_rate_then_rank(abilities)
    local scored = {}
    for _, ability in ipairs(abilities) do
        local skill = self:_resolve_skill(ability) or ability
        table.insert(scored, {
            ability = ability,
            xp      = DRSkill.getxp(skill) or 0,
            rank    = DRSkill.getrank(skill) or 0,
        })
    end
    table.sort(scored, function(a, b)
        if a.xp ~= b.xp then return a.xp < b.xp end
        return a.rank < b.rank
    end)
    local result = {}
    for _, s in ipairs(scored) do
        table.insert(result, s.ability)
    end
    return result
end

--- Return the ability whose mapped skill has the lowest mindstate (XP).
function TrainerProcess:skill_with_lowest_mindstate(abilities)
    local sorted = self:almanac_sort_by_rate_then_rank(abilities)
    return sorted[1]
end

--- Use almanac to train trading/scholarship.
-- Opens almanac, reads entries relevant to lowest-mindstate ability.
function TrainerProcess:use_almanac(game_state)
    local container = self.almanac_container
    local pouch     = self.almanac_pouch

    if not container and not pouch then
        echo("TrainerProcess: almanac_container or almanac_pouch not set")
        return
    end

    -- Find the almanac
    local get_cmd
    if pouch then
        get_cmd = "get almanac from my " .. pouch
    else
        get_cmd = "get almanac from my " .. container
    end

    local got = DRC.bput(get_cmd,
        "You remove", "You get",
        "What were you", "I could not find")
    if not got or got:match("What were you") or got:match("I could not find") then
        echo("TrainerProcess: could not retrieve almanac")
        return
    end

    -- Read the almanac
    local result = DRC.bput("read my almanac",
        "You read",
        "It reads",
        "You flip",
        "Roundtime",
        "don't have")
    waitrt()
    _ = result

    -- Put it back
    local put_cmd
    if pouch then
        put_cmd = "put almanac in my " .. pouch
    else
        put_cmd = "put almanac in my " .. container
    end
    DRC.bput(put_cmd,
        "You put", "You place",
        "What were you")
end

-- ---------------------------------------------------------------------------
-- smite
-- ---------------------------------------------------------------------------

--- Paladin Conviction: smite target.
function TrainerProcess:smite(game_state)
    local target = self.smite_target
    if not target then
        -- Fall back to first NPC in room
        local npcs = game_state:npcs()
        target = npcs[1]
    end
    if not target then return end

    local result = DRC.bput("smite " .. target,
        "You raise",
        "You call",
        "Your conviction",
        "smite what",
        "There is nothing",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- meraud_commune
-- ---------------------------------------------------------------------------

--- Cleric: commune with Meraud for Theurgy training.
function TrainerProcess:meraud_commune(game_state)
    local result = DRC.bput("commune meraud",
        "You reach out",
        "You close your eyes",
        "The faint smell",
        "You feel a presence",
        "You do not feel",
        "commune what",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- pray_mat
-- ---------------------------------------------------------------------------

--- Use prayer mat to pray for Theurgy training.
function TrainerProcess:pray_mat(game_state)
    local mat_noun = self.pray_mat_noun or "mat"
    local prayer   = self.pray_mat_prayer

    -- Get prayer mat
    local got = DRC.bput("get my " .. mat_noun,
        "You pick up", "You get",
        "What were you", "I could not find")
    if got and (got:match("What were you") or got:match("I could not find")) then
        echo("TrainerProcess: could not retrieve prayer mat")
        return
    end

    -- Kneel
    DRC.bput("kneel",
        "You kneel", "You are already kneeling",
        "Roundtime")
    waitrt()

    -- Pray on mat
    local pray_cmd
    if prayer then
        pray_cmd = "pray " .. prayer .. " on my " .. mat_noun
    else
        pray_cmd = "pray on my " .. mat_noun
    end
    local result = DRC.bput(pray_cmd,
        "You kneel",
        "You begin",
        "You pray",
        "You offer",
        "Roundtime",
        "don't have")
    waitrt()
    _ = result

    -- Stand back up
    DRC.bput("stand",
        "You stand", "You are already standing",
        "Roundtime")
    waitrt()

    -- Put mat away
    DRC.bput("put my " .. mat_noun .. " in my pack",
        "You put", "You place",
        "What were you")
end

-- ---------------------------------------------------------------------------
-- ambush_stun
-- ---------------------------------------------------------------------------

--- Thief ambush stun attempt.
function TrainerProcess:ambush_stun(game_state)
    local npcs = game_state:npcs()
    if #npcs == 0 then return end

    if not hidden() then
        self:hide_action(game_state)
        if not hidden() then return end
    end

    local target = npcs[1]
    local result = DRC.bput("ambush " .. target .. " stun",
        "You leap",
        "You attempt",
        "You strike",
        "You swing",
        "You can't do that",
        "must be hidden",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- ambush_choke
-- ---------------------------------------------------------------------------

--- Thief ambush choke attempt.
function TrainerProcess:ambush_choke(game_state)
    local npcs = game_state:npcs()
    if #npcs == 0 then return end

    if not hidden() then
        self:hide_action(game_state)
        if not hidden() then return end
    end

    local target = npcs[1]
    local result = DRC.bput("ambush " .. target .. " choke",
        "You grab",
        "You attempt",
        "You lunge",
        "You can't do that",
        "must be hidden",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- analyze
-- ---------------------------------------------------------------------------

--- Barbarian analyze for Tactics training.
function TrainerProcess:analyze(game_state)
    local npcs = game_state:npcs()
    if #npcs == 0 then return end

    -- Use combo array if enabled
    if game_state.use_analyze_combos and #game_state.analyze_combo_array > 0 then
        local combo = table.remove(game_state.analyze_combo_array, 1)
        local result = DRC.bput("analyze " .. combo,
            "You analyze",
            "You study",
            "Roundtime",
            "analyze what")
        waitrt()
        _ = result
        return
    end

    local target = npcs[1]
    local result = DRC.bput("analyze " .. target,
        "You analyze",
        "You study",
        "You observe",
        "Roundtime",
        "analyze what",
        "There is nothing")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- appraise
-- ---------------------------------------------------------------------------

--- Appraise an item. mode = "" | "quick" | "careful"
function TrainerProcess:appraise(game_state, mode)
    -- Build appraise command
    local cmd
    if mode and mode ~= "" then
        cmd = "appraise " .. mode
    else
        cmd = "appraise"
    end

    -- Try to appraise something in hand first; if nothing, use a nearby object
    local target = DRC.right_hand or DRC.left_hand
    if target then
        cmd = cmd .. " my " .. target
    end

    local result = DRC.bput(cmd,
        "You carefully inspect",
        "You quickly inspect",
        "You inspect",
        "You glance",
        "appraise what",
        "You don't seem",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- moon_mage_perc
-- ---------------------------------------------------------------------------

--- Moon Mage Attunement: perceive mana.
function TrainerProcess:moon_mage_perc(game_state)
    local result = DRC.bput("perc mana",
        "you sense",
        "You sense",
        "flows through",
        "pulsing energy",
        "don't sense")
    waitrt()
    _ = result

    -- If lunar magic enabled, also run prediction cycle
    if self.lunar_magic_enabled then
        self:check_predict(game_state)
    end
end

-- ---------------------------------------------------------------------------
-- astrology
-- ---------------------------------------------------------------------------

--- Moon Mage astrology sequence: check heavens, determine time, observe, predict.
function TrainerProcess:astrology(game_state)
    self:check_heavens(game_state)
    self:determine_time(game_state)
    self:observe(game_state)
    self:check_predict(game_state)
end

--- Check the heavens with the configured verb(s).
function TrainerProcess:check_heavens(game_state)
    local verbs = self.check_heavens_verbs
    if not verbs or #verbs == 0 then verbs = {"glance"} end

    for _, verb in ipairs(verbs) do
        local result = DRC.bput(verb .. " sky",
            "You glance",
            "You look",
            "The sky",
            "glance at what",
            "Roundtime")
        waitrt()
        if result and not result:match("Roundtime") then
            break
        end
    end
end

--- Determine the time astronomically.
function TrainerProcess:determine_time(game_state)
    if not self.determine_time_enabled then return end

    local result = DRC.bput("determine time",
        "You gaze",
        "After careful study",
        "determine what",
        "Roundtime")
    waitrt()
    _ = result
end

--- Observe celestial bodies for Astrology XP.
function TrainerProcess:observe(game_state)
    local result = DRC.bput("observe",
        "You look",
        "You study",
        "You observe",
        "There is nothing",
        "observe what",
        "Roundtime")
    waitrt()
    _ = result
end

--- Check if we have a predict ready to execute.
function TrainerProcess:check_predict(game_state)
    if not self.predict_events or #self.predict_events == 0 then return end

    -- Try each configured predict event
    for _, event in ipairs(self.predict_events) do
        local ready = DRC.bput("predict " .. event .. " check",
            "You will be able",
            "The omens do not",
            "not currently",
            "predict what",
            "Roundtime")
        waitrt()
        if ready and ready:match("You will be able") then
            self:execute_predict(event, game_state)
            return
        end
    end
end

--- Execute a queued prediction.
function TrainerProcess:execute_predict(event, game_state)
    local result = DRC.bput("predict " .. event,
        "You predict",
        "The stars foretell",
        "Predict as you might",
        "predict what",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- center (Moon Mage: center mana)
-- ---------------------------------------------------------------------------

--- Center mana pool (Moon Mage cyclic reset helper).
function TrainerProcess:center(game_state)
    local result = DRC.bput("center",
        "You reach",
        "You draw",
        "center what",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- invest_in_tessera
-- ---------------------------------------------------------------------------

--- Invest coins in tessera for Trading XP.
function TrainerProcess:invest_in_tessera(game_state)
    local target    = self.tessera_target
    local amounts   = self.tessera_amounts
    local currency  = self.tessera_currency
    local container = self.tessera_container

    if not target then
        echo("TrainerProcess: tessera_target not configured")
        return
    end

    -- Pick invest amount: lowest that still gives XP, cycling through configured list
    local amount = amounts[math.random(#amounts)]

    -- Optionally retrieve coins from container
    if container then
        DRC.bput("get " .. tostring(amount) .. " " .. currency .. " from my " .. container,
            "You remove", "You get",
            "not enough", "What were you")
    end

    local result = DRC.bput("invest " .. tostring(amount) .. " " .. currency .. " in " .. target,
        "You invest",
        "You place",
        "invest what",
        "don't have",
        "Roundtime")
    waitrt()
    _ = result
end

-- ---------------------------------------------------------------------------
-- reset_ability
-- ---------------------------------------------------------------------------

--- Reset the cooldown timer for an ability so it is eligible again immediately.
function TrainerProcess:reset_ability(ability, game_state)
    if game_state.cooldown_timers then
        game_state.cooldown_timers[ability] = nil
    end
    self._cooldown_timers[ability] = nil
end

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

--- Resolve the DR skill name for a given ability string.
-- Returns the skill name, or nil if not in the map.
function TrainerProcess:_resolve_skill(ability)
    return self.skill_map[ability]
end

--- Return the cooldown duration (seconds) for a given ability.
function TrainerProcess:_ability_cooldown(ability)
    -- Most abilities have no explicit cooldown; Berserk abilities need a longer gap
    if string.match(ability, "^Berserk") then return 60 end
    if string.match(ability, "^Barb Research") then return self.barb_research_interval end
    if ability == "Khri Prowess" then return 30 end
    if ability == "Smite" then return 10 end
    if ability == "Meraud" then return 30 end
    if ability == "Tessera" then return 5 end
    return 0
end

--- Teach combat skill to a friend in the room.
function TrainerProcess:_teach_action(game_state)
    local skill = self.combat_teaching_skill
    if not skill then
        echo("TrainerProcess: combat_teaching_skill not configured")
        return
    end

    -- Find a friend in the room
    local friends = UserVars.friends or {}
    local pcs     = DRRoom.pcs or {}

    local student = nil
    for _, pc in ipairs(pcs) do
        for _, friend in ipairs(friends) do
            if pc:lower() == friend:lower() then
                student = pc
                break
            end
        end
        if student then break end
    end

    if not student then return end

    local result = DRC.bput("teach " .. skill .. " to " .. student,
        "You begin",
        "You teach",
        "already being taught",
        "don't know enough",
        "teach what",
        "Roundtime")
    waitrt()
    _ = result
end

--- Pray to the configured favor god.
function TrainerProcess:_pray_action(game_state)
    local god = self.favor_god
    if not god then
        echo("TrainerProcess: favor_god not configured")
        return
    end

    local result = DRC.bput("pray " .. god,
        "You bow your head",
        "You kneel",
        "You close your eyes",
        "You raise your hands",
        "You feel a warmth",
        "You feel the presence",
        "You beseech",
        "prayer is heard",
        "Your prayer falls",
        "doesn't seem to hear you",
        "You already prayed",
        "must wait",
        "don't need to pray",
        "Roundtime")
    waitrt()
    _ = result
end

--- Execute Khri Prowess activation. Handles kneel if needed.
function TrainerProcess:_khri_prowess_action(game_state)
    local result = DRC.bput("khri " .. self.khri_prowess_type,
        "Your body",
        "You focus",
        "You already",
        "must be kneeling",
        "Roundtime")
    waitrt()

    -- If we need to kneel first
    if result and result:match("must be kneeling") then
        DRC.bput("kneel",
            "You kneel", "You are already kneeling",
            "Roundtime")
        waitrt()

        result = DRC.bput("khri " .. self.khri_prowess_type,
            "Your body",
            "You focus",
            "You already",
            "Roundtime")
        waitrt()

        -- Stand back up after activating
        DRC.bput("stand",
            "You stand", "You are already standing",
            "Roundtime")
        waitrt()
    end
    _ = result
end

--- Collect / forage for item.
function TrainerProcess:_collect_action(game_state)
    local item = self.forage_item
    if not item then
        echo("TrainerProcess: forage_item not configured")
        return
    end

    local result = DRC.bput("collect " .. item,
        "You find",
        "You search",
        "You look around",
        "collect what",
        "Roundtime")
    waitrt()
    if result and result:match("You find") then
        -- Put foraged item away
        DRC.bput("put my " .. item .. " in my pack",
            "You put", "You place",
            "What were you")
    end
end

return TrainerProcess
