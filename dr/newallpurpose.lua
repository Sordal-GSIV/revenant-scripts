--- @revenant-script
--- name: newallpurpose
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Combat watchdog - monitors for stuns, webs, balance issues and handles recovery
--- tags: combat, watchdog, recovery, stun, web
---
--- Ported from newallpurpose.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;newallpurpose <main_script> <guild> <augm> <ward> <buffprep> <cambrinth>
---
--- Monitors game output for stuns, imbalance, webbing, exhaustion, and other
--- combat problems, pausing companion scripts and taking recovery actions.

local main_script = Script.vars[1] or ""
local guild = Script.vars[2] or ""
local augm = Script.vars[3] or ""
local ward = Script.vars[4] or ""
local buffprep = Script.vars[4] or ""
local cambrinth = Script.vars[5] or ""

no_pause_all()

local function pause_companions()
    if main_script ~= "" then pcall(function() pause_script(main_script) end) end
end

local function unpause_companions()
    if main_script ~= "" then pcall(function() unpause_script(main_script) end) end
end

local function is_barb()
    return guild == "barb" or guild == "madm"
end

local function handle_roar()
    if is_barb() then
        fput("roar quiet kun")
    end
end

-- Main monitoring loop
while true do
    local line = get()
    if line then
        if line:find("squirts a stream of sticky webbing") then
            -- Webbed
            pause_companions()
            waitfor("You escape from the sticky webbing!")
            unpause_companions()

        elseif line:find("extremely imbalanced") or line:find("badly balanced")
            or line:find("very badly balanced") or line:find("You must stand first")
            or line:find("stand up first") or line:find("losing your balance and falling") then
            -- Knocked down / imbalanced
            pause_companions()
            handle_roar()
            pause(1)
            waitrt()
            fput("stand")
            unpause_companions()

        elseif line:find("You are still stunned") then
            pause_companions()
            if is_barb() then fput("roar quiet kun") end
            pause(1)
            waitrt()
            unpause_companions()

        elseif line:find("opponent dominating") or line:find("opponent in excellent position") then
            pause_companions()
            fput("bob")
            pause(1)
            waitrt()
            unpause_companions()

        elseif line:find("You aren't close enough to attack") then
            pause_companions()
            fput("advance")
            fput("bob")
            unpause_companions()

        elseif line:find("exhausted,") then
            if is_barb() then
                pause_companions()
                pause(1)
                waitrt()
                fput("berserk avalanche")
                pause(2)
                unpause_companions()
            else
                fput("bob")
                pause(1)
                waitrt()
            end

        elseif line:find("You're beat up") then
            if is_barb() then
                pause_companions()
                pause(1)
                waitrt()
                fput("berserk famine")
                pause(2)
                unpause_companions()
            end

        elseif line:find("You're badly hurt") or line:find("You're very badly hurt")
            or line:find("You're smashed up") or line:find("terribly wounded")
            or line:find("near death") then
            fput("quit")

        elseif line:find("What are you trying to attack") or line:find("Analyze what")
            or line:find("can't cast that at yourself") then
            -- Target gone - respawn/rebuff
            pause_companions()
            pause(1)
            waitrt()
            if is_barb() then
                start_script("meditate")
                pause(1)
                start_script("warhorn")
                wait_while(function() return running("warhorn") end)
            end
            unpause_companions()

        elseif line:find("is already quite dead") then
            pause_companions()
            fput("loot")
            unpause_companions()

        elseif line:find("You are engaged to") or line:find("too exhausted to be able to pick") then
            pause_companions()
            handle_roar()
            pause(1)
            waitrt()
            fput("retreat")
            fput("retreat")
            pause(1)
            waitrt()
            unpause_companions()

        elseif line:find("is flying too high") then
            pause_companions()
            fput("face next")
            unpause_companions()

        elseif line:find("no matter how you arrange it") then
            fput("drop chest")
            fput("drop strongbox")
            fput("drop casket")
            fput("drop trunk")
            fput("drop box")

        elseif line:find("You need two hands") or line:find("You can not load the") then
            fput("wear left")
            fput("stow left")

        elseif line:find("notices your attempt to hide") then
            pause_companions()
            pause(1)
            waitrt()
            fput("jab")
            fput("bob")
            pause(1)
            waitrt()
            fput("retreat")
            unpause_companions()
        end
    end
end
