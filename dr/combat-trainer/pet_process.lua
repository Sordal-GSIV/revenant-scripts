--- PetProcess — necromancer zombie/bonebug management for combat-trainer.
-- Ported from PetProcess class in combat-trainer.lic
local PetProcess = {}
PetProcess.__index = PetProcess

function PetProcess.new(settings)
    local self = setmetatable({}, PetProcess)
    self._zombie           = settings.zombie   or {}
    self._bonebug          = settings.bonebug  or {}
    self._is_present       = false
    self._current_stance   = nil
    self._current_behavior = nil
    return self
end

function PetProcess:execute(game_state)
    self:_check_zombie(game_state)
    if game_state:dismiss_pet() then
        self:_dismiss_zombie(game_state)
        self:_dismiss_bonebug(game_state)
        game_state:next_clean_up_step()
        return true
    end
    return false
end

function PetProcess:_summon_zombie(game_state)
    if not game_state:cfb_active() then return end
    if not self._zombie.summon then return end
    if self._is_present then return end
    self:_command_zombie("come", game_state)
end

function PetProcess:_dismiss_zombie(game_state)
    if not self._is_present then return end
    if not game_state:cfb_active() then return end
    self:_command_zombie("leave", game_state)
end

function PetProcess:_dismiss_bonebug(game_state)
    if not self._is_present then return end
    if not game_state:cfw_active() then return end
    DRCA.release_cyclics()
end

function PetProcess:_update_behavior(game_state)
    if not game_state:cfb_active() then return end
    if not self._zombie.behavior then return end
    if self._zombie.behavior == self._current_behavior then return end
    self:_command_zombie("behavior " .. self._zombie.behavior, game_state)
end

function PetProcess:_update_stance(game_state)
    if not game_state:cfb_active() then return end
    if not self._zombie.stance then return end
    if self._zombie.stance == self._current_stance then return end
    self:_command_zombie("stance " .. self._zombie.stance, game_state)
end

function PetProcess:_check_zombie(game_state)
    if not DRStats.necromancer() then return end
    if not game_state:cfb_active() then return end
    self:_summon_zombie(game_state)
    self:_update_behavior(game_state)
    self:_update_stance(game_state)
end

function PetProcess:_command_zombie(command, game_state)
    if not game_state:cfb_active() then return end
    local result = DRC.bput(
        "command zombie " .. command,
        "willing it to come back to you",
        "You have already shifted",
        "That is not a valid stance",
        "is already right beside you",
        "zombie shambles off with a groan",
        "You sense a flicker of acknowledgement through the link",
        "you sense your .+ shift into (a|an) %w+ stance",
        "you sense your .+ behavior shift"
    )
    if result == "is already right beside you" then
        self._is_present = true
    elseif result == "zombie shambles off with a groan" then
        self._is_present = false
    elseif result and result:match("shift into") then
        self._current_stance = self._zombie.stance
    elseif result and result:match("behavior shift") then
        self._current_behavior = self._zombie.behavior
    end
end

return PetProcess
