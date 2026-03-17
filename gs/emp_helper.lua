--- @revenant-script
--- name: emp_helper
--- version: 1.6.0
--- author: Felang Goredrinker
--- game: gs
--- tags: empath, autostart, healing, unstun, poison, disease
--- description: Empath automation - cure poison/disease, adrenaline surge, unstun PCs
---
--- Original Lich5 authors: Felang Goredrinker, Darkcipher (unstun)
--- Ported to Revenant Lua from emp-helper.lic v1.6
---
--- Usage: ;emp_helper (runs as autostart)

local DEBUG = false
local SCRIPTS_TO_PAUSE = { "bigshot", "sbounty", "treim", "useherbs", "1604", "unstun", "sigilz" }
local REJUV_REUSE_TIMER = 5
local STAMINA_THRESHOLD = 50
local HEALTH_THRESHOLD = 70
local UNSTUN_PCS = true
local UNSTUN_DURING_BIGSHOT = true

local last_rejuv = os.time()
local prev_stance = ""

local function pause_scripts()
    for _, s in ipairs(SCRIPTS_TO_PAUSE) do
        if Script.running(s) then Script.pause(s) end
    end
end

local function unpause_scripts()
    for _, s in ipairs(SCRIPTS_TO_PAUSE) do
        if Script.paused(s) then Script.unpause(s) end
    end
end

local function stance_def()
    prev_stance = checkstance()
    fput("stance def")
end

local function return_stance()
    fput("stance " .. prev_stance)
end

local function check_unstun()
    if checkstunned() or checkdead() then return end
    if Script.running("bigshot") and not UNSTUN_DURING_BIGSHOT then return end
    if DEBUG then echo("check_unstun()") end

    local players = GameObj.pcs()
    if players then
        for _, p in ipairs(players) do
            waitcastrt()
            if p.status and p.status:find("stun") then
                wait_until(function() return checkmana() >= 8 end)
                waitrt()
                waitcastrt()
                fput("prep 108")
                fput("cast " .. p.name)
                wait(3)
            end
        end
    end
end

local function check_disease()
    if not checkdisease() then return end
    if DEBUG then echo("check_disease()") end
    if not Spell[113].known() then return end
    pause_scripts()
    stance_def()
    Spell[113].cast()
    return_stance()
    unpause_scripts()
end

local function check_poison()
    if not checkpoison() then return end
    if DEBUG then echo("check_poison()") end
    if not Spell[114].known() then return end
    pause_scripts()
    stance_def()
    Spell[114].cast()
    return_stance()
    unpause_scripts()
end

local function check_stamina()
    if not Spell[1107].known() then return end
    if Spell[1107].active() then return end
    if os.time() - last_rejuv <= REJUV_REUSE_TIMER then return end
    if percentstamina() >= STAMINA_THRESHOLD then return end
    if not Spell[1107].affordable() then return end
    if DEBUG then echo("check_stamina()") end

    pause_scripts()
    stance_def()
    fput("prep 1107")
    fput("cast")
    last_rejuv = os.time()
    return_stance()
    unpause_scripts()
end

local function check_health()
    if not Spell[1101].known() then return end
    if os.time() - last_rejuv <= REJUV_REUSE_TIMER then return end
    if percenthealth() >= HEALTH_THRESHOLD then return end
    if not Spell[1101].affordable() then return end
    if DEBUG then echo("check_health()") end

    pause_scripts()
    stance_def()
    fput("cure")
    last_rejuv = os.time()
    return_stance()
    unpause_scripts()
end

-- Build check list based on known spells
local checks = {}
if Spell[1107].known() then
    checks[#checks + 1] = check_stamina
    checks[#checks + 1] = check_health
end
if Spell[113].known() then checks[#checks + 1] = check_disease end
if Spell[114].known() then checks[#checks + 1] = check_poison end
if Spell[108].known() and UNSTUN_PCS then checks[#checks + 1] = check_unstun end

while true do
    for _, check in ipairs(checks) do
        check()
    end
    wait(0.5)
end
