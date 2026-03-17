--- @revenant-script
--- name: fistoffury
--- version: 1.2
--- author: Ecnew
--- game: gs
--- description: UAC combat script with dynamic stance management and targeted attacks
--- tags: UAC, unarmed, fury, combat
---
--- Usage:
---   ;fistoffury         - Start combat
---   ;fistoffury setup   - Configure settings
---   ;fistoffury help    - Show help

CharSettings["fist_max_targets"] = CharSettings["fist_max_targets"] or 3
CharSettings["fist_kick_targets"] = CharSettings["fist_kick_targets"] or {"left leg", "neck"}

if script.vars[1] == "help" then
    respond("FistOfFury - UAC Combat Script")
    respond(";fistoffury       - Start combat")
    respond(";fistoffury setup - Configure")
    exit()
elseif script.vars[1] == "setup" then
    echo("Current settings:")
    echo("Max targets: " .. CharSettings["fist_max_targets"])
    echo("Kick targets: " .. table.concat(CharSettings["fist_kick_targets"], ", "))
    echo("Set via: ;e CharSettings['fist_max_targets'] = 3")
    exit()
end

local MAX = CharSettings["fist_max_targets"]
fput("target random")

local function check_target()
    if not GameObj.target or not GameObj.target.id then
        fput("stance defensive")
        exit()
    end
    if GameObj.target.status and GameObj.target.status:match("dead|gone") then exit() end
    if GameObj.targets and #GameObj.targets > MAX then
        echo("Too many targets!"); fput("stance defensive"); exit()
    end
end

local function adjust_stance()
    local count = GameObj.targets and #GameObj.targets or 1
    local stance = "offensive"
    if count == 2 then stance = "advance"
    elseif count >= 3 then stance = "forward" end
    fput("stance " .. stance)
end

local function safe_wait()
    pause(0.1); waitrt()
end

-- Combat loop
while true do
    check_target()
    adjust_stance()

    -- Try Weapon Fury
    if Weapon and Weapon.available and Weapon.available("Fury") and checkstamina() > 50 then
        safe_wait()
        fput("weapon fury #" .. GameObj.target.id)
        safe_wait()
    end

    -- Primary attack
    safe_wait()
    fput("jab #" .. GameObj.target.id)
    safe_wait()

    -- Followup kick
    check_target()
    for _, target in ipairs(CharSettings["fist_kick_targets"]) do
        safe_wait()
        fput("kick #" .. GameObj.target.id .. " " .. target)
        safe_wait()
        check_target()
    end

    pause(0.1)
end
