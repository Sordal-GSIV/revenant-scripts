--- SafetyProcess — health/safety monitoring for combat-trainer.
-- Ported from SafetyProcess class in combat-trainer.lic
local M = {}
M.__index = M

function M.new(settings, equip_mgr)
    local self = setmetatable({}, M)
    self._equip_mgr       = equip_mgr
    self._health_threshold = settings.health_threshold or 30
    self._stop_on_bleeding = settings.stop_hunting_if_bleeding
    self._untendable_counter = 0

    -- Register all flags
    Flags.add("ct-engaged",
        "closes to pole weapon range on you",
        "closes to melee range on you")

    Flags.add("ct-lodged",
        "from the .* lodged in your (?P<body_part>.*)[.]")

    Flags.add("ct-itemdropped",
        "^Your (?P<item>.*) falls to your feet[.]",
        "^You cannot maintain your grip on the (?P<item>.*), and it falls to the ground!")

    Flags.add("ct-germshieldlost",
        "It jerks the.* (?P<shield>\\w+) out of your hands")

    Flags.add("active-mitigation",
        "You believe you could \\b(?P<action>\\w+) out of the way of the \\b(?P<obstacle>\\w+)")

    Flags.add("ct-parasite",
        "blood mite on your (?P<body_part>.*)[.]")

    return self
end

function M:execute(game_state)
    -- Bleeding check
    if self._untendable_counter >= 3 and self._stop_on_bleeding then
        echo("Couldn't tend bleeders after three tries. Stopping hunt. Get healed!")
        Script.kill("tendme")
        -- Stop the main script
        return true
    elseif bleeding()
        and not Script.running("tendme")
        and not (DRSpells.active_spells["Devour"]
                 or DRSpells.active_spells["Heal"]
                 or DRSpells.active_spells["Regenerate"]) then
        if DRCH.has_tendable_bleeders() then
            DRC.wait_for_script_to_complete("tendme")
        end
        self._untendable_counter = self._untendable_counter + 1
    end

    -- Health threshold
    if DRStats.health < self._health_threshold then
        fput("exit")
    end

    DRC.fix_standing()
    self:_check_item_recovery(game_state)
    self:_tend_lodged()
    self:_tend_parasite()
    self:_active_mitigation()
    game_state.danger = self:_in_danger(game_state.danger)
    if not game_state.danger and game_state:retreating_p() then
        self:_keep_away()
    end
end

function M:_check_item_recovery(game_state)
    if Flags["ct-germshieldlost"] then
        local flag = Flags["ct-germshieldlost"]
        local shield = type(flag) == "table" and flag.shield or nil
        if shield then
            self:_recover_item(game_state, shield, "wear")
        end
        Flags.reset("ct-germshieldlost")
    end
    if Flags["ct-itemdropped"] then
        local flag = Flags["ct-itemdropped"]
        local item = type(flag) == "table" and flag.item or nil
        -- Free a hand first
        local left = DRC.left_hand
        local right = DRC.right_hand
        local temp_item = left or right
        if temp_item then
            if not self._equip_mgr.stow_weapon(temp_item) then
                DRCI.put_away_item(temp_item)
            end
        end
        if item then
            self:_recover_item(game_state, item, "pickup")
        end
        Flags.reset("ct-itemdropped")
        if temp_item then
            if not self._equip_mgr.wield_weapon(temp_item) then
                DRCI.get_item(temp_item)
            end
            if DRC.left_hand ~= left and DRC.right_hand ~= right then
                fput("swap")
            end
        end
    end
end

function M:_recover_item(game_state, item, action)
    if not item then return end
    echo("*** Recovering " .. tostring(item))
    local recovered = false
    game_state:sheath_whirlwind_offhand()
    if DRCI.get_item_unsafe(item) then
        if action == "pickup" then
            recovered = true
        elseif action == "wear" then
            recovered = DRCI.wear_item(item)
        elseif action == "stow" then
            recovered = self._equip_mgr.stow_weapon(item) or DRCI.put_away_item(item)
        end
    end
    if not recovered then
        for i = 1, 5 do
            DRC.message("UNABLE TO RECOVER FROM " .. tostring(item) .. " LOSS!")
            DRC.beep()
        end
    end
    waitrt()
    game_state:wield_whirlwind_offhand()
end

function M:_tend_lodged()
    if not Flags["ct-lodged"] then return end
    local flag = Flags["ct-lodged"]
    local part = type(flag) == "table" and flag.body_part or nil
    if part then
        DRCH.bind_wound(part)
    end
    Flags.reset("ct-lodged")
end

function M:_tend_parasite()
    if not Flags["ct-parasite"] then return end
    DRC.wait_for_script_to_complete("tendme")
    Flags.reset("ct-parasite")
end

function M:_keep_away()
    if not Flags["ct-engaged"] then return end
    Flags.reset("ct-engaged")
    DRC.retreat()
end

function M:_active_mitigation()
    if not Flags["active-mitigation"] then return end
    local flag = Flags["active-mitigation"]
    if type(flag) == "table" and flag.action and flag.obstacle then
        DRC.bput(flag.action .. " " .. flag.obstacle,
            "You manage to", "You've got to", "Please rephrase",
            "You jump back", "You can't do")
    end
    Flags.reset("active-mitigation")
end

function M:_in_danger(was_danger)
    if DRStats.health >= 75 then return false end
    if not was_danger then
        Flags.reset("ct-engaged")
        DRC.retreat()
    end
    self:_keep_away()
    return true
end

return M
