--- @revenant-script
--- name: almanac
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Passively use almanac for skill training during downtime.
--- tags: training, almanac, lore

local settings = get_settings()
UserVars.almanac_last_use = UserVars.almanac_last_use or (os.time() - 600)
local no_use_scripts = settings.almanac_no_use_scripts or {}
local almanac_skills = settings.almanac_skills

local function use_almanac()
    if os.time() - UserVars.almanac_last_use < 600 then return end
    for _, name in ipairs(no_use_scripts) do
        if running(name) then return end
    end
    if hidden() then return end

    local training_skill = nil
    if almanac_skills then
        local best_xp = 999
        for _, skill in ipairs(almanac_skills) do
            local xp = DRSkill.getxp(skill)
            if xp < 18 and xp < best_xp then
                best_xp = xp
                training_skill = skill
            end
        end
        if not training_skill then return end
    end

    waitrt()
    DRC.bput("stow left", "Stow what", "You put")
    local result = DRC.bput("get my almanac", "You get", "What were")
    if result == "What were" then
        echo("Almanac not found, exiting.")
        return
    end
    if training_skill then
        DRC.bput("turn almanac to " .. training_skill, "You turn")
    end
    DRC.bput("study my almanac", "You set about", "gleaned all", "Study what", "interrupt")
    waitrt()
    DRC.bput("stow my almanac", "You put", "Stow what")
    UserVars.almanac_last_use = os.time()
end

while true do
    use_almanac()
    pause(20)
end
