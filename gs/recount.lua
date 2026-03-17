--- @revenant-script
--- name: recount
--- version: 0.0.1
--- author: Nisugi
--- game: gs
--- tags: hunting, data collection, ttk, tracker
--- description: Track time-to-kill for creatures using downstream hooks
---
--- Original Lich5 authors: Nisugi
--- Ported to Revenant Lua from recount.lic v0.0.1
---
--- Usage:
---   ;recount                          - start tracking
---   ;eq Recount.generate_ttk_report() - report last 15 min

local HOOK_ID = "recount_downstream"
local recount = {}
recount.casttime = 0
recount.roundtime = 0

local NPC_PAT = '<pushBold/>.-<a exist="(%d+)" noun="(%w+)">([^<]+)</a><popBold/>'
local TARGET_PAT = 'You are now targeting <pushBold/>.-<a exist="(%d+)" noun="(%w+)">([^<]+)</a><popBold/>'
local ROUNDTIME_PAT = "<roundTime value='(%d+)'/>"
local CASTTIME_PAT = "<castTime value='(%d+)'/>"

local DEATH_KEYWORDS = {
    "lets out a final scream and goes still",
    "falls back into a heap and dies",
    "screams up at the heavens, then collapses and dies",
    "screams one last time and dies",
    "crumples to the ground and dies",
    "falls to the ground and dies",
    "falls to the ground motionless",
    "rolls over and dies",
    "lets out a final scream and dies",
    "collapses to the ground, emits a final",
    "shudders a final time and goes still",
    "arches its back in a tortured spasm and dies",
    "drops to the ground and shudders a final time",
    "emits a final hiss and dies",
    "kicks a leg one last time and lies still",
    "growls one last time in defiance",
}

DownstreamHook.add(HOOK_ID, function(server_string)
    -- Track NPCs seen
    for id, noun, name in server_string:gmatch(NPC_PAT) do
        if not recount[id] then
            recount[id] = { noun = noun, name = name, saw = os.time() }
        end
    end

    -- Roundtime
    local rt = server_string:match(ROUNDTIME_PAT)
    if rt then recount.roundtime = tonumber(rt) end

    -- Casttime
    local ct = server_string:match(CASTTIME_PAT)
    if ct then recount.casttime = tonumber(ct) end

    -- Target
    local tid = server_string:match(TARGET_PAT)
    if tid and recount[tid] then
        recount[tid].targetted = recount[tid].targetted or os.time()
    end

    -- Death
    for _, keyword in ipairs(DEATH_KEYWORDS) do
        if server_string:find(keyword, 1, true) then
            local did = server_string:match('<a exist="(%d+)"')
            if did and recount[did] then
                recount[did].death = recount[did].death or os.time()
                recount[did].rt = recount[did].rt or recount.roundtime
                recount[did].ct = recount[did].ct or recount.casttime
            end
            break
        end
    end

    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_ID)
end)

-- Expose report function globally
_G.Recount = {
    generate_ttk_report = function(time_range)
        time_range = time_range or 15
        local current = os.time()
        local min_time = current - (time_range * 60)
        local data = {}

        for id, info in pairs(recount) do
            if type(info) == "table" and info.death and info.death >= min_time then
                local death_time = info.death
                if info.rt and info.rt > death_time then death_time = info.rt end
                if info.ct and info.ct > death_time then death_time = info.ct end
                local start_time = info.targetted or info.saw
                if start_time then
                    local ttk = death_time - start_time
                    local ttk_str = info.targetted and tostring(ttk) or (ttk .. " (estimate)")
                    data[#data + 1] = { id = id, name = info.name or "Unknown", ttk = ttk_str }
                end
            end
        end

        if #data == 0 then
            put("No kills recorded in the last " .. time_range .. " minutes.")
            return
        end

        put("\nTime to Kill Report (Last " .. time_range .. " minutes):")
        put(string.rep("-", 50))
        put(string.format("%-10s %-30s %s", "ID", "Name", "TTK (sec)"))
        put(string.rep("-", 50))
        for _, row in ipairs(data) do
            put(string.format("%-10s %-30s %s", row.id, row.name, row.ttk))
        end
        put(string.rep("-", 50))
    end,
}

echo("Recount tracking started. Use ;eq Recount.generate_ttk_report() for reports.")

while true do
    wait(60)
end
