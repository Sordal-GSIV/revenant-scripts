--- @revenant-script
--- name: retreat
--- version: 1.0
--- author: Nyow
--- game: dr
--- description: Auto-retreat from combat when health is low.
--- tags: combat, safety, retreat

no_kill_all()
no_pause_all()
silence_me()

local retreat_at = 77

while true do
    local health = checkhealth()
    if health < retreat_at then
        while true do
            local result = dothistimeout("retreat", 5, {
                "You retreat back to pole range",
                "You are unable to retreat",
                "You try to retreat",
                "You retreat from combat",
                "You are already as far away",
            })
            if result and result:find("You retreat from combat") then
                echo("Retreated! Moving to safety...")
                break
            elseif result and result:find("already as far away") then
                if not checknpcs() then
                    echo("You are safe... for now.")
                end
                pause(15)
                break
            end
            pause(0.5)
        end
    end
    pause(1)
end
