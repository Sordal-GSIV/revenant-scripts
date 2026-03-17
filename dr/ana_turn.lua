--- @revenant-script
--- name: ana_turn
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Automate Anatase offerings to the priestess.
--- tags: theurgy, quest, offering
---
--- Converted from ana-turn.lic

Flags.add("task-closed", "A white-clad priestess of Albreda hands you")

local function ask_task()
    local result = DRC.bput("Ask second priestess for task",
        "You may accept by typing", "You are already on a task", "I am sorry")
    if result and result:find("You may accept") then
        DRC.bput("accept task", "Thank you,")
        return main_loop()
    elseif result and result:find("already on a task") then
        return main_loop()
    elseif result and result:find("I am sorry") then
        pause(40)
        return ask_task()
    end
end

function main_loop()
    while true do
        local result = DRC.bput("get ana", "You", "What were you referring to?")
        if result and result:find("What were") then
            echo("Need more!")
            return
        end
        result = DRC.bput("give ana to second priestess",
            "The priestess accepts your offering",
            "What is it you're trying to give?",
            "A white-clad priestess of Albreda ignores your offer")
        if result and result:find("What is it") then
            echo("Need more!")
            return
        elseif result and result:find("ignores your offer") then
            ask_task()
            return
        end
        if Flags["task-closed"] then break end
    end
    ask_task()
end

ask_task()
