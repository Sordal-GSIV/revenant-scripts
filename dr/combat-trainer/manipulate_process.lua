-- manipulate_process.lua
-- ManipulateProcess — empathy manipulation logic for combat-trainer
-- Ported from combat-trainer.lic by Ondreian and contributors

local ManipulateProcess = {}
ManipulateProcess.__index = ManipulateProcess

function ManipulateProcess.new(settings)
    local self = setmetatable({}, ManipulateProcess)
    self.threshold = settings.manipulate_threshold
    self.manip_to_train = settings.manipulate_only_to_train
    self.last_manip = os.time() - 200
    self.filtered_npcs = {}
    return self
end

function ManipulateProcess:execute(game_state)
    if game_state.danger or self.threshold == nil or game_state:construct_mode() then return end
    self.filtered_npcs = game_state.npcs
    if self:should_manipulate() then self:manipulate(game_state) end
end

function ManipulateProcess:should_manipulate()
    if self.manip_to_train and DRSkill.getxp('Empathy') > 30 then return false end
    return #self.filtered_npcs >= self.threshold and (os.time() - self.last_manip) > 120
end

function ManipulateProcess:manipulate(game_state)
    DRC.bput('manipulate stop all', 'You relax your will', "But you aren't manipulating anything")
    local manipulate_count = 0
    for _, npc in ipairs(self.filtered_npcs) do
        if game_state:is_construct(npc) then goto continue end
        if manipulate_count >= self.threshold then break end
        local result = DRC.bput('manipulate friendship ' .. npc,
            "You're already manipulating",
            'beyond your ken',
            'You attempt to empathically manipulate',
            'You strain',
            'does not seem to have a life essence',
            'Manipulate what')
        if result == 'does not seem to have a life essence' then
            game_state:mark_construct(npc)
        else
            manipulate_count = manipulate_count + 1
        end
        ::continue::
    end
    self.last_manip = os.time()
end

return ManipulateProcess
