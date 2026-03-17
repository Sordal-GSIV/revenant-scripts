--- @revenant-script
--- name: horse_trainer
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Teach ranger horse all available skills.
--- tags: ranger, horse, training
---
--- Converted from horse-trainer.lic

if not DRStats.ranger then
    echo("***MUST BE A RANGER***")
    return
end

local skills = {
    "leadrope", "saddle", "animal", "joust", "kneel", "prance",
    "beg", "spin", "jump", "combat", "magic", "war"
}

for _, skill in ipairs(skills) do
    local result = DRC.bput("instruct horse " .. skill, "You begin", "already trained to do that")
    if result ~= "already trained to do that" then
        waitfor("You finish instructing")
    end
end

echo("All done!")
