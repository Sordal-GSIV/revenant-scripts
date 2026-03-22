--- LootProcess — body disposal and item looting for combat-trainer.
-- Ported from LootProcess class in combat-trainer.lic
local defs = require("defs")

local M = {}
M.__index = M

function M.new(settings, equip_mgr)
    local self = setmetatable({}, M)
    self._equip_mgr = equip_mgr

    -- Skinning settings
    local skinning = settings.skinning or {}
    self._skin            = skinning.skin or false
    self._dissect         = skinning.dissect or false
    self._dissect_priority = skinning.dissect_priority
    self._dissect_for_thanatology = skinning.dissect_for_thanatology or false
    self._dissect_retry_once = skinning.dissect_retry_once or false
    self._arrange_for_dissect = skinning.arrange_for_dissect ~= false
    self._arrange_all     = skinning.arrange_all or false
    self._arrange_count   = skinning.arrange_all and 1 or (skinning.arrange_count or 0)
    self._tie_bundle      = skinning.tie_bundle or false
    self._arrange_types   = skinning.arrange_types or {}
    self._dissect_cycle_skills = {}
    if self._dissect_for_thanatology then table.insert(self._dissect_cycle_skills, "Thanatology") end
    if self._dissect then table.insert(self._dissect_cycle_skills, "First Aid") end
    if self._skin then table.insert(self._dissect_cycle_skills, "Skinning") end

    -- Loot settings
    self._lootables       = settings.lootables or {}
    self._loot_bodies     = settings.loot_bodies or false
    self._loot_specials   = settings.loot_specials or {}
    self._custom_loot_type = settings.custom_loot_type or ""
    self._dump_junk       = settings.dump_junk
    self._dump_item_count = settings.dump_item_count or 20
    self._dump_timer      = os.time() - 300
    self._last_rites      = settings.last_rites
    self._last_rites_timer = os.time() - 600
    self._loot_delay      = settings.loot_delay or 0
    self._loot_timer      = os.time() - self._loot_delay

    -- Box loot
    self._box_loot_limit  = settings.box_loot_limit
    self._current_box_count = 0
    if self._box_loot_limit then
        self._current_box_count = DRCI.count_all_boxes(settings)
    end

    -- Gem pouch settings
    self._gem_nouns       = {} -- from get_data('items').gem_nouns - approximation
    self._box_nouns       = {} -- from get_data('items').box_nouns
    self._tie_pouch       = settings.tie_gem_pouches
    self._spare_gem_pouch_container = settings.spare_gem_pouch_container
    self._full_pouch_container = settings.full_pouch_container
    self._gem_pouch_adjective = settings.gem_pouch_adjective
    self._gem_pouch_noun  = settings.gem_pouch_noun
    self._autoloot_container = settings.autoloot_container
    self._autoloot_gems   = settings.autoloot_gems
    self._autoloot_fill_gem_pouch_delay = settings.autoloot_fill_gem_pouch_delay or 60
    self._autoloot_fill_gem_pouch_timer = os.time()
    self._worn_trashcan   = settings.worn_trashcan
    self._worn_trashcan_verb = settings.worn_trashcan_verb

    -- Thanatology / necro settings
    local thanatology = settings.thanatology or {}
    self._ritual_type     = (thanatology.ritual_type or ""):lower()
    self._cycle_rituals   = self._ritual_type == "cycle"
    self._dissect_and_butcher = settings.dissect_and_butcher
    self._redeemed        = settings.necro_redeemed
    self._force_rituals   = settings.necro_force_rituals
    self._last_ritual     = nil
    self._necro_heal      = (thanatology.heal and (
        (settings.necromancer_healing or {})["Consumed Flesh"] or
        (settings.necromancer_healing or {})["Devour"])) or false
    self._necro_store     = thanatology.store or false
    self._necro_container = thanatology.harvest_container
    self._current_harvest_count = 0
    if self._necro_container then
        local items = DRC.rummage("C material", self._necro_container) or {}
        self._current_harvest_count = #items
    end
    self._necro_count     = thanatology.harvest_count or 0
    self._make_zombie     = (settings.zombie or {}).make
    self._make_bonebug    = (settings.bonebug or {}).make
    self._necro_corpse_priority = settings.necro_corpse_priority
    self._wound_level_threshold = (settings.necromancer_healing or {}).wound_level_threshold or 1

    -- Ritual patterns (approximation - real data from get_data('spells'))
    self._rituals = {
        arise    = {"You begin the ritual of Arise"},
        preserve = {"You begin the ritual of Preserve"},
        dissect  = {"You begin the ritual of Dissect", "You succeed in dissecting"},
        harvest  = {"You begin the ritual of Harvest"},
        consume  = {"You begin the ritual of Consume"},
        construct = {"Rituals do not work upon constructs"},
        butcher  = {"You carve", "You butcher"},
        failures = {"You can not perform", "You fail to", "That is not a valid"},
    }

    -- Register flags
    Flags.add("using-corpse",
        "begins arranging", "completes arranging",
        "kneels down briefly and draws a knife",
        "cruelly into the body and carving out a chunk",
        "makes additional cuts, purposeful but seemingly at random")
    Flags.add("pouch-full",
        "You think the .* is too full to fit another gem into",
        "You'd better tie it up before putting")
    Flags.add("container-full", "There isn't any more room")
    Flags.add("ct-successful-skin", "^You carefully fit .* into your bundle")

    return self
end

function M:execute(game_state)
    -- Dump junk check
    local room_objs = DRRoom.room_objs or {}
    local junk_count = 0
    for _, obj in ipairs(room_objs) do
        if type(obj) == "string" and obj:match("junk") then
            junk_count = junk_count + 3
        end
    end
    local effective_limit = self._dump_item_count - junk_count
    if self._dump_junk
       and (os.time() - self._dump_timer > 300)
       and #room_objs >= effective_limit then
        fput("DUMP JUNK")
        self._dump_timer = os.time()
    end

    -- Autoloot gem pouch refill
    if self._autoloot_container and self._autoloot_gems then
        self:_fill_pouch_with_autolooter(game_state)
    end

    game_state.mob_died = false

    self:_dispose_body(game_state)
    self:_stow_lootables(game_state)

    if (game_state.mob_died or #game_state:npcs() == 0) and game_state:finish_killing() then
        local tries = 0
        while tries < 15 do
            if not Flags["using-corpse"] then break end
            if #(DRRoom.dead_npcs or {}) == 0 then break end
            pause(1)
            tries = tries + 1
        end
        self:_stow_lootables(game_state)
        game_state:next_clean_up_step()
    end

    -- Bundle management
    if game_state.need_bundle and Flags["ct-successful-skin"] then
        if self._tie_bundle then
            DRC.bput("tie my bundle", "TIE the bundle again", "But this bundle has already been tied off")
            local result = DRC.bput("tie my bundle",
                "you tie the bundle", "But this bundle has already been tied off",
                "You don't seem to be able to do that right now")
            if result:match("you tie the bundle") or result:match("already been tied off") then
                -- adjust bundle
                local adj_done = false
                while not adj_done do
                    local adj = DRC.bput("adjust my bundle", "You adjust your .* bundle so that you can more easily")
                    if adj:match("adjust your") then
                        adj_done = true
                    else
                        if DRC.right_hand and DRC.left_hand then
                            DRCI.lower_item(DRC.left_hand)
                        end
                    end
                end
                game_state.need_bundle = false
            end
        else
            game_state.need_bundle = false
        end
    end

    if game_state:finish_spell_casting() or game_state:stowing() then
        return true
    end
    return false
end

function M:_fill_pouch_with_autolooter(game_state)
    if (os.time() - self._autoloot_fill_gem_pouch_timer) < self._autoloot_fill_gem_pouch_delay then return end
    if DRC.left_hand ~= nil and not game_state.currently_whirlwinding then return end
    if game_state.currently_whirlwinding then
        game_state:sheath_whirlwind_offhand()
    end
    DRCI.fill_gem_pouch_with_container(
        self._gem_pouch_adjective,
        self._gem_pouch_noun,
        self._autoloot_container,
        self._full_pouch_container,
        self._spare_gem_pouch_container,
        self._tie_pouch)
    self._autoloot_fill_gem_pouch_timer = os.time()
    if game_state.currently_whirlwinding then
        game_state:wield_whirlwind_offhand()
    end
end

function M:_stow_loot(item, game_state)
    Flags.reset("pouch-full")
    Flags.reset("container-full")

    local special = nil
    for _, s in ipairs(self._loot_specials) do
        if s.name == item then special = s; break end
    end
    if special and DRCI.get_item_unsafe(item) then
        if DRCI.put_away_item(item, special.bag) then return end
    end

    local result = DRC.bput("stow " .. item,
        "You pick up", "You put", "You get",
        "You need a free hand", "needs to be tended to be removed",
        "There isn't any more room", "You just can't",
        "push you over the item limit",
        "You stop as you realize the .* is not yours",
        "Stow what", "already in your inventory",
        "The .* is not designed to carry anything",
        "rapidly decays away", "cracks and rots away",
        "That can't be picked up")

    if result:match("already in your inventory") then
        -- Gem or box handling
        DRC.bput("stow gem",
            "You pick up", "You get", "You need a free hand",
            "You just can't", "push you over the item limit",
            "You stop as you realize", "Stow what", "already in your inventory")
    elseif result:match("You pick up") or result:match("You get") then
        if self._box_loot_limit then
            self._current_box_count = self._current_box_count + 1
        end
    end

    pause(0.25)

    if Flags["container-full"] then
        DRC.bput("drop " .. item, "You drop")
        game_state:unlootable(item)
    end

    if Flags["pouch-full"] then
        DRC.bput("drop my " .. item, "You drop", "What were")
        if not self._spare_gem_pouch_container then
            game_state:unlootable(item)
            return
        end
        -- Swap gem pouches
        local adj = self._gem_pouch_adjective or ""
        local noun = self._gem_pouch_noun or ""
        DRC.bput("remove my " .. adj .. " " .. noun, "You remove")
        if self._full_pouch_container then
            local put_result = DRC.bput(
                "put my " .. adj .. " " .. noun .. " in my " .. self._full_pouch_container,
                "You put", "too heavy to go in there")
            if put_result:match("too heavy") then
                DRC.bput("stow my " .. adj .. " " .. noun, "You put")
            end
        else
            DRC.bput("stow my " .. adj .. " " .. noun, "You put")
        end
        DRC.bput("get " .. adj .. " " .. noun .. " from my " .. self._spare_gem_pouch_container, "You get a")
        DRC.bput("wear my " .. adj .. " " .. noun, "You attach")
        DRC.bput("stow gem",
            "You pick up", "You get", "You need a free hand",
            "You just can't", "push you over the item limit",
            "You stop as you realize", "Stow what", "already in your inventory")
        if self._tie_pouch then
            DRC.bput("tie my " .. noun, "You tie")
        else
            DRC.bput("close my " .. noun, "You close")
        end
    end
end

function M:_stow_lootables(game_state)
    if not self._loot_bodies then return end
    local pair_left  = DRC.left_hand
    local pair_right = DRC.right_hand
    local tried_loot = false
    local items_to_loot = {}
    local room_objs = DRRoom.room_objs or {}

    for _, item in ipairs(self._lootables) do
        if game_state:lootable(item) then
            if not (self._box_loot_limit and self._current_box_count >= self._box_loot_limit) then
                local item_pattern = item:gsub(" ", ".*")
                for _, obj in ipairs(room_objs) do
                    if type(obj) == "string" and obj:match(item_pattern .. "$") then
                        tried_loot = true
                        table.insert(items_to_loot, item)
                    end
                end
            end
        end
    end

    if #items_to_loot > 0 then
        game_state:sheath_whirlwind_offhand()
        for _, item in ipairs(items_to_loot) do
            self:_stow_loot(item, game_state)
        end
        game_state:wield_whirlwind_offhand()
    end

    if not tried_loot then return end

    pause(1)
    -- Check for unexpected items in hands
    if DRC.left_hand ~= pair_left or DRC.right_hand ~= pair_right then
        DRC.bput("glance", "You glance .*")
    end
    if DRC.left_hand ~= pair_left and not self._equip_mgr.is_listed_item(DRC.left_hand) then
        DRC.message("Out of room, failed to store: " .. tostring(DRC.left_hand))
        if DRC.left_hand then game_state:unlootable(DRC.left_hand) end
        DRCI.dispose_trash(DRC.left_hand)
    end
    if DRC.right_hand ~= pair_right and not self._equip_mgr.is_listed_item(DRC.right_hand) then
        DRC.message("Out of room, failed to store: " .. tostring(DRC.right_hand))
        if DRC.right_hand then game_state:unlootable(DRC.right_hand) end
        DRCI.dispose_trash(DRC.right_hand)
    end
end

function M:_dispose_body(game_state)
    if not self._loot_bodies then return end
    local dead = DRRoom.dead_npcs or {}
    if #dead == 0 then
        Flags.reset("using-corpse")
        self._last_ritual = nil
        return
    end
    if (os.time() - self._loot_timer) < self._loot_delay then return end

    game_state.mob_died = true
    waitrt()
    if Flags["using-corpse"] then return end

    -- Last rites
    if (os.time() - self._last_rites_timer > 600) and self._last_rites and game_state.blessed_room then
        DRC.bput("pray " .. dead[1],
            "You beseech your god for mercy", "You pray fervently",
            "You continue praying for guidance",
            "Quietly touching your lips", "murmur a brief prayer for")
        waitrt()
        self._last_rites_timer = os.time()
        return
    end

    game_state:sheath_whirlwind_offhand()

    if self:_check_rituals(game_state) then
        self:_skin_or_dissect(dead[1], game_state)
    end

    game_state:wield_whirlwind_offhand()

    if not game_state:necro_casting() then
        local loot_cmd = "loot"
        if self._custom_loot_type and self._custom_loot_type ~= "" then
            loot_cmd = "loot " .. self._custom_loot_type
        end
        local loot_result = DRC.bput(loot_cmd,
            "You search", "I could not find what you were referring to",
            "and get ready to search it")
        while loot_result:match("and get ready to search it") do
            pause(1)
            waitrt()
            loot_result = DRC.bput(loot_cmd, "You search",
                "I could not find what you were referring to",
                "and get ready to search it")
        end
        self._last_ritual = nil
    end
    self._loot_timer = os.time()
end

function M:_should_perform_ritual(game_state)
    if not DRStats.necromancer then return false end
    if not self._ritual_type or self._ritual_type == "" then return false end
    if game_state:necro_casting() then return false end
    if self._force_rituals then return true end
    if self._ritual_type == "cycle" then return true end
    if self._ritual_type == "butcher" and DRSkill.getxp("Thanatology") < 32 then return true end
    if self._ritual_type == "dissect" and DRSkill.getxp("First Aid") < 32 then return true end
    if self._ritual_type == "harvest" and DRSkill.getxp("Skinning") < 32 then return true end
    if DRSkill.getxp("Thanatology") < 32 then return true end
    return false
end

function M:_determine_next_ritual()
    if not self._cycle_rituals then return nil end
    if DRSkill.getxp("Skinning") > 31 and DRSkill.getxp("First Aid") > 31 and DRSkill.getxp("Thanatology") > 31 then
        return self._dissect_and_butcher and "butcher" or "dissect"
    elseif DRSkill.getxp("Skinning") < DRSkill.getxp("First Aid") then
        return "harvest"
    elseif self._dissect_and_butcher then
        return "butcher"
    else
        return "dissect"
    end
end

function M:_check_rituals(game_state)
    if not DRStats.necromancer then return true end
    local mob_noun = (DRRoom.dead_npcs or {})[1]
    if game_state:construct_p(mob_noun) then return true end

    if not self._last_ritual then
        -- Priority: pet or heal first based on settings
        if self._necro_corpse_priority == "pet" then
            self:_check_necro_pet(mob_noun, game_state)
            self:_check_necro_heal(mob_noun, game_state)
        else
            self:_check_necro_heal(mob_noun, game_state)
            self:_check_necro_pet(mob_noun, game_state)
        end

        local ritual
        if self._redeemed then
            ritual = "dissect"
        elseif self._current_harvest_count < self._necro_count then
            ritual = "harvest"
        elseif self._cycle_rituals then
            ritual = self:_determine_next_ritual()
        elseif self._ritual_type == "dissect" and self._dissect_and_butcher then
            ritual = "butcher"
        else
            ritual = self._ritual_type
        end

        if self:_should_perform_ritual(game_state) then
            self:_do_necro_ritual(mob_noun, ritual, game_state)
        end
    end

    if self._last_ritual == "consume" or self._last_ritual == "harvest" or self._last_ritual == "dissect" then
        return false
    end
    return true
end

function M:_check_necro_heal(mob_noun, game_state)
    if not self._necro_heal then return end
    if game_state:necro_casting() then return end
    game_state.wounds = DRCH.check_health().wounds or {}
    if next(game_state.wounds) then
        local max_wound = 0
        for _, severity in pairs(game_state.wounds) do
            if severity > max_wound then max_wound = severity end
        end
        if self._wound_level_threshold <= max_wound and not DRSpells.active_spells["Devour"] then
            self:_do_necro_ritual(mob_noun, "consume", game_state)
        end
    end
end

function M:_check_necro_pet(mob_noun, game_state)
    if self._make_zombie and not game_state:necro_casting() and not game_state:cfb_active() then
        self:_do_necro_ritual(mob_noun, "arise", game_state)
        return
    end
    if self._make_bonebug and not game_state:necro_casting() and not game_state:cfw_active() then
        self:_do_necro_ritual(mob_noun, "arise", game_state)
    end
end

function M:_do_necro_ritual(mob_noun, ritual, game_state)
    if not DRStats.necromancer then return end
    if not ritual then return end
    if game_state:construct_p(mob_noun) then return end

    if ritual == "butcher" then
        self:_butcher_corpse(mob_noun, ritual, game_state)
        return
    end

    -- Preserve first for consume/harvest/arise
    if ritual == "consume" or ritual == "harvest" or ritual == "arise" then
        self:_do_necro_ritual(mob_noun, "preserve", game_state)
    end

    local all_patterns = {}
    for _, pats in pairs(self._rituals) do
        if type(pats) == "table" then
            for _, p in ipairs(pats) do table.insert(all_patterns, p) end
        end
    end

    local result = DRC.bput("perform " .. ritual .. " on " .. tostring(mob_noun), table.unpack(all_patterns))

    if result:match("Rituals do not work upon constructs") then
        game_state:construct(mob_noun)
    elseif result:match("You begin the ritual of Arise")
        or result:match("willing it to come back") then
        game_state.prepare_nr = self._make_zombie and not game_state:cfb_active() or false
        game_state.prepare_cfb = self._make_zombie and not game_state:cfb_active() or false
        game_state.prepare_cfw = self._make_bonebug and not game_state:cfw_active() or false
        self._last_ritual = ritual
    elseif result:match("You begin the ritual of Harvest") then
        self._last_ritual = ritual
        waitrt()
        self:_necro_harvest_check()
    elseif result:match("You begin the ritual of Consume") then
        self._last_ritual = ritual
        if self._necro_heal then game_state.prepare_consume = true end
    elseif result:match("You begin the ritual") or result:match("You succeed in dissecting") then
        self._last_ritual = ritual
    end
end

function M:_butcher_corpse(mob_noun, ritual, game_state)
    self._equip_mgr.stow_weapon(game_state:weapon_name())
    while true do
        local all_patterns = {}
        for _, pats in pairs(self._rituals) do
            if type(pats) == "table" then
                for _, p in ipairs(pats) do table.insert(all_patterns, p) end
            end
        end
        local result = DRC.bput("perform " .. ritual .. " on " .. tostring(mob_noun), table.unpack(all_patterns))
        if result:match("Rituals do not work upon constructs") then
            game_state:construct(mob_noun)
        end
        if result:match("You carve") or result:match("You butcher") then
            self._last_ritual = "butcher"
        end

        local failed = false
        for _, msg in ipairs(self._rituals.failures or {}) do
            if result:match(msg) then failed = true; break end
        end
        if failed or result == "" then break end

        DRC.bput("drop my " .. tostring(DRC.right_hand), "You drop", "You discard", "Please rephrase")
        if self._dissect_and_butcher and self._ritual_type ~= "butcher" then break end
    end

    if self._dissect_and_butcher and self._ritual_type ~= "butcher" then
        self:_do_necro_ritual(mob_noun, "dissect", game_state)
    end
    self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
end

function M:_necro_harvest_check()
    if not self._necro_store then
        DRC.bput("drop material", "you discard it")
        return
    end
    local quality = DRC.bput("glance", "You glance down.*")
    if not (quality:match("great") or quality:match("excellent")
            or quality:match("perfect") or quality:match("flawless")) then
        DRC.bput("drop material", "you discard it")
        return
    end
    if self._current_harvest_count >= self._necro_count then
        DRC.bput("drop material", "you discard it")
        return
    end
    local put_result = DRC.bput(
        "put material in my " .. tostring(self._necro_container),
        "You put", "material doesn't seem to fit")
    if put_result:match("^You put") then
        self._current_harvest_count = self._current_harvest_count + 1
    else
        DRC.bput("drop material", "you discard it")
    end
end

function M:_arrange_mob(mob_noun, game_state)
    if not (self._skin or self._arrange_for_dissect) then return end
    if self._arrange_count <= 0 then return end
    if not game_state:skinnable(mob_noun) then return end
    if game_state:necro_casting() then return end

    local arr_type = self._arrange_types[mob_noun] or "skin"
    local arrange_msg = self._arrange_all
        and ("arrange all for " .. arr_type)
        or  ("arrange for " .. arr_type)

    for i = 1, self._arrange_count do
        local result = DRC.bput(arrange_msg,
            "You begin to arrange", "You continue arranging",
            "You make a mistake", "You complete arranging",
            "That creature cannot", "That has already been arranged",
            "Arrange what", "cannot be skinned",
            "You make a serious mistake in the arranging process",
            "The .* is currently being arranged to produce")
        if result:match("You complete arranging")
           or result:match("That has already been arranged")
           or result:match("You make a serious mistake")
           or result:match("Arrange what") then
            break
        elseif result:match("cannot be skinned") then
            game_state:unskinnable(mob_noun)
            defs.tremove_val(self._dissect_cycle_skills, "Skinning")
            self._skin = false
            break
        elseif result:match("That creature cannot") then
            -- Retry without type
            arrange_msg = self._arrange_all and "arrange all" or "arrange"
        end
    end
end

function M:_skin_or_dissect(mob_noun, game_state)
    if not (game_state:dissectable(mob_noun) or game_state:skinnable(mob_noun)) then return end
    if not (self._dissect or self._skin) then return end

    local already_arranged = false

    if self._dissect and game_state:dissectable(mob_noun) then
        if self._arrange_for_dissect then
            self:_arrange_mob(mob_noun, game_state)
            already_arranged = true
        end

        local skill_to_train
        if game_state:skinnable(mob_noun) then
            local sorted = game_state:sort_by_rate_then_rank(self._dissect_cycle_skills, self._dissect_priority and {self._dissect_priority} or {})
            skill_to_train = sorted[1]
        else
            skill_to_train = "First Aid"
        end

        if skill_to_train == "First Aid" or skill_to_train == "Thanatology" then
            if not self:_dissected(mob_noun, game_state) then
                if not already_arranged then self:_arrange_mob(mob_noun, game_state) end
                if self._skin then self:_check_skinning(mob_noun, game_state) end
            end
        elseif skill_to_train == "Skinning" then
            if not already_arranged then self:_arrange_mob(mob_noun, game_state) end
            if self._skin then self:_check_skinning(mob_noun, game_state) end
        end
    elseif self._skin and game_state:skinnable(mob_noun) then
        if not already_arranged then self:_arrange_mob(mob_noun, game_state) end
        self:_check_skinning(mob_noun, game_state)
    end
end

function M:_dissected(mob_noun, game_state)
    if not game_state:dissectable(mob_noun) then return false end
    if self._dissect_for_thanatology then
        if DRSkill.getxp("Thanatology") == 34 and DRSkill.getxp("First Aid") == 34 then return false end
    else
        if DRSkill.getxp("First Aid") == 34 then return false end
    end

    local result = DRC.bput("dissect " .. tostring(mob_noun),
        "You'll gain no insights from this attempt",
        "You succeed in dissecting the corpse",
        "What exactly are you trying to dissect",
        "You'll learn nothing",
        "While likely a fascinating study",
        "You cannot dissect",
        "would probably object",
        "should be left alone.",
        "That'd be a waste of time.",
        "A skinned creature is worthless",
        "You do not yet possess the knowledge",
        "This ritual may only be performed on a corpse",
        "You learn something",
        "A failed or completed ritual has rendered",
        "You realize after a few seconds",
        "prevents a meaningful dissection",
        "With less concern than you'd give a fresh corpse",
        "Rituals do not work upon constructs")

    if result:match("You succeed in dissecting")
       or result:match("You learn something")
       or result:match("With less concern") then
        return true
    elseif result:match("You'll gain no insights") then
        waitrt()
        fput("dissect")
        return false
    elseif result:match("Rituals do not work upon constructs") then
        game_state:construct(mob_noun)
        game_state:undissectable(mob_noun)
        return false
    elseif result:match("While likely a fascinating study")
        or result:match("That'd be a waste of time")
        or result:match("You do not yet possess") then
        game_state:undissectable(mob_noun)
        defs.tremove_val(self._dissect_cycle_skills, "First Aid")
        if self._dissect_for_thanatology then
            defs.tremove_val(self._dissect_cycle_skills, "Thanatology")
        end
        self._dissect = false
        return false
    end
    return false
end

function M:_check_skinning(mob_noun, game_state)
    if not game_state:skinnable(mob_noun) then return end

    -- Bundle check
    if game_state.need_bundle then
        local tap = DRC.bput("tap my bundle",
            "You tap a %w+ bundle that you are wearing",
            "I could not find what you were referring to",
            "You tap a tight bundle inside")
        if tap:match("lumpy") then
            if self._tie_bundle then
                DRC.bput("tie my bundle", "TIE the bundle again", "But this bundle has already been tied off")
                local tie_res = DRC.bput("tie my bundle",
                    "you tie the bundle", "But this bundle has already been tied off",
                    "You don't seem to be able to do that right now")
                if tie_res:match("you tie the bundle") or tie_res:match("already been tied off") then
                    -- adjust
                    while true do
                        local adj = DRC.bput("adjust my bundle",
                            "You adjust your .* bundle so that you can more easily",
                            "You'll need a free hand for that")
                        if adj:match("You adjust your") then break end
                        if DRC.right_hand and DRC.left_hand then
                            DRCI.lower_item(DRC.left_hand)
                        end
                    end
                    game_state.need_bundle = false
                end
            else
                game_state.need_bundle = false
            end
        elseif tap:match("tight") then
            game_state.need_bundle = false
        end
    end

    local snap_left  = DRC.left_hand
    local snap_right = DRC.right_hand

    local skin_result = DRC.bput("skin",
        "roundtime", "skin what", "cannot be skinned",
        "carrying far too many items", "need a more appropriate weapon",
        "need to have a bladed instrument to skin",
        "You must have one hand free to skin")

    if skin_result:match("You must have one hand free to skin") then
        local temp_item = DRC.left_hand
        if DRCI.lower_item(temp_item) then
            self:_check_skinning(mob_noun, game_state)
            DRCI.get_item(temp_item)
        end
        return
    elseif skin_result:match("need a more appropriate weapon")
        or skin_result:match("need to have a bladed instrument") then
        DRC.message("BUY A SKINNING KNIFE")
        self._skin = false
        return
    elseif skin_result:match("cannot be skinned") or skin_result:match("carrying far too many items") then
        game_state:unskinnable(mob_noun)
        return
    end

    pause(1)
    waitrt()

    local left_changed  = DRC.left_hand  ~= snap_left
    local right_changed = DRC.right_hand ~= snap_right

    if game_state.need_bundle and (left_changed or right_changed) then
        local stored_moon = false
        local summoned = game_state:summoned_info(game_state:weapon_skill())
        if DRStats.moon_mage and DRCMM.wear_moon_weapon() then
            stored_moon = true
        elseif summoned then
            DRCS.break_summoned_weapon(game_state:weapon_name())
        else
            self._equip_mgr.stow_weapon(game_state:weapon_name())
        end

        if DRCI.get_item_if_not_held("bundling rope") then
            DRC.bput("bundle", "You bundle")
            DRCI.wear_item("bundle")
            if self._tie_bundle then
                DRC.bput("tie my bundle", "TIE the bundle again")
                DRC.bput("tie my bundle", "you tie the bundle")
                DRC.bput("adjust my bundle", "You adjust")
            end
        else
            if snap_left ~= DRC.left_hand and not self._equip_mgr.is_listed_item(DRC.left_hand) then
                DRCI.dispose_trash(DRC.left_hand)
            end
            if snap_right ~= DRC.right_hand and not self._equip_mgr.is_listed_item(DRC.right_hand) then
                DRCI.dispose_trash(DRC.right_hand)
            end
        end
        game_state.need_bundle = false

        if not (stored_moon and DRCMM.hold_moon_weapon()) then
            if summoned then
                game_state:prepare_summoned_weapon(false)
            else
                self._equip_mgr.wield_weapon(game_state:weapon_name(), game_state:weapon_skill())
            end
        end
    end

    if snap_left ~= DRC.left_hand and not self._equip_mgr.is_listed_item(DRC.left_hand) then
        DRCI.dispose_trash(DRC.left_hand)
    end
    if snap_right ~= DRC.right_hand and not self._equip_mgr.is_listed_item(DRC.right_hand) then
        DRCI.dispose_trash(DRC.right_hand)
    end
end

return M
