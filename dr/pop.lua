--- @revenant-script
--- name: pop
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Locksmith box popping script - detect traps, disarm, pick locks via spells
--- tags: locksmith, boxes, traps, disarm
---
--- Processes boxes from inventory using detect (402/404), disarm (408), and pick (407) spells.

local BOX_NOUNS = {"box", "chest", "coffer", "strongbox", "trunk"}

local function ensure_rapid()
    waitrt(); waitcastrt()
    if Spell[515].affordable and not Spell[515].active then
        fput("incant 515")
        waitcastrt()
    end
end

local function detect_trap(noun)
    Spell[402].cast()
    waitrt(); waitcastrt()
    Spell[404].cast()
    waitrt(); waitcastrt()
    local result = dothistimeout("detect my " .. noun, 2, "You discover no traps|free of all obstructions|plate over the lock|scales|vial|rods|scarab|crystal|sliver|spring open|discolored|spiderweb|grainy substance")
    if not result then return "unknown" end
    if result:match("no traps") or result:match("free of all") or result:match("plate over") then
        return "safe"
    elseif result:match("spiderweb") or result:match("grainy substance") then
        return "drop" -- too dangerous
    else
        return "disarm"
    end
end

local function disarm_box(noun)
    while true do
        ensure_rapid()
        waitrt(); waitcastrt()
        Spell[404].cast()
        waitcastrt()
        if Spell[408].affordable then
            fput("prepare 408")
            local result = dothistimeout("cast my " .. noun, 2, "vibrates slightly|pulses once")
            if result and result:match("pulses once") then return true end
        else
            echo("No mana"); pause(5)
        end
    end
end

local function pick_box(noun)
    while true do
        ensure_rapid()
        waitrt(); waitcastrt()
        Spell[403].cast()
        waitcastrt()
        if Spell[407].affordable then
            fput("prepare 407")
            local result = dothistimeout("cast my " .. noun, 2, "vibrates slightly|flies open|already open")
            if result and (result:match("flies open") or result:match("already open")) then return true end
        else
            echo("No mana"); pause(5)
        end
    end
end

for _, box in ipairs(BOX_NOUNS) do
    local result = dothistimeout("get my " .. box, 5, "You remove|Get what")
    if result and result:match("You remove") then
        ensure_rapid()
        local trap = detect_trap(GameObj.right_hand.noun)
        if trap == "drop" then
            fput("drop " .. GameObj.right_hand.noun)
        elseif trap == "disarm" then
            disarm_box(GameObj.right_hand.noun)
            pick_box(GameObj.right_hand.noun)
            fput("loot my " .. GameObj.right_hand.noun)
            fput("drop " .. GameObj.right_hand.noun)
        elseif trap == "safe" then
            pick_box(GameObj.right_hand.noun)
            fput("loot my " .. GameObj.right_hand.noun)
            fput("drop " .. GameObj.right_hand.noun)
        end
    end
end
