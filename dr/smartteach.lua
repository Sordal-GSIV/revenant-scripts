--- @revenant-script
--- name: smartteach
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-teach skills when an approved student whispers "teach me <skill>".
--- tags: teach,education
---
--- Configure approved_students in your character settings.
--- Usage: ;smartteach (runs in background, waiting for whisper requests)

no_pause_all()
no_kill_all()

local approved_students = CharSettings["approved_students"] or {}

echo("Waiting for student...")

while true do
    local line = get()
    if line then
        local student, skill = line:match("(.+) whispers, \"teach me (.+)\"")
        if student and skill then
            echo("Checking if I should teach " .. student .. " a class on " .. skill)

            -- Check if student is approved
            local approved = false
            for _, name in ipairs(approved_students) do
                if name == student then
                    approved = true
                    break
                end
            end

            if approved then
                echo("Attempting to teach " .. student)
                pause(1)
                waitrt()
                put("stop listen")
                put("stop teach")
                fput("teach " .. skill .. " to " .. student)
            end
        end
    end
end
