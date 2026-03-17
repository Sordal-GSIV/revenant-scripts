--- @revenant-script
--- name: tactics
--- version: 1.0
--- author: Zadrix
--- game: dr
--- description: Analyze creatures and execute tactical brawling moves.
--- tags: combat, tactics, training
--- Converted from tactics.lic
no_kill_all(); no_pause_all(); silence_me()

local actions = {"claw","gouge","punch","elbow","kick","slap","feint","jab","draw","slice","thrust","chop","sweep","lunge"}

while true do
    pause(1)
    fput("analyze")
    local line = get()
    if line and line:find("by landing") then
        local moves = line:match("by landing (.+)")
        if moves then
            for _, action in ipairs(actions) do
                if moves:find(action) then
                    fput(action); waitrt()
                end
            end
        end
    end
    -- Check mindlock
    put("exp tactics")
    local exp_line = get()
    if exp_line and exp_line:find("mind lock") then break end
end
