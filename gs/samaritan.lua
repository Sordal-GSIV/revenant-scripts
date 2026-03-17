--- @revenant-script
--- name: samaritan
--- version: 1.0.0
--- author: Ondreian
--- game: gs
--- description: Auto-pull companions to their feet, unstun, and keep yourself standing
--- tags: util,group,support
---
--- Usage:
---   ;samaritan              start helping group members
---   ;samaritan --invasion   skip town checks (defend walls)
---   ;samaritan --debug      enable debug output
---
--- Will pull prone members, poke sleeping ones, unstun (108/1040),
--- untrammel (209), and rally (1040) as appropriate.

local args = require("lib/args")
local GroupLib = require("lib/group")

local opts = args.parse(Script.vars[0])
local DEBUG = opts.debug or false
local INVASION = opts.invasion or false

local BLACKLIST = {}
local TTL = {}

local DEMEANOR_IS_COLD = "looks content"

local TOWN_PATTERNS = {
    "kharam", "teras", "landing", "sol", "icemule trace",
    "mist", "vaalor", "illistim", "rest", "cysaegir", "logoth",
}

local function debug(msg)
    if DEBUG then echo("[debug] " .. msg) end
end

local function blacklist(name)
    debug("blacklisting " .. name .. " for this session")
    BLACKLIST[name] = true
end

local function is_blacklisted(name)
    return BLACKLIST[name] == true
end

local function on_cooldown(name)
    if not TTL[name] then return false end
    local elapsed = os.time() - TTL[name] > 3
    if elapsed then TTL[name] = nil end
    return not elapsed
end

local function in_town()
    if INVASION then return false end
    local loc = GameState.room_location or ""
    loc = loc:lower()
    for _, pat in ipairs(TOWN_PATTERNS) do
        if loc:find(pat) then return true end
    end
    return false
end

local function can_help(member)
    if is_blacklisted(member.name) then return false end
    if not GameState.standing then return false end
    if GameState.stunned then return false end
    if member.dead then return false end
    if on_cooldown(member.name) then return false end
    return true
end

local function pull_member(member)
    if not can_help(member) then return end
    waitrt()
    local result = dothistimeout("pull #" .. member.id, 2,
        "You pull .* to .* feet|You try to pull|You pull .* falls over|You are unable to pull|looks content")
    if not result then return end
    if result:find(DEMEANOR_IS_COLD) then
        blacklist(member.name)
    elseif result:find("falls over") or result:find("unable to pull") then
        TTL[member.name] = os.time()
    end
end

local function unstun_member(member)
    if Spell[108] and Spell[108].known() and checkprep() == "None" then
        Spell[108].cast(member.name)
    end
    if Spell[1040] and Spell[1040].known() then
        if checkmana() > 70 then
            dothistimeout("shout 1040", 3, "rises smoothly|break free|muscles twitch")
        end
    end
end

local function untrammel_member(member)
    if Spell[209] and Spell[209].known() then
        Spell[209].cast(member.name)
    end
end

local function poke_member(member)
    fput("poke #" .. member.id)
end

local function check_self()
    while in_town() do sleep(0.1) end
    while not GameState.standing or GameState.dead or GameState.sleeping do
        sleep(0.1)
    end
    -- Try to rally self if stunned
    if GameState.stunned and Spell[1040] and Spell[1040].known() then
        if checkmana() > 70 then
            dothistimeout("shout 1040", 3, "break free|rises smoothly|muscles twitch")
        end
    end
end

local function get_group_members()
    -- Refresh group info
    fput("group")
    sleep(0.3)
    return Group.members or {}
end

echo("Samaritan active" .. (INVASION and " (invasion mode)" or ""))

-- Main loop
while true do
    check_self()

    local members = get_group_members()

    for _, member_name in ipairs(members) do
        if member_name ~= GameState.name then
            -- Look for this PC in the room
            local pcs = GameObj.pcs()
            if pcs then
                for _, pc in ipairs(pcs) do
                    if pc.name == member_name or pc.noun == member_name then
                        local status = pc.status or ""

                        -- Pull prone/sitting members
                        if status:find("prone") or status:find("sitting") or status:find("kneeling") then
                            pull_member(pc)
                        end

                        -- Poke sleeping members
                        if status:find("sleeping") then
                            poke_member(pc)
                        end

                        -- Unstun stunned members
                        if status:find("stunned") then
                            unstun_member(pc)
                        end

                        -- Untrammel webbed members
                        if status:find("webbed") then
                            untrammel_member(pc)
                        end
                    end
                end
            end
        end
    end

    sleep(0.5)
end
