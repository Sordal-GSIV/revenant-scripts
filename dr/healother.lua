--- @revenant-script
--- name: healother
--- version: 1.0
--- author: Relaife
--- game: dr
--- description: Heal a target player, wait for whisper to repeat.
--- tags: empath, healing, automated
--- Usage: ;healother <name>
--- Converted from healother.lic
local target = Script.vars[1]
if not target then echo("Usage: ;healother <name>") return end

local body_parts = {"head","neck","chest","abdomen","back","left arm","right arm",
    "left hand","right hand","left leg","right leg","left eye","right eye"}

local function heal_target()
    waitrt(); put("touch " .. target)
    local line = get()
    if not line then return end
    if line:find("no injuries") or line:find("Touch what") then return end
    for _, part in ipairs(body_parts) do
        if line:find("to the " .. part) then
            waitrt(); put("trans " .. target .. " " .. part)
            waitrt(); put("trans " .. target .. " " .. part .. " internal")
            waitrt(); put("trans " .. target .. " " .. part .. " scar")
            waitrt(); put("trans " .. target .. " " .. part .. " internal scar")
            break
        end
    end
    heal_target()
end

heal_target()
start_script("healself")
pause_script("healother")
pause(1)
waitfor(target .. " whispers,")
