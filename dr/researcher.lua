--- @revenant-script
--- name: researcher
--- version: 0.0.4
--- author: Crannach
--- game: dr
--- description: Automated magic research on a subject.
--- tags: magic, research, training
--- Usage: ;researcher <augmentation|utility|warding|symbiosis>
--- Converted from researcher.lic
local skill = Script.vars[1]
if not skill then echo("Usage: ;researcher <skill>") return end
Flags.add("research-partial", "still more to learn", "distracted by combat", "lose your focus")
Flags.add("research-complete", "Breakthrough!", "commit the details to memory")
local function start_research()
    if skill:lower() == "attunement" then skill = "stream" end
    DRC.bput("research " .. skill .. " 300", "You focus", "You tentatively",
        "You confidently", "Abandoning", "You cannot begin", "already busy", "You start")
end
start_research()
while true do
    pause(5)
    if Flags["research-partial"] then Flags.reset("research-partial"); start_research()
    elseif Flags["research-complete"] then Flags.reset("research-complete"); break end
end
